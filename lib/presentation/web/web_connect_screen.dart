import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../app_shell.dart';
import '../providers/analytics_provider.dart';
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
  /// On page refresh, prefer a saved session token from sessionStorage so
  /// the user doesn't need to scan a new QR code.
  void _tryAutoConnect() {
    if (_triedAutoConnect) return;
    _triedAutoConnect = true;
    if (!kIsWeb) return;

    // 1. Try session token from sessionStorage (survives page refresh).
    final savedSession = url_reader.getSavedSessionId();
    final savedWsUrl   = url_reader.getSavedWsUrl();
    if (savedSession != null && savedWsUrl != null) {
      trackEvent(ref, AnalyticsEvents.webBrowserSessionRestored);
      ref.read(webSyncProvider.notifier)
          .connect(savedWsUrl, savedSession, isSession: true);
      return;
    }

    // 2. Fall back to QR token from the URL (first load).
    final token  = url_reader.getInitialToken();
    final origin = url_reader.getOrigin(); // 'http://192.168.1.8:60567'
    if (token == null || origin == null) return;

    trackEvent(ref, AnalyticsEvents.webBrowserAutoConnected);
    final wsUrl = '${origin.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
    ref.read(webSyncProvider.notifier).connect(wsUrl, token);
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
      trackEvent(ref, AnalyticsEvents.webBrowserManualConnect);
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
    ref.listen<WebSyncState>(webSyncProvider, (prev, next) {
      if (next.state == WsConnState.connected && mounted) {
        trackScreen(ref, 'web_companion_shell');
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
