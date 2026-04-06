import 'package:equatable/equatable.dart';

/// Relationship types for product associations.
enum ProductRelationshipType {
  accessory('accessory', 'Accessory', 'Compatible accessories sold separately'),
  sparePart('spare_part', 'Spare Part', 'Replacement parts for this product'),
  consumable('consumable', 'Consumable', 'Regularly purchased consumables'),
  relatedProduct('related_product', 'Related Product', 'Similar or complementary products');

  const ProductRelationshipType(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  static ProductRelationshipType fromString(String value) {
    return ProductRelationshipType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProductRelationshipType.relatedProduct,
    );
  }
}

/// A relationship between two products (e.g., phone → charger accessory).
///
/// Implements schema.org isAccessoryOrSparePartFor and related properties.
class ProductRelationship extends Equatable {
  const ProductRelationship({
    this.id,
    required this.productId,
    required this.relatedProductId,
    required this.relationshipType,
    required this.createdAt,
    this.deletedAt,
  });

  final int? id;

  /// The primary product (e.g., phone).
  final int productId;

  /// The related product (e.g., charger).
  final int relatedProductId;

  /// Type of relationship.
  final ProductRelationshipType relationshipType;

  final DateTime createdAt;
  final DateTime? deletedAt;

  ProductRelationship copyWith({
    int? id,
    int? productId,
    int? relatedProductId,
    ProductRelationshipType? relationshipType,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return ProductRelationship(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      relatedProductId: relatedProductId ?? this.relatedProductId,
      relationshipType: relationshipType ?? this.relationshipType,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'related_product_id': relatedProductId,
        'relationship_type': relationshipType.value,
        'created_at': createdAt.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      };

  factory ProductRelationship.fromMap(Map<String, dynamic> map) =>
      ProductRelationship(
        id: map['id'] as int?,
        productId: map['product_id'] as int,
        relatedProductId: map['related_product_id'] as int,
        relationshipType: ProductRelationshipType.fromString(
          map['relationship_type'] as String,
        ),
        createdAt: DateTime.parse(map['created_at'] as String),
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [
        id,
        productId,
        relatedProductId,
        relationshipType,
        createdAt,
        deletedAt,
      ];
}
