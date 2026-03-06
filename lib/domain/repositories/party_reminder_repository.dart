import '../../data/models/party_reminder.dart';

/// Repository interface for party reminder history.
abstract class PartyReminderRepository {
  /// Persists a new reminder and returns its generated row id.
  Future<int> insert(PartyReminder reminder);

  /// Returns all reminders for [partyName], newest first.
  Future<List<PartyReminder>> getByParty(String partyName);

  /// Returns the most recent [limit] reminders across all parties, newest first.
  Future<List<PartyReminder>> getRecent({int limit = 50});

  /// Permanently removes a reminder by [id].
  Future<void> delete(int id);
}
