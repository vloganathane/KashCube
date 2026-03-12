import 'package:sqflite/sqflite.dart';

import '../../data/models/app_user.dart';
import '../../data/models/user_permission.dart';
import '../../data/services/database_helper.dart';
import '../../domain/models/permission.dart';
import '../../domain/repositories/app_user_repository.dart';

class AppUserRepositoryImpl implements AppUserRepository {
  final DatabaseHelper _dbHelper;

  AppUserRepositoryImpl({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  // ── AppUser CRUD ────────────────────────────────────────────────────────────

  @override
  Future<List<AppUser>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'app_users',
      where: 'is_active = 1',
      orderBy: 'display_name ASC',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  @override
  Future<AppUser?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'app_users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  @override
  Future<int> insert(AppUser user) async {
    final db = await _db;
    return db.insert('app_users', user.toMap());
  }

  @override
  Future<void> update(AppUser user) async {
    final db = await _db;
    final map = user.toMap()
      ..['updated_at'] = DateTime.now().toIso8601String();
    await db.update('app_users', map, where: 'id = ?', whereArgs: [user.id]);
  }

  @override
  Future<void> deactivate(int id) async {
    final db = await _db;
    await db.update(
      'app_users',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> recordLogin(int id) async {
    final db = await _db;
    await db.update(
      'app_users',
      {'last_login_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<bool> hasAnyUser() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM app_users WHERE is_active = 1',
    );
    return (result.first['count'] as int) > 0;
  }

  // ── Permissions ─────────────────────────────────────────────────────────────

  @override
  Future<List<UserPermission>> getPermissionsForUser(int userId) async {
    final db = await _db;
    final rows = await db.query(
      'user_permissions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'business_id ASC, module ASC',
    );
    return rows.map(UserPermission.fromMap).toList();
  }

  @override
  Future<void> setPermissions({
    required int userId,
    required int businessId,
    required List<UserPermission> permissions,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'user_permissions',
        where: 'user_id = ? AND business_id = ?',
        whereArgs: [userId, businessId],
      );
      for (final perm in permissions) {
        await txn.insert('user_permissions', perm.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> seedRolePreset({
    required int userId,
    required int businessId,
    required AppUserRole role,
  }) async {
    final rows = RolePreset.seedRows(
      userId: userId,
      businessId: businessId,
      role: role,
    );
    final db = await _db;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.insert(
          'user_permissions',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<Permission> getPermission({
    required int userId,
    required String module,
    required int businessId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'user_permissions',
      where: 'user_id = ? AND business_id = ? AND module = ?',
      whereArgs: [userId, businessId, module],
      limit: 1,
    );
    if (rows.isEmpty) return Permission.none;
    final r = rows.first;
    return Permission(
      canView:   (r['can_view']   as int? ?? 0) == 1,
      canCreate: (r['can_create'] as int? ?? 0) == 1,
      canEdit:   (r['can_edit']   as int? ?? 0) == 1,
      canDelete: (r['can_delete'] as int? ?? 0) == 1,
    );
  }
}
