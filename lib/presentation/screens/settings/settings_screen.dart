import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../providers/settings_provider.dart';
import 'accounts_manage_screen.dart';
import 'opening_balances_screen.dart';
import 'pin_lock_screen.dart';
import 'businesses_screen.dart';
import 'unit_types_screen.dart';
import 'document_terms_screen.dart';
import 'manage_users_screen.dart';
import 'my_personal_card_screen.dart';
import 'encrypted_backup_screen.dart';
import 'fy_close_wizard_screen.dart';
import 'notification_settings_screen.dart';
import 'storage_health_screen.dart';
import 'linked_devices_screen.dart';
import 'template_list_screen.dart';
import 'upgrade_screen.dart';

// ── Profile provider ──────────────────────────────────────────────────────────

final _profileProvider = FutureProvider<({String? name, String? phone})>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final results = await Future.wait([
    repo.get(SettingsKeys.ownerName),
    repo.get(SettingsKeys.personalPhone),
  ]);
  final name  = (results[0]?.trim().isEmpty ?? true) ? null : results[0];
  final phone = (results[1]?.trim().isEmpty ?? true) ? null : results[1];
  return (name: name, phone: phone);
});

/// Settings screen for app preferences, backup, security, and export.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLockAsync = ref.watch(appLockEnabledProvider);
    final biometricAsync = ref.watch(biometricEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // -- Profile Header --
          _ProfileHeader(),

          // -- KashCube Plan --
          Consumer(builder: (context, ref, _) {
            final tier = ref.watch(subscriptionTierProvider);
            return _SettingsSection(
              title: 'KashCube Plan',
              children: [
                ListTile(
                  leading: Icon(
                    tier.isFree
                        ? Icons.workspace_premium_outlined
                        : Icons.workspace_premium,
                    color: tier.isFree ? null : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(tier.isFree
                      ? 'Upgrade to Starter or Business'
                      : 'Plan: ${tier.displayName}'),
                  subtitle: Text(tier.isFree
                      ? 'Remove watermarks · Export reports · UPI QR'
                      : 'Manage your subscription'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                  ),
                ),
              ],
            );
          }),
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
                  final lockEnabled = appLockAsync.valueOrNull ?? false;
                  return SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Biometric Unlock'),
                    subtitle: const Text('Use fingerprint or face'),
                    value: bioEnabled,
                    onChanged: lockEnabled
                        ? (value) => _toggleBiometric(context, ref, value)
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

          // -- Team --
          _SettingsSection(
            title: 'Sync',
            children: [
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Linked Devices'),
                subtitle: const Text(
                    'Pair a tablet or second phone for shared access over Wi-Fi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LinkedDevicesScreen(),
                  ),
                ),
              ),
            ],
          ),

          // -- Team --
          _SettingsSection(
            title: 'Team',
            children: [
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Team Members'),
                subtitle: const Text('Add staff, assign roles & permissions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageUsersScreen(),
                  ),
                ),
              ),
            ],
          ),

          // -- Accounts --
          _SettingsSection(
            title: 'Accounts',
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Manage Accounts'),
                subtitle: const Text('Bank, UPI, Wallet, Cash'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AccountsManageScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Opening Balances'),
                subtitle: const Text('Set starting balance per payment method'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpeningBalancesScreen(),
                  ),
                ),
              ),
            ],
          ),

          // -- General --
          _SettingsSection(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme'),
                subtitle: Text(_themeModeLabel(themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemePicker(context, ref, themeMode),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Financial Year'),
                subtitle: const Text('Year-end closing, archive & FY settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FyCloseWizardScreen(),
                  ),
                ),
              ),
            ],
          ),

          // -- Data --
          _SettingsSection(
            title: 'Data',
            children: [
              ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: const Text('Storage & Backup'),
                subtitle: const Text('Usage, backup & cache management'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StorageHealthScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Encrypted Backup (.kashcube)'),
                subtitle: const Text('Export or restore with AES-256 encryption'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EncryptedBackupScreen(),
                  ),
                ),
              ),

            ],
          ),

          // -- Notifications --
          _SettingsSection(
            title: 'Notifications',
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notification Settings'),
                subtitle: const Text('Reminders, quiet hours & toggles'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),

          // -- Business Mode --
          _SettingsSection(
            title: 'Business Mode',
            children: [
              Consumer(builder: (context, ref, _) {
                final enabled = ref.watch(businessModeProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.storefront_outlined),
                  title: const Text('Enable Business Mode'),
                  subtitle: const Text('Unlock invoicing & item catalog'),
                  value: enabled,
                  onChanged: (v) =>
                      ref.read(businessModeProvider.notifier).setEnabled(v),
                );
              }),
              Consumer(builder: (context, ref, _) {
                final enabled = ref.watch(businessModeProvider);
                if (!enabled) return const SizedBox.shrink();
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.business_outlined),
                      title: const Text('Business Profiles'),
                      subtitle: const Text('Name, address, GST, logo & more'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BusinessesScreen()),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.straighten_outlined),
                      title: const Text('Unit Types'),
                      subtitle: const Text('Manage units used in item catalog'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const UnitTypesScreen()),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Default Terms & Conditions'),
                      subtitle: const Text(
                          'T&C footer for invoice, quote & booking PDFs'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DocumentTermsScreen()),
                      ),
                    ),
                    Consumer(builder: (context, ref, _) {
                      final template = ref.watch(documentTemplateProvider);
                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: const Text('PDF Templates'),
                        subtitle: Text(template.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TemplateListScreen(),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
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
  // Theme
  // ---------------------------------------------------------------------------

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System default';
    }
  }

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.sm,
              ),
              child: Text(
                'Choose Theme',
                style: context.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(themeModeProvider.notifier).setTheme(v);
                  Navigator.pop(ctx);
                }
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      title: Text(_themeModeLabel(mode)),
                      secondary: Icon(
                        mode == ThemeMode.light
                            ? Icons.light_mode_outlined
                            : mode == ThemeMode.dark
                                ? Icons.dark_mode_outlined
                                : Icons.brightness_auto_outlined,
                      ),
                      value: mode,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
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

}

// ---------------------------------------------------------------------------
// Profile header card
// ---------------------------------------------------------------------------

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_profileProvider);
    final scheme = context.colorScheme;

    return profileAsync.when(
      loading: () => const SizedBox(height: AppSpacing.sm),
      error: (_, _) => const SizedBox.shrink(),
      data: (profile) {
        final hasProfile = profile.name != null;
        final initials = _initials(profile.name);

        return InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyPersonalCardScreen(),
              ),
            );
            ref.invalidate(_profileProvider);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.base,
              AppSpacing.base, AppSpacing.sm,
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.base),
                // Info
                Expanded(
                  child: hasProfile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name!,
                              style: context.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (profile.phone != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                profile.phone!,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set up your profile',
                              style: context.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Add name, phone & personal card',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
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
