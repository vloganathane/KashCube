import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/currency_formatter.dart';
import '../../data/models/booking.dart';
import '../../data/services/fiscal_year_service.dart';
import '../../data/services/encrypted_backup_service.dart';
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
// Bookings: 30_000 + booking.id
const _bookingBase = 30000;
// Fiscal year alerts: 40_000
const _fyBase = 40000;
// Backup reminder: 50_000
const _backupBase = 50000;

const _bookingChannelId = 'kash_bookings';
const _bookingChannelName = 'Booking Reminders';
const _bookingChannelDesc =
    'Reminders 24 hours before confirmed appointment or reservation';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Initialise ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    // Set up timezone database (IST = Asia/Kolkata)
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // macOS (and iOS) share DarwinInitializationSettings.
    // Request alert/badge/sound so notifications appear in Notification Center.
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, macOS: darwinInit),
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
    if (kIsWeb) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
  Future<void> scheduleUpcomingNotifications(List<UpcomingItem> items) async {
    if (!_initialized) await initialize();
    await cancelAll();

    final now = tz.TZDateTime.now(tz.local);

    for (final item in items) {
      if (item.isOverdue) continue;

      final due = item.dueDate;
      // 9:00 AM IST on the due date
      final dueMorning = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day,
        9,
        0,
        0,
      );

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
      '[Notifications] Scheduled ${items.where((i) => !i.isOverdue).length} upcoming reminders',
    );
  }

  // ── Bookings ───────────────────────────────────────────────────────────────

  /// Schedules a reminder notification 24 h before [booking.startDatetime].
  ///
  /// If the booking starts in less than 24 h (but still in the future) the
  /// notification is scheduled for now + 1 minute so the user still gets
  /// an immediate heads-up. No-ops if startDatetime is already in the past.
  Future<void> scheduleBookingReminder(Booking booking) async {
    if (!_initialized) await initialize();

    final id = booking.id;
    if (id == null) return;

    final start = tz.TZDateTime.from(booking.startDatetime, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    if (start.isBefore(now)) return; // already past

    final target = start.subtract(const Duration(hours: 24));
    final fireAt = target.isAfter(now)
        ? target
        : now.add(const Duration(minutes: 1)); // less than 24 h away

    final title = booking.customerName.isNotEmpty
        ? '${booking.serviceName} — ${booking.customerName}'
        : booking.serviceName;

    final timeStr =
        '${booking.startDatetime.hour % 12 == 0 ? 12 : booking.startDatetime.hour % 12}'
        ':${booking.startDatetime.minute.toString().padLeft(2, '0')} '
        '${booking.startDatetime.hour < 12 ? 'AM' : 'PM'}';

    final body = booking.totalAmount > 0
        ? 'Tomorrow at $timeStr · ${CurrencyFormatter.format(booking.totalAmount)}'
        : 'Tomorrow at $timeStr';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _bookingChannelId,
        _bookingChannelName,
        channelDescription: _bookingChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );

    await _plugin.zonedSchedule(
      _bookingBase + id,
      title,
      body,
      fireAt,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    debugPrint(
      '[Notifications] Booking reminder scheduled for id=$id at $fireAt',
    );
  }

  /// Cancels the 24-h reminder for the given booking.
  Future<void> cancelBookingReminder(int bookingId) async {
    if (!_initialized) await initialize();
    await _plugin.cancel(_bookingBase + bookingId);
    debugPrint('[Notifications] Booking reminder cancelled for id=$bookingId');
  }

  // ── Fiscal Year Alerts ──────────────────────────────────────────────────

  /// Checks FY proximity on app startup and shows an immediate notification
  /// if the FY ends within 7 days, or if the old FY was never closed after
  /// the new FY has started.
  ///
  /// Safe to call every launch — only fires if a condition is met.
  Future<void> checkAndShowYearEndAlerts() async {
    if (!_initialized) await initialize();

    final isApproaching = await FiscalYearService.instance.isApproachingYearEnd(
      daysBeforeEnd: 7,
    );
    final isResetDue = await FiscalYearService.instance.isResetDue();

    if (!isApproaching && !isResetDue) return;

    final fy = await FiscalYearService.instance.currentFiscalYear;
    final label = await FiscalYearService.instance.getFYLabel(fy);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );

    if (isApproaching && !isResetDue) {
      final daysLeft = fy.end.difference(DateTime.now()).inDays;
      final dayWord = daysLeft == 1 ? 'day' : 'days';
      await _plugin.show(
        _fyBase,
        '$label is ending',
        '$label ends in $daysLeft $dayWord — review and close on time.',
        details,
      );
      debugPrint(
        '[Notifications] Year-end alert: $daysLeft days left for $label',
      );
    }

    if (isResetDue) {
      // The FY has already flipped but the user never ran the closing wizard.
      final fy = await FiscalYearService.instance.currentFiscalYear;
      final prevFyEnd = fy.start.subtract(const Duration(days: 1));
      final prevFy = await FiscalYearService.instance.getFiscalYearFor(
        prevFyEnd,
      );
      final prevLabel = await FiscalYearService.instance.getFYLabel(prevFy);
      await _plugin.show(
        _fyBase + 1,
        'Year-end closing pending',
        'Close $prevLabel to reset invoice numbering for the new year.',
        details,
      );
      debugPrint('[Notifications] Reset-due alert for $prevLabel');
    }
  }

  // ── Backup Reminder ────────────────────────────────────────────────────────

  /// Shows a local notification if no encrypted backup has been made in the
  /// last 30 days (or ever). Safe to call on every launch — no-ops if a
  /// recent backup exists.
  Future<void> checkAndShowBackupReminder() async {
    if (!_initialized) await initialize();

    final days = await EncryptedBackupService.instance.daysSinceLastBackup();
    final neverBacked = days == null;
    final stale = days != null && days > 30;
    if (!neverBacked && !stale) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
    );

    if (neverBacked) {
      await _plugin.show(
        _backupBase,
        'Back up your Kash Cube data',
        'Your data is only on this device. Create an encrypted backup to keep it safe.',
        details,
      );
      debugPrint('[Notifications] Backup reminder: never backed up');
    } else {
      await _plugin.show(
        _backupBase,
        'Backup due',
        'Your last backup was $days days ago. Back up now to protect your data.',
        details,
      );
      debugPrint(
        '[Notifications] Backup reminder: $days days since last backup',
      );
    }
  }

  // ── Cancel ──────────────────────────────────────────────────────────────

  Future<void> cancelAll() async {
    if (kIsWeb || !_initialized) return;
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
