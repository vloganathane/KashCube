import 'package:equatable/equatable.dart';

/// Categories for organizing catalog items
enum ItemCategory {
  product('Product'),
  service('Service'),
  material('Material'),
  labor('Labor'),
  equipment('Equipment'),
  other('Other');

  const ItemCategory(this.label);
  final String label;
}

/// A product or service in the item catalog.
class ItemCatalog extends Equatable {
  const ItemCatalog({
    this.id,
    this.businessId,
    required this.name,
    this.description,
    this.sku,
    this.category = ItemCategory.product,
    this.unit = 'pcs',
    required this.unitPrice,
    this.taxPct = 0,
    this.hsnCode,
    this.isFavorite = false,
    this.isActive = true,
    this.lastUsedAt,
    this.usageCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int? businessId;
  final String name;
  final String? description;
  final String? sku;
  final ItemCategory category;
  final String unit;
  final double unitPrice;
  final double taxPct;
  final String? hsnCode;
  final bool isFavorite;
  final bool isActive;
  final DateTime? lastUsedAt;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  ItemCatalog copyWith({
    int? id,
    int? businessId,
    String? name,
    String? description,
    String? sku,
    ItemCategory? category,
    String? unit,
    double? unitPrice,
    double? taxPct,
    String? hsnCode,
    bool? isFavorite,
    bool? isActive,
    DateTime? lastUsedAt,
    int? usageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItemCatalog(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      description: description ?? this.description,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPct: taxPct ?? this.taxPct,
      hsnCode: hsnCode ?? this.hsnCode,
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (businessId != null) 'business_id': businessId,
        'name': name,
        'description': description,
        'sku': sku,
        'category': category.name,
        'unit': unit,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'hsn_code': hsnCode,
        'is_favorite': isFavorite ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'last_used_at': lastUsedAt?.toIso8601String(),
        'usage_count': usageCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ItemCatalog.fromMap(Map<String, dynamic> map) => ItemCatalog(
        id: map['id'] as int?,
        businessId: map['business_id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String?,
        sku: map['sku'] as String?,
        category: ItemCategory.values.firstWhere(
          (c) => c.name == (map['category'] as String?),
          orElse: () => ItemCategory.product,
        ),
        unit: (map['unit'] as String?) ?? 'pcs',
        unitPrice: (map['unit_price'] as num).toDouble(),
        taxPct: (map['tax_pct'] as num?)?.toDouble() ?? 0,
        hsnCode: map['hsn_code'] as String?,
        isFavorite: (map['is_favorite'] as int?) == 1,
        isActive: (map['is_active'] as int?) == 1,
        lastUsedAt: map['last_used_at'] != null 
            ? DateTime.parse(map['last_used_at'] as String)
            : null,
        usageCount: (map['usage_count'] as int?) ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        businessId,
        name,
        description,
        sku,
        category,
        unit,
        unitPrice,
        taxPct,
        hsnCode,
        isFavorite,
        isActive,
        lastUsedAt,
        usageCount,
      ];
}
