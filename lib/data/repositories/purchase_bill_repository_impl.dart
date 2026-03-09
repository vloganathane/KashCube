import '../../data/models/purchase_bill.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/purchase_bill_repository.dart';

class PurchaseBillRepositoryImpl implements PurchaseBillRepository {
  final _db = DatabaseHelper.instance;

  // ── helpers ─────────────────────────────────────────────────────────────

  Future<List<PurchaseBillItem>> _itemsFor(dynamic db, int billId) async {
    final rows = await db.query(
      'purchase_bill_items',
      where: 'bill_id = ?',
      whereArgs: [billId],
    );
    return rows.map<PurchaseBillItem>(PurchaseBillItem.fromMap).toList();
  }

  PurchaseBillStatus _deriveStatus(double total, double paid) {
    if (paid <= 0) return PurchaseBillStatus.unpaid;
    if (paid >= total) return PurchaseBillStatus.paid;
    return PurchaseBillStatus.partiallyPaid;
  }

  // ── interface ────────────────────────────────────────────────────────────

  @override
  Future<int> insert(PurchaseBill bill, List<PurchaseBillItem> items) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final id = await txn.insert(
        'purchase_bills',
        bill.copyWith(createdAt: now, updatedAt: now).toMap(),
      );
      for (final item in items) {
        await txn.insert(
          'purchase_bill_items',
          item.copyWith(billId: id).toMap(),
        );
      }
      return id;
    });
  }

  @override
  Future<void> update(PurchaseBill bill, List<PurchaseBillItem> items) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'purchase_bills',
        bill.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [bill.id],
      );
      await txn.delete(
        'purchase_bill_items',
        where: 'bill_id = ?',
        whereArgs: [bill.id],
      );
      for (final item in items) {
        await txn.insert(
          'purchase_bill_items',
          item.copyWith(billId: bill.id!).toMap(),
        );
      }
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('purchase_bills', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<PurchaseBill?> fetchById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'purchase_bills',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final items = await _itemsFor(db, id);
    return PurchaseBill.fromMap(rows.first, items: items);
  }

  @override
  Future<List<PurchaseBill>> fetchForBusiness(int businessId) async {
    final db = await _db.database;
    final rows = await db.query(
      'purchase_bills',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'bill_date DESC',
    );
    final result = <PurchaseBill>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsFor(db, id);
      result.add(PurchaseBill.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<List<PurchaseBill>> fetchForPeriod({
    required int businessId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'purchase_bills',
      where: 'business_id = ? AND bill_date >= ? AND bill_date <= ?',
      whereArgs: [
        businessId,
        from.toIso8601String().substring(0, 10),
        '${to.toIso8601String().substring(0, 10)}T23:59:59',
      ],
      orderBy: 'bill_date ASC',
    );
    final result = <PurchaseBill>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsFor(db, id);
      result.add(PurchaseBill.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<List<PurchaseBill>> fetchUnpaid(int businessId) async {
    final db = await _db.database;
    final rows = await db.query(
      'purchase_bills',
      where: "business_id = ? AND status IN ('unpaid', 'partially_paid')",
      whereArgs: [businessId],
      orderBy: 'due_date ASC',
    );
    final result = <PurchaseBill>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsFor(db, id);
      result.add(PurchaseBill.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<void> recordPayment({
    required int billId,
    required double amount,
    required DateTime paidAt,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'purchase_bills',
        columns: ['total', 'paid_amount'],
        where: 'id = ?',
        whereArgs: [billId],
      );
      if (rows.isEmpty) return;
      final total = (rows.first['total'] as num).toDouble();
      final newPaid =
          (rows.first['paid_amount'] as num).toDouble() + amount;
      final status = _deriveStatus(total, newPaid);
      await txn.update(
        'purchase_bills',
        {
          'paid_amount': newPaid,
          'status': status.dbValue,
          'updated_at': paidAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [billId],
      );
    });
  }

  @override
  Future<void> markItcAvailed(int billId, {required bool availed}) async {
    final db = await _db.database;
    await db.update(
      'purchase_bills',
      {
        'itc_availed': availed ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [billId],
    );
  }
}
