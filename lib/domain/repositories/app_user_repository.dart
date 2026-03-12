import '../../data/models/app_user.dart';
import '../../data/models/user_permission.dart';
import '../models/permission.dart';

abstract class AppUserRepository {
  /// Returns all active app users, sorted by display_name.
  Future<List<AppUser>> getAll();

  /// Returns [AppUser] by primary key, or null if not found.
  Future<AppUser?> getById(int id);

  /// Inserts a new user and returns the inserted row id.
  Future<int> insert(AppUser user);

  /// Updates an existing user (must have non-null [AppUser.id]).
  Future<void> update(AppUser user);

  /// Soft-deactivates a user (sets is_active = 0).
  Future<void> deactivate(int id);

  /// Stamps last_login_at for [id] to now.
  Future<void> recordLogin(int id);

  /// Returns true if any app users exist (used to gate user-selection screen).
  Future<bool> hasAnyUser();

  /// Returns all [UserPermission] rows for [userId].
  Future<List<UserPermission>> getPermissionsForUser(int userId);

  /// Upserts a complete permission set for [userId] × [businessId].
  /// Replaces all existing rows for that (userId, businessId) pair.
  Future<void> setPermissions({
    required int userId,
    required int businessId,
    required List<UserPermission> permissions,
  });

  /// Seeds default permissions for [userId] with [businessId] using [role] preset.
  Future<void> seedRolePreset({
    required int userId,
    required int businessId,
    required AppUserRole role,
  });

  /// Returns the [Permission] for [userId] × [businessId] × [module].
  /// Returns [Permission.none] if no row exists.
  Future<Permission> getPermission({
    required int userId,
    required String module,
    required int businessId,
  });
}
