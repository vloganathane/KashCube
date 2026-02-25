import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/notification_service.dart';
import 'upcoming_provider.dart';

// ---------------------------------------------------------------------------
// Notification Provider
// ---------------------------------------------------------------------------
// Provides the NotificationService singleton and wires upcoming-items changes
// into the scheduler so notifications always stay in sync.
// ---------------------------------------------------------------------------

/// The singleton [NotificationService] instance, pre-initialized.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

/// Watches [upcomingItemsProvider] and re-schedules notifications whenever
/// the list of upcoming items changes.
///
/// Activate this provider once from the root widget:
///   ```dart
///   ref.watch(notificationSchedulerProvider);
///   ```
final notificationSchedulerProvider = Provider<void>((ref) {
  final upcoming = ref.watch(upcomingItemsProvider);
  upcoming.whenData((items) async {
    final svc = ref.read(notificationServiceProvider);
    await svc.scheduleUpcomingNotifications(items);
  });
});
