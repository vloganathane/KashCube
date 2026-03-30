import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

import '../models/lot_movement.dart';
import '../models/stock_lot.dart';
import 'database_helper.dart';

/// Snapshot of a single lot consumed during a FEFO outbound allocation.
///
/// Serialized to JSON and stored in [invoice_items.lot_allocation_json].
class LotAllocation {
  const LotAllocation({
    required this.lotId,
    required this.qty,
    this.lotNo,
    this.expiryDate,
  });

  final int lotId;
  final double qty;
  final String? lotNo;

  /// ISO date string (YYYY-MM-DD), matches what is stored on [StockLot].
  final String? expiryDate;

  Map<String, dynamic> toMap() => {
        'lot_id': lotId,
        'qty': qty,
        if (lotNo != null) 'lot_no': lotNo,
        if (expiryDate != null) 'expiry_date': expiryDate,
      };

  factory LotAllocation.fromMap(Map<String, dynamic> m) => LotAllocation(
        lotId: m['lot_id'] as int,
        qty: (m['qty'] as num).toDouble(),
        lotNo: m['lot_no'] as String?,
        expiryDate: m['expiry_date'] as String?,
      );

  /// Serialize a list of allocations to a JSON string for DB storage.
  static String encodeList(List<LotAllocation> list) =>
      jsonEncode(list.map((a) => a.toMap()).toList());

  /// Deserializes a stored JSON string back to allocation objects.
  static List<LotAllocation> decodeList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => LotAllocation.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      AppLogger.instance.debug(
        'Failed to decode lot allocation JSON',
        category: 'lot_allocation',
        error: e,
      );
      return [];
    }
  }
}

/// Manages lot-level stock: creation (purchase inward), FEFO consumption
/// (invoice/challan outward), and reversal.
///
/// Works in tandem with [InventoryService] which maintains the aggregate
/// [item_stock] + [stock_movements] ledger. Both services must be called
/// together to keep the two ledgers consistent.
class LotAllocationService {
  LotAllocationService._();

  static final LotAllocationService instance = LotAllocationService._();

  final _db = DatabaseHelper.instance;

  // ── Inward ─────────────────────────────────────────────────────────────────

  /// Creates a lot record when stock arrives via a purchase bill.
  ///
  /// Returns the new lot's [id]. Safe to call even when the item is not
  /// inventory-tracked — the lot is created regardless (it will just never be
  /// allocated by FEFO since [InventoryService._isTracked] gates deductions).
  Future<int> createLot({
    required int businessId,
    required int itemId,
    required int purchaseBillId,
    String? lotNo,
    DateTime? expiryDate,
    DateTime? mfgDate,
    required double unitCost,
    required double qty,
    String? notes,
  }) async {
    assert(qty > 0, 'Lot qty must be positive');
    final db = await _db.database;
    final now = DateTime.now();

    final lot = StockLot(
      businessId: businessId,
      itemId: itemId,
      purchaseBillId: purchaseBillId,
      lotNo: lotNo?.trim().isNotEmpty == true ? lotNo!.trim() : null,
      expiryDate: expiryDate,
      mfgDate: mfgDate,
      unitCost: unitCost,
      qtyIn: qty,
      qtyRemaining: qty,
      status: StockLotStatus.active,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final lotId = await db.insert('stock_lots', lot.toMap());

    await db.insert('lot_movements', LotMovement(
      businessId: businessId,
      itemId: itemId,
      lotId: lotId,
      movementType: LotMovementType.purchaseIn,
      qty: qty,
      lotQtyAfter: qty,
      referenceType: 'purchase_bill',
      referenceId: purchaseBillId,
      notes: notes,
      createdAt: now,
    ).toMap());

    debugPrint('[Lot] Created lot $lotId for item $itemId qty=$qty '
        'lot_no=${lot.lotNo} expiry=${lot.expiryDate}');
    return lotId;
  }

  // ── Outward (FEFO) ─────────────────────────────────────────────────────────

  /// Allocates [qty] units from available lots using FEFO ordering.
  ///
  /// FEFO order:
  ///   1. Lots with an expiry date come before no-expiry lots.
  ///   2. Earliest expiry first.
  ///   3. Oldest created_at first.
  ///   4. Lowest id first (tie-break).
  ///
  /// Returns the list of [LotAllocation]s. If total available stock < [qty],
  /// the returned list covers only what was available (partial allocation).
  /// Callers that require strict enforcement should check the sum themselves.
  ///
  /// Side-effects: updates [stock_lots.qty_remaining]; inserts [lot_movements].
  Future<List<LotAllocation>> allocateFefo({
    required int businessId,
    required int itemId,
    required double qty,
    required String referenceType,
    required int referenceId,
    int? referenceLineId,
  }) async {
    assert(qty > 0);
    final db = await _db.database;

    final lots = await db.rawQuery('''
      SELECT id, lot_no, expiry_date, qty_remaining
      FROM stock_lots
      WHERE business_id = ? AND item_id = ? AND qty_remaining > 0 AND status = 'active'
      ORDER BY
        CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END ASC,
        expiry_date ASC,
        created_at ASC,
        id ASC
    ''', [businessId, itemId]);

    if (lots.isEmpty) return [];

    final allocations = <LotAllocation>[];
    double needed = qty;
    final now = DateTime.now().toIso8601String();
    final movType = referenceType == 'invoice'
        ? LotMovementType.saleOut
        : LotMovementType.challanOut;

    await db.transaction((txn) async {
      for (final lot in lots) {
        if (needed <= 0) break;
        final lotId = lot['id'] as int;
        final available = (lot['qty_remaining'] as num).toDouble();
        final take = needed <= available ? needed : available;
        final newRemaining = available - take;

        await txn.update(
          'stock_lots',
          {
            'qty_remaining': newRemaining,
            'status': newRemaining <= 0
                ? StockLotStatus.depleted.name
                : StockLotStatus.active.name,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [lotId],
        );

        final movMap = {
          'business_id': businessId,
          'item_id': itemId,
          'lot_id': lotId,
          'movement_type': movType.name,
          'qty': -take,
          'lot_qty_after': newRemaining,
          'reference_type': referenceType,
          'reference_id': referenceId,
          'created_at': now,
        };
        if (referenceLineId != null) {
          movMap['reference_line_id'] = referenceLineId;
        }
        await txn.insert('lot_movements', movMap);

        allocations.add(LotAllocation(
          lotId: lotId,
          qty: take,
          lotNo: lot['lot_no'] as String?,
          expiryDate: lot['expiry_date'] as String?,
        ));
        needed -= take;
      }
    });

    debugPrint('[Lot] FEFO allocated ${qty - needed}/$qty for item $itemId '
        'via $referenceType #$referenceId in ${allocations.length} lot(s)');
    return allocations;
  }

  // ── Reversal ────────────────────────────────────────────────────────────────

  /// Reverses all lot-level movements recorded for [referenceType] + [referenceId].
  ///
  /// Re-activates depleted lots whose [qty_remaining] rises above 0 after the
  /// reversal. Safe to call even when no lot movements exist (no-op).
  Future<void> reverseLotMovements(
      String referenceType, int referenceId) async {
    final db = await _db.database;
    final movements = await db.query(
      'lot_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [referenceType, referenceId],
    );
    if (movements.isEmpty) return;

    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final m in movements) {
        final lotId = m['lot_id'] as int;
        final originalQty = (m['qty'] as num).toDouble();
        if (originalQty == 0) continue;

        final lotRows = await txn.query(
          'stock_lots',
          where: 'id = ?',
          whereArgs: [lotId],
        );
        if (lotRows.isEmpty) continue;

        final currentRemaining =
            (lotRows.first['qty_remaining'] as num).toDouble();
        final qtyIn = (lotRows.first['qty_in'] as num).toDouble();
        // originalQty is negative for outbound movements; subtracting it
        // adds back the quantity.
        final newRemaining =
            (currentRemaining - originalQty).clamp(0.0, qtyIn);

        await txn.update(
          'stock_lots',
          {
            'qty_remaining': newRemaining,
            'status': newRemaining > 0
                ? StockLotStatus.active.name
                : StockLotStatus.depleted.name,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [lotId],
        );

        await txn.insert('lot_movements', {
          'business_id': m['business_id'],
          'item_id': m['item_id'],
          'lot_id': lotId,
          'movement_type': LotMovementType.reversal.name,
          'qty': -originalQty,
          'lot_qty_after': newRemaining,
          'reference_type': '${referenceType}_reversal',
          'reference_id': referenceId,
          'notes': 'Reversal of $referenceType #$referenceId',
          'created_at': now,
        });
      }
    });

    debugPrint('[Lot] Reversed lot movements for $referenceType #$referenceId '
        '(${movements.length} movement(s))');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Persists a FEFO allocation snapshot to [invoice_items.lot_allocation_json].
  Future<void> saveAllocationToInvoiceItem(
      int invoiceItemId, List<LotAllocation> allocations) async {
    if (allocations.isEmpty) return;
    final db = await _db.database;
    await db.update(
      'invoice_items',
      {'lot_allocation_json': LotAllocation.encodeList(allocations)},
      where: 'id = ?',
      whereArgs: [invoiceItemId],
    );
  }

  /// Returns active / partially-consumed lots for an item, FEFO-ordered.
  Future<List<StockLot>> getLotsForItem(int itemId, int businessId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT * FROM stock_lots
      WHERE item_id = ? AND business_id = ? AND status != 'depleted'
      ORDER BY
        CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END ASC,
        expiry_date ASC,
        created_at ASC
    ''', [itemId, businessId]);
    return rows.map(StockLot.fromMap).toList();
  }

  /// Returns all active lots expiring within [daysAhead] days across the
  /// given business (useful for expiry-alert badges on the inventory screen).
  Future<List<StockLot>> getExpiringLots(
    int businessId, {
    int daysAhead = 30,
  }) async {
    final db = await _db.database;
    final cutoff = DateTime.now()
        .add(Duration(days: daysAhead))
        .toIso8601String()
        .substring(0, 10);
    final rows = await db.rawQuery('''
      SELECT * FROM stock_lots
      WHERE business_id = ?
        AND status = 'active'
        AND expiry_date IS NOT NULL
        AND expiry_date <= ?
      ORDER BY expiry_date ASC
    ''', [businessId, cutoff]);
    return rows.map(StockLot.fromMap).toList();
  }
}
