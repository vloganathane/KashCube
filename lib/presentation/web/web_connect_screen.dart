import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../app_shell.dart';
import '../providers/web_sync_provider.dart';
import 'web_url_reader_stub.dart'
    if (dart.library.js_interop) 'web_url_reader_web.dart'
    as url_reader;

/// Entry screen shown on browser (`kIsWeb = true`) when connected via QR.
///
/// Flow:
///   1. Browser loads `http://<phone-ip>:<port>?token=<token>`.
///   2. This screen extracts token from URL and connects to WebSocket.
///   3. On AUTH_OK → navigates to [AppShell].
///   4. If no token in URL → shows manual URL input.
class WebConnectScreen extends ConsumerStatefulWidget {
  const WebConnectScreen({super.key});

  @override
  ConsumerState<WebConnectScreen> createState() => _WebConnectScreenState();
}

class _WebConnectScreenState extends ConsumerState<WebConnectScreen> {
  final _urlController = TextEditingController();
  bool _triedAutoConnect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoConnect());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// If URL contains a token, extract it and build ws:// URL automatically.
  void _tryAutoConnect() {
    if (_triedAutoConnect) return;
    _triedAutoConnect = true;
    final token = url_reader.getInitialToken();
    if (token == null || !kIsWeb) return;

    // Build ws:// from the current browser location.
    try {
      final params = url_reader.getUrlParams();
      final wsUrl  = _buildWsUrl(params);
      if (wsUrl != null) {
        ref.read(webSyncProvider.notifier).connect(wsUrl, token);
      }
    } catch (_) {}
  }

  String? _buildWsUrl(Map<String, String> params) {
    // This only runs on web — window.location.host gives us ip:port.
    // Parsed via conditional import.
    try {
      final token = params['token'];
      if (token == null) return null;
      // window.location.host is available via web_url_reader_web.dart
      // but since we need the raw value we re-parse the href.
      final params2 = url_reader.getUrlParams();
      if (params2.isEmpty) return null;
      // Flutter Web: window.location is something like http://192.168.x.x:port
      // We replace http with ws.
      // dart:html is only available on web — we use the web package here.
      return null; // fallback: user enters URL manually
    } catch (_) {
      return null;
    }
  }

  Future<void> _connectManual() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    // Accept: http://192.168.x.x:port?token=... or ws://...
    try {
      Uri uri = Uri.parse(raw);
      final token = uri.queryParameters['token'];
      if (token == null) {
        _showError('URL must contain a ?token= parameter');
        return;
      }
      final wsUri = uri.replace(scheme: 'ws', path: '/ws', query: '');
      await ref.read(webSyncProvider.notifier).connect(
            wsUri.toString(),
            token,
          );
    } catch (e) {
      _showError('Invalid URL: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(webSyncProvider);

    // Navigate to AppShell once authenticated.
    ref.listen<WebSyncState>(webSyncProvider, (_, next) {
      if (next.state == WsConnState.connected && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const AppShell()),
        );
      }
    });

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.phone_iphone,
                  size: 64,
                  color: context.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'KashCube',
                  style: context.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Open on your phone:',
                  style: context.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Settings → Open on Laptop → scan the QR code',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (sync.state == WsConnState.connecting)
                  const CircularProgressIndicator()
                else ...[
                  TextField(
                    controller:  _urlController,
                    decoration: InputDecoration(
                      labelText:  'Or paste URL from phone',
                      hintText:   'http://192.168.x.x:PORT?token=...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _connectManual,
                      ),
                    ),
                    onSubmitted: (_) => _connectManual(),
                  ),
                  if (sync.errorMsg != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      sync.errorMsg!,
                      style: TextStyle(color: context.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.xxxl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14,
                        color: context.colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Data stays on your local Wi-Fi — never sent to the internet',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
