// ---------------------------------------------------------------------------
// Action Center Background Service (WorkManager)
// ---------------------------------------------------------------------------
// Runs a daily background task (around 9 AM) that:
//   1. Opens the local SQLite database directly (no Riverpod — separate isolate)
//   2. Counts overdue credits, invoices, loan EMIs, and bills
//   3. Fires a local notification summarising the count
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

// ────────────────────────────────────────────────────────────────────────────
// Task constants
// ────────────────────────────────────────────────────────────────────────────

const _taskName       = 'com.kashcube.action_center_daily';
const _taskUniqueName = 'kash_cube_action_center_daily';

const _channelId   = 'kash_action_center';
const _channelName = 'Action Center Alerts';
const _channelDesc =
    'Daily summary of overdue invoices, dues, bills and loan EMIs';

const _notificationId = 60000;

// ────────────────────────────────────────────────────────────────────────────
// Callback dispatcher — MUST be a top-level function
// ────────────────────────────────────────────────────────────────────────────

/// Entry point for all WorkManager background tasks.
///
/// Called by the OS in a separate isolate.  Must be a top-level (or static)
/// function annotated with `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _taskName) return Future.value(true);
    try {
      await _runActionCenterCheck();
    } catch (e) {
      debugPrint('[ActionCenterBg] Error: $e');
    }
    return Future.value(true);
  });
}

// ────────────────────────────────────────────────────────────────────────────
// Core logic — runs inside the WorkManager isolate
// ────────────────────────────────────────────────────────────────────────────

Future<void> _runActionCenterCheck() async {
  final dbDir = await getDatabasesPath();
  final dbPath = path_pkg.join(dbDir, 'kash_cube.db');

  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true);
    final today = DateTime.now();
    final todayIso = DateTime(today.year, today.month, today.day)
        .toIso8601String()
        .substring(0, 10); // 'YYYY-MM-DD'

    int overdueCount = 0;

    // Overdue credits (due_date in past, not cleared)
    final creditRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM credits "
      "WHERE is_cleared = 0 AND due_date IS NOT NULL AND due_date < ? "
      "AND deleted_at IS NULL",
      [todayIso],
    );
    overdueCount += (creditRows.first['c'] as int? ?? 0);

    // Overdue invoices (status = 'overdue' or 'partiallyPaid' with past due)
    final invoiceRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM invoices "
      "WHERE status IN ('overdue') "
      "AND deleted_at IS NULL",
    );
    overdueCount += (invoiceRows.first['c'] as int? ?? 0);

    // Overdue loan EMIs (nextEmiDate or dueDate in past, not cleared)
    final loanRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM loans "
      "WHERE is_cleared = 0 AND deleted_at IS NULL "
      "AND (next_emi_date < ? OR (next_emi_date IS NULL AND due_date < ?))",
      [todayIso, todayIso],
    );
    overdueCount += (loanRows.first['c'] as int? ?? 0);

    // Overdue scheduled payments (next_date in past, active)
    final billRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM scheduled_payments "
      "WHERE is_active = 1 AND next_date < ? "
      "AND deleted_at IS NULL",
      [todayIso],
    );
    overdueCount += (billRows.first['c'] as int? ?? 0);

    debugPrint('[ActionCenterBg] Overdue count: $overdueCount');

    if (overdueCount > 0) {
      await _showNotification(overdueCount);
    }
  } finally {
    await db?.close();
  }
}

Future<void> _showNotification(int overdueCount) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
  );

  final itemWord = overdueCount == 1 ? 'item needs' : 'items need';
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

  await plugin.show(
    _notificationId,
    '$overdueCount $itemWord attention',
    'Open Kash Cube Action Center to review and clear pending items.',
    details,
  );

  debugPrint('[ActionCenterBg] Notification shown for $overdueCount overdue items');
}

// ────────────────────────────────────────────────────────────────────────────
// Registration — called from main() at app startup
// ────────────────────────────────────────────────────────────────────────────

/// Registers the daily Action Center check with WorkManager.
///
/// Uses [ExistingWorkPolicy.keep]: if the task is already scheduled, no-op.
/// Call once from [main()] after [WidgetsFlutterBinding.ensureInitialized()].
Future<void> registerActionCenterDailyTask() async {
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(hours: 24),
      initialDelay: _initialDelayUntil9am(),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    debugPrint('[ActionCenterBg] Daily task registered');
  } catch (e) {
    // WorkManager registration can fail on emulators or restricted devices.
    // Non-fatal: the feature gracefully degrades.
    debugPrint('[ActionCenterBg] Registration failed (non-fatal): $e');
  }
}

/// Computes an initial delay so the first run fires at approximately 9 AM.
Duration _initialDelayUntil9am() {
  final now = DateTime.now();
  var target = DateTime(now.year, now.month, now.day, 9, 0, 0);
  if (target.isBefore(now)) {
    target = target.add(const Duration(days: 1));
  }
  final delay = target.difference(now);
  // Cap at 24 h (WorkManager periodic task minimum is 15 min)
  return delay > const Duration(hours: 24)
      ? const Duration(hours: 24)
      : delay;
}
