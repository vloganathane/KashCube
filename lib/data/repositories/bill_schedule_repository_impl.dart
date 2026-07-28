import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/bill_schedule_repository.dart';
import '../models/bill.dart';
import '../models/recurring_transaction.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [BillScheduleRepository].
class BillScheduleRepositoryImpl implements BillScheduleRepository {
  final DatabaseHelper _dbHelper;

  BillScheduleRepositoryImpl([DatabaseHelper? dbHelper])
    : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  static const _table = 'bills';

  @override
  Future<List<Bill>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'deleted_at IS NULL AND is_active = 1',
      orderBy: 'due_day ASC',
    );
    return rows.map(Bill.fromMap).toList();
  }

  @override
  Future<List<Bill>> getOverdue() async {
    final bills = await getAll();
    return bills.where((b) => b.isOverdue).toList();
  }

  @override
  Future<List<Bill>> getUpcoming({int days = 7}) async {
    final bills = await getAll();
    return bills
        .where(
          (b) =>
              !b.isPaidThisPeriod &&
              b.daysUntilDue >= 0 &&
              b.daysUntilDue <= days,
        )
        .toList();
  }

  @override
  Future<Bill?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Bill.fromMap(rows.first);
  }

  @override
  Future<int> insert(Bill bill) async {
    final db = await _db;
    return db.insert(_table, bill.toMap());
  }

  @override
  Future<void> update(Bill bill) async {
    final db = await _db;
    final map = bill.copyWith(updatedAt: DateTime.now()).toMap();
    await db.update(_table, map, where: 'id = ?', whereArgs: [bill.id]);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.update(
      _table,
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markPaid(int id) async {
    final db = await _db;
    await db.update(
      _table,
      {
        'last_paid_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markUnpaid(int id) async {
    final db = await _db;
    await db.update(
      _table,
      {'last_paid_date': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<double> getTotalMonthly() async {
    final bills = await getAll();
    double total = 0;
    for (final bill in bills) {
      total += _toMonthly(bill.amount, bill.frequency);
    }
    return total;
  }

  double _toMonthly(double amount, RecurringFrequency freq) {
    switch (freq) {
      case RecurringFrequency.daily:
        return amount * 30;
      case RecurringFrequency.weekly:
        return amount * 4;
      case RecurringFrequency.biweekly:
        return amount * 2;
      case RecurringFrequency.monthly:
        return amount;
      case RecurringFrequency.quarterly:
        return amount / 3;
      case RecurringFrequency.yearly:
        return amount / 12;
    }
  }
}
