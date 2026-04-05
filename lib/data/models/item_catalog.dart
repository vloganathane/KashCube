import 'package:equatable/equatable.dart';

/// Categories for organizing catalog items
enum ItemCategory {
  product('Product', 'Products', 'PROD'),
  service('Service', 'Services', 'SERV'),
  material('Material', 'Materials', 'MATL'),
  labor('Labor', 'Labor', 'LABR'),
  equipment('Equipment', 'Equipment', 'EQUP'),
  other('Other', 'Other', 'OTHR');

  const ItemCategory(this.label, this.pluralLabel, this.skuPrefix);

  /// Singular label — e.g. "Product", "Service".
  final String label;

  /// Plural label for filter chips and headings — e.g. "Products", "Services".
  final String pluralLabel;

  /// 4-char prefix used in auto-generated SKUs — e.g. "PROD-001".
  final String skuPrefix;
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
    this.brandName,
    this.primaryImagePath,
    this.barcode,
    this.additionalPropertiesJson,
    this.isFavorite = false,
    this.isActive = true,
    this.lastUsedAt,
    this.usageCount = 0,
    this.durationMinutes,
    this.isBookable = false,
    this.trackInventory = false,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.lastCountedQty,
    this.lastCountedAt,
    this.mrp,
    this.dealerPrice,
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
  final String? brandName;
  final String? primaryImagePath;
  final String? barcode;
  final String? additionalPropertiesJson;
  final bool isFavorite;
  final bool isActive;
  final DateTime? lastUsedAt;
  final int usageCount;
  final int? durationMinutes;
  final bool isBookable;
  final bool trackInventory;
  final double stockQty;
  final double lowStockThreshold;

  /// Quantity recorded at the last physical count for this business (read-only overlay from item_stock).
  final double? lastCountedQty;

  /// When the last physical count was recorded.
  final DateTime? lastCountedAt;

  /// Maximum Retail Price — legal ceiling; warn if invoice price exceeds this.
  final double? mrp;

  /// Dealer / trade purchase price — used as default price on purchase bills.
  final double? dealerPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLowStock => trackInventory && stockQty <= lowStockThreshold;

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
    String? brandName,
    String? primaryImagePath,
    String? barcode,
    String? additionalPropertiesJson,
    bool? isFavorite,
    bool? isActive,
    DateTime? lastUsedAt,
    int? usageCount,
    int? durationMinutes,
    bool? isBookable,
    bool? trackInventory,
    double? stockQty,
    double? lowStockThreshold,
    double? lastCountedQty,
    DateTime? lastCountedAt,
    double? mrp,
    double? dealerPrice,
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
      brandName: brandName ?? this.brandName,
      primaryImagePath: primaryImagePath ?? this.primaryImagePath,
      barcode: barcode ?? this.barcode,
      additionalPropertiesJson:
          additionalPropertiesJson ?? this.additionalPropertiesJson,
      isFavorite: isFavorite ?? this.isFavorite,
      isActive: isActive ?? this.isActive,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      usageCount: usageCount ?? this.usageCount,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isBookable: isBookable ?? this.isBookable,
      trackInventory: trackInventory ?? this.trackInventory,
      stockQty: stockQty ?? this.stockQty,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      lastCountedQty: lastCountedQty ?? this.lastCountedQty,
      lastCountedAt: lastCountedAt ?? this.lastCountedAt,
      mrp: mrp ?? this.mrp,
      dealerPrice: dealerPrice ?? this.dealerPrice,
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
    'brand_name': brandName,
    'primary_image_path': primaryImagePath,
    'barcode': barcode,
    'additional_properties_json': additionalPropertiesJson,
    'is_favorite': isFavorite ? 1 : 0,
    'is_active': isActive ? 1 : 0,
    'last_used_at': lastUsedAt?.toIso8601String(),
    'usage_count': usageCount,
    'duration_minutes': durationMinutes,
    'is_bookable': isBookable ? 1 : 0,
    'track_inventory': trackInventory ? 1 : 0,
    'stock_qty': stockQty,
    'low_stock_threshold': lowStockThreshold,
    if (mrp != null) 'mrp': mrp,
    if (dealerPrice != null) 'dealer_price': dealerPrice,
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
    brandName: map['brand_name'] as String?,
    primaryImagePath: map['primary_image_path'] as String?,
    barcode: map['barcode'] as String?,
    additionalPropertiesJson: map['additional_properties_json'] as String?,
    isFavorite: (map['is_favorite'] as int?) == 1,
    isActive: (map['is_active'] as int?) == 1,
    lastUsedAt: map['last_used_at'] != null
        ? DateTime.parse(map['last_used_at'] as String)
        : null,
    usageCount: (map['usage_count'] as int?) ?? 0,
    durationMinutes: map['duration_minutes'] as int?,
    isBookable: (map['is_bookable'] as int?) == 1,
    trackInventory: (map['track_inventory'] as int?) == 1,
    stockQty: (map['stock_qty'] as num?)?.toDouble() ?? 0,
    lowStockThreshold: (map['low_stock_threshold'] as num?)?.toDouble() ?? 5,
    lastCountedQty: (map['last_counted_qty'] as num?)?.toDouble(),
    lastCountedAt: map['last_counted_at'] != null
        ? DateTime.parse(map['last_counted_at'] as String)
        : null,
    mrp: (map['mrp'] as num?)?.toDouble(),
    dealerPrice: (map['dealer_price'] as num?)?.toDouble(),
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
    brandName,
    primaryImagePath,
    barcode,
    additionalPropertiesJson,
    isFavorite,
    isActive,
    lastUsedAt,
    usageCount,
    durationMinutes,
    isBookable,
    trackInventory,
    stockQty,
    lowStockThreshold,
    lastCountedQty,
    lastCountedAt,
    mrp,
    dealerPrice,
    createdAt,
    updatedAt,
  ];
}
