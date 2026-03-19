import '../../domain/repositories/scheduled_payment_repository.dart';
import '../models/scheduled_payment.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [ScheduledPaymentRepository].
class ScheduledPaymentRepositoryImpl implements ScheduledPaymentRepository {
  ScheduledPaymentRepositoryImpl([DatabaseHelper? dbHelper, this.contextId])
      : _db = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;
  static const _table = 'scheduled_payments';

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Future<List<ScheduledPayment>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'deleted_at IS NULL AND is_active = 1 AND $_ctx',
      orderBy: 'next_date ASC',
    );
    return rows.map(ScheduledPayment.fromMap).toList();
  }

  @override
  Future<List<ScheduledPayment>> getByParty(String partyName) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'deleted_at IS NULL AND is_active = 1 AND $_ctx AND party_name = ?',
      whereArgs: [partyName],
      orderBy: 'next_date ASC',
    );
    return rows.map(ScheduledPayment.fromMap).toList();
  }

  @override
  Future<List<ScheduledPayment>> getByContext(String context) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'deleted_at IS NULL AND is_active = 1 AND $_ctx AND bill_context = ?',
      whereArgs: [context],
      orderBy: 'next_date ASC',
    );
    return rows.map(ScheduledPayment.fromMap).toList();
  }

  @override
  Future<List<ScheduledPayment>> getOverdue() async {
    final all = await getAll();
    return all.where((p) => p.isOverdue).toList();
  }

  @override
  Future<List<ScheduledPayment>> getUpcoming({int days = 7}) async {
    final all = await getAll();
    return all
        .where((p) =>
            !p.isPaidThisPeriod &&
            p.daysUntilDue >= 0 &&
            p.daysUntilDue <= days)
        .toList();
  }

  @override
  Future<List<ScheduledPayment>> getDueForAutoCreate() async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      _table,
      where:
          'deleted_at IS NULL AND is_active = 1 AND $_ctx AND auto_create = 1 AND next_date <= ?',
      whereArgs: [now],
    );
    return rows.map(ScheduledPayment.fromMap).toList();
  }

  @override
  Future<ScheduledPayment?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return ScheduledPayment.fromMap(rows.first);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  @override
  Future<int> insert(ScheduledPayment payment) async {
    final db = await _db.database;
    final map = payment.toMap();
    map['context_id'] = contextId;
    final id = await db.insert(_table, map);
    _db.notifyChange(_table);
    return id;
  }

  @override
  Future<void> update(ScheduledPayment payment) async {
    final db = await _db.database;
    final map = payment.copyWith(updatedAt: DateTime.now()).toMap();
    await db.update(_table, map, where: 'id = ?', whereArgs: [payment.id]);
    _db.notifyChange(_table);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.update(
      _table,
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _db.notifyChange(_table);
  }

  // ── Aggregates ────────────────────────────────────────────────────────────

  @override
  Future<double> getTotalMonthlyExpense() async {
    final all = await getAll();
    double total = 0;
    for (final p in all) {
      if (p.type != 'expense' || p.isOneTime) continue;
      if (p.frequency == null) continue;
      total += p.frequency!.toMonthly(p.amount);
    }
    return total;
  }

  @override
  Future<({double income, double expense})> getMonthlySummary() async {
    final all = await getAll();
    double income = 0;
    double expense = 0;
    for (final p in all) {
      if (p.isOneTime || p.frequency == null) continue;
      final monthly = p.frequency!.toMonthly(p.amount);
      if (p.type == 'income') {
        income += monthly;
      } else {
        expense += monthly;
      }
    }
    return (income: income, expense: expense);
  }
}
