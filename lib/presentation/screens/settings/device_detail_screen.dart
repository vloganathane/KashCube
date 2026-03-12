import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/linked_device.dart';
import '../../providers/sync_provider.dart';

/// Detail view for a single linked device.
/// Shows device info, sync history, and provides a revoke action.
class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({super.key, required this.device});

  final LinkedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(device.deviceName),
        actions: [
          if (device.isActive)
            IconButton(
              icon: Icon(Icons.link_off_rounded, color: cs.error),
              tooltip: 'Revoke access',
              onPressed: () => _confirmRevoke(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // ── Status banner ──────────────────────────────────────────────
          if (!device.isActive)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color:        cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.block_rounded, color: cs.onErrorContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Access revoked on ${DateFormatter.format(device.revokedAt!)}',
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          if (!device.isActive) const SizedBox(height: AppSpacing.base),

          // ── Device info card ───────────────────────────────────────────
          _InfoCard(
            children: [
              _InfoRow(
                icon: device.deviceType == 'tablet'
                    ? Icons.tablet_android_rounded
                    : Icons.smartphone_rounded,
                label: 'Device',
                value: device.deviceName,
              ),
              if (device.deviceOs != null)
                _InfoRow(
                  icon:  Icons.phone_android_rounded,
                  label: 'OS',
                  value: device.deviceOs!,
                ),
              _InfoRow(
                icon:  Icons.admin_panel_settings_outlined,
                label: 'Role',
                value: device.preset.label,
              ),
              _InfoRow(
                icon:  Icons.timer_outlined,
                label: 'Offline grace',
                value: '${device.offlineGraceDays} days',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.base),

          // ── Sync info card ─────────────────────────────────────────────
          _InfoCard(
            children: [
              _InfoRow(
                icon:  Icons.sync_rounded,
                label: 'Last sync',
                value: device.lastSyncAt != null
                    ? DateFormatter.format(device.lastSyncAt!)
                    : 'Never',
              ),
              if (device.createdAt != null)
                _InfoRow(
                  icon:  Icons.link_rounded,
                  label: 'Linked on',
                  value: DateFormatter.format(device.createdAt!),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Revoke button ──────────────────────────────────────────────
          if (device.isActive)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _confirmRevoke(context, ref),
              icon:  const Icon(Icons.link_off_rounded),
              label: const Text('Revoke Access'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text(
          '${device.deviceName} will no longer be able to sync with this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await ref.read(linkedDevicesProvider.notifier).revoke(device.deviceId);
    if (context.mounted) Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Reusable info card + row
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: 52),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String   label;
  final String   value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title:   Text(label, style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: cs.onSurfaceVariant)),
      subtitle: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
      dense: true,
    );
  }
}
