import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/item_catalog.dart';
import '../models/stock_movement.dart';
import 'database_helper.dart';

/// Service for inventory stock tracking.
///
/// Handles stock adjustments on [item_catalog] and records every change
/// in [stock_movements]. All operations run atomically inside a transaction
/// so stock_qty and movement history are always consistent.
class InventoryService {
  InventoryService._();
  static final InventoryService instance = InventoryService._();

  final _db = DatabaseHelper.instance;

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All items that have inventory tracking enabled (active items only).
  Future<List<ItemCatalog>> getTrackedItems({int? businessId}) async {
    final db = await _db.database;
    final conditions = <String>['is_active = 1', 'track_inventory = 1'];
    final args = <dynamic>[];
    if (businessId != null) {
      conditions.add('(business_id = ? OR business_id IS NULL)');
      args.add(businessId);
    }
    final where = conditions.join(' AND ');
    final rows = await db.rawQuery(
      'SELECT * FROM item_catalog WHERE $where ORDER BY name COLLATE NOCASE',
      args,
    );
    return rows.map(ItemCatalog.fromMap).toList();
  }

  /// Items where stock_qty <= low_stock_threshold (and tracking is on).
  Future<List<ItemCatalog>> getLowStockItems({int? businessId}) async {
    final db = await _db.database;
    final conditions = <String>[
      'is_active = 1',
      'track_inventory = 1',
      'stock_qty <= low_stock_threshold',
    ];
    final args = <dynamic>[];
    if (businessId != null) {
      conditions.add('(business_id = ? OR business_id IS NULL)');
      args.add(businessId);
    }
    final where = conditions.join(' AND ');
    final rows = await db.rawQuery(
      'SELECT * FROM item_catalog WHERE $where ORDER BY stock_qty ASC',
      args,
    );
    return rows.map(ItemCatalog.fromMap).toList();
  }

  /// Recent movements for a specific item (newest first).
  Future<List<StockMovement>> getMovementsForItem(
    int itemId, {
    int limit = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT * FROM stock_movements WHERE item_id = ? ORDER BY created_at DESC LIMIT ?',
      [itemId, limit],
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Adds stock to an item (positive qty).
  Future<void> addStock(
    int itemId,
    double qty, {
    String? notes,
    int? referenceId,
    String? referenceType,
  }) async {
    assert(qty > 0, 'addStock qty must be positive');
    await _applyMovement(
      itemId: itemId,
      delta: qty,
      type: referenceType == 'purchase'
          ? StockMovementType.purchaseAddition
          : StockMovementType.stockIn,
      notes: notes,
      referenceId: referenceId,
      referenceType: referenceType,
    );
  }

  /// Deducts stock from an item (positive qty = amount to remove).
  Future<void> deductStock(
    int itemId,
    double qty, {
    String? notes,
    int? referenceId,
    String? referenceType,
  }) async {
    assert(qty > 0, 'deductStock qty must be positive');
    await _applyMovement(
      itemId: itemId,
      delta: -qty,
      type: referenceType == 'sale'
          ? StockMovementType.saleDeduction
          : StockMovementType.stockOut,
      notes: notes,
      referenceId: referenceId,
      referenceType: referenceType,
    );
  }

  /// Sets stock to an absolute value (creates an adjustment movement).
  Future<void> setStock(
    int itemId,
    double newQty, {
    String? notes,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'item_catalog',
      columns: ['stock_qty'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (rows.isEmpty) return;
    final current = (rows.first['stock_qty'] as num).toDouble();
    final delta = newQty - current;
    if (delta == 0) return;
    await _applyMovement(
      itemId: itemId,
      delta: delta,
      type: StockMovementType.adjustment,
      notes: notes ?? 'Manual adjustment',
    );
  }

  /// Enables or disables inventory tracking for an item without touching stock_qty.
  Future<void> setTrackInventory(int itemId, {required bool track}) async {
    final db = await _db.database;
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

  /// Sets the low-stock alert threshold for an item.
  Future<void> setLowStockThreshold(int itemId, double threshold) async {
    final db = await _db.database;
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

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _applyMovement({
    required int itemId,
    required double delta,
    required StockMovementType type,
    String? notes,
    int? referenceId,
    String? referenceType,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Read current stock
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
      final currentStock = (rows.first['stock_qty'] as num).toDouble();
      final newStock = currentStock + delta;

      // Update item stock
      await txn.update(
        'item_catalog',
        {
          'stock_qty': newStock,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      // Record movement
      final movement = StockMovement(
        itemId: itemId,
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
        '[Inventory] ${type.label}: ${'${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)}'} '
        '→ stock now ${newStock.toStringAsFixed(2)} for item $itemId',
      );
    });
  }

  /// Returns the count of low-stock items across all businesses.
  /// Used by WorkManager background task — opens the DB directly.
  static Future<int> countLowStockItemsInBackground(Database db) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM item_catalog '
      'WHERE is_active = 1 AND track_inventory = 1 AND stock_qty <= low_stock_threshold',
    );
    return (result.first['c'] as int? ?? 0);
  }

  /// Returns low-stock item names for notification body text.
  static Future<List<String>> getLowStockNamesInBackground(
    Database db, {
    int limit = 5,
  }) async {
    final rows = await db.rawQuery(
      'SELECT name FROM item_catalog '
      'WHERE is_active = 1 AND track_inventory = 1 AND stock_qty <= low_stock_threshold '
      'ORDER BY stock_qty ASC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['name'] as String).toList();
  }
}
