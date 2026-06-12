import 'package:sqflite/sqflite.dart';

import '../../data/models/account.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/account_repository.dart';

/// SQLite implementation of [AccountRepository].
class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl({DatabaseHelper? dbHelper, this.contextId})
    : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<List<Account>> getAll({bool activeOnly = true}) async {
    final db = await _db;
    final rows = await db.query(
      'accounts',
      where: activeOnly
          ? 'is_active = 1 AND deleted_at IS NULL AND $_ctx'
          : 'deleted_at IS NULL AND $_ctx',
      orderBy: 'is_primary DESC, account_name ASC',
    );
    return rows
        .map((r) => Account.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<List<Account>> getByType(
    AccountType type, {
    bool activeOnly = true,
  }) async {
    final db = await _db;
    final where = [
      'account_type = ?',
      'deleted_at IS NULL',
      _ctx,
      if (activeOnly) 'is_active = 1',
    ].join(' AND ');
    final rows = await db.query(
      'accounts',
      where: where,
      whereArgs: [type.dbValue],
      orderBy: 'is_primary DESC, account_name ASC',
    );
    return rows
        .map((r) => Account.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<Account?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Account.fromMap(Map<String, dynamic>.from(rows.first));
  }

  @override
  Future<int> insert(Account account) async {
    final db = await _db;
    final map = account.toMap();
    map['context_id'] = contextId;
    final id = await db.insert('accounts', map);
    _dbHelper.notifyChange('accounts');
    return id;
  }

  @override
  Future<void> update(Account account) async {
    final db = await _db;
    await db.update(
      'accounts',
      account.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
    _dbHelper.notifyChange('accounts');
  }

  @override
  Future<void> setActive(int id, {required bool active}) async {
    final db = await _db;
    await db.update(
      'accounts',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _dbHelper.notifyChange('accounts');
  }
}
