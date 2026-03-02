import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/database_helper.dart';
import '../../data/services/encrypted_backup_service.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// Show the nudge after the user has this many transactions.
const _nudgeAfterTransactions = 5;

/// Key: true once the user has dismissed the in-app nudge permanently.
const _prefNudgeDismissed = 'backup_nudge_dismissed';

// ── Providers ──────────────────────────────────────────────────────────────

/// True when the backup nudge should be shown on the home screen:
///   • Total transaction count ≥ [_nudgeAfterTransactions]
///   • User has never dismissed the nudge (SharedPreferences gate)
///   • User has never created an encrypted backup
final backupNudgeVisibleProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefNudgeDismissed) ?? false) return false;

  // Quick count query — avoiding a full ORM load.
  final db = await DatabaseHelper.instance.database;
  final rows = await db.rawQuery(
    "SELECT COUNT(*) AS cnt FROM transactions WHERE deleted_at IS NULL",
  );
  final count = (rows.first['cnt'] as int?) ?? 0;
  if (count < _nudgeAfterTransactions) return false;

  // If they already have an encrypted backup, suppress.
  final lastBackup = await EncryptedBackupService.instance.lastBackupDate();
  if (lastBackup != null) return false;

  return true;
});

/// Call this to permanently dismiss the backup nudge.
Future<void> dismissBackupNudge() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefNudgeDismissed, true);
}
