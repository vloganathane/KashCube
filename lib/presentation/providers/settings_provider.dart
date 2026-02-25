import 'package:flutter/material.dart';
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
  static const themeMode = 'theme_mode';
  static const defaultAccountId = 'default_account_id';
}

// ---------------------------------------------------------------------------
// Theme mode
// ---------------------------------------------------------------------------

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._repo) : super(ThemeMode.system) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final value = await _repo.get(SettingsKeys.themeMode);
    state = _fromString(value);
  }

  Future<void> setTheme(ThemeMode mode) async {
    await _repo.set(SettingsKeys.themeMode, _toDbString(mode));
    state = mode;
  }

  static ThemeMode _fromString(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toDbString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(settingsRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Default account
// ---------------------------------------------------------------------------

class DefaultAccountNotifier extends StateNotifier<int?> {
  DefaultAccountNotifier(this._repo) : super(null) {
    _load();
  }

  final SettingsRepository _repo;

  Future<void> _load() async {
    final value = await _repo.get(SettingsKeys.defaultAccountId);
    if (value != null) state = int.tryParse(value);
  }

  Future<void> setDefault(int? accountId) async {
    if (accountId == null) {
      await _repo.set(SettingsKeys.defaultAccountId, '');
    } else {
      await _repo.set(SettingsKeys.defaultAccountId, accountId.toString());
    }
    state = accountId;
  }
}

final defaultAccountIdProvider =
    StateNotifierProvider<DefaultAccountNotifier, int?>(
  (ref) => DefaultAccountNotifier(ref.read(settingsRepositoryProvider)),
);

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


