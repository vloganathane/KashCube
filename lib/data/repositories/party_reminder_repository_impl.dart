import '../models/party_reminder.dart';
import '../services/database_helper.dart';
import '../../domain/repositories/party_reminder_repository.dart';

class PartyReminderRepositoryImpl implements PartyReminderRepository {
  PartyReminderRepositoryImpl([DatabaseHelper? helper])
      : _db = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  @override
  Future<int> insert(PartyReminder reminder) async {
    final db = await _db.database;
    return db.insert('party_reminders', reminder.toMap());
  }

  @override
  Future<List<PartyReminder>> getByParty(String partyName) async {
    final db = await _db.database;
    final rows = await db.query(
      'party_reminders',
      where: 'party_name = ?',
      whereArgs: [partyName],
      orderBy: 'sent_at DESC',
    );
    return rows.map(PartyReminder.fromMap).toList();
  }

  @override
  Future<List<PartyReminder>> getRecent({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'party_reminders',
      orderBy: 'sent_at DESC',
      limit: limit,
    );
    return rows.map(PartyReminder.fromMap).toList();
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('party_reminders', where: 'id = ?', whereArgs: [id]);
  }
}
