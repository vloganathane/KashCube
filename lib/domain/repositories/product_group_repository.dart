import '../../data/models/product_group.dart';

abstract class ProductGroupRepository {
  Future<List<ProductGroup>> getAll({bool activeOnly = true});
  Future<ProductGroup?> getById(int id);
  Future<int> insert(ProductGroup group);
  Future<void> update(ProductGroup group);
  Future<void> delete(int id);
}
