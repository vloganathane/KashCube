import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/currency_formatter.dart';
import '../../presentation/providers/upcoming_provider.dart';

// ---------------------------------------------------------------------------
// KashCube Notification Service
// ---------------------------------------------------------------------------
// Handles ALL local notification scheduling for upcoming loan EMIs and bills.
// 100% on-device — no network calls, no analytics.
// ---------------------------------------------------------------------------

const _channelId = 'kash_upcoming';
const _channelName = 'Upcoming Payments';
const _channelDesc =
    'Reminders for upcoming loan EMI repayments and bill due dates';

/// Base IDs to prevent collision between scheduled payments and loans.
/// Scheduled: 10_000 + payment.id
/// Loans (due):  20_000 + loan.id
/// Loans (day−1): 25_000 + loan.id
/// Scheduled (day−1): 15_000 + payment.id
const _billBase = 10000;
const _loanBase = 20000;
const _dayBeforeOffset = 5000;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Initialise ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    // Set up timezone database (IST = Asia/Kolkata)
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (_) {
        // Notifications are informational only — no deep-link needed yet.
      },
    );

    _initialized = true;
    debugPrint('[Notifications] Service initialized (IST timezone)');
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Requests POST_NOTIFICATIONS permission on Android 13+ (API 33+).
  /// Safe to call repeatedly; no-op if already granted.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    debugPrint('[Notifications] Permission granted: $granted');
    return granted;
  }

  // ── Schedule ───────────────────────────────────────────────────────────────

  /// Cancels all existing upcoming notifications and reschedules from [items].
  ///
  /// Strategy:
  ///  • Overdue items → skipped (visible on home screen, no noise).
  ///  • Due today:    → notification at 9:00 AM (if 9 AM is still in future).
  ///  • Due in 1 day  → notification at 9:00 AM tomorrow.
  ///  • Due in 2+ days→ notification at 9:00 AM on due date
  ///                     + "1 day before" at 9:00 AM the day prior.
  Future<void> scheduleUpcomingNotifications(
      List<UpcomingItem> items) async {
    if (!_initialized) await initialize();
    await cancelAll();

    final now = tz.TZDateTime.now(tz.local);

    for (final item in items) {
      if (item.isOverdue) continue;

      final due = item.dueDate;
      // 9:00 AM IST on the due date
      final dueMorning = tz.TZDateTime(
          tz.local, due.year, due.month, due.day, 9, 0, 0);

      final (int baseId, String title, String body) = switch (item) {
        LoanUpcomingItem l => (
            _loanBase + (l.loan.id ?? 0),
            l.loan.isLent
                ? 'Collect from ${l.loan.lenderName}'
                : 'Pay back ${l.loan.lenderName}',
            '${CurrencyFormatter.format(l.paymentAmount)} installment due',
          ),
        ScheduledUpcomingItem b => (
            _billBase + (b.payment.id ?? 0),
            b.payment.name,
            '${CurrencyFormatter.format(b.payment.amount)} due',
          ),
      };

      // ── Due-date notification ──
      if (dueMorning.isAfter(now)) {
        await _scheduleOne(
          id: baseId,
          title: title,
          body: '$body today',
          at: dueMorning,
          important: true,
        );
      }

      // ── 1-day-before notification ──
      if (item.daysUntilDue >= 2) {
        final dayBefore = dueMorning.subtract(const Duration(days: 1));
        if (dayBefore.isAfter(now)) {
          await _scheduleOne(
            id: baseId + _dayBeforeOffset,
            title: title,
            body: '$body tomorrow',
            at: dayBefore,
            important: false,
          );
        }
      }
    }

    debugPrint(
        '[Notifications] Scheduled ${items.where((i) => !i.isOverdue).length} upcoming reminders');
  }

  // ── Cancel ─────────────────────────────────────────────────────────────────

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required bool important,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: important ? Importance.high : Importance.defaultImportance,
        priority: important ? Priority.high : Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
