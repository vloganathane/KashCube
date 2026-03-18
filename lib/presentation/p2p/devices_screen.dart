import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../data/models/peer_device.dart';
import '../../data/models/trusted_peer.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../providers/p2p_provider.dart';
import 'pair_screen.dart';

/// Lists peers visible on the local LAN and shows live sync status.
///
/// Accessible from Settings → Devices & LAN Sync.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled          = ref.watch(p2pEnabledProvider);
    final peersAsync        = ref.watch(p2pPeersProvider);
    final statusAsync       = ref.watch(p2pSyncStatusProvider);
    final trustedPeersAsync = ref.watch(trustedPeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices & LAN Sync'),
        actions: [
          if (enabled)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync Now',
              onPressed: () => P2pCoordinator.instance.syncNow(),
            ),
        ],
      ),
      body: ListView(
        children: [
          // ── Enable toggle ──────────────────────────────────────────────
          SwitchListTile(
            secondary: Icon(
              enabled ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              color: enabled ? context.colorScheme.primary : null,
            ),
            title: const Text('LAN Sync'),
            subtitle: Text(
              enabled
                  ? 'Syncing with trusted devices on this network'
                  : 'Tap to start syncing on your local Wi-Fi',
            ),
            value: enabled,
            onChanged: (v) {
              if (v) {
                ref.read(p2pEnabledProvider.notifier).enable();
              } else {
                ref.read(p2pEnabledProvider.notifier).disable();
              }
            },
          ),

          const Divider(height: 1),

          // ── Sync status banner ─────────────────────────────────────────
          statusAsync.when(
            data:    (s) => _SyncStatusBanner(status: s),
            loading: () => const SizedBox.shrink(),
            error:   (_, _) => const SizedBox.shrink(),
          ),

          // ── Paired devices ─────────────────────────────────────────────
          trustedPeersAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, _) => const SizedBox.shrink(),
            data: (peers) {
              if (peers.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base, AppSpacing.lg,
                      AppSpacing.base, AppSpacing.sm,
                    ),
                    child: Text(
                      'PAIRED DEVICES',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  ...peers.map((p) => _TrustedPeerTile(peer: p)),
                  const Divider(height: 1),
                ],
              );
            },
          ),

          // ── Peer list ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.sm,
            ),
            child: Text(
              'NEARBY DEVICES',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),

          peersAsync.when(
            data: (peers) => peers.isEmpty
                ? _EmptyPeers(enabled: enabled)
                : Column(
                    children: peers
                        .map((p) => _PeerTile(peer: p))
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text('Discovery error: $e',
                  style: TextStyle(color: context.colorScheme.error)),
            ),
          ),

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),

      // ── FAB: open PairScreen ───────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PairScreen()),
        ),
        icon:  const Icon(Icons.qr_code_scanner),
        label: const Text('Pair Device'),
      ),
    );
  }
}

// ── Trusted peer tile ──────────────────────────────────────────────────

class _TrustedPeerTile extends StatelessWidget {
  const _TrustedPeerTile({required this.peer});

  final TrustedPeer peer;

  String _ago(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Synced just now';
    if (diff.inMinutes < 60)  return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return 'Synced ${diff.inHours}h ago';
    if (diff.inDays    < 30)  return 'Synced ${diff.inDays}d ago';
    return 'Synced ${DateFormat('d MMM').format(dt)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.incomeBackground,
        child: Icon(Icons.devices, color: colors.income, size: 20),
      ),
      title: Text(peer.peerName ?? 'Unknown Device'),
      subtitle: Text(
        _ago(peer.lastSyncedAt),
        style: TextStyle(
          color: peer.lastSyncedAt != null
              ? colors.income
              : context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        'Paired ${DateFormat('d MMM').format(peer.pairedAt)}',
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── Sync status banner ─────────────────────────────────────────────────────

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final phase = status.phase;
    if (phase == SyncPhase.idle || phase == SyncPhase.starting) {
      return const SizedBox.shrink();
    }

    final (icon, color) = switch (phase) {
      SyncPhase.syncing => (Icons.sync, context.colorScheme.primary),
      SyncPhase.done    => (Icons.check_circle_outline, context.kashColors.income),
      SyncPhase.error   => (Icons.error_outline, context.colorScheme.error),
      _                 => (Icons.info_outline, context.colorScheme.secondary),
    };

    return Material(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            phase == SyncPhase.syncing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                status.message ?? '',
                style: context.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Icon(
            Icons.devices_other,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            enabled
                ? 'No devices found nearby'
                : 'Enable LAN Sync to discover devices',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Make sure the other device is on the same Wi-Fi and has LAN Sync enabled.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.outlineVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Peer tile ──────────────────────────────────────────────────────────────

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final PeerDevice peer;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: peer.isTrusted
            ? colors.incomeBackground
            : context.colorScheme.surfaceContainerHighest,
        child: Icon(
          peer.isTrusted ? Icons.devices : Icons.device_unknown_outlined,
          color: peer.isTrusted ? colors.income : context.colorScheme.outline,
          size: 20,
        ),
      ),
      title: Text(peer.displayName),
      subtitle: Text(
        peer.isTrusted ? '${peer.host}  ·  Trusted' : peer.host,
        style: TextStyle(
          color: peer.isTrusted
              ? colors.income
              : context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: peer.isTrusted
          ? null
          : TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const PairScreen()),
              ),
              child: const Text('Pair'),
            ),
    );
  }
}

// ── Shared formatter ───────────────────────────────────────────────────────

// ignore: unused_element
String _fmtTs(DateTime? dt) {
  if (dt == null) return 'Never';
  return DateFormat('d MMM, h:mm a').format(dt.toLocal());
}
