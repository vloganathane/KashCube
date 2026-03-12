import 'package:equatable/equatable.dart';

/// Per-business stock record for an item in the master catalog.
///
/// Stores the three mutable inventory values (quantity, threshold, tracking
/// flag) separately from [ItemCatalog] so that the same catalog entry can
/// have independent stock levels across multiple business profiles.
class ItemStock extends Equatable {
  const ItemStock({
    required this.businessId,
    required this.itemId,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.trackInventory = false,
    this.lastCountedQty,
    this.lastCountedAt,
  });

  final int businessId;
  final int itemId;
  final double stockQty;
  final double lowStockThreshold;
  final bool trackInventory;
  /// Quantity entered at the last physical stock count for this business.
  final double? lastCountedQty;
  /// When the last physical count was recorded.
  final DateTime? lastCountedAt;

  bool get isLowStock => trackInventory && stockQty <= lowStockThreshold;

  ItemStock copyWith({
    double? stockQty,
    double? lowStockThreshold,
    bool? trackInventory,
    double? lastCountedQty,
    DateTime? lastCountedAt,
  }) =>
      ItemStock(
        businessId: businessId,
        itemId: itemId,
        stockQty: stockQty ?? this.stockQty,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        trackInventory: trackInventory ?? this.trackInventory,
        lastCountedQty: lastCountedQty ?? this.lastCountedQty,
        lastCountedAt: lastCountedAt ?? this.lastCountedAt,
      );

  Map<String, dynamic> toMap() => {
        'business_id': businessId,
        'item_id': itemId,
        'stock_qty': stockQty,
        'low_stock_threshold': lowStockThreshold,
        'track_inventory': trackInventory ? 1 : 0,
        if (lastCountedQty != null) 'last_counted_qty': lastCountedQty,
        if (lastCountedAt != null)
          'last_counted_at': lastCountedAt!.toIso8601String(),
      };

  factory ItemStock.fromMap(Map<String, dynamic> map) => ItemStock(
        businessId: map['business_id'] as int,
        itemId: map['item_id'] as int,
        stockQty: (map['stock_qty'] as num?)?.toDouble() ?? 0,
        lowStockThreshold:
            (map['low_stock_threshold'] as num?)?.toDouble() ?? 5,
        trackInventory: (map['track_inventory'] as int?) == 1,
        lastCountedQty: (map['last_counted_qty'] as num?)?.toDouble(),
        lastCountedAt: map['last_counted_at'] != null
            ? DateTime.parse(map['last_counted_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [
        businessId,
        itemId,
        stockQty,
        lowStockThreshold,
        trackInventory,
        lastCountedQty,
        lastCountedAt,
      ];
}
