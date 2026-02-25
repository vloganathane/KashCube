import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/loan_payment_repository.dart';
import '../models/loan_payment.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [LoanPaymentRepository].
class LoanPaymentRepositoryImpl implements LoanPaymentRepository {
  final DatabaseHelper _dbHelper;

  LoanPaymentRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<List<LoanPayment>> getByLoanId(int loanId) async {
    final db = await _db;
    final rows = await db.query(
      'loan_payments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'installment_number ASC',
    );
    return rows.map(LoanPayment.fromMap).toList();
  }

  @override
  Future<List<LoanPayment>> getUpcoming(int loanId) async {
    final db = await _db;
    final rows = await db.query(
      'loan_payments',
      where: 'loan_id = ? AND is_paid = 0',
      whereArgs: [loanId],
      orderBy: 'due_date ASC',
    );
    return rows.map(LoanPayment.fromMap).toList();
  }

  @override
  Future<List<LoanPayment>> getOverdue(int loanId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'loan_payments',
      where: 'loan_id = ? AND is_paid = 0 AND due_date < ?',
      whereArgs: [loanId, now],
      orderBy: 'due_date ASC',
    );
    return rows.map(LoanPayment.fromMap).toList();
  }

  @override
  Future<LoanPayment?> getNextPayment(int loanId) async {
    final db = await _db;
    final rows = await db.query(
      'loan_payments',
      where: 'loan_id = ? AND is_paid = 0',
      whereArgs: [loanId],
      orderBy: 'due_date ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LoanPayment.fromMap(rows.first);
  }

  @override
  Future<void> insertAll(List<LoanPayment> payments) async {
    final db = await _db;
    final batch = db.batch();
    for (final payment in payments) {
      batch.insert('loan_payments', payment.toMap());
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> markPaid(int paymentId, double amount) async {
    final db = await _db;
    // Get current payment
    final rows = await db.query(
      'loan_payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    if (rows.isEmpty) return;

    final payment = LoanPayment.fromMap(rows.first);
    final newPaid = payment.paidAmount + amount;
    final isPaid = newPaid >= payment.amount;

    await db.update(
      'loan_payments',
      {
        'paid_amount': newPaid,
        'is_paid': isPaid ? 1 : 0,
        if (isPaid) 'paid_date': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  @override
  Future<void> deleteByLoanId(int loanId) async {
    final db = await _db;
    await db.delete(
      'loan_payments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
    );
  }

  @override
  Future<int> getPaidCount(int loanId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM loan_payments '
      'WHERE loan_id = ? AND is_paid = 1',
      [loanId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  @override
  Future<double> getTotalPaid(int loanId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(paid_amount), 0) as total '
      'FROM loan_payments WHERE loan_id = ?',
      [loanId],
    );
    return (result.first['total'] as num).toDouble();
  }
}
