import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/loan_repository.dart';
import '../models/loan.dart';
import '../models/loan_payment.dart';
import '../services/database_helper.dart';
import '../services/schedule_generator.dart';

/// SQLite implementation of [LoanRepository].
class LoanRepositoryImpl implements LoanRepository {
  final DatabaseHelper _dbHelper;

  LoanRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<List<Loan>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL',
      orderBy: 'loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getActive() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND is_cleared = 0',
      orderBy: 'due_date ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getCleared() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND is_cleared = 1',
      orderBy: 'cleared_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getOverdue() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'loans',
      where:
          'deleted_at IS NULL AND is_cleared = 0 AND due_date IS NOT NULL AND due_date < ?',
      whereArgs: [now],
      orderBy: 'due_date ASC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<Loan?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Loan.fromMap(rows.first);
  }

  @override
  Future<int> insert(Loan loan) async {
    final db = await _db;
    final loanId = await db.insert('loans', loan.toMap());

    // Auto-generate repayment schedule if frequency is set
    if (loan.repaymentFrequency != null &&
        loan.emiAmount != null &&
        loan.totalEmis != null) {
      final payments = ScheduleGenerator.generate(
        loanId: loanId,
        startDate: loan.loanDate,
        frequency: loan.repaymentFrequency!,
        installmentAmount: loan.emiAmount!,
        totalInstallments: loan.totalEmis!,
      );
      final batch = db.batch();
      for (final payment in payments) {
        batch.insert('loan_payments', payment.toMap());
      }
      await batch.commit(noResult: true);
    }

    return loanId;
  }

  @override
  Future<void> update(Loan loan) async {
    final db = await _db;
    final map = loan.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('loans', map, where: 'id = ?', whereArgs: [loan.id]);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.update(
      'loans',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordPayment(int loanId, double amount) async {
    final db = await _db;
    final loan = await getById(loanId);
    if (loan == null) return;

    final newPaid = loan.paidAmount + amount;
    final newPending = (loan.principalAmount - newPaid).clamp(0, double.infinity);
    final isCleared = newPending <= 0;

    // If loan has a repayment schedule, mark the next installment as paid
    int newPaidEmis = loan.paidEmis;
    if (loan.repaymentFrequency != null) {
      var remaining = amount;
      final unpaid = await db.query(
        'loan_payments',
        where: 'loan_id = ? AND is_paid = 0',
        whereArgs: [loanId],
        orderBy: 'installment_number ASC',
      );
      for (final row in unpaid) {
        if (remaining <= 0) break;
        final payment = LoanPayment.fromMap(row);
        final payable =
            (payment.amount - payment.paidAmount).clamp(0, double.infinity);
        final toPay = remaining >= payable ? payable : remaining;
        final totalPaid = payment.paidAmount + toPay;
        final isPaid = totalPaid >= payment.amount;

        await db.update(
          'loan_payments',
          {
            'paid_amount': totalPaid,
            'is_paid': isPaid ? 1 : 0,
            if (isPaid) 'paid_date': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [payment.id],
        );

        if (isPaid) newPaidEmis++;
        remaining -= toPay;
      }
    }

    await db.update(
      'loans',
      {
        'paid_amount': newPaid,
        'pending_amount': newPending,
        'paid_emis': newPaidEmis,
        'is_cleared': isCleared ? 1 : 0,
        if (isCleared) 'cleared_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [loanId],
    );
  }

  @override
  Future<void> addPaymentAmount(int loanId, double amount) async {
    final db = await _db;
    final loan = await getById(loanId);
    if (loan == null) return;

    final newPaid = loan.paidAmount + amount;
    final newPending =
        (loan.principalAmount - newPaid).clamp(0, double.infinity);
    final isCleared = newPending <= 0;

    // Count paid installments from the schedule table
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM loan_payments '
      'WHERE loan_id = ? AND is_paid = 1',
      [loanId],
    );
    final paidEmis = (countResult.first['cnt'] as int?) ?? 0;

    await db.update(
      'loans',
      {
        'paid_amount': newPaid,
        'pending_amount': newPending,
        'paid_emis': paidEmis,
        'is_cleared': isCleared ? 1 : 0,
        if (isCleared) 'cleared_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [loanId],
    );
  }

  @override
  Future<double> getTotalPending() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(pending_amount), 0) as total '
      'FROM loans WHERE deleted_at IS NULL AND is_cleared = 0',
    );
    return (result.first['total'] as num).toDouble();
  }
}
