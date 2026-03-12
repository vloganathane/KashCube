import 'package:equatable/equatable.dart';

/// Type of stock movement.
enum StockMovementType {
  stockIn('Stock In'),
  stockOut('Stock Out'),
  adjustment('Adjustment'),
  opening('Opening Stock'),
  saleDeduction('Sale'),
  purchaseAddition('Purchase'),
  physicalCount('Physical Count');

  const StockMovementType(this.label);
  final String label;
}

/// A single stock movement event for an inventory item.
class StockMovement extends Equatable {
  const StockMovement({
    this.id,
    required this.itemId,
    this.businessId,
    required this.movementType,
    required this.qty,
    required this.stockAfter,
    this.referenceId,
    this.referenceType,
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int itemId;
  /// Which business's stock this movement belongs to. Null for legacy
  /// movements recorded before the per-business stock (v55) migration.
  final int? businessId;
  final StockMovementType movementType;
  final double qty;
  final double stockAfter;
  final int? referenceId;
  final String? referenceType;
  final String? notes;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'item_id': itemId,
        'business_id': businessId,
        'movement_type': movementType.name,
        'qty': qty,
        'stock_after': stockAfter,
        'reference_id': referenceId,
        'reference_type': referenceType,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };

  factory StockMovement.fromMap(Map<String, dynamic> map) => StockMovement(
        id: map['id'] as int?,
        itemId: map['item_id'] as int,
        businessId: map['business_id'] as int?,
        movementType: StockMovementType.values.firstWhere(
          (t) => t.name == (map['movement_type'] as String?),
          orElse: () => StockMovementType.adjustment,
        ),
        qty: (map['qty'] as num).toDouble(),
        stockAfter: (map['stock_after'] as num).toDouble(),
        referenceId: map['reference_id'] as int?,
        referenceType: map['reference_type'] as String?,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, itemId, businessId, movementType, qty, stockAfter, referenceId, referenceType, notes, createdAt];
}
