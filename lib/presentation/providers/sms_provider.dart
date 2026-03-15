import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/parsed_sms.dart';
import '../../data/services/sms_parser.dart';
import '../../data/services/sms_parser_service.dart';
import '../../data/services/sms_service.dart';
import '../providers/transaction_provider.dart';

/// Provider for the injectable SMS parser service.
///
/// Inject this into [SmsService] rather than calling [SmsParser] statics
/// directly — doing so allows mocking in unit tests.
final smsParserProvider = Provider<SmsParserService>((_) => const SmsParserService());

/// Provider for the SMS service instance.
final smsServiceProvider = Provider<SmsService>((ref) {
  return SmsService(parser: ref.read(smsParserProvider));
});

/// Provider for SMS permission status.
final smsPermissionProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(smsServiceProvider);
  return service.hasPermission;
});

/// Provider to read and parse existing SMS from inbox.
final existingSmsProvider = FutureProvider<List<ParsedSms>>((ref) async {
  final service = ref.read(smsServiceProvider);
  final hasPermission = await service.hasPermission;
  if (!hasPermission) return [];
  return service.readExistingSms();
});

/// Notifier that manages pending SMS confirmations.
///
/// When SMS auto-detection finds a transaction, it's added here
/// for the user to confirm/reject before saving.
final pendingSmsConfirmationsProvider =
    StateNotifierProvider<PendingSmsNotifier, List<ParsedSms>>(
  (ref) => PendingSmsNotifier(),
);

class PendingSmsNotifier extends StateNotifier<List<ParsedSms>> {
  PendingSmsNotifier() : super([]);

  void addPending(ParsedSms parsed) {
    // Avoid duplicates
    if (state.any((s) => s.smsBody == parsed.smsBody)) return;
    state = [...state, parsed];
  }

  void addAllPending(List<ParsedSms> items) {
    final existing = state.map((s) => s.smsBody).toSet();
    final newItems = items.where((s) => !existing.contains(s.smsBody)).toList();
    if (newItems.isEmpty) return;
    state = [...state, ...newItems];
  }

  void removePending(ParsedSms parsed) {
    state = state.where((s) => s.smsBody != parsed.smsBody).toList();
  }

  void clear() {
    state = [];
  }
}

// ---------------------------------------------------------------------------
// Inbox scan state
// ---------------------------------------------------------------------------

/// SharedPreferences key for the last inbox scan timestamp (ISO-8601).
const _kLastScanKey = 'sms_last_inbox_scan';

/// Whether an inbox scan is currently in progress.
final smsScanningProvider = StateProvider<bool>((ref) => false);

/// Timestamp of the last successful inbox scan (null = never scanned).
final smsLastScanProvider = StateNotifierProvider<_LastScanNotifier, DateTime?>(
  (ref) => _LastScanNotifier(),
);

class _LastScanNotifier extends StateNotifier<DateTime?> {
  _LastScanNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastScanKey);
    if (raw != null) state = DateTime.tryParse(raw);
  }

  Future<void> setNow() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastScanKey, now.toIso8601String());
    state = now;
  }
}

/// Scans the SMS inbox, deduplicates against saved transactions, and enqueues
/// new matches in [pendingSmsConfirmationsProvider].
///
/// Returns the count of newly found (not yet saved) transactions.
Future<int> scanSmsInbox(WidgetRef ref) async {
  final smsService = ref.read(smsServiceProvider);
  final hasPermission = await smsService.hasPermission;
  if (!hasPermission) return 0;

  ref.read(smsScanningProvider.notifier).state = true;
  try {
    final parsed = await smsService.readExistingSms(maxCount: 300);
    final repo = ref.read(transactionRepositoryProvider);

    final fresh = <ParsedSms>[];
    for (final p in parsed) {
      final hash = SmsParser.generateDedupeHash(p);
      final exists = await repo.existsByDedupeHash(hash);
      if (!exists) fresh.add(p);
    }

    ref.read(pendingSmsConfirmationsProvider.notifier).addAllPending(fresh);
    await ref.read(smsLastScanProvider.notifier).setNow();
    return fresh.length;
  } finally {
    ref.read(smsScanningProvider.notifier).state = false;
  }
}

