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
    this.hsnOrSac = 'HSN',
    this.isFavorite = false,
    this.isActive = true,
    this.lastUsedAt,
    this.usageCount = 0,
    this.durationMinutes,
    this.isBookable = false,
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
  /// 'HSN' for products/materials/equipment, 'SAC' for services/labour.
  /// Stored explicitly so user overrides are preserved.
  final String hsnOrSac;
  final bool isFavorite;
  final bool isActive;
  final DateTime? lastUsedAt;
  final int usageCount;
  final int? durationMinutes;
  final bool isBookable;
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
    String? hsnOrSac,
    bool? isFavorite,
    bool? isActive,
    DateTime? lastUsedAt,
    int? usageCount,
    int? durationMinutes,
    bool? isBookable,
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
      hsnOrSac: hsnOrSac ?? this.hsnOrSac,
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      usageCount: usageCount ?? this.usageCount,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isBookable: isBookable ?? this.isBookable,
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
        'hsn_or_sac': hsnOrSac,
        'is_favorite': isFavorite ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'last_used_at': lastUsedAt?.toIso8601String(),
        'usage_count': usageCount,
        'duration_minutes': durationMinutes,
        'is_bookable': isBookable ? 1 : 0,
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
        hsnOrSac: (map['hsn_or_sac'] as String?) ?? 'HSN',
        isFavorite: (map['is_favorite'] as int?) == 1,
        isActive: (map['is_active'] as int?) == 1,
        lastUsedAt: map['last_used_at'] != null 
            ? DateTime.parse(map['last_used_at'] as String)
            : null,
        usageCount: (map['usage_count'] as int?) ?? 0,
        durationMinutes: map['duration_minutes'] as int?,
        isBookable: (map['is_bookable'] as int?) == 1,
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
        hsnOrSac,
        isFavorite,
        isActive,
        lastUsedAt,
        usageCount,
        durationMinutes,
        isBookable,
        createdAt,
        updatedAt,
      ];
}
