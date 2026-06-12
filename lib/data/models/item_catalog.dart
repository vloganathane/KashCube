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
    this.mpn,
    this.availability = 'InStock',
    this.priceCurrency = 'INR',
    this.priceValidUntil,
    this.manufacturerName,
    this.color,
    this.size,
    this.weightValue,
    this.weightUnit = 'g',
    this.widthCm,
    this.heightCm,
    this.depthCm,
    this.material,
    this.keywords,
    this.countryOfOrigin,
    this.releaseDate,
    this.productId,
    this.asin,
    this.logoPath,
    this.pattern,
    this.slogan,
    this.itemCondition = 'NewCondition',
    this.modelNumber,
    this.productGroupId,
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

  // ── P0 schema.org/Product fields ──────────────────────────────────────────

  /// Manufacturer Part Number (schema.org mpn).
  final String? mpn;

  /// Offer availability status (schema.org availability).
  /// Valid values: InStock, OutOfStock, PreOrder, Discontinued.
  final String availability;

  /// ISO 4217 currency code for pricing (schema.org priceCurrency).
  final String priceCurrency;

  /// Date until which the listed price is valid (schema.org priceValidUntil).
  final DateTime? priceValidUntil;

  /// Name of the product manufacturer (schema.org manufacturer.name).
  final String? manufacturerName;

  // ── P1 schema.org/Product fields ──────────────────────────────────────────

  /// Product color (schema.org color).
  final String? color;

  /// Size descriptor (schema.org size).
  final String? size;

  /// Numeric weight value (schema.org weight.value).
  final double? weightValue;

  /// Weight unit: g, kg, oz, lb (schema.org weight.unitCode).
  final String weightUnit;

  /// Width in centimetres (schema.org width).
  final double? widthCm;

  /// Height in centimetres (schema.org height).
  final double? heightCm;

  /// Depth in centimetres (schema.org depth).
  final double? depthCm;

  /// Material composition (schema.org material).
  final String? material;

  /// Comma-separated keywords for search/SEO (schema.org keywords).
  final String? keywords;

  /// ISO 3166-1 alpha-2 country code (schema.org countryOfOrigin).
  final String? countryOfOrigin;

  /// Product launch / release date (schema.org releaseDate).
  final DateTime? releaseDate;

  // ── P2 schema.org/Product fields ──────────────────────────────────────────

  /// Global Trade Item Number or unique product identifier (schema.org productID).
  final String? productId;

  /// Amazon Standard Identification Number (schema.org gtin or asin).
  final String? asin;

  /// Path to product logo image (schema.org logo).
  final String? logoPath;

  /// Pattern or design description (schema.org pattern).
  final String? pattern;

  /// Marketing slogan or tagline (schema.org slogan).
  final String? slogan;

  /// Condition: NewCondition, UsedCondition, RefurbishedCondition, DamagedCondition (schema.org itemCondition).
  final String itemCondition;

  /// Model number or identifier (schema.org model).
  final String? modelNumber;

  // ── P3 schema.org/Product fields ──────────────────────────────────────────

  /// Foreign key to product_groups table for variant management (schema.org isVariantOf).
  final int? productGroupId;

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
    String? mpn,
    String? availability,
    String? priceCurrency,
    DateTime? priceValidUntil,
    String? manufacturerName,
    String? color,
    String? size,
    double? weightValue,
    String? weightUnit,
    double? widthCm,
    double? heightCm,
    double? depthCm,
    String? material,
    String? keywords,
    String? countryOfOrigin,
    DateTime? releaseDate,
    String? productId,
    String? asin,
    String? logoPath,
    String? pattern,
    String? slogan,
    String? itemCondition,
    String? modelNumber,
    int? productGroupId,
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
      mpn: mpn ?? this.mpn,
      availability: availability ?? this.availability,
      priceCurrency: priceCurrency ?? this.priceCurrency,
      priceValidUntil: priceValidUntil ?? this.priceValidUntil,
      manufacturerName: manufacturerName ?? this.manufacturerName,
      color: color ?? this.color,
      size: size ?? this.size,
      weightValue: weightValue ?? this.weightValue,
      weightUnit: weightUnit ?? this.weightUnit,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      depthCm: depthCm ?? this.depthCm,
      material: material ?? this.material,
      keywords: keywords ?? this.keywords,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      releaseDate: releaseDate ?? this.releaseDate,
      productId: productId ?? this.productId,
      asin: asin ?? this.asin,
      logoPath: logoPath ?? this.logoPath,
      pattern: pattern ?? this.pattern,
      slogan: slogan ?? this.slogan,
      itemCondition: itemCondition ?? this.itemCondition,
      modelNumber: modelNumber ?? this.modelNumber,
      productGroupId: productGroupId ?? this.productGroupId,
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
    if (mpn != null) 'mpn': mpn,
    'availability': availability,
    'price_currency': priceCurrency,
    if (priceValidUntil != null)
      'price_valid_until': priceValidUntil!.toIso8601String(),
    if (manufacturerName != null) 'manufacturer_name': manufacturerName,
    if (color != null) 'color': color,
    if (size != null) 'size': size,
    if (weightValue != null) 'weight_value': weightValue,
    'weight_unit': weightUnit,
    if (widthCm != null) 'width_cm': widthCm,
    if (heightCm != null) 'height_cm': heightCm,
    if (depthCm != null) 'depth_cm': depthCm,
    if (material != null) 'material': material,
    if (keywords != null) 'keywords': keywords,
    if (countryOfOrigin != null) 'country_of_origin': countryOfOrigin,
    if (releaseDate != null) 'release_date': releaseDate!.toIso8601String(),
    if (productId != null) 'product_id': productId,
    if (asin != null) 'asin': asin,
    if (logoPath != null) 'logo_path': logoPath,
    if (pattern != null) 'pattern': pattern,
    if (slogan != null) 'slogan': slogan,
    'item_condition': itemCondition,
    if (modelNumber != null) 'model_number': modelNumber,
    if (productGroupId != null) 'product_group_id': productGroupId,
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
    mpn: map['mpn'] as String?,
    availability: (map['availability'] as String?) ?? 'InStock',
    priceCurrency: (map['price_currency'] as String?) ?? 'INR',
    priceValidUntil: map['price_valid_until'] != null
        ? DateTime.parse(map['price_valid_until'] as String)
        : null,
    manufacturerName: map['manufacturer_name'] as String?,
    color: map['color'] as String?,
    size: map['size'] as String?,
    weightValue: (map['weight_value'] as num?)?.toDouble(),
    weightUnit: (map['weight_unit'] as String?) ?? 'g',
    widthCm: (map['width_cm'] as num?)?.toDouble(),
    heightCm: (map['height_cm'] as num?)?.toDouble(),
    depthCm: (map['depth_cm'] as num?)?.toDouble(),
    material: map['material'] as String?,
    keywords: map['keywords'] as String?,
    countryOfOrigin: map['country_of_origin'] as String?,
    releaseDate: map['release_date'] != null
        ? DateTime.parse(map['release_date'] as String)
        : null,
    productId: map['product_id'] as String?,
    asin: map['asin'] as String?,
    logoPath: map['logo_path'] as String?,
    pattern: map['pattern'] as String?,
    slogan: map['slogan'] as String?,
    itemCondition: (map['item_condition'] as String?) ?? 'NewCondition',
    modelNumber: map['model_number'] as String?,
    productGroupId: map['product_group_id'] as int?,
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
    mpn,
    availability,
    priceCurrency,
    priceValidUntil,
    manufacturerName,
    color,
    size,
    weightValue,
    weightUnit,
    widthCm,
    heightCm,
    depthCm,
    material,
    keywords,
    countryOfOrigin,
    releaseDate,
    productId,
    asin,
    logoPath,
    pattern,
    slogan,
    itemCondition,
    modelNumber,
    productGroupId,
    createdAt,
    updatedAt,
  ];
}
