import '../../data/models/product_review.dart';

abstract class ProductReviewRepository {
  Future<List<ProductReview>> getAllForProduct(int productId);
  Future<ProductReview?> getById(int id);
  Future<int> insert(ProductReview review);
  Future<void> delete(int id);
  Future<Map<String, dynamic>> getAggregateRating(int productId);
}
