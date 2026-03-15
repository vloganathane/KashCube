import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/device_session_token.dart';
import '../../../data/models/linked_device.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/qr_scanner_sheet.dart' show showQrScannerSheet;
import 'device_detail_screen.dart';
import 'link_device_screen.dart';

/// Unified "Devices & Sync" screen — replaces the former separate
/// "Linked Devices" and "Linked Sessions" screens.
///
/// Two sections, each shown only when populated:
///   • "Devices I manage"  — primary side ([linked_devices] table)
///   • "Businesses I'm connected to" — secondary side ([device_session] table)
///
/// When both are empty a unified empty state + role-picker FAB is shown.
class DevicesSyncScreen extends ConsumerWidget {
  const DevicesSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync  = ref.watch(linkedDevicesProvider);
    final sessionsAsync = ref.watch(linkedSessionsProvider);
    final isSecondary   = ref.watch(isSecondaryDeviceProvider).valueOrNull ?? false;
    final syncState     = ref.watch(syncNowProvider);

    final devices           = devicesAsync.valueOrNull  ?? [];
    final sessions          = sessionsAsync.valueOrNull ?? [];
    final isLoading         = devicesAsync.isLoading || sessionsAsync.isLoading;
    final hasManagedDevices = devices.isNotEmpty;
    final hasSessions       = sessions.isNotEmpty;

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
        title: const Text('Devices & Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(linkedDevicesProvider.notifier).refresh();
              ref.read(linkedSessionsProvider.notifier).refresh();
            },
          ),
          if (isSecondary)
            IconButton(
              icon:    const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Scan QR to link',
              onPressed: () => _scanAndJoin(context, ref),
            ),
          // Both roles: expose Link Device in AppBar so it's reachable
          // alongside the Sync Now FAB
          if (hasManagedDevices && isSecondary)
            IconButton(
              icon:    const Icon(Icons.add_link_rounded),
              tooltip: 'Link Device',
              onPressed: () => _showLinkRolePicker(context, ref),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!hasManagedDevices && !hasSessions)
              ? const _UnifiedEmptyState()
              : CustomScrollView(
                  slivers: [
                    if (hasManagedDevices) ..._managedDevicesSection(
                        context, devices),
                    if (hasSessions) ..._linkedSessionsSection(
                        context, sessions,
                        addTopPadding: hasManagedDevices),
                    const SliverPadding(
                      padding: EdgeInsets.only(bottom: AppSpacing.xxxl),
                    ),
                  ],
                ),
      floatingActionButton: isSecondary
          ? FloatingActionButton.extended(
              onPressed: syncState.isRunning
                  ? null
                  : () => ref.read(syncNowProvider.notifier).syncNow(),
              icon: syncState.isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_syncLabel(syncState)),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showLinkRolePicker(context, ref),
              icon:  const Icon(Icons.add_link_rounded),
              label: const Text('Link Device'),
            ),
    );
  }

  List<Widget> _managedDevicesSection(
      BuildContext context, List<LinkedDevice> devices) {
    return [
      _sliverSectionHeader(context, 'Devices I manage'),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => i.isOdd
              ? const Divider(height: 1, indent: 72)
              : _DeviceTile(device: devices[i ~/ 2]),
          childCount: devices.length * 2 - 1,
        ),
      ),
    ];
  }

  List<Widget> _linkedSessionsSection(
      BuildContext context, List<DeviceSession> sessions,
      {bool addTopPadding = false}) {
    return [
      _sliverSectionHeader(
        context,
        "Businesses I'm connected to",
        topPadding: addTopPadding ? AppSpacing.lg : AppSpacing.xs,
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => i.isOdd
              ? const Divider(height: 1, indent: 72)
              : _SessionTile(session: sessions[i ~/ 2]),
          childCount: sessions.length * 2 - 1,
        ),
      ),
    ];
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
// Unified empty state
// ---------------------------------------------------------------------------

class _UnifiedEmptyState extends StatelessWidget {
  const _UnifiedEmptyState();

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
              Icons.devices_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No connections yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "Link Device" to manage another device from here, '
              'or scan a QR code to connect to a primary device over Wi-Fi.',
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
// Session tile (secondary side)
// ---------------------------------------------------------------------------

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final DeviceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final lastSync = session.lastSyncAt;
    final isRO     = session.isReadOnlyForced;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical:   AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: isRO ? cs.errorContainer : cs.primaryContainer,
        child: Icon(
          Icons.business_rounded,
          color: isRO ? cs.onErrorContainer : cs.onPrimaryContainer,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              session.businessName,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (isRO)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(Icons.lock_outline_rounded,
                  size: 16, color: cs.onSurfaceVariant),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _presetLabel(session.token),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.primary),
          ),
          if (lastSync != null)
            Text(
              'Last sync: ${DateFormatter.format(lastSync)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.link_off_rounded),
        tooltip: 'Unlink',
        color: cs.error,
        onPressed: () => _confirmUnlink(context, ref),
      ),
    );
  }

  String _presetLabel(DeviceSessionToken token) => switch (token.preset) {
        'owner_mirror' => 'Owner Mirror',
        'manager'      => 'Manager',
        'cashier'      => 'Cashier',
        'auditor'      => 'Auditor',
        _              => 'Custom',
      };

  Future<void> _confirmUnlink(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unlink session?'),
        content: Text(
          'This will remove the link to "${session.businessName}". '
          'You can re-link by scanning a new QR code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.errorContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onErrorContainer,
            ),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(linkedSessionsProvider.notifier)
          .unlink(session.sessionId);
    }
  }
}

// ---------------------------------------------------------------------------

SliverToBoxAdapter _sliverSectionHeader(
  BuildContext context,
  String label, {
  double topPadding = AppSpacing.sm,
}) {
  return SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.base, topPadding, AppSpacing.base, AppSpacing.xs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------

String _syncLabel(SyncNowState state) => switch (state.status) {
      SyncStatus.scanning   => 'Scanning…',
      SyncStatus.connecting => state.foundLabel != null
          ? 'Connecting to ${state.foundLabel}…'
          : 'Connecting…',
      SyncStatus.syncing    => state.foundLabel != null
          ? 'Syncing with ${state.foundLabel}…'
          : 'Syncing…',
      _                     => 'Sync Now',
    };

