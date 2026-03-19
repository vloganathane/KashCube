import 'package:flutter/foundation.dart';

import '../../data/models/party.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/party_repository.dart';

class PartyRepositoryImpl implements PartyRepository {
  PartyRepositoryImpl([DatabaseHelper? dbHelper, this.contextId])
      : _db = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx =>
      contextId == null ? 'context_id IS NULL' : 'context_id = $contextId';

  @override
  Future<int> insert(Party party) async {
    final db = await _db.database;
    final map = party.toMap();
    map['context_id'] = contextId;
    final id = await db.insert('parties', map);
    _db.notifyChange('parties');
    return id;
  }

  @override
  Future<void> update(Party party) async {
    final db = await _db.database;
    await db.update(
      'parties',
      {...party.toMap(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [party.id],
    );
    _db.notifyChange('parties');
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.update(
      'parties',
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _db.notifyChange('parties');
  }

  @override
  Future<Party?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Party.fromMap(rows.first);
  }

  @override
  Future<List<Party>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'parties',
      where: 'deleted_at IS NULL AND $_ctx',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Party.fromMap).toList();
  }

  @override
  Future<List<Party>> getByType(PartyType type) async {
    final db = await _db.database;
    final rows = await db.query(
      'parties',
      where: 'deleted_at IS NULL AND $_ctx AND party_type = ?',
      whereArgs: [type.name],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Party.fromMap).toList();
  }

  @override
  Future<List<Party>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final db = await _db.database;
    final q = '%${query.trim()}%';
    final rows = await db.query(
      'parties',
      where: 'deleted_at IS NULL AND $_ctx AND (name LIKE ? OR phone_number LIKE ?)',
      whereArgs: [q, q],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Party.fromMap).toList();
  }

  @override
  Future<Party> getOrCreate(String name) async {
    final db = await _db.database;
    final trimmed = name.trim();
    final rows = await db.query(
      'parties',
      where: 'deleted_at IS NULL AND $_ctx AND name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isNotEmpty) return Party.fromMap(rows.first);

    final party = Party(name: trimmed, partyType: PartyType.customer);
    final id = await insert(party);
    return party.copyWith(id: id);
  }

  @override
  Future<void> markReminderSent(int transactionId) async {
    final db = await _db.database;
    await db.update(
      'transactions',
      {
        'reminder_sent_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    debugPrint('Reminder sent logged for transaction #$transactionId');
  }

  @override
  Future<List<Party>> getStaffMembers() async {
    final db = await _db.database;
    final rows = await db.query(
      'parties',
      where: "deleted_at IS NULL AND $_ctx AND party_type = 'staff'",
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Party.fromMap).toList();
  }
}
