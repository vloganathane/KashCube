import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/settings_repository.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [SettingsRepository] using the settings table.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  @override
  Future<String?> get(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  @override
  Future<void> set(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> remove(String key) async {
    final db = await _dbHelper.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<Map<String, String>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }
}
