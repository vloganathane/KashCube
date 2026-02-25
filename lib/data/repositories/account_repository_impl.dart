import 'package:sqflite/sqflite.dart';

import '../../data/models/account.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/account_repository.dart';

/// SQLite implementation of [AccountRepository].
class AccountRepositoryImpl implements AccountRepository {
  final Future<Database> _db = DatabaseHelper.instance.database;

  @override
  Future<List<Account>> getAll({bool activeOnly = true}) async {
    final db = await _db;
    final rows = await db.query(
      'accounts',
      where: activeOnly ? 'is_active = 1 AND deleted_at IS NULL' : 'deleted_at IS NULL',
      orderBy: 'is_primary DESC, account_name ASC',
    );
    return rows.map((r) => Account.fromMap(Map<String, dynamic>.from(r))).toList();
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
    return db.insert('accounts', account.toMap());
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
  }

  @override
  Future<void> setActive(int id, {required bool active}) async {
    final db = await _db;
    await db.update(
      'accounts',
      {'is_active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
