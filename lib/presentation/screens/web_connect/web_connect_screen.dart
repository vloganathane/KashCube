import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/ws_sync_transport.dart';
import '../../../data/services/identity_service.dart';
import '../../providers/sync_provider.dart';

/// Shows on browser-first-open when there is no active paired session.
///
/// Flow:
/// 1. User opens the app in a browser on the same LAN.
/// 2. On phone: Settings → KashCube Web → tap Start → copy payload.
/// 3. User pastes / scans the QR payload into this screen.
/// 4. We open a WebSocket to the phone, run pair_request + initial delta pull.
/// 5. Navigate to [AppShell].
class WebConnectScreen extends ConsumerStatefulWidget {
  const WebConnectScreen({super.key, required this.onConnected});

  final VoidCallback onConnected;

  @override
  ConsumerState<WebConnectScreen> createState() => _WebConnectScreenState();
}

class _WebConnectScreenState extends ConsumerState<WebConnectScreen> {
  final _urlController = TextEditingController();
  bool    _loading     = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    // mobile_scanner v6+ supports web via the BarcodeDetector API
    // (Chrome 83+ / Edge 83+), so _QrScanDialog works on all platforms.
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _QrScanDialog(),
    );
    if (result == null || !mounted) return;
    _urlController.text = result;
    await _connect();
  }

  Future<void> _connect() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste the payload shown below the QR on your phone.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      // Ensure IdentityService is initialized before use on web.
      await ref.read(identityServiceProvider.future);

      String wsUrl;
      String? sessionToken;

      if (raw.startsWith('{')) {
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        if (payload['type'] != 'kashcube_web_v1') {
          throw const FormatException('Not a KashCube Web QR code.');
        }
        wsUrl         = payload['ws'] as String;
        sessionToken  = payload['token'] as String?;
      } else {
        // Plain URL: ws:// or http:// with optional ?token=
        final uri = Uri.parse(raw);
        sessionToken  = uri.queryParameters['token'];
        if (raw.startsWith('ws://') || raw.startsWith('wss://')) {
          wsUrl = '${uri.scheme}://${uri.host}:${uri.port}${uri.path}';
        } else {
          wsUrl = 'ws://${uri.host}:${uri.port}/ws';
        }
      }

      if (sessionToken == null || sessionToken.isEmpty) {
        throw const FormatException('No session token found in payload.');
      }

      // Build the full WS URL with the session token and persist it.
      // sync_provider reads this on every subsequent Sync Now tap.
      final wsUrlWithToken = Uri.parse(wsUrl)
          .replace(queryParameters: {'token': sessionToken})
          .toString();

      await DatabaseHelper.instance.withDatabase((db) async {
        await db.insert(
          'settings',
          {'key': 'web_sync_url', 'value': wsUrlWithToken},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      final transport = WsSyncTransport(
        identity: IdentityService.instance,
        dbHelper: DatabaseHelper.instance,
      );

      try {
        await transport.open(Uri.parse(wsUrlWithToken));
        final session = await transport.sendPairRequest(
          preset:     'owner_mirror',
          deviceOs:   'browser',
          deviceType: 'web',
          deviceName: 'KashCube Web',
        );

        await DatabaseHelper.instance.withDatabase((db) async {
          await db.insert(
            'linked_business_sessions',
            session.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });

        await transport.pullDeltas(session: session);
      } finally {
        await transport.close();
      }

      ref.invalidate(activeDeviceSessionProvider);
      if (mounted) widget.onConnected();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst(RegExp(r'^.*Exception: '), '');
        setState(() { _loading = false; _error = msg; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 56, color: cs.primary),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Connect to KashCube',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Open KashCube on your Android phone\n'
                    'Go to  Settings → KashCube Web → tap Start\n'
                    'Then tap the copy icon below the QR and paste it here.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  TextField(
                    controller:  _urlController,
                    decoration: InputDecoration(
                      labelText:  'Paste connection URL or QR payload',
                      hintText:   '{"type":"kashcube_web_v1"…}',
                      border:     const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _loading ? null : _connect(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color:        cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color:    cs.onErrorContainer,
                          fontSize: 13,
                          height:   1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  FilledButton.icon(
                    onPressed: _loading ? null : _connect,
                    icon:  _loading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering_rounded),
                    label: Text(_loading ? 'Connecting…' : 'Connect'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _scanQr,
                    icon:      const Icon(Icons.qr_code_scanner_rounded),
                    label:     const Text('Scan QR with camera'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen camera dialog used on Android/iOS via MobileScanner.
class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  late MobileScannerController _controller;
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      // No CameraFacing override — default back/environment camera is best.
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .where((v) => v != null)
        .firstOrNull;
    if (value == null) return;
    _detected = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            // Torch unavailable on web/desktop.
            if (!kIsWeb)
              IconButton(
                icon:    const Icon(Icons.flash_on_rounded),
                tooltip: 'Toggle torch',
                onPressed: () => _controller.toggleTorch(),
              ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller:   _controller,
              onDetect:     _onDetect,
              errorBuilder: (context, error, child) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          size: 48, color: cs.error),
                      const SizedBox(height: 12),
                      Text(error.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width:  260,
                height: 260,
                decoration: BoxDecoration(
                  border:       Border.all(color: cs.primary, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Positioned(
              bottom: 48,
              left: 0, right: 0,
              child: Text(
                'Point camera at the QR code on your phone',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
