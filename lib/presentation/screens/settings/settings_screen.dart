import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sms_provider.dart';
import '../../providers/app_user_provider.dart';
import '../../p2p/devices_screen.dart';
import 'settings_search_helper.dart';
import 'accounts_manage_screen.dart';
import 'app_logs_screen.dart';
import 'pin_lock_screen.dart';
import 'profile_screen.dart';
import 'businesses_screen.dart';
import 'unit_types_screen.dart';
import 'document_terms_screen.dart';
import 'manage_users_screen.dart';
import 'my_personal_card_screen.dart';
import 'encrypted_backup_screen.dart';
import 'fy_close_wizard_screen.dart';
import 'notification_settings_screen.dart';
import 'permissions_screen.dart';
import 'sms_permission_screen.dart';
import 'storage_health_screen.dart';
import 'template_list_screen.dart';
import 'upgrade_screen.dart';
import 'open_on_laptop_screen.dart';

// ── Profile provider ──────────────────────────────────────────────────────────

final _profileProvider = FutureProvider<({String? name, String? phone})>((
  ref,
) async {
  final repo = ref.read(settingsRepositoryProvider);
  final results = await Future.wait([
    repo.get(SettingsKeys.ownerName),
    repo.get(SettingsKeys.personalPhone),
  ]);
  final name = (results[0]?.trim().isEmpty ?? true) ? null : results[0];
  final phone = (results[1]?.trim().isEmpty ?? true) ? null : results[1];
  return (name: name, phone: phone);
});

// ── Settings section ids ───────────────────────────────────────────────────────

enum _SettingsSectionId {
  profile('My Profile', Icons.person_outline),
  plan('KashCube Plan', Icons.workspace_premium_outlined),
  security('Security', Icons.lock_outline),
  team('Team', Icons.group_outlined),
  accounts('Accounts', Icons.account_balance_outlined),
  general('General', Icons.settings_outlined),
  data('Data', Icons.storage_outlined),
  notifications('Notifications', Icons.notifications_outlined),
  automation('Automation', Icons.sms_outlined),
  privacy('Privacy', Icons.privacy_tip_outlined),
  business('Business Mode', Icons.storefront_outlined),
  about('About', Icons.info_outline);

  const _SettingsSectionId(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Settings screen for app preferences, backup, security, and export.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsSectionId _selectedSection = _SettingsSectionId.profile;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SettingItem> _buildAllSettings(BuildContext context) {
    return [
      // Security
      SettingItem(
        title: 'My Identity',
        subtitle: 'View your identity QR and display name',
        icon: Icons.fingerprint_rounded,
        sectionLabel: 'Security',
        keywords: ['qr', 'identity', 'display', 'profile'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
      ),
      SettingItem(
        title: 'App Lock',
        subtitle: 'Require PIN to open app',
        icon: Icons.lock_outline,
        sectionLabel: 'Security',
        keywords: ['pin', 'lock', 'password', 'security', 'passcode'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      SettingItem(
        title: 'Biometric Unlock',
        subtitle: 'Use fingerprint or face',
        icon: Icons.fingerprint,
        sectionLabel: 'Security',
        keywords: ['fingerprint', 'face', 'faceid', 'touchid', 'biometric'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),

      // Team
      SettingItem(
        title: 'Team Members',
        subtitle: 'Add staff, assign roles & permissions',
        icon: Icons.group_outlined,
        sectionLabel: 'Team',
        keywords: ['staff', 'users', 'roles', 'permissions', 'team'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
        ),
      ),

      // Accounts
      SettingItem(
        title: 'Accounts',
        subtitle: 'Bank, UPI, Wallet, Cash · Opening Balances',
        icon: Icons.account_balance_outlined,
        sectionLabel: 'Accounts',
        keywords: ['bank', 'upi', 'wallet', 'cash', 'balance', 'opening'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountsManageScreen()),
        ),
      ),

      // General
      SettingItem(
        title: 'Theme',
        subtitle: 'Light, Dark or System',
        icon: Icons.palette_outlined,
        sectionLabel: 'General',
        keywords: ['dark', 'light', 'theme', 'appearance', 'color'],
        onTap: () =>
            _showThemePicker(context, ref, ref.read(themeModeProvider)),
      ),
      SettingItem(
        title: 'Financial Year',
        subtitle: 'Year-end closing, archive & FY settings',
        icon: Icons.calendar_month_outlined,
        sectionLabel: 'General',
        keywords: ['fy', 'year', 'closing', 'archive', 'financial'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FyCloseWizardScreen()),
        ),
      ),

      // Data
      SettingItem(
        title: 'Storage & Backup',
        subtitle: 'Usage, backup & cache management',
        icon: Icons.health_and_safety_outlined,
        sectionLabel: 'Data',
        keywords: ['storage', 'backup', 'cache', 'usage', 'space'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StorageHealthScreen()),
        ),
      ),
      SettingItem(
        title: 'Encrypted Backup',
        subtitle: 'Export or restore with AES-256 encryption',
        icon: Icons.shield_outlined,
        sectionLabel: 'Data',
        keywords: [
          'backup',
          'export',
          'restore',
          'encrypted',
          'aes',
          'kashcube',
        ],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EncryptedBackupScreen()),
        ),
      ),
      SettingItem(
        title: 'Devices & LAN Sync',
        subtitle: 'Pair devices and sync over Wi-Fi',
        icon: Icons.devices_outlined,
        sectionLabel: 'Data',
        keywords: ['devices', 'lan', 'sync', 'wifi', 'pair', 'p2p'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DevicesScreen()),
        ),
      ),
      SettingItem(
        title: 'Experimental: libp2p Sync',
        subtitle: 'Using dart_libp2p for peer-to-peer sync',
        icon: Icons.science_outlined,
        sectionLabel: 'Data',
        keywords: [
          'libp2p',
          'experimental',
          'sync',
          'webrtc',
          'protocol',
          'dart',
        ],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      SettingItem(
        title: 'Open on Laptop',
        subtitle: 'View KashCube in browser over Wi-Fi',
        icon: Icons.laptop_outlined,
        sectionLabel: 'Data',
        keywords: ['laptop', 'browser', 'web', 'wifi', 'companion'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OpenOnLaptopScreen()),
        ),
      ),
      SettingItem(
        title: 'Diagnostics Logs',
        subtitle: 'View, copy, and share recent app logs',
        icon: Icons.bug_report_outlined,
        sectionLabel: 'Data',
        keywords: ['logs', 'diagnostics', 'debug', 'troubleshoot'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AppLogsScreen()),
        ),
      ),

      // Notifications
      SettingItem(
        title: 'Notification Settings',
        subtitle: 'Reminders, quiet hours & toggles',
        icon: Icons.notifications_outlined,
        sectionLabel: 'Notifications',
        keywords: ['notifications', 'reminders', 'alerts', 'quiet'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
        ),
      ),

      // Automation
      SettingItem(
        title: 'Auto-detect SMS transactions',
        subtitle: 'Detect bank & UPI transactions from SMS',
        icon: Icons.sms_outlined,
        sectionLabel: 'Automation',
        keywords: ['sms', 'auto', 'detect', 'transaction', 'bank', 'upi'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      SettingItem(
        title: 'Scan SMS inbox',
        subtitle: 'Find past transactions in SMS',
        icon: Icons.inbox_outlined,
        sectionLabel: 'Automation',
        keywords: ['sms', 'scan', 'inbox', 'messages', 'import'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),

      // Privacy
      SettingItem(
        title: 'Permissions',
        subtitle: 'Check real-time permission status',
        icon: Icons.admin_panel_settings_outlined,
        sectionLabel: 'Privacy',
        keywords: ['permissions', 'access', 'settings', 'allow'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsScreen()),
        ),
      ),
      SettingItem(
        title: 'Anonymous Analytics',
        subtitle: 'Share anonymous feature usage',
        icon: Icons.analytics_outlined,
        sectionLabel: 'Privacy',
        keywords: ['analytics', 'usage', 'data', 'privacy', 'firebase'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),

      // Business Mode
      SettingItem(
        title: 'Enable Business Mode',
        subtitle: 'Unlock invoicing & item catalog',
        icon: Icons.storefront_outlined,
        sectionLabel: 'Business Mode',
        keywords: ['business', 'invoice', 'catalog', 'items', 'gst'],
        onTap: () {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      SettingItem(
        title: 'Business Profiles',
        subtitle: 'Name, address, GST, logo & more',
        icon: Icons.business_outlined,
        sectionLabel: 'Business Mode',
        keywords: ['business', 'profile', 'gst', 'logo', 'address'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BusinessesScreen()),
        ),
      ),
      SettingItem(
        title: 'Unit Types',
        subtitle: 'Manage units used in item catalog',
        icon: Icons.straighten_outlined,
        sectionLabel: 'Business Mode',
        keywords: ['unit', 'types', 'kg', 'meter', 'quantity'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UnitTypesScreen()),
        ),
      ),
      SettingItem(
        title: 'Default Terms & Conditions',
        subtitle: 'T&C footer for PDFs',
        icon: Icons.gavel_outlined,
        sectionLabel: 'Business Mode',
        keywords: ['terms', 'conditions', 'tc', 'footer', 'pdf'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentTermsScreen()),
        ),
      ),
      SettingItem(
        title: 'PDF Templates',
        subtitle: 'Invoice and document templates',
        icon: Icons.picture_as_pdf_outlined,
        sectionLabel: 'Business Mode',
        keywords: ['pdf', 'template', 'invoice', 'document'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TemplateListScreen()),
        ),
      ),

      // About
      SettingItem(
        title: 'About Kash Cube',
        subtitle: 'Version & app information',
        icon: Icons.info_outline,
        sectionLabel: 'About',
        keywords: ['about', 'version', 'info', 'app'],
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'Kash Cube',
          applicationVersion: '1.0.0',
          applicationLegalese:
              '© 2026 Kash Cube\nAll data stays on your device.',
        ),
      ),
      SettingItem(
        title: 'Privacy Policy',
        subtitle: '100% local, zero network calls',
        icon: Icons.privacy_tip_outlined,
        sectionLabel: 'About',
        keywords: ['privacy', 'policy', 'local', 'data'],
        onTap: () => _showLegalSheet(
          context,
          title: 'Privacy Policy',
          content: _kPrivacyPolicy,
        ),
      ),
      SettingItem(
        title: 'Terms of Use',
        subtitle: 'Legal terms and conditions',
        icon: Icons.gavel_outlined,
        sectionLabel: 'About',
        keywords: ['terms', 'use', 'legal', 'agreement'],
        onTap: () => _showLegalSheet(
          context,
          title: 'Terms of Use & Privacy Policy',
          content: _kTermsOfUse,
        ),
      ),
    ];
  }

  Widget _buildSearchResults(BuildContext context) {
    final allSettings = _buildAllSettings(context);
    final filtered = allSettings
        .where((item) => item.matches(_searchQuery))
        .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: context.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                'No settings found',
                style: context.textTheme.titleMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Try "backup", "notifications", or "theme"',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Group by section
    final grouped = <String, List<SettingItem>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.sectionLabel, () => []).add(item);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.md,
              AppSpacing.base,
              AppSpacing.xs,
            ),
            child: Text(
              entry.key,
              style: context.textTheme.labelLarge?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in entry.value)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.title),
              subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Debug: Ensure tap is registered
                print('ListTile tapped: ${item.title}');
                item.onTap();
              },
              enabled: true,
            ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = context.isExpanded;
    final appLockAsync = ref.watch(appLockEnabledProvider);
    final biometricAsync = ref.watch(biometricEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Wide layout (≥ 840 dp): section nav on left, content pane on right.
    if (isWide) {
      return _buildWideScaffold(
        context,
        ref,
        appLockAsync,
        biometricAsync,
        themeMode,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search settings...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // Settings list
          Expanded(
            child: _searchQuery.isEmpty
                ? ListView(
                    children: [
                      // -- Profile Header --
                      _ProfileHeader(),

                      // -- KashCube Plan --
                      Consumer(
                        builder: (context, ref, _) {
                          final tier = ref.watch(subscriptionTierProvider);
                          return _SettingsSection(
                            title: 'KashCube Plan',
                            children: [
                              ListTile(
                                leading: Icon(
                                  tier.isFree
                                      ? Icons.workspace_premium_outlined
                                      : Icons.workspace_premium,
                                  color: tier.isFree
                                      ? null
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  tier.isFree
                                      ? 'Upgrade to Starter or Business'
                                      : 'Plan: ${tier.displayName}',
                                ),
                                subtitle: Text(
                                  tier.isFree
                                      ? 'Remove watermarks · Export reports · UPI QR'
                                      : 'Manage your subscription',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const UpgradeScreen(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      _SettingsSection(
                        title: 'Security',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.fingerprint_rounded),
                            title: const Text('My Identity'),
                            subtitle: const Text(
                              'View your identity QR and display name',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            ),
                          ),
                          appLockAsync.when(
                            data: (enabled) => SwitchListTile(
                              secondary: const Icon(Icons.lock_outline),
                              title: const Text('App Lock'),
                              subtitle: Text(
                                enabled ? 'PIN enabled' : 'Not configured',
                              ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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

                      // -- Team --
                      _SettingsSection(
                        title: 'Team',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.group_outlined),
                            title: const Text('Team Members'),
                            subtitle: const Text(
                              'Add staff, assign roles & permissions',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageUsersScreen(),
                              ),
                            ),
                          ),
                          Consumer(
                            builder: (context, ref, _) {
                              final hasUsers = ref.watch(hasAnyAppUserProvider);
                              if (hasUsers.valueOrNull != true)
                                return const SizedBox.shrink();
                              return ListTile(
                                leading: const Icon(
                                  Icons.switch_account_outlined,
                                ),
                                title: const Text('Switch Profile'),
                                subtitle: const Text(
                                  'Return to the profile selection screen',
                                ),
                                onTap: () => ref
                                    .read(switchUserProvider.notifier)
                                    .state++,
                              );
                            },
                          ),
                        ],
                      ),

                      // -- Accounts --
                      _SettingsSection(
                        title: 'Accounts',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.account_balance_outlined),
                            title: const Text('Accounts'),
                            subtitle: const Text(
                              'Bank, UPI, Wallet, Cash · Opening Balances',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AccountsManageScreen(),
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
                            onTap: () =>
                                _showThemePicker(context, ref, themeMode),
                          ),
                          ListTile(
                            leading: const Icon(Icons.calendar_month_outlined),
                            title: const Text('Financial Year'),
                            subtitle: const Text(
                              'Year-end closing, archive & FY settings',
                            ),
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
                            leading: const Icon(
                              Icons.health_and_safety_outlined,
                            ),
                            title: const Text('Storage & Backup'),
                            subtitle: const Text(
                              'Usage, backup & cache management',
                            ),
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
                            subtitle: const Text(
                              'Export or restore with AES-256 encryption',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EncryptedBackupScreen(),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.devices_outlined),
                            title: const Text('Devices & LAN Sync'),
                            subtitle: const Text(
                              'Pair devices and sync over Wi-Fi',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DevicesScreen(),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.laptop_outlined),
                            title: const Text('Open on Laptop'),
                            subtitle: const Text(
                              'View KashCube in your browser over Wi-Fi',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OpenOnLaptopScreen(),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.bug_report_outlined),
                            title: const Text('Diagnostics Logs'),
                            subtitle: const Text(
                              'View, copy, and share recent app logs',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AppLogsScreen(),
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
                            subtitle: const Text(
                              'Reminders, quiet hours & toggles',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const NotificationSettingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // -- Automation (SMS) --
                      const _AutomationSection(),

                      // -- Privacy --
                      const _PrivacySection(),

                      // -- Business Mode --
                      _SettingsSection(
                        title: 'Business Mode',
                        children: [
                          Consumer(
                            builder: (context, ref, _) {
                              final enabled = ref.watch(businessModeProvider);
                              return SwitchListTile(
                                secondary: const Icon(
                                  Icons.storefront_outlined,
                                ),
                                title: const Text('Enable Business Mode'),
                                subtitle: const Text(
                                  'Unlock invoicing & item catalog',
                                ),
                                value: enabled,
                                onChanged: (v) => ref
                                    .read(businessModeProvider.notifier)
                                    .setEnabled(v),
                              );
                            },
                          ),
                          Consumer(
                            builder: (context, ref, _) {
                              final enabled = ref.watch(businessModeProvider);
                              if (!enabled) return const SizedBox.shrink();
                              return Column(
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.business_outlined,
                                    ),
                                    title: const Text('Business Profiles'),
                                    subtitle: const Text(
                                      'Name, address, GST, logo & more',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const BusinessesScreen(),
                                      ),
                                    ),
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.straighten_outlined,
                                    ),
                                    title: const Text('Unit Types'),
                                    subtitle: const Text(
                                      'Manage units used in item catalog',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const UnitTypesScreen(),
                                      ),
                                    ),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.gavel_outlined),
                                    title: const Text(
                                      'Default Terms & Conditions',
                                    ),
                                    subtitle: const Text(
                                      'T&C footer for invoice, quote & booking PDFs',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const DocumentTermsScreen(),
                                      ),
                                    ),
                                  ),
                                  Consumer(
                                    builder: (context, ref, _) {
                                      final template = ref.watch(
                                        documentTemplateProvider,
                                      );
                                      return ListTile(
                                        leading: const Icon(
                                          Icons.picture_as_pdf_outlined,
                                        ),
                                        title: const Text('PDF Templates'),
                                        subtitle: Text(template.name),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const TemplateListScreen(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
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
                            subtitle: const Text(
                              '100% local, zero network calls',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showLegalSheet(
                              context,
                              title: 'Privacy Policy',
                              content: _kPrivacyPolicy,
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.gavel_outlined),
                            title: const Text('Terms of Use'),
                            subtitle: const Text(
                              'v2.2 · Effective 16 March 2026',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showLegalSheet(
                              context,
                              title: 'Terms of Use & Privacy Policy',
                              content: _kTermsOfUse,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  )
                : _buildSearchResults(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Wide layout (≥ 840 dp)
  // ---------------------------------------------------------------------------

  Widget _buildWideScaffold(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> appLockAsync,
    AsyncValue<bool> biometricAsync,
    ThemeMode themeMode,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Row(
        children: [
          SizedBox(width: 260, child: _buildSectionNav(context)),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: _buildSectionContent(
              context,
              ref,
              appLockAsync,
              biometricAsync,
              themeMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionNav(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: AppSpacing.sm),
        for (final section in _SettingsSectionId.values)
          ListTile(
            leading: Icon(section.icon),
            title: Text(section.label),
            selected: _selectedSection == section,
            selectedColor: context.colorScheme.primary,
            selectedTileColor: context.colorScheme.secondaryContainer
                .withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            onTap: () => setState(() => _selectedSection = section),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> appLockAsync,
    AsyncValue<bool> biometricAsync,
    ThemeMode themeMode,
  ) {
    final Widget content = switch (_selectedSection) {
      _SettingsSectionId.profile => _ProfileHeader(),
      _SettingsSectionId.plan => Consumer(
        builder: (ctx, r, _) {
          final tier = r.watch(subscriptionTierProvider);
          return _SettingsSection(
            title: 'KashCube Plan',
            children: [
              ListTile(
                leading: Icon(
                  tier.isFree
                      ? Icons.workspace_premium_outlined
                      : Icons.workspace_premium,
                  color: tier.isFree ? null : Theme.of(ctx).colorScheme.primary,
                ),
                title: Text(
                  tier.isFree
                      ? 'Upgrade to Starter or Business'
                      : 'Plan: ${tier.displayName}',
                ),
                subtitle: Text(
                  tier.isFree
                      ? 'Remove watermarks · Export reports · UPI QR'
                      : 'Manage your subscription',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                ),
              ),
            ],
          );
        },
      ),
      _SettingsSectionId.security => _SettingsSection(
        title: 'Security',
        children: [
          ListTile(
            leading: const Icon(Icons.fingerprint_rounded),
            title: const Text('My Identity'),
            subtitle: const Text('View your identity QR and display name'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          appLockAsync.when(
            data: (enabled) => SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('App Lock'),
              subtitle: Text(enabled ? 'PIN enabled' : 'Not configured'),
              value: enabled,
              onChanged: (value) => _toggleAppLock(context, ref, value),
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
      _SettingsSectionId.team => _SettingsSection(
        title: 'Team',
        children: [
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Team Members'),
            subtitle: const Text('Add staff, assign roles & permissions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
            ),
          ),
          Consumer(
            builder: (ctx, r, _) {
              final hasUsers = r.watch(hasAnyAppUserProvider);
              if (hasUsers.valueOrNull != true) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.switch_account_outlined),
                title: const Text('Switch Profile'),
                subtitle: const Text('Return to the profile selection screen'),
                onTap: () => r.read(switchUserProvider.notifier).state++,
              );
            },
          ),
        ],
      ),
      _SettingsSectionId.accounts => _SettingsSection(
        title: 'Accounts',
        children: [
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Accounts'),
            subtitle: const Text('Bank, UPI, Wallet, Cash · Opening Balances'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsManageScreen()),
            ),
          ),
        ],
      ),
      _SettingsSectionId.general => _SettingsSection(
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
              MaterialPageRoute(builder: (_) => const FyCloseWizardScreen()),
            ),
          ),
        ],
      ),
      _SettingsSectionId.data => _SettingsSection(
        title: 'Data',
        children: [
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Storage & Backup'),
            subtitle: const Text('Usage, backup & cache management'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StorageHealthScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Encrypted Backup (.kashcube)'),
            subtitle: const Text('Export or restore with AES-256 encryption'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EncryptedBackupScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Devices & LAN Sync'),
            subtitle: const Text('Pair devices and sync over Wi-Fi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DevicesScreen()),
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final enabled = ref.watch(libp2pSyncEnabledProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.science_outlined),
                title: const Text('Experimental: libp2p Sync'),
                subtitle: Text(
                  enabled
                      ? 'Using dart_libp2p (Phase 1) · Restart app to apply'
                      : 'Using WebRTC (default) · Enable for testing',
                ),
                value: enabled,
                onChanged: (v) =>
                    ref.read(libp2pSyncEnabledProvider.notifier).setEnabled(v),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.laptop_outlined),
            title: const Text('Open on Laptop'),
            subtitle: const Text('View KashCube in your browser over Wi-Fi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OpenOnLaptopScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Diagnostics Logs'),
            subtitle: const Text('View, copy, and share recent app logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppLogsScreen()),
            ),
          ),
        ],
      ),
      _SettingsSectionId.notifications => _SettingsSection(
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
      _SettingsSectionId.automation => const _AutomationSection(),
      _SettingsSectionId.privacy => const _PrivacySection(),
      _SettingsSectionId.business => Consumer(
        builder: (ctx, r, _) {
          final enabled = r.watch(businessModeProvider);
          return _SettingsSection(
            title: 'Business Mode',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.storefront_outlined),
                title: const Text('Enable Business Mode'),
                subtitle: const Text('Unlock invoicing & item catalog'),
                value: enabled,
                onChanged: (v) =>
                    r.read(businessModeProvider.notifier).setEnabled(v),
              ),
              if (enabled) ...[
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('Business Profiles'),
                  subtitle: const Text('Name, address, GST, logo & more'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const BusinessesScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.straighten_outlined),
                  title: const Text('Unit Types'),
                  subtitle: const Text('Manage units used in item catalog'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const UnitTypesScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Default Terms & Conditions'),
                  subtitle: const Text(
                    'T&C footer for invoice, quote & booking PDFs',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const DocumentTermsScreen(),
                    ),
                  ),
                ),
                Consumer(
                  builder: (ctx2, r2, _) {
                    final template = r2.watch(documentTemplateProvider);
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: const Text('PDF Templates'),
                      subtitle: Text(template.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        ctx2,
                        MaterialPageRoute(
                          builder: (_) => const TemplateListScreen(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
      _SettingsSectionId.about => _SettingsSection(
        title: 'About',
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Kash Cube'),
            subtitle: const Text('v1.0.0 · Privacy-first financial tracker'),
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
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLegalSheet(
              context,
              title: 'Privacy Policy',
              content: _kPrivacyPolicy,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of Use'),
            subtitle: const Text('v2.2 · Effective 16 March 2026'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLegalSheet(
              context,
              title: 'Terms of Use & Privacy Policy',
              content: _kTermsOfUse,
            ),
          ),
        ],
      ),
    };
    return ListView(
      children: [
        content,
        const SizedBox(height: AppSpacing.xxl),
      ],
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
              child: Text('Choose Theme', style: context.textTheme.titleMedium),
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

  void _toggleAppLock(BuildContext context, WidgetRef ref, bool enable) {
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
      final canAuth =
          await localAuth.canCheckBiometrics ||
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
              MaterialPageRoute(builder: (_) => const MyPersonalCardScreen()),
            );
            ref.invalidate(_profileProvider);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.base,
              AppSpacing.base,
              AppSpacing.sm,
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
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
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

  const _SettingsSection({required this.title, required this.children});

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

// ---------------------------------------------------------------------------
// Automation section (SMS auto-detect + inbox scan)
// ---------------------------------------------------------------------------

class _AutomationSection extends ConsumerWidget {
  const _AutomationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoDetect = ref.watch(smsAutoDetectEnabledProvider);
    final scanning = ref.watch(smsScanningProvider);
    final lastScan = ref.watch(smsLastScanProvider);

    String subtitleText;
    if (lastScan == null) {
      subtitleText = 'Never scanned';
    } else {
      subtitleText = 'Last scanned: ${DateFormatter.formatDateTime(lastScan)}';
    }

    return _SettingsSection(
      title: 'Automation',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sms_outlined),
          title: const Text('Auto-detect SMS transactions'),
          subtitle: const Text(
            'Detect bank & UPI transactions from incoming SMS',
          ),
          value: autoDetect,
          onChanged: (v) async {
            if (!v) {
              ref.read(smsAutoDetectEnabledProvider.notifier).setEnabled(false);
              return;
            }
            // Show rationale + OS permission request before enabling.
            // SmsPermissionScreen calls setEnabled(true/false) internally.
            if (!context.mounted) return;
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const SmsPermissionScreen()),
            );
          },
        ),
        ListTile(
          leading: scanning
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.inbox_outlined),
          title: const Text('Scan SMS inbox'),
          subtitle: Text(subtitleText),
          trailing: scanning ? null : const Icon(Icons.chevron_right),
          onTap: scanning ? null : () => _scanInbox(context, ref),
        ),
      ],
    );
  }

  Future<void> _scanInbox(BuildContext context, WidgetRef ref) async {
    final smsService = ref.read(smsServiceProvider);
    final hasPermission = await smsService.hasPermission;

    if (!hasPermission) {
      final granted = await smsService.requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS permission is required to scan inbox.'),
            ),
          );
        }
        return;
      }
    }

    final count = await scanSmsInbox(ref);

    if (context.mounted) {
      final msg = count == 0
          ? 'No new transactions found in SMS inbox.'
          : 'Found $count new transaction${count == 1 ? '' : 's'} — review them on the Home screen.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

// ---------------------------------------------------------------------------
// Privacy section (analytics consent toggle)
// ---------------------------------------------------------------------------

class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentAsync = ref.watch(analyticsConsentProvider);

    return _SettingsSection(
      title: 'Privacy',
      children: [
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Permissions'),
          subtitle: const Text(
            'Check real-time permission status and troubleshoot',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PermissionsScreen()),
          ),
        ),
        consentAsync.when(
          loading: () => const ListTile(
            leading: Icon(Icons.analytics_outlined),
            title: Text('Anonymous Analytics'),
            trailing: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => const ListTile(
            leading: Icon(Icons.analytics_outlined),
            title: Text('Anonymous Analytics'),
            subtitle: Text('Error loading setting'),
          ),
          data: (consent) => SwitchListTile(
            secondary: const Icon(Icons.analytics_outlined),
            title: const Text('Anonymous Analytics'),
            subtitle: const Text(
              'Share anonymous feature usage to help improve the app. '
              'No financial data is ever included.',
            ),
            value: consent ?? false,
            onChanged: (value) =>
                ref.read(analyticsConsentProvider.notifier).setConsent(value),
          ),
        ),
      ],
    );
  }
}

// ── Legal bottom-sheet helper ─────────────────────────────────────────────────

void _showLegalSheet(
  BuildContext context, {
  required String title,
  required String content,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                SelectableText(
                  content,
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Legal content ─────────────────────────────────────────────────────────────

const _kPrivacyPolicy =
    'Kash Cube — Privacy Policy\n'
    'Version 1.1 · Last Updated: March 22, 2026\n\n'
    'OUR COMMITMENT\n'
    'Kash Cube is built with privacy at its core. Your financial data is yours and yours alone.\n\n'
    'DATA STORAGE\n'
    'All data is stored locally on your device using SQLite. There is no cloud sync, no remote servers, and no login required. Your data never leaves your device.\n\n'
    'What we store:\n'
    '• Transaction amounts, categories, descriptions, and dates\n'
    '• Party names and notes (stored locally)\n'
    '• Account and credit records\n\n'
    'Where it is stored:\n'
    '• Android: App-private local storage\n'
    '• iOS: App sandbox (Application Support)\n\n'
    'DATA WE DO NOT COLLECT\n'
    '✗ Personal information (name, email, phone)\n'
    '✗ Location data\n'
    '✗ Device identifiers or advertising IDs\n'
    '✗ Crash reports\n'
    '✗ IP addresses\n'
    '✗ Any financial data sent to third parties\n\n'
    'ANALYTICS (opt-in, off by default)\n'
    'Optional anonymous analytics via Firebase Analytics — OFF by default. Enable in Settings → Privacy → Anonymous Analytics.\n\n'
    'When opted in, we collect:\n'
    '• Screen navigation events (e.g. "opened Reports")\n'
    '• Feature interaction events (e.g. "exported CSV")\n'
    '• App session metadata from Firebase (OS version, country)\n\n'
    'We NEVER collect (even when opted in):\n'
    '✗ Transaction amounts, descriptions, or dates\n'
    '✗ Party names, balances, or contact details\n'
    '✗ SMS content\n'
    '✗ Any personally identifiable financial information\n\n'
    'Disabling analytics stops all event collection immediately.\n\n'
    'PERMISSIONS\n'
    'Core app storage: Local SQLite files on your device\n'
    'Declared on Android build:\n'
    '• Internet + network state (LAN web companion/P2P sync and optional analytics transport)\n'
    '• Wi-Fi/multicast access (LAN discovery and local connectivity)\n'
    '• Notifications + boot receiver + vibration (local reminders)\n'
    '• Camera (QR scan and camera capture flows)\n'
    '• Contacts read/write (optional import/save contact flows)\n'
    '• Biometric/fingerprint (optional app lock)\n'
    '• Billing/install-referrer permissions (Play Billing and install attribution)\n'
    '• Additional platform/SDK-injected permissions used by enabled dependencies\n\n'
    'Runtime prompts shown only when feature is used:\n'
    '• Notifications (when enabling reminders)\n'
    '• SMS (when enabling SMS auto-detect)\n'
    '• Camera (when using QR/camera flows)\n'
    '• Contacts (when importing/saving contacts)\n'
    '• Biometric (when enabling biometric app lock)\n\n'
    'DATA SHARING\n'
    'We do not share any data — because we do not have access to it. Your data never leaves your device, is never uploaded, and is never sold.\n\n'
    'SECURITY\n'
    '• Device-level security (lock screen, encryption)\n'
    '• PIN protected with PBKDF2-HMAC-SHA256 (100,000 iterations)\n'
    '• No data transmission = no network interception risk\n\n'
    'YOUR RIGHTS\n'
    '• Access: View all your data in the app at any time\n'
    '• Delete: Uninstall the app to clear all data\n'
    '• Export: PDF/CSV export from within the app\n'
    '• Modify: Edit or delete any record\n\n'
    'COMPLIANCE\n'
    'GDPR: Compliant by design — no data collection\n'
    'CCPA: Compliant — no data sale\n'
    'COPPA: Compliant — no collection from anyone\n'
    'DPDP Act 2023: Compliant\n\n'
    'CONTACT\n'
    'Review the code or raise an issue on the official GitHub repository. Trust, but verify.';

const _kTermsOfUse =
    'Kash Cube — Terms of Use & Privacy Policy\n'
    'Version 2.2 (Hardened) · Effective: 16 March 2026\n\n'
    'ACCEPTANCE OF TERMS\n'
    'By downloading, installing, or using Kash Cube, you agree to these Terms. These Terms form a legally binding agreement between you and the developer of Kash Cube.\n\n'
    'ELIGIBILITY\n'
    'You must be at least 18 years old and legally capable of entering into a binding agreement.\n\n'
    'NATURE OF THE APP\n'
    'Kash Cube is a financial record-keeping tool for transaction logging, invoice generation, payment tracking, and GST-related calculations. It is not a substitute for professional accounting, legal, or tax services.\n\n'
    'NO FINANCIAL, LEGAL, OR TAX ADVICE\n'
    'Nothing in the App constitutes financial, accounting, legal, tax, or investment advice. Outputs are generated from user-entered data and may contain errors. You are solely responsible for reviewing and validating all information before relying on it.\n\n'
    'GST COMPLIANCE DISCLAIMER\n'
    'The App may assist with GST-related workflows but does not guarantee that any output is accurate, complete, or compliant. GST laws may change at any time. You are solely responsible for verifying GST values and filing accurate returns.\n\n'
    'DATA & PRIVACY\n'
    'Kash Cube is a privacy-first, local-first application. Financial records are stored on your device only. The Developer does not transmit your financial records to its servers.\n\n'
    'You are solely responsible for data accuracy, backups, and device security. The Developer cannot recover data lost due to device failure, theft, factory reset, or uninstall.\n\n'
    'On Android, the App may request optional runtime permissions for Notifications, SMS, Camera, Contacts, and Biometric features. These are requested contextually when the related feature is used. Financial and contact data is processed on-device only.\n\n'
    'SECURITY DISCLAIMER\n'
    'No software can be guaranteed fully secure. The Developer is not responsible for compromise caused by rooted devices, malware, or unauthorised device access.\n\n'
    'DISCLAIMER OF WARRANTIES\n'
    'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF ANY KIND, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.\n\n'
    'LIMITATION OF LIABILITY\n'
    'To the maximum extent permitted by law, the Developer is not liable for indirect, incidental, special, or consequential damages. Aggregate liability will not exceed the amount paid by you in the 12 months preceding the claim, or INR 1 if no amount was paid.\n\n'
    'INDEMNIFICATION\n'
    'You agree to defend, indemnify, and hold harmless the Developer from claims arising from your misuse of the App, your content, or your violation of law or these Terms.\n\n'
    'INTELLECTUAL PROPERTY\n'
    'All rights in the App remain with the Developer. You receive a limited, non-exclusive, revocable licence to use the App per these Terms. You may not copy, modify, distribute, reverse engineer, or decompile the App except where prohibited by law.\n\n'
    'PROHIBITED USES\n'
    'You must not use the App for unlawful activity, fraud, tax evasion, money laundering, or unauthorised processing of third-party personal data.\n\n'
    'DISPUTE RESOLUTION\n'
    'Any dispute shall be resolved by binding arbitration under the Arbitration and Conciliation Act, 1996. Seat: Puducherry, India. Language: English. Claims must be filed within one (1) year of arising.\n\n'
    'CLASS ACTION WAIVER\n'
    'Disputes will be resolved on an individual basis only. You waive any right to participate in class-action or representative proceedings.\n\n'
    'GOVERNING LAW\n'
    'These Terms are governed by the laws of India. The courts at Puducherry shall have jurisdiction for matters not subject to arbitration.\n\n'
    'CONTACT\n'
    'For support or legal questions, contact the official support channel listed on the App store listing.\n\n'
    'Last Updated: March 2026';
