import 'package:equatable/equatable.dart';

/// A customer review for a product.
///
/// Implements schema.org Review and supports aggregateRating calculations.
class ProductReview extends Equatable {
  const ProductReview({
    this.id,
    required this.productId,
    required this.rating,
    this.reviewText,
    this.reviewerName,
    required this.createdAt,
    this.deletedAt,
  });

  final int? id;

  /// Foreign key to item_catalog.
  final int productId;

  /// Star rating (1-5).
  final int rating;

  /// Optional review text.
  final String? reviewText;

  /// Name of the reviewer (nullable for anonymous reviews).
  final String? reviewerName;

  final DateTime createdAt;
  final DateTime? deletedAt;

  ProductReview copyWith({
    int? id,
    int? productId,
    int? rating,
    String? reviewText,
    String? reviewerName,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return ProductReview(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      rating: rating ?? this.rating,
      reviewText: reviewText ?? this.reviewText,
      reviewerName: reviewerName ?? this.reviewerName,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'product_id': productId,
    'rating': rating,
    if (reviewText != null) 'review_text': reviewText,
    if (reviewerName != null) 'reviewer_name': reviewerName,
    'created_at': createdAt.toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
  };

  factory ProductReview.fromMap(Map<String, dynamic> map) => ProductReview(
    id: map['id'] as int?,
    productId: map['product_id'] as int,
    rating: map['rating'] as int,
    reviewText: map['review_text'] as String?,
    reviewerName: map['reviewer_name'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    deletedAt: map['deleted_at'] != null
        ? DateTime.parse(map['deleted_at'] as String)
        : null,
  );

  @override
  List<Object?> get props => [
    id,
    productId,
    rating,
    reviewText,
    reviewerName,
    createdAt,
    deletedAt,
  ];
}
