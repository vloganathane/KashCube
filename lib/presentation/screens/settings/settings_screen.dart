import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/backup_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import 'pin_lock_screen.dart';

/// Settings screen for app preferences, backup, security, and export.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLockAsync = ref.watch(appLockEnabledProvider);
    final biometricAsync = ref.watch(biometricEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),

          // -- General --
          _SettingsSection(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme'),
                subtitle: const Text('System default'),
                onTap: () {
                  // Theme follows system
                },
              ),
            ],
          ),

          // -- Security --
          _SettingsSection(
            title: 'Security',
            children: [
              appLockAsync.when(
                data: (enabled) => SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('App Lock'),
                  subtitle: Text(enabled ? 'PIN enabled' : 'Not configured'),
                  value: enabled,
                  onChanged: (value) =>
                      _toggleAppLock(context, ref, value),
                ),
                loading: () => const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('App Lock'),
                  trailing: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, _) => const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('App Lock'),
                  subtitle: Text('Error loading'),
                ),
              ),
              biometricAsync.when(
                data: (bioEnabled) {
                  final lockEnabled =
                      appLockAsync.valueOrNull ?? false;
                  return SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Biometric Unlock'),
                    subtitle: const Text('Use fingerprint or face'),
                    value: bioEnabled,
                    onChanged: lockEnabled
                        ? (value) =>
                            _toggleBiometric(context, ref, value)
                        : null,
                  );
                },
                loading: () => const ListTile(
                  leading: Icon(Icons.fingerprint),
                  title: Text('Biometric Unlock'),
                ),
                error: (_, _) => const ListTile(
                  leading: Icon(Icons.fingerprint),
                  title: Text('Biometric Unlock'),
                  subtitle: Text('Error loading'),
                ),
              ),
            ],
          ),

          // -- Data --
          _SettingsSection(
            title: 'Data',
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Create Backup'),
                subtitle: const Text('Save database locally'),
                onTap: () => _createBackup(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore Backup'),
                subtitle: const Text('Restore from a saved backup'),
                onTap: () => _showRestoreDialog(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Export CSV'),
                subtitle: const Text('Export transactions to CSV'),
                onTap: () => _exportCsv(context, ref),
              ),
            ],
          ),

          // -- About --
          _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Kash Cube'),
                subtitle: const Text(
                  'v1.0.0 · Privacy-first financial tracker',
                ),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Kash Cube',
                    applicationVersion: '1.0.0',
                    applicationLegalese:
                        '© 2026 Kash Cube\nAll data stays on your device.',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                subtitle: const Text('100% local, zero network calls'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Privacy Policy'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'Kash Cube stores all data locally on your device.\n\n'
                          '• No data is ever sent to any server.\n'
                          '• No analytics or crash reporting.\n'
                          '• No third-party SDKs that transmit data.\n'
                          '• SMS is read, parsed, and stored locally.\n'
                          '• Backups and exports stay on your device\n'
                          '  unless you explicitly share them.\n\n'
                          'Your financial data is yours alone.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App Lock (PIN)
  // ---------------------------------------------------------------------------

  void _toggleAppLock(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) {
    if (enable) {
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PinLockScreen(
            mode: PinScreenMode.setup,
            onSuccess: () {
              ref.invalidate(appLockEnabledProvider);
            },
          ),
        ),
      );
    } else {
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PinLockScreen(
            mode: PinScreenMode.remove,
            onSuccess: () {
              ref.invalidate(appLockEnabledProvider);
              ref.invalidate(biometricEnabledProvider);
            },
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Biometric
  // ---------------------------------------------------------------------------

  Future<void> _toggleBiometric(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (enable) {
      final localAuth = LocalAuthentication();
      final canAuth = await localAuth.canCheckBiometrics ||
          await localAuth.isDeviceSupported();

      if (!canAuth) {
        if (context.mounted) {
          context.showSnackBar(
            'Biometric authentication is not available on this device',
            isError: true,
          );
        }
        return;
      }

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Verify your identity to enable biometric unlock',
      );

      if (authenticated) {
        final repo = ref.read(settingsRepositoryProvider);
        await repo.set(SettingsKeys.biometricEnabled, 'true');
        ref.invalidate(biometricEnabledProvider);
        if (context.mounted) {
          context.showSnackBar('Biometric unlock enabled');
        }
      }
    } else {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.set(SettingsKeys.biometricEnabled, 'false');
      ref.invalidate(biometricEnabledProvider);
      if (context.mounted) {
        context.showSnackBar('Biometric unlock disabled');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(backupServiceProvider);
      final path = await service.createBackup();

      if (!context.mounted) return;

      final backupFile = path.split('/').last;
      context.showSnackBar('Backup created: $backupFile');

      final shouldShare = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Backup Created'),
          content: Text(
            'Backup saved locally as:\n$backupFile\n\n'
            'Would you like to share the backup file?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No Thanks'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Share'),
            ),
          ],
        ),
      );

      if (shouldShare == true) {
        await Share.shareXFiles([XFile(path)]);
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Backup failed: $e', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  Future<void> _showRestoreDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = ref.read(backupServiceProvider);
    final backups = await service.listBackups();

    if (!context.mounted) return;

    if (backups.isEmpty) {
      context.showSnackBar('No backups found');
      return;
    }

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    final selected = await showModalBottomSheet<BackupInfo>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text(
                'Select Backup',
                style: ctx.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: backups.length,
                itemBuilder: (_, i) {
                  final b = backups[i];
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(dateFormat.format(b.createdAt)),
                    subtitle: Text(b.formattedSize),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await service.deleteBackup(b.path);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _showRestoreDialog(context, ref);
                        }
                      },
                    ),
                    onTap: () => Navigator.pop(ctx, b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: const Text(
          'This will replace all current data with the backup.\n\n'
          'This action cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await service.restoreFromBackup(selected.path);
      if (context.mounted) {
        context.showSnackBar(
          'Backup restored. Please restart the app.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Restore failed: $e', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CSV Export
  // ---------------------------------------------------------------------------

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final transactions = await repo.getAll();

      if (transactions.isEmpty) {
        if (context.mounted) {
          context.showSnackBar('No transactions to export');
        }
        return;
      }

      final csvService = ref.read(csvExportServiceProvider);
      final path = await csvService.exportTransactions(transactions);

      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar('Export failed: $e', isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Settings section header
// ---------------------------------------------------------------------------

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}
