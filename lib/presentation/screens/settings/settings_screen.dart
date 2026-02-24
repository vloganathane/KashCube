import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';

/// Settings screen for app preferences, backup, and security.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          _SettingsSection(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Theme'),
                subtitle: const Text('System default'),
                onTap: () {
                  // TODO: Theme picker
                },
              ),
            ],
          ),
          _SettingsSection(
            title: 'Security',
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('App Lock'),
                subtitle: const Text('Not configured'),
                onTap: () {
                  // TODO: PIN / Biometric setup
                },
              ),
            ],
          ),
          _SettingsSection(
            title: 'Data',
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Backup'),
                subtitle: const Text('Create a local backup'),
                onTap: () {
                  // TODO: Backup
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore'),
                subtitle: const Text('Restore from backup'),
                onTap: () {
                  // TODO: Restore
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Export CSV'),
                subtitle: const Text('Export transactions to CSV'),
                onTap: () {
                  // TODO: Export
                },
              ),
            ],
          ),
          _SettingsSection(
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
                    applicationLegalese: '© 2026 Kash Cube\nAll data stays on your device.',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                subtitle: const Text('100% local, zero network calls'),
                onTap: () {
                  // TODO: Show privacy policy
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

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
