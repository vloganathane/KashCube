import '../../data/models/business.dart';

abstract class BusinessRepository {
  Future<List<Business>> getAll();

  Future<Business?> getActive();

  Future<Business?> getById(int id);

  /// Inserts a new business. If [setActive] is true, all others are deactivated.
  Future<int> insert(Business business, {bool setActive = false});

  Future<void> update(Business business);

  Future<void> delete(int id);

  /// Marks [id] as the active business, deactivating all others.
  Future<void> setActive(int id);
}
