import 'package:equatable/equatable.dart';

/// Type of lot-level stock movement.
enum LotMovementType {
  purchaseIn,
  saleOut,
  challanOut,
  adjustment,
  reversal,
  physicalCount,
}

/// A single quantity change recorded against a [StockLot].
///
/// Works in parallel with [StockMovement] (aggregate) — both tables are
/// updated together so they stay consistent.
class LotMovement extends Equatable {
  const LotMovement({
    this.id,
    required this.businessId,
    required this.itemId,
    required this.lotId,
    required this.movementType,
    required this.qty,
    required this.lotQtyAfter,
    this.referenceType,
    this.referenceId,
    this.referenceLineId,
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int businessId;
  final int itemId;
  final int lotId;
  final LotMovementType movementType;

  /// Quantity delta — positive for inward, negative for outward.
  final double qty;

  /// Absolute remaining quantity on the lot after this movement.
  final double lotQtyAfter;

  final String? referenceType;
  final int? referenceId;

  /// FK to the specific line item (e.g. invoice_items.id) that triggered this.
  final int? referenceLineId;

  final String? notes;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'business_id': businessId,
    'item_id': itemId,
    'lot_id': lotId,
    'movement_type': movementType.name,
    'qty': qty,
    'lot_qty_after': lotQtyAfter,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'reference_line_id': referenceLineId,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  factory LotMovement.fromMap(Map<String, dynamic> m) => LotMovement(
    id: m['id'] as int?,
    businessId: m['business_id'] as int,
    itemId: m['item_id'] as int,
    lotId: m['lot_id'] as int,
    movementType: LotMovementType.values.firstWhere(
      (t) => t.name == (m['movement_type'] as String?),
      orElse: () => LotMovementType.adjustment,
    ),
    qty: (m['qty'] as num).toDouble(),
    lotQtyAfter: (m['lot_qty_after'] as num).toDouble(),
    referenceType: m['reference_type'] as String?,
    referenceId: m['reference_id'] as int?,
    referenceLineId: m['reference_line_id'] as int?,
    notes: m['notes'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  @override
  List<Object?> get props => [id, lotId, movementType, qty, createdAt];
}
