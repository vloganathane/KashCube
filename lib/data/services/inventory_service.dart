import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/item_catalog.dart';
import '../models/stock_movement.dart';
import 'database_helper.dart';

/// Service for inventory stock tracking.
///
/// As of DB v55, stock levels are stored per-business in [item_stock].
/// Every write also records a movement in [stock_movements] with
/// [businessId] for full per-company audit history.
///
/// When [businessId] is null (legacy paths or background workers) the service
/// falls back to the old behaviour: reading/writing [item_catalog.stock_qty]
/// directly. This keeps all callsites that pre-date v55 working without
/// changes while new callers pass [businessId] for correct multi-company
/// behaviour.
class InventoryService {
  InventoryService._();
  static final InventoryService instance = InventoryService._();

  final _db = DatabaseHelper.instance;

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All items that have inventory tracking enabled for [businessId].
  ///
  /// When [businessId] is provided the result merges [item_catalog] columns
  /// with per-business values from [item_stock] (stock_qty, track_inventory,
  /// low_stock_threshold).  Without a businessId the legacy item_catalog
  /// columns are used (backwards-compatible).
  ///
  /// Uses LEFT JOIN so items marked as tracked in the catalog appear for ALL
  /// businesses, even if no [item_stock] row exists yet for that business.
  /// A per-business [item_stock] row overrides the catalog-level flag.
  Future<List<ItemCatalog>> getTrackedItems({int? businessId}) async {
    final db = await _db.database;
    if (businessId != null) {
      final rows = await db.rawQuery(
        '''
        SELECT
          ic.id, ic.name, ic.description, ic.sku, ic.category, ic.unit,
          ic.unit_price, ic.tax_pct, ic.hsn_code, ic.hsn_or_sac,
          ic.is_favorite, ic.is_active, ic.last_used_at, ic.usage_count,
          ic.duration_minutes, ic.is_bookable, ic.business_id,
          ic.created_at, ic.updated_at,
          COALESCE(ist.track_inventory, ic.track_inventory)  AS track_inventory,
          COALESCE(ist.stock_qty,        ic.stock_qty)        AS stock_qty,
          COALESCE(ist.low_stock_threshold, ic.low_stock_threshold) AS low_stock_threshold,
          ist.last_counted_qty,
          ist.last_counted_at
        FROM item_catalog ic
        LEFT JOIN item_stock ist ON ist.item_id = ic.id AND ist.business_id = ?
        WHERE ic.is_active = 1
          AND COALESCE(ist.track_inventory, ic.track_inventory) = 1
        ORDER BY ic.name COLLATE NOCASE
        ''',
        [businessId],
      );
      return rows.map(ItemCatalog.fromMap).toList();
    }
    // Legacy fallback
    final rows = await db.rawQuery(
      'SELECT * FROM item_catalog '
      'WHERE is_active = 1 AND track_inventory = 1 '
      'ORDER BY name COLLATE NOCASE',
    );
    return rows.map(ItemCatalog.fromMap).toList();
  }

  /// Items where stock_qty ≤ low_stock_threshold for [businessId].
  Future<List<ItemCatalog>> getLowStockItems({int? businessId}) async {
    final db = await _db.database;
    if (businessId != null) {
      final rows = await db.rawQuery(
        '''
        SELECT
          ic.id, ic.name, ic.description, ic.sku, ic.category, ic.unit,
          ic.unit_price, ic.tax_pct, ic.hsn_code, ic.hsn_or_sac,
          ic.is_favorite, ic.is_active, ic.last_used_at, ic.usage_count,
          ic.duration_minutes, ic.is_bookable, ic.business_id,
          ic.created_at, ic.updated_at,
          ist.track_inventory,
          ist.stock_qty,
          ist.low_stock_threshold
        FROM item_catalog ic
        JOIN item_stock ist ON ist.item_id = ic.id AND ist.business_id = ?
        WHERE ic.is_active = 1
          AND ist.track_inventory = 1
          AND ist.stock_qty <= ist.low_stock_threshold
        ORDER BY ist.stock_qty ASC
        ''',
        [businessId],
      );
      return rows.map(ItemCatalog.fromMap).toList();
    }
    // Legacy fallback
    final rows = await db.rawQuery(
      'SELECT * FROM item_catalog '
      'WHERE is_active = 1 AND track_inventory = 1 '
      '  AND stock_qty <= low_stock_threshold '
      'ORDER BY stock_qty ASC',
    );
    return rows.map(ItemCatalog.fromMap).toList();
  }

  /// Recent movements for a specific item (newest first).
  ///
  /// When [businessId] is provided only movements for that business are
  /// returned.
  Future<List<StockMovement>> getMovementsForItem(
    int itemId, {
    int limit = 50,
    int? businessId,
  }) async {
    final db = await _db.database;
    if (businessId != null) {
      final rows = await db.rawQuery(
        'SELECT * FROM stock_movements '
        'WHERE item_id = ? AND business_id = ? '
        'ORDER BY created_at DESC LIMIT ?',
        [itemId, businessId, limit],
      );
      return rows.map(StockMovement.fromMap).toList();
    }
    final rows = await db.rawQuery(
      'SELECT * FROM stock_movements WHERE item_id = ? '
      'ORDER BY created_at DESC LIMIT ?',
      [itemId, limit],
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Returns true if inventory tracking is enabled for [itemId].
  ///
  /// When [businessId] is provided, the per-business [item_stock] value takes
  /// precedence over the catalog-level flag (COALESCE logic mirrors the query
  /// used in [getTrackedItems]). This is the single gate that prevents silent
  /// stock movements for items — or users — that have not enabled tracking.
  Future<bool> _isTracked(int itemId, {int? businessId}) async {
    final db = await _db.database;
    if (businessId != null) {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(ist.track_inventory, ic.track_inventory) AS tracked
        FROM item_catalog ic
        LEFT JOIN item_stock ist
          ON ist.item_id = ic.id AND ist.business_id = ?
        WHERE ic.id = ?
        ''',
        [businessId, itemId],
      );
      if (rows.isEmpty) return false;
      return (rows.first['tracked'] as int?) == 1;
    }
    // Legacy fallback
    final rows = await db.query(
      'item_catalog',
      columns: ['track_inventory'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (rows.isEmpty) return false;
    return (rows.first['track_inventory'] as int?) == 1;
  }

  /// Adds [qty] units of stock for [businessId] (or globally when null).
  ///
  /// No-op if the item does not have inventory tracking enabled — this prevents
  /// silent stock movements for Free/Starter users who have no inventory access.
  Future<void> addStock(
    int itemId,
    double qty, {
    String? notes,
    int? referenceId,
    String? referenceType,
    int? businessId,
  }) async {
    assert(qty > 0, 'addStock qty must be positive');
    if (!await _isTracked(itemId, businessId: businessId)) return;
    await _applyMovement(
      itemId: itemId,
      delta: qty,
      type: referenceType == 'purchase'
          ? StockMovementType.purchaseAddition
          : StockMovementType.stockIn,
      notes: notes,
      referenceId: referenceId,
      referenceType: referenceType,
      businessId: businessId,
    );
  }

  /// Deducts [qty] units of stock (positive qty = amount to remove).
  ///
  /// No-op if the item does not have inventory tracking enabled — this prevents
  /// silent stock movements for Free/Starter users who have no inventory access.
  Future<void> deductStock(
    int itemId,
    double qty, {
    String? notes,
    int? referenceId,
    String? referenceType,
    int? businessId,
  }) async {
    assert(qty > 0, 'deductStock qty must be positive');
    if (!await _isTracked(itemId, businessId: businessId)) return;
    await _applyMovement(
      itemId: itemId,
      delta: -qty,
      type: referenceType == 'sale'
          ? StockMovementType.saleDeduction
          : StockMovementType.stockOut,
      notes: notes,
      referenceId: referenceId,
      referenceType: referenceType,
      businessId: businessId,
    );
  }

  /// Sets stock to an absolute value (creates an adjustment movement).
  Future<void> setStock(
    int itemId,
    double newQty, {
    String? notes,
    int? businessId,
  }) async {
    final db = await _db.database;
    double current;
    if (businessId != null) {
      final rows = await db.rawQuery(
        'SELECT stock_qty FROM item_stock WHERE business_id = ? AND item_id = ?',
        [businessId, itemId],
      );
      current =
          rows.isNotEmpty ? (rows.first['stock_qty'] as num).toDouble() : 0.0;
    } else {
      final rows = await db.query(
        'item_catalog',
        columns: ['stock_qty'],
        where: 'id = ?',
        whereArgs: [itemId],
      );
      if (rows.isEmpty) return;
      current = (rows.first['stock_qty'] as num).toDouble();
    }
    final delta = newQty - current;
    if (delta == 0) return;
    await _applyMovement(
      itemId: itemId,
      delta: delta,
      type: StockMovementType.adjustment,
      notes: notes ?? 'Manual adjustment',
      businessId: businessId,
    );
  }

  /// Enables or disables inventory tracking for [businessId].
  ///
  /// Upserts an [item_stock] row for [businessId] and also keeps the legacy
  /// [item_catalog.track_inventory] column in sync as a global default.
  Future<void> setTrackInventory(
    int itemId, {
    required bool track,
    int? businessId,
  }) async {
    final db = await _db.database;
    if (businessId != null) {
      await db.rawInsert(
        '''
        INSERT INTO item_stock (business_id, item_id, track_inventory, stock_qty, low_stock_threshold)
        VALUES (?, ?, ?, 0, 5)
        ON CONFLICT(business_id, item_id) DO UPDATE SET track_inventory = excluded.track_inventory
        ''',
        [businessId, itemId, track ? 1 : 0],
      );
    }
    // Keep item_catalog in sync as a global default.
    await db.update(
      'item_catalog',
      {
        'track_inventory': track ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Sets the low-stock alert threshold for [businessId].
  Future<void> setLowStockThreshold(
    int itemId,
    double threshold, {
    int? businessId,
  }) async {
    final db = await _db.database;
    if (businessId != null) {
      await db.rawInsert(
        '''
        INSERT INTO item_stock (business_id, item_id, low_stock_threshold, stock_qty, track_inventory)
        VALUES (?, ?, ?, 0, 0)
        ON CONFLICT(business_id, item_id) DO UPDATE SET low_stock_threshold = excluded.low_stock_threshold
        ''',
        [businessId, itemId, threshold],
      );
    }
    await db.update(
      'item_catalog',
      {
        'low_stock_threshold': threshold,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Records an actual physical stock count for [itemId] at [businessId].
  ///
  /// If the count differs from book stock a [StockMovementType.physicalCount]
  /// movement is created so the variance is fully auditable. [last_counted_qty]
  /// and [last_counted_at] are always stamped on [item_stock] — even when there
  /// is no variance — so the inventory screen can show when the item was last
  /// counted.
  Future<void> recordPhysicalCount(
    int itemId,
    double actualQty, {
    String? notes,
    required int businessId,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT stock_qty FROM item_stock WHERE business_id = ? AND item_id = ?',
      [businessId, itemId],
    );
    final bookStock =
        rows.isNotEmpty ? (rows.first['stock_qty'] as num).toDouble() : 0.0;
    final delta = actualQty - bookStock;
    if (delta != 0) {
      await _applyMovement(
        itemId: itemId,
        delta: delta,
        type: StockMovementType.physicalCount,
        notes: notes ??
            'Physical count – actual '
            '${actualQty.toStringAsFixed(actualQty % 1 == 0 ? 0 : 2)}, '
            'book ${bookStock.toStringAsFixed(bookStock % 1 == 0 ? 0 : 2)}',
        businessId: businessId,
      );
    }
    // Always stamp the count date — even when qty matches book.
    final countedAt = DateTime.now().toIso8601String();
    await db.rawInsert(
      '''
      INSERT INTO item_stock
        (business_id, item_id, stock_qty, track_inventory, low_stock_threshold,
         last_counted_qty, last_counted_at)
      VALUES (?, ?, ?, 1, 5, ?, ?)
      ON CONFLICT(business_id, item_id) DO UPDATE SET
        last_counted_qty = excluded.last_counted_qty,
        last_counted_at  = excluded.last_counted_at
      ''',
      [businessId, itemId, actualQty, actualQty, countedAt],
    );
  }

  /// Reverses all stock movements for a given [referenceType] + [referenceId].
  ///
  /// The [business_id] recorded on each original movement is preserved so
  /// reversals are applied to the correct per-company stock.
  Future<void> reverseMovementsFor(
    String referenceType,
    int referenceId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: [referenceType, referenceId],
    );
    for (final row in rows) {
      final itemId = row['item_id'] as int;
      final originalDelta = (row['qty'] as num).toDouble();
      final movementBusinessId = row['business_id'] as int?;
      if (originalDelta == 0) continue;
      await _applyMovement(
        itemId: itemId,
        delta: -originalDelta,
        type: StockMovementType.adjustment,
        notes: 'Reversal of $referenceType #$referenceId',
        referenceId: referenceId,
        referenceType: '${referenceType}_reversal',
        businessId: movementBusinessId,
      );
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _applyMovement({
    required int itemId,
    required double delta,
    required StockMovementType type,
    int? businessId,
    String? notes,
    int? referenceId,
    String? referenceType,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      double currentStock;
      double newStock;

      if (businessId != null) {
        // ── Per-business stock in item_stock ──────────────────────────────
        final rows = await txn.rawQuery(
          'SELECT stock_qty FROM item_stock WHERE business_id = ? AND item_id = ?',
          [businessId, itemId],
        );
        currentStock =
            rows.isNotEmpty ? (rows.first['stock_qty'] as num).toDouble() : 0.0;
        newStock = currentStock + delta;

        await txn.rawInsert(
          '''
          INSERT INTO item_stock
            (business_id, item_id, stock_qty, low_stock_threshold, track_inventory)
          VALUES (?, ?, ?, 5, 1)
          ON CONFLICT(business_id, item_id) DO UPDATE SET stock_qty = excluded.stock_qty
          ''',
          [businessId, itemId, newStock],
        );
      } else {
        // ── Legacy: update item_catalog directly ──────────────────────────
        final rows = await txn.query(
          'item_catalog',
          columns: ['stock_qty'],
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (rows.isEmpty) {
          debugPrint('[Inventory] Item $itemId not found — skipping movement');
          return;
        }
        currentStock = (rows.first['stock_qty'] as num).toDouble();
        newStock = currentStock + delta;
        await txn.update(
          'item_catalog',
          {
            'stock_qty': newStock,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }

      // Record movement
      final movement = StockMovement(
        itemId: itemId,
        businessId: businessId,
        movementType: type,
        qty: delta,
        stockAfter: newStock,
        referenceId: referenceId,
        referenceType: referenceType,
        notes: notes,
        createdAt: DateTime.now(),
      );
      await txn.insert('stock_movements', movement.toMap());

      debugPrint(
        '[Inventory] ${type.label}: '
        '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} '
        '→ stock now ${newStock.toStringAsFixed(2)} '
        'for item $itemId (biz: $businessId)',
      );
    });
  }

  // ── Background-safe static helpers ────────────────────────────────────────

  /// Returns the count of low-stock items across all businesses.
  ///
  /// Uses [item_stock] when available, falling back to [item_catalog].
  static Future<int> countLowStockItemsInBackground(Database db) async {
    // Prefer item_stock (v55+); table may not exist on older schemas.
    try {
      final result = await db.rawQuery(
        'SELECT COUNT(DISTINCT item_id) AS c FROM item_stock '
        'WHERE track_inventory = 1 AND stock_qty <= low_stock_threshold',
      );
      return (result.first['c'] as int? ?? 0);
    } catch (_) {
      // Fallback for pre-v55 databases.
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM item_catalog '
        'WHERE is_active = 1 AND track_inventory = 1 '
        '  AND stock_qty <= low_stock_threshold',
      );
      return (result.first['c'] as int? ?? 0);
    }
  }

  /// Returns low-stock item names for notification body text.
  static Future<List<String>> getLowStockNamesInBackground(
    Database db, {
    int limit = 5,
  }) async {
    try {
      final rows = await db.rawQuery(
        'SELECT DISTINCT ic.name '
        'FROM item_stock ist '
        'JOIN item_catalog ic ON ic.id = ist.item_id '
        'WHERE ist.track_inventory = 1 '
        '  AND ist.stock_qty <= ist.low_stock_threshold '
        '  AND ic.is_active = 1 '
        'ORDER BY ist.stock_qty ASC LIMIT ?',
        [limit],
      );
      return rows.map((r) => r['name'] as String).toList();
    } catch (_) {
      // Fallback for pre-v55 databases.
      final rows = await db.rawQuery(
        'SELECT name FROM item_catalog '
        'WHERE is_active = 1 AND track_inventory = 1 '
        '  AND stock_qty <= low_stock_threshold '
        'ORDER BY stock_qty ASC LIMIT ?',
        [limit],
      );
      return rows.map((r) => r['name'] as String).toList();
    }
  }
}
