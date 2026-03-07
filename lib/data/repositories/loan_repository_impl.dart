import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../domain/repositories/loan_repository.dart';
import '../models/loan.dart';
import '../models/loan_payment.dart';
import '../models/transaction.dart' as tx;
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
  Future<List<Loan>> getPersonal() async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'business_id IS NULL AND is_cleared = 0 AND deleted_at IS NULL',
      orderBy: 'due_date ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getForBusiness(int businessId) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'business_id = ? AND is_cleared = 0 AND deleted_at IS NULL',
      whereArgs: [businessId],
      orderBy: 'due_date ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<Loan>> getActiveByDirection(LoanDirection direction) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND is_cleared = 0 AND direction = ?',
      whereArgs: [direction.dbValue],
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

    // Auto-create a transaction representing this loan creation
    final txType = loan.isLent ? tx.TransactionType.lent : tx.TransactionType.borrowed;
    final linkedTx = tx.Transaction(
      amount: loan.principalAmount,
      date: loan.loanDate,
      type: txType,
      category: loan.isLent ? 'Lent' : 'Borrowed',
      partyName: loan.lenderName,
      phoneNumber: loan.phoneNumber,
      dueDate: loan.dueDate,
      interestRate: loan.interestRate,
      interestType: loan.interestType == InterestType.none
          ? null
          : tx.InterestType.fromDb(loan.interestType.dbValue),
      repaymentFrequency:
          tx.RepaymentFrequency.fromDb(loan.repaymentFrequency?.dbValue),
      totalInstallments: loan.totalEmis,
      emiAmount: loan.emiAmount,
      loanId: loanId,
      notes: loan.notes,
    );
    await db.insert('transactions', linkedTx.toMap());

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

      // Keep next_emi_date in sync
      if (payments.isNotEmpty) {
        await db.update(
          'loans',
          {'next_emi_date': payments.first.dueDate.toIso8601String()},
          where: 'id = ?',
          whereArgs: [loanId],
        );
      }
    }

    return loanId;
  }

  @override
  Future<void> update(Loan loan) async {
    final db = await _db;
    final map = loan.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('loans', map, where: 'id = ?', whereArgs: [loan.id]);

    // Sync the auto-created creation transaction (amount, party, dates may change)
    if (loan.id != null) {
      await db.update(
        'transactions',
        {
          'amount': loan.principalAmount,
          'party_name': loan.lenderName,
          'phone_number': loan.phoneNumber,
          'due_date': loan.dueDate?.toIso8601String(),
          'interest_rate': loan.interestRate,
          'interest_type': loan.interestType.dbValue,
          'repayment_frequency': loan.repaymentFrequency?.dbValue,
          'total_installments': loan.totalEmis,
          'emi_amount': loan.emiAmount,
          'notes': loan.notes,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'loan_id = ? AND type IN (?, ?) AND deleted_at IS NULL',
        whereArgs: [loan.id, tx.TransactionType.lent.dbValue, tx.TransactionType.borrowed.dbValue],
      );
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'loans',
      {'deleted_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Soft-delete all transactions linked to this loan
    await db.update(
      'transactions',
      {'deleted_at': now},
      where: 'loan_id = ? AND deleted_at IS NULL',
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

    // Advance next_emi_date to the next unpaid installment
    if (loan.repaymentFrequency != null) {
      final nextRow = await db.query(
        'loan_payments',
        columns: ['due_date'],
        where: 'loan_id = ? AND is_paid = 0',
        whereArgs: [loanId],
        orderBy: 'due_date ASC',
        limit: 1,
      );
      final nextEmi = nextRow.isNotEmpty
          ? nextRow.first['due_date'] as String?
          : null;
      await db.update(
        'loans',
        {'next_emi_date': nextEmi},
        where: 'id = ?',
        whereArgs: [loanId],
      );
    }

    // Auto-create a repayment transaction so it appears in Khata/reports
    final repayType = loan.isLent ? tx.TransactionType.receivedBack : tx.TransactionType.paidBack;
    final repayTx = tx.Transaction(
      amount: amount,
      date: DateTime.now(),
      type: repayType,
      category: loan.isLent ? 'Received Back' : 'Paid Back',
      partyName: loan.lenderName,
      loanId: loanId,
    );
    await db.insert('transactions', repayTx.toMap());
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

    // Advance next_emi_date to the next unpaid installment
    if (loan.repaymentFrequency != null) {
      final nextRow = await db.query(
        'loan_payments',
        columns: ['due_date'],
        where: 'loan_id = ? AND is_paid = 0',
        whereArgs: [loanId],
        orderBy: 'due_date ASC',
        limit: 1,
      );
      final nextEmi = nextRow.isNotEmpty
          ? nextRow.first['due_date'] as String?
          : null;
      await db.update(
        'loans',
        {'next_emi_date': nextEmi},
        where: 'id = ?',
        whereArgs: [loanId],
      );
    }

    // Auto-create a repayment transaction so it appears in Khata/reports
    final repayType = loan.isLent ? tx.TransactionType.receivedBack : tx.TransactionType.paidBack;
    final repayTx2 = tx.Transaction(
      amount: amount,
      date: DateTime.now(),
      type: repayType,
      category: loan.isLent ? 'Received Back' : 'Paid Back',
      partyName: loan.lenderName,
      loanId: loanId,
    );
    await db.insert('transactions', repayTx2.toMap());
  }

  @override
  Future<void> reversePaymentAmount(int loanId, double amount) async {
    final db = await _db;
    final loan = await getById(loanId);
    if (loan == null) return;

    final newPaid = (loan.paidAmount - amount).clamp(0.0, double.infinity);
    final newPending = (loan.principalAmount - newPaid).clamp(0.0, double.infinity);

    // Recount paid installments after the reversal (is_paid already reset by caller)
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
        'is_cleared': 0,
        'cleared_date': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [loanId],
    );

    // Recalculate next_emi_date to the earliest remaining unpaid installment
    if (loan.repaymentFrequency != null) {
      final nextRow = await db.query(
        'loan_payments',
        columns: ['due_date'],
        where: 'loan_id = ? AND is_paid = 0',
        whereArgs: [loanId],
        orderBy: 'due_date ASC',
        limit: 1,
      );
      final nextEmi =
          nextRow.isNotEmpty ? nextRow.first['due_date'] as String? : null;
      await db.update(
        'loans',
        {'next_emi_date': nextEmi},
        where: 'id = ?',
        whereArgs: [loanId],
      );
    }
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

  @override
  Future<double> getTotalPendingLent() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) as total "
      "FROM loans WHERE deleted_at IS NULL AND is_cleared = 0 AND direction = 'lent'",
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<double> getTotalPendingBorrowed() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(pending_amount), 0) as total "
      "FROM loans WHERE deleted_at IS NULL AND is_cleared = 0 AND direction = 'borrowed'",
    );
    return (result.first['total'] as num).toDouble();
  }

  @override
  Future<List<PartyLedgerSummary>> getPartySummaries() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        lender_name,
        SUM(CASE WHEN direction = 'lent' THEN principal_amount ELSE 0 END) as total_lent,
        SUM(CASE WHEN direction = 'borrowed' THEN principal_amount ELSE 0 END) as total_borrowed,
        SUM(CASE WHEN direction = 'lent' AND is_cleared = 0 THEN pending_amount ELSE 0 END) as pending_lent,
        SUM(CASE WHEN direction = 'borrowed' AND is_cleared = 0 THEN pending_amount ELSE 0 END) as pending_borrowed,
        SUM(CASE WHEN is_cleared = 0 THEN 1 ELSE 0 END) as active_count
      FROM loans
      WHERE deleted_at IS NULL
      GROUP BY lender_name
      ORDER BY active_count DESC, lender_name ASC
    ''');

    return rows.map((r) => PartyLedgerSummary(
      partyName: r['lender_name'] as String,
      totalLent: (r['total_lent'] as num?)?.toDouble() ?? 0,
      totalBorrowed: (r['total_borrowed'] as num?)?.toDouble() ?? 0,
      pendingLent: (r['pending_lent'] as num?)?.toDouble() ?? 0,
      pendingBorrowed: (r['pending_borrowed'] as num?)?.toDouble() ?? 0,
      activeCount: (r['active_count'] as int?) ?? 0,
    )).toList();
  }

  @override
  Future<List<Loan>> getByPartyName(String partyName) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'deleted_at IS NULL AND lender_name = ?',
      whereArgs: [partyName],
      orderBy: 'is_cleared ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }

  @override
  Future<List<String>> getPartyNames() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT DISTINCT lender_name FROM loans WHERE deleted_at IS NULL ORDER BY lender_name',
    );
    return rows.map((r) => r['lender_name'] as String).toList();
  }

  @override
  Future<List<Loan>> getByLenderId(int partyId) async {
    final db = await _db;
    final rows = await db.query(
      'loans',
      where: 'lender_id = ? AND deleted_at IS NULL',
      whereArgs: [partyId],
      orderBy: 'is_cleared ASC, loan_date DESC',
    );
    return rows.map(Loan.fromMap).toList();
  }
}
