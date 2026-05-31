import '../../data/models/document_template_record.dart';
import '../../domain/repositories/document_template_repository.dart';
import '../services/database_helper.dart';

/// SQLite-backed implementation of [DocumentTemplateRepository].
class DocumentTemplateRepositoryImpl implements DocumentTemplateRepository {
  DocumentTemplateRepositoryImpl([DatabaseHelper? dbHelper])
    : _db = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  static const _table = 'document_templates';

  @override
  Future<List<DocumentTemplateRecord>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(_table, orderBy: 'is_preset DESC, name ASC');
    return rows.map(DocumentTemplateRecord.fromMap).toList();
  }

  @override
  Future<DocumentTemplateRecord?> getActive() async {
    final db = await _db.database;
    final rows = await db.query(_table, where: 'is_active = 1', limit: 1);
    if (rows.isEmpty) return null;
    return DocumentTemplateRecord.fromMap(rows.first);
  }

  @override
  Future<int> insert(DocumentTemplateRecord record) async {
    final db = await _db.database;
    return db.insert(_table, record.toMap());
  }

  @override
  Future<void> update(DocumentTemplateRecord record) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      if (record.isActive) {
        await txn.update(
          _table,
          {'is_active': 0},
          where: 'id != ?',
          whereArgs: [record.id],
        );
      }
      await txn.update(
        _table,
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: const ['is_active', 'is_preset'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.first['is_preset'] == 1) return;

      final wasActive = rows.first['is_active'] == 1;
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      if (wasActive) {
        await txn.update(_table, {'is_active': 0});
        await txn.update(_table, {
          'is_active': 1,
        }, where: "is_preset = 1 AND based_on = 'modern'");
      }
    });
  }

  @override
  Future<void> setActive(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final targetRows = await txn.query(
        _table,
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (targetRows.isEmpty) {
        throw StateError('Document template $id does not exist.');
      }

      await txn.update(_table, {'is_active': 0});
      final updated = await txn.update(
        _table,
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated != 1) {
        throw StateError('Failed to activate document template $id.');
      }
    });
  }
}
