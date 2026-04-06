import '../../data/models/product_relationship.dart';

abstract class ProductRelationshipRepository {
  Future<List<ProductRelationship>> getAllForProduct(int productId);
  Future<ProductRelationship?> getById(int id);
  Future<int> insert(ProductRelationship relationship);
  Future<void> delete(int id);
}
