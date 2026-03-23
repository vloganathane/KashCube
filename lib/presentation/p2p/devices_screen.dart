import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../data/models/peer_device.dart';
import '../../data/models/trusted_peer.dart';
import '../../data/services/p2p/p2p_coordinator.dart';
import '../../data/services/p2p/p2p_discovery_service.dart';
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

    // Refresh the trusted-peers list ("last synced" timestamps) whenever a
    // sync cycle completes so the UI reflects the updated DB values.
    ref.listen<AsyncValue<SyncStatus>>(p2pSyncStatusProvider, (_, next) {
      next.whenData((status) {
        if (status.phase == SyncPhase.done) {
          ref.invalidate(trustedPeersProvider);
        }
      });
    });

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

          // ── Diagnostics (tap to expand) ──────────────────────────────────
          if (enabled) const _DiagnosticsPanel(),

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
        heroTag: null,
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

class _TrustedPeerTile extends ConsumerWidget {
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

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final name = peer.peerName ?? 'this device';
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          '$name will no longer be able to sync with this device. '
          'Your existing data is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await P2pCoordinator.instance.revokePeer(peer.peerIdentityId);
    ref.invalidate(trustedPeersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name removed'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Paired ${DateFormat('d MMM').format(peer.pairedAt)}',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Device options',
            onSelected: (v) {
              if (v == 'revoke') _confirmRevoke(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'revoke',
                child: Row(
                  children: [
                    Icon(Icons.link_off,
                        size: 18, color: context.colorScheme.error),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Revoke access',
                      style: TextStyle(color: context.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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

// ── Diagnostics panel ──────────────────────────────────────────────────────

/// Collapsible section showing the local server address, a live mDNS
/// event log, and a live HTTP request log with a /hello probe button.
class _DiagnosticsPanel extends ConsumerStatefulWidget {
  const _DiagnosticsPanel();

  @override
  ConsumerState<_DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends ConsumerState<_DiagnosticsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _testResult;
  bool    _testing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _testHello() async {
    if (_testing) return;
    // dart:io HttpClient is not available on Flutter Web.
    if (kIsWeb) {
      setState(() { _testResult = '⚠️ Not available in browser'; });
      return;
    }
    setState(() { _testing = true; _testResult = null; });
    final ip   = await P2pDiscoveryService.getLocalIp();
    final port = P2pCoordinator.instance.serverPort;
    if (ip == null || port == null) {
      setState(() { _testResult = '❌ Server not running'; _testing = false; });
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req  = await client.getUrl(Uri.parse('http://$ip:$port/hello'));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      final body = await resp.transform(Utf8Decoder()).join();
      setState(() {
        _testResult = resp.statusCode == 200
            ? '✅ $ip:$port  →  $body'
            : '❌ HTTP ${resp.statusCode}';
      });
    } catch (e) {
      setState(() { _testResult = '❌ $e'; });
    } finally {
      client.close(force: true);
      setState(() { _testing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final discoveryLog = ref.watch(p2pDiscoveryLogProvider).valueOrNull ?? const [];
    final httpLog      = ref.watch(p2pServerLogProvider).valueOrNull    ?? const [];
    final ipAsync      = ref.watch(p2pLocalIpProvider);

    final ip   = ipAsync.valueOrNull;
    final port = P2pCoordinator.instance.serverPort;
    final addressLine = [
      if (ip != null) ip,
      if (port != null) 'port $port',
    ].join('  ');

    return ExpansionTile(
      leading: Icon(
        Icons.bug_report_outlined,
        color: context.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        'Diagnostics',
        style: context.textTheme.bodyMedium,
      ),
      subtitle: Text(
        addressLine.isEmpty ? 'Starting…' : addressLine,
        style: context.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.base, 0, AppSpacing.base, AppSpacing.base,
      ),
      children: [
        // ── Tab bar ──────────────────────────────────────────────────────
        TabBar(
          controller:     _tabController,
          labelStyle:     context.textTheme.labelSmall,
          indicatorSize:  TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'mDNS'),
            Tab(text: 'Web / HTTP'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── mDNS tab ─────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            if (_tabController.index != 0) return const SizedBox.shrink();
            return _LogBox(
              log:         discoveryLog,
              addressLine: addressLine,
              label:       'mDNS',
            );
          },
        ),

        // ── Web / HTTP tab ────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            if (_tabController.index != 1) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Test button
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _testing ? null : _testHello,
                      child: _testing
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Test /hello'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _testResult ?? 'Tap to probe the server from this device',
                        style: context.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _LogBox(
                  log:         httpLog,
                  addressLine: addressLine,
                  label:       'HTTP',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Shared log-box widget used by both the mDNS and HTTP tabs.
class _LogBox extends StatelessWidget {
  const _LogBox({
    required this.log,
    required this.addressLine,
    required this.label,
  });

  final List<String> log;
  final String addressLine;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                log.isEmpty ? 'No events yet' : '${log.length} event(s)',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copy log',
              onPressed: () {
                final text = log.reversed.join('\n');
                Clipboard.setData(ClipboardData(
                  text: '--- KashCube $label Log ---\n'
                      'Server: $addressLine\n\n$text',
                ));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Log copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
        if (log.isNotEmpty) ...[
          const Divider(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:        context.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: log.reversed.take(30).map(
                (e) => Text(
                  e,
                  style: context.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: context.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
