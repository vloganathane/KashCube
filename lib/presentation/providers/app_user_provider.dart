import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/models/user_permission.dart';
import '../../data/repositories/app_user_repository_impl.dart';
import '../../domain/models/permission.dart';
import '../../domain/repositories/app_user_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final appUserRepositoryProvider = Provider<AppUserRepository>(
  (ref) => AppUserRepositoryImpl(),
);

// ── Active session ────────────────────────────────────────────────────────────

/// The currently authenticated app user.
/// null = owner (device PIN / biometric — full access).
/// Non-null = a staff AppUser (restricted by their permissions).
final activeAppUserProvider = StateProvider<AppUser?>((ref) => null);

// ── User list ─────────────────────────────────────────────────────────────────

final appUsersProvider =
    StateNotifierProvider<AppUsersNotifier, AsyncValue<List<AppUser>>>(
  (ref) => AppUsersNotifier(ref.read(appUserRepositoryProvider)),
);

class AppUsersNotifier extends StateNotifier<AsyncValue<List<AppUser>>> {
  final AppUserRepository _repository;

  AppUsersNotifier(this._repository) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repository.getAll());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<int> add(AppUser user) async {
    try {
      final id = await _repository.insert(user);
      await load();
      return id;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> save(AppUser user) async {
    try {
      await _repository.update(user);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deactivate(int id) async {
    try {
      await _repository.deactivate(id);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

// ── Has-any-user flag (used by _LockGate to decide if UserSelectionScreen needed) ─

final hasAnyAppUserProvider = FutureProvider<bool>(
  (ref) => ref.watch(appUserRepositoryProvider).hasAnyUser(),
);

// ── Permission lookup ─────────────────────────────────────────────────────────

/// Returns the resolved [Permission] for the given module + businessId.
/// Owner (activeAppUserProvider == null) always gets [Permission.full].
final permissionProvider = Provider.family<
    Future<Permission>, ({String module, int businessId})>(
  (ref, arg) async {
    final user = ref.watch(activeAppUserProvider);
    if (user == null) return Permission.full;
    return ref
        .read(appUserRepositoryProvider)
        .getPermission(userId: user.id!, module: arg.module, businessId: arg.businessId);
  },
);

// ── Permissions for a specific user (used by ManageUsersScreen / UserPermissionsScreen) ─

final userPermissionsProvider =
    FutureProvider.family<List<UserPermission>, int>(
  (ref, userId) =>
      ref.read(appUserRepositoryProvider).getPermissionsForUser(userId),
);
