import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/linked_device.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/qr_scanner_sheet.dart' show showQrScannerSheet;
import 'device_detail_screen.dart';
import 'link_device_screen.dart';

/// Shows all non-revoked devices linked to this device.
/// - PRIMARY (already has linked devices or confirmed host): FAB → [LinkDeviceScreen] (show QR).
/// - SECONDARY (already paired): FAB → Sync; AppBar → Re-pair QR scanner.
/// - UNPAIRED (neither role yet): FAB → role picker (host QR or scan QR).
class LinkedDevicesScreen extends ConsumerWidget {
  const LinkedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync     = ref.watch(linkedDevicesProvider);
    final isSecondaryAsync = ref.watch(isSecondaryDeviceProvider);
    final isSecondary      = isSecondaryAsync.valueOrNull ?? false;
    final syncState        = ref.watch(syncNowProvider);

    ref.listen<SyncNowState>(syncNowProvider, (_, next) {
      if (!context.mounted) return;
      if (next.status == SyncStatus.done) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Synced — ${next.pulled} received, ${next.pushed} sent'),
        ));
      } else if (next.status == SyncStatus.error && next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(next.error!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(linkedDevicesProvider.notifier).refresh(),
          ),
          if (isSecondary)
            IconButton(
              icon:    const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Re-pair (Scan QR)',
              onPressed: () => _scanAndJoin(context, ref),
            ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (devices) {
          if (devices.isEmpty) {
            return _EmptyState(isSecondary: isSecondary);
          }
          return ListView.separated(
            padding:          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount:        devices.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder:      (_, i) => _DeviceTile(device: devices[i]),
          );
        },
      ),
      floatingActionButton: isSecondary
          ? FloatingActionButton.extended(
              onPressed: syncState.isRunning
                  ? null
                  : () => ref.read(syncNowProvider.notifier).syncNow(),
              icon: syncState.isRunning
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_syncLabel(syncState.status)),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showLinkRolePicker(context, ref),
              icon:  const Icon(Icons.add_link_rounded),
              label: const Text('Link Device'),
            ),
    );
  }

  Future<void> _showLinkRolePicker(BuildContext context, WidgetRef ref) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.lg,
            horizontal: AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.md,
                ),
                child: Text(
                  'How do you want to link?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                title: const Text('Show QR — link another device to me'),
                subtitle: const Text(
                  'This device acts as the primary host',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LinkDeviceScreen()),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: cs.onSecondaryContainer,
                  ),
                ),
                title: const Text('Scan QR — join another device'),
                subtitle: const Text(
                  'Scan the QR shown on the primary device',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _scanAndJoin(context, ref);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanAndJoin(BuildContext context, WidgetRef ref) async {
    final result = await showQrScannerSheet(context);
    if (result == null || !context.mounted) return;

    final rawQr = result['name'];
    if (rawQr == null || !rawQr.startsWith('{')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a KashCube pairing QR.')),
      );
      return;
    }

    try {
      final payload = jsonDecode(rawQr) as Map<String, dynamic>;
      if (payload['type'] != 'kashcube_pair_v1') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unrecognised QR type.')),
        );
        return;
      }
      final ip     = payload['ip']     as String;
      final port   = payload['port']   as int;
      final preset = payload['preset'] as String? ?? 'owner_mirror';

      // D3: identity-first pairing — confirm who we are linking with.
      final primaryDisplayName = payload['primary_display_name'] as String?;
      if (primaryDisplayName != null && context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _LinkConfirmDialog(primaryName: primaryDisplayName),
        );
        if (confirmed != true || !context.mounted) return;
      }

      await ref.read(linkJoinProvider.notifier).pair(
            ip:     ip,
            port:   port,
            preset: preset,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paired successfully!')),
      );
      ref.read(linkedDevicesProvider.notifier).refresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pairing failed. Please try again.')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Link confirmation dialog
// ---------------------------------------------------------------------------

/// Shown when the QR payload includes the primary's identity display name.
/// Gives the user a chance to verify they are linking to the right person.
class _LinkConfirmDialog extends StatelessWidget {
  const _LinkConfirmDialog({required this.primaryName});
  final String primaryName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Confirm pairing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 48, color: cs.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'You are linking to:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            primaryName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Make sure you are on the same Wi-Fi as this person before confirming.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Link'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Device tile
// ---------------------------------------------------------------------------

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final LinkedDevice device;

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final lastSync = device.lastSyncAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical:   AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Icon(
          device.deviceType == 'web'
              ? Icons.laptop_rounded
              : device.deviceType == 'tablet'
                  ? Icons.tablet_android_rounded
                  : Icons.smartphone_rounded,
          color: cs.onPrimaryContainer,
        ),
      ),
      title: Text(
        // D3: Prefer identity display name (e.g. "Ravi Kumar") over device name.
        device.secondaryDisplayName ?? device.deviceName,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.deviceType == 'web' ? 'Browser Session' : device.preset.label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.primary),
          ),
          if (lastSync != null)
            Text(
              '${device.deviceType == 'web' ? 'Last active' : 'Last sync'}: ${DateFormatter.format(lastSync)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DeviceDetailScreen(device: device)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSecondary});
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isSecondary ? 'Paired as secondary device' : 'No linked devices yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isSecondary
                  ? 'Tap "Sync Now" to exchange changes with your primary device.'
                  : 'Link a tablet or second phone to share your Kash Cube data over Wi-Fi. No internet needed.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

String _syncLabel(SyncStatus status) => switch (status) {
      SyncStatus.scanning   => 'Scanning…',
      SyncStatus.connecting => 'Connecting…',
      SyncStatus.syncing    => 'Syncing…',
      _                     => 'Sync Now',
    };

