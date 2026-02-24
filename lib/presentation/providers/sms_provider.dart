import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/parsed_sms.dart';
import '../../data/services/sms_service.dart';

/// Provider for the SMS service instance.
final smsServiceProvider = Provider<SmsService>((ref) {
  return SmsService.instance;
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

  void removePending(ParsedSms parsed) {
    state = state.where((s) => s.smsBody != parsed.smsBody).toList();
  }

  void clear() {
    state = [];
  }
}
