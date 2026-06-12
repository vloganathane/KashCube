import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../data/services/app_logger.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/p2p/p2p_coordinator.dart';
import '../../../data/services/p2p/p2p_discovery_service.dart';
import '../../../data/services/p2p/p2p_server.dart';
import '../../../data/services/web/web_companion_auth_qr.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/p2p_provider.dart';

/// Shows the LAN URL for the browser companion and lets the phone scan the
/// browser's approval QR.
class OpenOnLaptopScreen extends ConsumerStatefulWidget {
  const OpenOnLaptopScreen({super.key});

  @override
  ConsumerState<OpenOnLaptopScreen> createState() => _OpenOnLaptopScreenState();
}

class _OpenOnLaptopScreenState extends ConsumerState<OpenOnLaptopScreen> {
  String? _url;
  String? _error;
  String _loadingMessage = 'Starting local server…';
  bool _loading = true;

  DateTime? _traceStartedAt;
  DateTime? _traceServerReadyAt;
  DateTime? _traceUrlReadyAt;
  DateTime? _traceScanStartedAt;
  DateTime? _traceScanDetectedAt;
  DateTime? _traceApprovedAt;
  bool _traceConnectionLogged = false;

  bool _diagnosticsLoading = false;
  bool? _diagnosticsHealthy;
  String? _diagnosticsIp;
  int? _diagnosticsPort;
  List<String> _diagnosticsInterfaces = const [];
  List<String> _diagnosticsHints = const [];
  String? _diagnosticsReport;

  @override
  void initState() {
    super.initState();
    _buildUrl();
  }

  int? _msBetween(DateTime? from, DateTime? to) {
    if (from == null || to == null) return null;
    return to.difference(from).inMilliseconds;
  }

  void _logTiming(
    String stage, {
    Map<String, Object?> extra = const {},
    AppLogLevel level = AppLogLevel.info,
  }) {
    final now = DateTime.now();
    final context = <String, Object?>{
      'stage': stage,
      'since_start_ms': _msBetween(_traceStartedAt, now),
      'since_server_ready_ms': _msBetween(_traceServerReadyAt, now),
      ...extra,
    };

    switch (level) {
      case AppLogLevel.warning:
        unawaited(
          AppLogger.instance.warning(
            'Web companion timing trace',
            category: 'web_companion_timing',
            eventName: 'web_companion_timing',
            context: context,
          ),
        );
        return;
      case AppLogLevel.error:
      case AppLogLevel.fatal:
        unawaited(
          AppLogger.instance.error(
            'Web companion timing trace',
            category: 'web_companion_timing',
            eventName: 'web_companion_timing',
            context: context,
          ),
        );
        return;
      default:
        unawaited(
          AppLogger.instance.info(
            'Web companion timing trace',
            category: 'web_companion_timing',
            eventName: 'web_companion_timing',
            context: context,
          ),
        );
        return;
    }
  }

  Future<void> _buildUrl() async {
    _traceStartedAt = DateTime.now();
    _traceServerReadyAt = null;
    _traceUrlReadyAt = null;
    _traceScanStartedAt = null;
    _traceScanDetectedAt = null;
    _traceApprovedAt = null;
    _traceConnectionLogged = false;
    _logTiming('open_on_laptop_started');

    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = 'Starting local server…';
    });

    // Start the HTTP server (web companion mode) if it isn't running yet.
    // This works whether or not the user has LAN sync enabled — the server
    // starts in server-only mode and does NOT turn on mDNS broadcast/discovery.
    await ref.read(webCompanionProvider.notifier).ensureStarted();
    _logTiming('server_start_requested');

    if (!mounted) return;
    setState(() {
      _loadingMessage = 'Preparing browser view…';
    });

    // Readiness gate: wait until the server socket is bound and static web
    // assets are ready before showing the LAN URL.
    var healthy = await P2pCoordinator.instance.isServerHealthy();
    for (var attempt = 0; !healthy && attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      healthy = await P2pCoordinator.instance.isServerHealthy();
    }
    if (!healthy) {
      _logTiming('server_warmup_timeout', level: AppLogLevel.warning);
      setState(() {
        _error = 'Server is still warming up. Please retry in a moment.';
        _loading = false;
      });
      return;
    }
    _traceServerReadyAt = DateTime.now();
    _logTiming('server_ready');

    // Use the actual bound port from the running server. This may differ from
    // AppConstants.p2pPort when startup falls back to a random free port.
    final port = P2pCoordinator.instance.serverPort;
    if (port == null) {
      _logTiming('server_port_missing', level: AppLogLevel.warning);
      await _refreshDiagnostics();
      setState(() {
        _error =
            'Could not start the local server. Restart the app and try again.';
        _loading = false;
      });
      return;
    }

    final ip = await P2pDiscoveryService.getLocalIp();
    if (ip == null || ip == '0.0.0.0') {
      _logTiming(
        'local_ip_unavailable',
        level: AppLogLevel.warning,
        extra: {'port': port},
      );
      await _refreshDiagnostics(portOverride: port);
      setState(() {
        _error =
            'Could not detect a local network address.\nConnect your phone to Wi-Fi or enable the hotspot, then try again.';
        _loading = false;
      });
      return;
    }

    final url = 'http://$ip:$port';

    await _refreshDiagnostics(ipOverride: ip, portOverride: port);

    if (mounted) {
      setState(() {
        _url = url;
        _loading = false;
      });
      _traceUrlReadyAt = DateTime.now();
      _logTiming(
        'url_ready',
        extra: {
          'port': port,
          'url_ready_ms': _msBetween(_traceStartedAt, _traceUrlReadyAt),
        },
      );
      trackEvent(ref, AnalyticsEvents.webCompanionQrShown);
    }
  }

  Future<void> _scanBrowserQr() async {
    _traceScanStartedAt = DateTime.now();
    _logTiming('scanner_opened');

    final parsed = await Navigator.of(context)
        .push<({String sessionId, String challenge})>(
          MaterialPageRoute(
            builder: (_) => const _BrowserApprovalScannerScreen(),
          ),
        );
    if (!mounted || parsed == null) return;

    _traceScanDetectedAt = DateTime.now();
    _logTiming(
      'qr_scanned',
      extra: {'scan_ms': _msBetween(_traceScanStartedAt, _traceScanDetectedAt)},
    );

    final approved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Approve Browser'),
            content: const Text(
              'Allow this browser tab to open KashCube on your local network?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Approve'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;

    _traceApprovedAt = DateTime.now();
    _logTiming(
      'approval_confirmed',
      extra: {
        'approve_dialog_ms': _msBetween(_traceScanDetectedAt, _traceApprovedAt),
      },
    );

    final ok = P2pCoordinator.instance.approveBrowserSession(
      sessionId: parsed.sessionId,
      challenge: parsed.challenge,
    );
    _logTiming(
      ok ? 'approval_sent_ok' : 'approval_sent_failed',
      level: ok ? AppLogLevel.info : AppLogLevel.warning,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Browser approved. The laptop should open now.'
              : 'Approval failed. Refresh the browser page and scan again.',
        ),
      ),
    );
  }

  Future<void> _refreshDiagnostics({
    String? ipOverride,
    int? portOverride,
  }) async {
    if (!mounted) return;
    setState(() {
      _diagnosticsLoading = true;
    });

    final healthy = await P2pCoordinator.instance.isServerHealthy();
    final port = portOverride ?? P2pCoordinator.instance.serverPort;
    final ip = ipOverride ?? await P2pDiscoveryService.getLocalIp();
    final interfaces = await _collectInterfaceSnapshot();
    final hints = _buildNetworkHints(
      healthy: healthy,
      ip: ip,
      port: port,
      interfaces: interfaces,
    );
    final report = _buildDiagnosticsReport(
      healthy: healthy,
      ip: ip,
      port: port,
      interfaces: interfaces,
      hints: hints,
    );

    if (!mounted) return;
    setState(() {
      _diagnosticsHealthy = healthy;
      _diagnosticsIp = ip;
      _diagnosticsPort = port;
      _diagnosticsInterfaces = interfaces;
      _diagnosticsHints = hints;
      _diagnosticsReport = report;
      _diagnosticsLoading = false;
    });
  }

  Future<List<String>> _collectInterfaceSnapshot() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      final lines = <String>[];
      for (final iface in interfaces) {
        final addresses = iface.addresses
            .where((a) => !a.isLoopback)
            .map((a) => a.address)
            .toList();
        if (addresses.isEmpty) continue;
        lines.add('${iface.name}: ${addresses.join(', ')}');
      }
      return lines;
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to enumerate network interfaces',
        category: 'open_on_laptop',
        error: e,
      );
      return const [];
    }
  }

  List<String> _buildNetworkHints({
    required bool healthy,
    required String? ip,
    required int? port,
    required List<String> interfaces,
  }) {
    final hints = <String>[];

    if (!healthy || port == null) {
      hints.add(
        'Server is not fully ready yet. Tap "Refresh diagnostics" after a few seconds.',
      );
      return hints;
    }

    if (ip == null || ip == '0.0.0.0') {
      hints.add(
        'No reachable LAN IP detected on phone. Enable Wi-Fi or phone hotspot and retry.',
      );
      return hints;
    }

    hints.add(
      'Same-device check: open http://127.0.0.1:$port on this phone. If this works, shelf is healthy.',
    );
    hints.add(
      'Laptop check: open http://$ip:$port on laptop browser while both devices are on same Wi-Fi/hotspot.',
    );
    hints.add(
      'If phone works but laptop fails, this is usually network isolation (guest Wi-Fi/AP isolation/VPN/firewall), not shelf.',
    );

    final hasLikelyLanIface = interfaces.any(
      (line) =>
          line.startsWith('wlan') ||
          line.startsWith('en') ||
          line.startsWith('ap'),
    );
    if (!hasLikelyLanIface) {
      hints.add(
        'No typical LAN interface found (wlan/en/ap). You may be on cellular/VPN-only path.',
      );
    }

    return hints;
  }

  String _buildDiagnosticsReport({
    required bool healthy,
    required String? ip,
    required int? port,
    required List<String> interfaces,
    required List<String> hints,
  }) {
    final lines = <String>[
      'KashCube Web Companion Diagnostics',
      'Time: ${DateTime.now().toIso8601String()}',
      'Server healthy: $healthy',
      'Bound port: ${port ?? 'unknown'}',
      'Local IP: ${ip ?? 'unknown'}',
      if (port != null) 'Loopback URL: http://127.0.0.1:$port',
      if (ip != null && port != null) 'LAN URL: http://$ip:$port',
      '',
      'IPv4 interfaces:',
      if (interfaces.isEmpty) '- none detected',
      ...interfaces.map((e) => '- $e'),
      '',
      'Troubleshooting hints:',
      ...hints.map((e) => '- $e'),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    // Fire once each time a browser successfully authenticates.
    ref.listen<AsyncValue<bool>>(browserConnectionEventProvider, (_, next) {
      next.whenData((connected) {
        if (!connected) return;
        trackEvent(ref, AnalyticsEvents.webCompanionBrowserConnected);

        if (_traceConnectionLogged) return;
        _traceConnectionLogged = true;
        final now = DateTime.now();
        _logTiming(
          'browser_connected',
          extra: {
            'total_connect_ms': _msBetween(_traceStartedAt, now),
            'url_to_connect_ms': _msBetween(_traceUrlReadyAt, now),
            'scan_to_connect_ms': _msBetween(_traceScanDetectedAt, now),
            'approve_to_connect_ms': _msBetween(_traceApprovedAt, now),
          },
        );
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open on Laptop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh server',
            onPressed: _buildUrl,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.base),
            Text(
              'Open this URL on your laptop',
              style: context.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The browser page will show a QR code. Scan that QR with KashCube on this phone to approve access.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_loading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _loadingMessage,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _buildUrl)
            else ...[
              _UrlChip(
                url: _url!,
                onCopied: () =>
                    trackEvent(ref, AnalyticsEvents.webCompanionUrlCopied),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _scanBrowserQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Browser QR'),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            _DiagnosticsTabs(
              diagnosticsLoading: _diagnosticsLoading,
              diagnosticsHealthy: _diagnosticsHealthy,
              diagnosticsIp: _diagnosticsIp,
              diagnosticsPort: _diagnosticsPort,
              diagnosticsInterfaces: _diagnosticsInterfaces,
              diagnosticsHints: _diagnosticsHints,
              diagnosticsReport: _diagnosticsReport,
              onRefreshDiagnostics: _refreshDiagnostics,
            ),

            const SizedBox(height: AppSpacing.xl),
            _InfoRow(
              icon: Icons.phone_android_outlined,
              label:
                  'Keep KashCube open on your phone while using the browser view',
            ),
            _InfoRow(
              icon: Icons.language_outlined,
              label: 'Open the plain LAN URL on your laptop browser first',
            ),
            _InfoRow(
              icon: Icons.wifi_outlined,
              label:
                  'Browser must be on the same network — same Wi-Fi or connected to this phone\'s hotspot',
            ),
            _InfoRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Data never leaves your local network',
            ),
            _InfoRow(
              icon: Icons.lock_outline,
              label:
                  'Browser access is granted only after you scan and approve its QR',
            ),

            const SizedBox(height: AppSpacing.xxl),
            if (_url != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Disconnect browser'),
                onPressed: () {
                  trackEvent(
                    ref,
                    AnalyticsEvents.webCompanionDisconnectedManually,
                  );
                  P2pCoordinator.instance.disconnectBrowser();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Browser disconnected'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  _buildUrl();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _BrowserApprovalScannerScreen extends StatefulWidget {
  const _BrowserApprovalScannerScreen();

  @override
  State<_BrowserApprovalScannerScreen> createState() =>
      _BrowserApprovalScannerScreenState();
}

class _BrowserApprovalScannerScreenState
    extends State<_BrowserApprovalScannerScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = parseWebCompanionAuthQr(raw);
    if (parsed == null) return;
    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Browser QR')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: context.colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.base),
              ),
            ),
          ),
          Positioned(
            bottom: AppSpacing.xxl,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(AppSpacing.xl),
                ),
                child: Text(
                  'Point your camera at the QR shown in the browser',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrlChip extends StatefulWidget {
  const _UrlChip({required this.url, this.onCopied});
  final String url;
  final VoidCallback? onCopied;
  @override
  State<_UrlChip> createState() => _UrlChipState();
}

class _UrlChipState extends State<_UrlChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    widget.onCopied?.call();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.url,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: context.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 16,
              color: _copied
                  ? context.colorScheme.primary
                  : context.colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Copy URL',
            onPressed: _copy,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: context.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        children: [
          Text(
            message,
            style: TextStyle(color: context.colorScheme.onErrorContainer),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _NetworkDiagnosticsCard extends StatelessWidget {
  const _NetworkDiagnosticsCard({
    required this.loading,
    required this.healthy,
    required this.ip,
    required this.port,
    required this.interfaces,
    required this.hints,
    required this.report,
    required this.onRefresh,
  });

  final bool loading;
  final bool? healthy;
  final String? ip;
  final int? port;
  final List<String> interfaces;
  final List<String> hints;
  final String? report;
  final Future<void> Function() onRefresh;

  String _quickTriageCommands() {
    final host = ip ?? 'PHONE_IP';
    final targetPort = port ?? 50505;
    return [
      'arp -an | grep $host || true',
      'ping -c 3 $host',
      'nc -vz -w 3 $host $targetPort',
      'curl -i --max-time 5 http://$host:$targetPort/health',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final statusText = healthy == null
        ? 'Unknown'
        : (healthy! ? 'Healthy' : 'Warming up');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: context.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.network_check,
                size: 18,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Network diagnostics', style: context.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _DiagnosticLine(label: 'Server status', value: statusText),
          _DiagnosticLine(
            label: 'Bound port',
            value: port?.toString() ?? 'unknown',
          ),
          _DiagnosticLine(label: 'Local IP', value: ip ?? 'unknown'),
          if (port != null)
            _DiagnosticLine(
              label: 'Same-device URL',
              value: 'http://127.0.0.1:$port',
            ),
          if (ip != null && port != null)
            _DiagnosticLine(label: 'Laptop URL', value: 'http://$ip:$port'),
          const SizedBox(height: AppSpacing.sm),
          if (interfaces.isNotEmpty)
            Text(
              'Interfaces: ${interfaces.join(' | ')}',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          if (hints.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final hint in hints)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '• $hint',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Quick triage (Mac Terminal)',
            style: context.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.xs),
            ),
            child: SelectableText(
              _quickTriageCommands(),
              style: context.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Troubleshoot steps: run top-to-bottom. ARP must resolve, then ping, then TCP :50505, then /health must return 200.',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh diagnostics'),
                onPressed: loading ? null : onRefresh,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy quick triage'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _quickTriageCommands()),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Quick triage commands copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy report'),
                onPressed: report == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: report!));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Diagnostics copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(value, style: context.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _DiagnosticsTabs extends StatefulWidget {
  const _DiagnosticsTabs({
    required this.diagnosticsLoading,
    required this.diagnosticsHealthy,
    required this.diagnosticsIp,
    required this.diagnosticsPort,
    required this.diagnosticsInterfaces,
    required this.diagnosticsHints,
    required this.diagnosticsReport,
    required this.onRefreshDiagnostics,
  });

  final bool diagnosticsLoading;
  final bool? diagnosticsHealthy;
  final String? diagnosticsIp;
  final int? diagnosticsPort;
  final List<String> diagnosticsInterfaces;
  final List<String> diagnosticsHints;
  final String? diagnosticsReport;
  final Future<void> Function() onRefreshDiagnostics;

  @override
  State<_DiagnosticsTabs> createState() => _DiagnosticsTabsState();
}

class _DiagnosticsTabsState extends State<_DiagnosticsTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Network diagnostics'),
            Tab(text: 'Web request log'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_tabController.index == 0)
          _NetworkDiagnosticsCard(
            loading: widget.diagnosticsLoading,
            healthy: widget.diagnosticsHealthy,
            ip: widget.diagnosticsIp,
            port: widget.diagnosticsPort,
            interfaces: widget.diagnosticsInterfaces,
            hints: widget.diagnosticsHints,
            report: widget.diagnosticsReport,
            onRefresh: widget.onRefreshDiagnostics,
          )
        else
          const _WebLogCard(),
      ],
    );
  }
}

class _WebLogCard extends StatefulWidget {
  const _WebLogCard();

  @override
  State<_WebLogCard> createState() => _WebLogCardState();
}

class _WebLogCardState extends State<_WebLogCard> {
  static const _kAutoClearInterval = Duration(minutes: 2);

  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _autoClear = false;
  int _lastLogCount = 0;
  Timer? _autoClearTimer;

  @override
  void dispose() {
    _autoClearTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleAutoClear(bool enabled) {
    setState(() => _autoClear = enabled);
    _autoClearTimer?.cancel();
    if (!enabled) return;
    _autoClearTimer = Timer.periodic(_kAutoClearInterval, (_) {
      P2pServer.instance.clearHttpLog();
    });
  }

  void _scrollToLatest() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  String _buildLogReport(List<String> entries) {
    final lines = <String>[
      'KashCube Web Companion HTTP Log',
      'Time: ${DateTime.now().toIso8601String()}',
      if (entries.isEmpty) '(no requests captured yet)',
      ...entries,
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: P2pServer.instance.httpLogStream,
      initialData: P2pServer.instance.currentHttpLog,
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const <String>[];
        final recentLogs = logs.length <= 25
            ? logs
            : logs.sublist(logs.length - 25);

        if (recentLogs.length != _lastLogCount) {
          _lastLogCount = recentLogs.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToLatest();
          });
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            border: Border.all(color: context.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Web request log', style: context.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Shows the latest HTTP activity reaching this phone. If this stays empty while opening from laptop, traffic is not reaching the server.',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.xs),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'When to switch checks',
                      style: context.textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '1) Run LAN quick triage first (ARP → ping → TCP :50505 → /health).',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '2) If LAN triage passes but browser still fails, switch here and watch this log while loading from laptop.',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '3) Empty log means LAN path is still blocked. Non-empty log means traffic reaches phone; investigate auth/session/browser flow next.',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Auto-scroll latest'),
                    selected: _autoScroll,
                    onSelected: (value) {
                      setState(() => _autoScroll = value);
                      if (value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _scrollToLatest();
                        });
                      }
                    },
                  ),
                  FilterChip(
                    label: const Text('Auto-clear every 2 min'),
                    selected: _autoClear,
                    onSelected: _toggleAutoClear,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.xs),
                ),
                child: recentLogs.isEmpty
                    ? Text(
                        'No HTTP requests yet',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        child: SelectableText(
                          recentLogs.join('\n'),
                          style: context.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy web log'),
                onPressed: () async {
                  final report = _buildLogReport(recentLogs);
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Web log copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('Clear log now'),
                onPressed: () {
                  P2pServer.instance.clearHttpLog();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Web log cleared'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
