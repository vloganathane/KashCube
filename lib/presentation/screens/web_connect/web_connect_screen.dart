import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/ws_sync_transport.dart';
import '../../../data/services/identity_service.dart';
import '../../providers/sync_provider.dart';

/// Shows on browser-first-open when there is no active WS session.
///
/// Flow:
/// 1. User opens the app in a browser on the same LAN.
/// 2. This screen explains: "Open KashCube on your phone → Settings →
///    KashCube Web → Show QR".
/// 3. User pastes the URL from the QR code into the text field
///    (or we'll add mobile_scanner later for camera).
/// 4. We parse the `kashcube_web_v1` QR payload, send a `pair_request`
///    over WS, and persist the session to `linked_business_sessions`.
/// 5. On success, navigate to [AppShell].
class WebConnectScreen extends ConsumerStatefulWidget {
  const WebConnectScreen({super.key, required this.onConnected});

  /// Called when pairing + initial pull succeeds; typically navigate to AppShell.
  final VoidCallback onConnected;

  @override
  ConsumerState<WebConnectScreen> createState() => _WebConnectScreenState();
}

class _WebConnectScreenState extends ConsumerState<WebConnectScreen> {
  final _urlController = TextEditingController();
  bool   _loading      = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste the URL shown below the QR code on your phone.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      // The URL text field should contain the full JSON QR payload or
      // just the WS URL.  Accept both forms.
      String wsUrl;
      String? sessionToken;

      if (raw.startsWith('{')) {
        // Full JSON payload from QR code.
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        if (payload['type'] != 'kashcube_web_v1') {
          throw const FormatException('Not a KashCube Web QR code.');
        }
        wsUrl        = payload['ws']    as String;
        sessionToken = payload['token'] as String?;
      } else {
        // Plain WS URL (e.g. ws://192.168.1.5:8080/ws).
        wsUrl = raw;
        // Extract token from query string if present.
        final uri = Uri.parse(wsUrl);
        sessionToken = uri.queryParameters['token'];
      }

      // Append token to WS URL if not already there.
      if (sessionToken != null) {
        final uri = Uri.parse(wsUrl);
        if (!uri.queryParameters.containsKey('token')) {
          wsUrl = uri.replace(
            queryParameters: {...uri.queryParameters, 'token': sessionToken},
          ).toString();
        }
      }

      // Persist WS URL for future `syncNow()` calls.
      await DatabaseHelper.instance.withDatabase((db) async {
        await db.insert(
          'settings',
          {'key': 'web_sync_url', 'value': wsUrl},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      // Connect and pair.
      final transport = WsSyncTransport(
        identity: IdentityService.instance,
        dbHelper: DatabaseHelper.instance,
      );
      await transport.open(Uri.parse(wsUrl));

      try {
        final session = await transport.sendPairRequest(
          preset:     'owner_mirror',
          deviceOs:   'browser',
          deviceType: 'web',
          deviceName: 'KashCube Web',
        );

        // Persist session row.
        await DatabaseHelper.instance.withDatabase((db) async {
          await db.insert(
            'linked_business_sessions',
            session.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });

        // Initial full pull.
        await transport.pullDeltas(session: session);
      } finally {
        await transport.close();
      }

      // Invalidate session cache so AppShell sees the new session.
      ref.invalidate(activeDeviceSessionProvider);

      if (mounted) widget.onConnected();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = 'Connection failed: $e';
        });
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
                  // Logo / title
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
                    'Go to  Settings → KashCube Web → Show QR\n'
                    'Then paste the URL shown below the QR here.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // URL/payload input
                  TextField(
                    controller:    _urlController,
                    decoration: InputDecoration(
                      labelText:   'Paste connection URL or QR payload',
                      hintText:    'ws://192.168.x.x:8080/ws  or  {"type":"kashcube_web_v1"…}',
                      border:      const OutlineInputBorder(),
                      prefixIcon:  const Icon(Icons.link),
                    ),
                    onSubmitted:   (_) => _loading ? null : _connect(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.error, fontSize: 13),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
