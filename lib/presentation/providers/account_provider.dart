import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../data/repositories/account_repository_impl.dart';
import '../../domain/repositories/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (_) => AccountRepositoryImpl(),
);

/// Provides the list of active accounts.
final accountsProvider =
    StateNotifierProvider<AccountsNotifier, AsyncValue<List<Account>>>(
  (ref) => AccountsNotifier(ref.read(accountRepositoryProvider)),
);

class AccountsNotifier extends StateNotifier<AsyncValue<List<Account>>> {
  AccountsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final AccountRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<void> addAccount(Account account) async {
    await _repo.insert(account);
    await load();
  }

  Future<void> updateAccount(Account account) async {
    await _repo.update(account);
    await load();
  }

  Future<void> setActive(int id, {required bool active}) async {
    await _repo.setActive(id, active: active);
    await load();
  }
}
