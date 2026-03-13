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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import 'inventory_service.dart';

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

// Auto-backup task constants
const _autoBackupTaskName       = 'com.kashcube.auto_backup';
const _autoBackupUniqueName     = 'kash_cube_auto_backup';
const _autoBackupChannelId      = 'kash_auto_backup';
const _autoBackupChannelName    = 'Auto Backup';
const _autoBackupNotifId        = 60001;
// SharedPreferences keys (mirrors EncryptedBackupService)
const _kAutoBackupEnabled  = 'auto_backup_enabled';
const _kAutoBackupInterval = 'auto_backup_interval';
const _kLastBackupDate     = 'last_backup_date';

// Low-stock alert task constants
const _lowStockTaskName       = 'com.kashcube.low_stock_alert';
const _lowStockUniqueName     = 'kash_cube_low_stock_alert';
const _lowStockChannelId      = 'kash_low_stock';
const _lowStockChannelName    = 'Low Stock Alerts';
const _lowStockChannelDesc    = 'Daily check for products that are running low on inventory';
const _lowStockNotifId        = 60002;

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
    if (taskName == _taskName) {
      try {
        await _runActionCenterCheck();
      } catch (e) {
        debugPrint('[ActionCenterBg] Error: $e');
      }
    } else if (taskName == _autoBackupTaskName) {
      try {
        await _runAutoBackup();
      } catch (e) {
        debugPrint('[AutoBackup] Task error: $e');
      }
    } else if (taskName == _lowStockTaskName) {
      try {
        await _runLowStockCheck();
      } catch (e) {
        debugPrint('[LowStock] Task error: $e');
      }
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
    // singleInstance: false gives this background isolate its own native DB
    // handle, preventing it from sharing (and closing) the main isolate's handle.
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
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

    // Overdue invoices (status = 'overdue')
    // Note: invoices table has no deleted_at column — no soft-delete filter needed.
    final invoiceRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM invoices "
      "WHERE status IN ('overdue')",
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
// Auto-backup logic — runs inside the WorkManager isolate
// ────────────────────────────────────────────────────────────────────────────

Future<void> _runAutoBackup() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(_kAutoBackupEnabled) ?? false;
  if (!enabled) {
    debugPrint('[AutoBackup] Disabled, skipping');
    return;
  }

  try {
    final dbDir = await getDatabasesPath();
    final dbFile = File(path_pkg.join(dbDir, 'kash_cube.db'));
    if (!await dbFile.exists()) throw Exception('Database file not found');

    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(path_pkg.join(appDir.path, 'backups'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backupPath = path_pkg.join(backupDir.path, 'auto_kash_cube_$ts.db');
    await dbFile.copy(backupPath);

    await _pruneAutoBackupsInDir(backupDir);

    await prefs.setString(_kLastBackupDate, DateTime.now().toIso8601String());
    debugPrint('[AutoBackup] Created: $backupPath');
  } catch (e) {
    debugPrint('[AutoBackup] Failed: $e');
    await _showAutoBackupFailureNotification();
  }
}

/// Keeps only the 3 most-recent auto-backup files; deletes older ones.
Future<void> _pruneAutoBackupsInDir(Directory backupDir) async {
  final files = <File>[];
  await for (final entity in backupDir.list()) {
    if (entity is File &&
        path_pkg.basename(entity.path).startsWith('auto_')) {
      files.add(entity);
    }
  }
  if (files.length <= 3) return;

  final withDates = <({File file, DateTime modified})>[];
  for (final f in files) {
    final stat = await f.stat();
    withDates.add((file: f, modified: stat.modified));
  }
  withDates.sort((a, b) => a.modified.compareTo(b.modified));

  for (var i = 0; i < withDates.length - 3; i++) {
    await withDates[i].file.delete();
    debugPrint('[AutoBackup] Pruned: ${withDates[i].file.path}');
  }
}

Future<void> _showAutoBackupFailureNotification() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
  );
  await plugin.show(
    _autoBackupNotifId,
    'Auto Backup Failed',
    'Kash Cube could not complete the scheduled backup. '
        'Open the app to back up manually.',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _autoBackupChannelId,
        _autoBackupChannelName,
        channelDescription:
            'Notifications when automatic database backup fails',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Low-stock check — runs inside the WorkManager isolate
// ────────────────────────────────────────────────────────────────────────────

Future<void> _runLowStockCheck() async {
  final dbDir = await getDatabasesPath();
  final dbPath = path_pkg.join(dbDir, 'kash_cube.db');

  Database? db;
  try {
    // singleInstance: false gives this background isolate its own native DB handle.
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    final count = await InventoryService.countLowStockItemsInBackground(db);
    if (count > 0) {
      final names = await InventoryService.getLowStockNamesInBackground(db);
      await _showLowStockNotification(count, names);
    }
    debugPrint('[LowStock] Check complete — $count low-stock items');
  } finally {
    await db?.close();
  }
}

Future<void> _showLowStockNotification(
    int count, List<String> names) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
  );

  final itemWord = count == 1 ? 'product is' : 'products are';
  final body = names.isNotEmpty
      ? names.join(', ')
      : 'Check inventory to restock before running out.';

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _lowStockChannelId,
      _lowStockChannelName,
      channelDescription: _lowStockChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    ),
  );

  await plugin.show(
    _lowStockNotifId,
    '$count $itemWord running low on stock',
    body,
    details,
  );

  debugPrint('[LowStock] Notification shown for $count items');
}

// ────────────────────────────────────────────────────────────────────────────
// Registration — called from main() at app startup
// ────────────────────────────────────────────────────────────────────────────

/// Registers the daily Action Center check with WorkManager.
///
/// Uses [ExistingWorkPolicy.keep]: if the task is already scheduled, no-op.
/// Call once from [main()] after [WidgetsFlutterBinding.ensureInitialized()].
Future<void> registerActionCenterDailyTask() async {
  if (kIsWeb) return;
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

// ────────────────────────────────────────────────────────────────────────────
// Auto-backup registration / cancellation — called from settings
// ────────────────────────────────────────────────────────────────────────────

/// Registers (or replaces) the periodic auto-backup WorkManager task.
///
/// [interval] must be one of: 'daily', 'weekly', 'monthly'.
/// Always call after [registerActionCenterDailyTask] so WorkManager is
/// already initialised.
Future<void> registerAutoBackupTask(String interval) async {
  if (kIsWeb) return;
  try {
    await Workmanager().registerPeriodicTask(
      _autoBackupUniqueName,
      _autoBackupTaskName,
      frequency: _intervalToDuration(interval),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: true,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint('[AutoBackup] Task registered (interval: $interval)');
  } catch (e) {
    debugPrint('[AutoBackup] Registration failed (non-fatal): $e');
  }
}

/// Cancels the periodic auto-backup task.
Future<void> cancelAutoBackupTask() async {
  if (kIsWeb) return;
  try {
    await Workmanager().cancelByUniqueName(_autoBackupUniqueName);
    debugPrint('[AutoBackup] Task cancelled');
  } catch (e) {
    debugPrint('[AutoBackup] Cancel failed (non-fatal): $e');
  }
}

/// Re-registers the auto-backup task on app start if the user had it enabled.
///
/// WorkManager tasks can be cleared by OS updates or app installs — calling
/// this on every startup ensures the schedule stays active.
Future<void> maybeRestoreAutoBackupTask() async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAutoBackupEnabled) ?? false;
    if (!enabled) return;
    final interval = prefs.getString(_kAutoBackupInterval) ?? 'weekly';
    await registerAutoBackupTask(interval);
    debugPrint('[AutoBackup] Restored task on startup (interval: $interval)');
  } catch (e) {
    debugPrint('[AutoBackup] Restore on startup failed (non-fatal): $e');
  }
}

Duration _intervalToDuration(String interval) {
  switch (interval) {
    case 'daily':
      return const Duration(hours: 24);
    case 'monthly':
      return const Duration(days: 30);
    case 'weekly':
    default:
      return const Duration(days: 7);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Low-stock — registration / cancellation
// ────────────────────────────────────────────────────────────────────────────

/// Registers the daily low-stock alert task with WorkManager.
///
/// Fires around the same initial time as the Action Center check.
/// No-op if WorkManager is unavailable.  Call after
/// [registerActionCenterDailyTask] so WorkManager is already initialised.
Future<void> registerLowStockDailyTask() async {
  if (kIsWeb) return;
  try {
    await Workmanager().registerPeriodicTask(
      _lowStockUniqueName,
      _lowStockTaskName,
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
    debugPrint('[LowStock] Daily task registered');
  } catch (e) {
    debugPrint('[LowStock] Registration failed (non-fatal): $e');
  }
}
