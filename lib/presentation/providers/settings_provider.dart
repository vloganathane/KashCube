import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository_impl.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/csv_export_service.dart';
import '../../domain/repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Settings repository
// ---------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (_) => SettingsRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// App lock settings
// ---------------------------------------------------------------------------

/// Keys used in the settings table.
class SettingsKeys {
  SettingsKeys._();
  static const pinHash = 'pin_hash';
  static const appLockEnabled = 'app_lock_enabled';
  static const biometricEnabled = 'biometric_enabled';
}

/// Whether app lock (PIN) is enabled.
final appLockEnabledProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final value = await repo.get(SettingsKeys.appLockEnabled);
  return value == 'true';
});

/// Whether biometric unlock is enabled.
final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final value = await repo.get(SettingsKeys.biometricEnabled);
  return value == 'true';
});

// ---------------------------------------------------------------------------
// Backup
// ---------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>(
  (_) => BackupService.instance,
);

final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final service = ref.read(backupServiceProvider);
  return service.listBackups();
});

// ---------------------------------------------------------------------------
// CSV Export
// ---------------------------------------------------------------------------

final csvExportServiceProvider = Provider<CsvExportService>(
  (_) => CsvExportService.instance,
);


