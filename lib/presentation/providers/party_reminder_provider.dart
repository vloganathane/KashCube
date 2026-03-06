import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/party_reminder.dart';
import '../../data/repositories/party_reminder_repository_impl.dart';
import '../../domain/repositories/party_reminder_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final partyReminderRepositoryProvider = Provider<PartyReminderRepository>(
  (_) => PartyReminderRepositoryImpl(),
);

// ── Per-party reminders (newest first) ───────────────────────────────────────

final partyRemindersProvider =
    FutureProvider.family<List<PartyReminder>, String>((ref, partyName) {
  return ref.read(partyReminderRepositoryProvider).getByParty(partyName);
});

// ── Global recent reminders ───────────────────────────────────────────────────

final recentRemindersProvider = FutureProvider<List<PartyReminder>>((ref) {
  return ref.read(partyReminderRepositoryProvider).getRecent(limit: 50);
});
