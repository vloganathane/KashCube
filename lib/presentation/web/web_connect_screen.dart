import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../app_shell.dart';
import '../providers/analytics_provider.dart';
import '../providers/web_sync_provider.dart';
import 'web_url_reader_stub.dart'
    if (dart.library.js_interop) 'web_url_reader_web.dart'
    as url_reader;

/// Entry screen shown on browser (`kIsWeb = true`) for web companion auth.
///
/// Flow:
///   1. Browser loads `http://<phone-ip>:<port>`.
///   2. This screen opens `/ws` and requests an AUTH_CHALLENGE.
///   3. Browser renders the QR payload returned by the phone server.
///   4. User scans it using KashCube on the phone.
///   5. On AUTH_OK → navigates to [AppShell].
///
/// Legacy token URLs remain supported for fallback/debug paths.
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
    _urlController.addListener(() {
      if (mounted) setState(() {});
    });
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

    // 2. Fall back to QR token from the URL (legacy flow) or start a new
    // browser-auth challenge on plain LAN URLs.
    final token  = url_reader.getInitialToken();
    final origin = url_reader.getOrigin(); // 'http://192.168.1.8:60567'
    if (token != null) {
      if (origin == null) {
        _showError('Could not determine the current browser origin.');
        return;
      }
      final wsUrl = '${origin.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
      trackEvent(ref, AnalyticsEvents.webBrowserAutoConnected);
      ref.read(webSyncProvider.notifier).connect(wsUrl, token);
      return;
    }

    if (origin != null) {
      final wsUrl = '${origin.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
      ref.read(webSyncProvider.notifier).beginBrowserAuth(wsUrl);
    }
  }

  Future<void> _connectManual() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;

    // Accept plain LAN URL, token URL, or ws://...
    try {
      Uri uri = Uri.parse(raw);
      final token = uri.queryParameters['token'];
      trackEvent(ref, AnalyticsEvents.webBrowserManualConnect);
      final wsUri = uri.replace(scheme: 'ws', path: '/ws', query: '');
      if (token != null) {
        await ref.read(webSyncProvider.notifier).connect(
              wsUri.toString(),
              token,
            );
        return;
      }
      await ref.read(webSyncProvider.notifier).beginBrowserAuth(
            wsUri.toString(),
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
                  'Open KashCube in your browser',
                  style: context.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Then scan the QR below with KashCube on your phone to approve this browser.',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (sync.authQrPayload != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _WebQrCard(qrPayload: sync.authQrPayload!),
                ],
                const SizedBox(height: AppSpacing.xxl),
                if (sync.state == WsConnState.connecting)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        sync.progressMsg ?? 'Connecting…',
                        style: context.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (sync.awaitingApproval) ...[
                        const SizedBox(height: AppSpacing.base),
                        Text(
                          'Waiting for phone approval…',
                          style: context.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  )
                else ...[
                  TextField(
                    controller:  _urlController,
                    decoration: InputDecoration(
                      labelText:  'Or paste phone URL',
                      hintText:   'http://192.168.x.x:PORT',
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
                      'Browser auth stays on your local Wi-Fi — never sent to the internet',
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

class _WebQrCard extends StatelessWidget {
  const _WebQrCard({required this.qrPayload});

  final String qrPayload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final payload = qrPayload.trim();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            'Scan This With KashCube',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: payload.isEmpty
                ? const SizedBox(
                    width: 180,
                    height: 180,
                    child: Center(
                      child: Text('Waiting for challenge...'),
                    ),
                  )
                : QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 180,
                    gapless: false,
                    errorStateBuilder: (context, error) => SizedBox(
                      width: 180,
                      height: 180,
                      child: Center(
                        child: Text(
                          'QR render failed',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            payload.isEmpty
                ? 'Awaiting AUTH_CHALLENGE payload'
                : 'Challenge ready (${payload.length} chars)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
