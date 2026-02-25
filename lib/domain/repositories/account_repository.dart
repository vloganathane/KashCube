import '../../data/models/account.dart';

/// Abstract interface for account data access.
abstract class AccountRepository {
  Future<List<Account>> getAll({bool activeOnly = true});
  Future<Account?> getById(int id);
  Future<int> insert(Account account);
  Future<void> update(Account account);
  Future<void> setActive(int id, {required bool active});
}
