import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/p2p/p2p_coordinator.dart';
import '../../../data/services/p2p/p2p_discovery_service.dart';
import '../../../data/services/web/web_session_service.dart';
import '../../providers/p2p_provider.dart';
import '../../providers/settings_provider.dart';

/// Shows a QR code that lets the user open KashCube on a laptop browser.
///
/// QR payload: `http://<phone-ip>:<port>?token=<session_token>`
///
/// The token is:
///   - 32 random bytes (256-bit, single-use, expires in 5 minutes)
///   - Consumed on first successful WebSocket AUTH
class OpenOnLaptopScreen extends ConsumerStatefulWidget {
  const OpenOnLaptopScreen({super.key});

  @override
  ConsumerState<OpenOnLaptopScreen> createState() =>
      _OpenOnLaptopScreenState();
}

class _OpenOnLaptopScreenState extends ConsumerState<OpenOnLaptopScreen> {
  String? _url;
  String? _error;
  bool    _loading = true;

  @override
  void initState() {
    super.initState();
    _buildUrl();
  }

  Future<void> _buildUrl() async {
    setState(() { _loading = true; _error = null; });

    // Ensure the server is running — starts LAN sync if not enabled.
    final port = P2pCoordinator.instance.serverPort;
    if (port == null) {
      final enabled = ref.read(p2pEnabledProvider);
      setState(() {
        _error = enabled
            ? 'LAN Sync server is not ready yet — tap ↺ to retry.'
            : 'Enable LAN Sync first to use this feature.';
        _loading = false;
      });
      return;
    }

    final ip = await P2pDiscoveryService.getLocalIp();
    if (ip == null || ip == '0.0.0.0') {
      setState(() {
        _error   = 'Could not detect local IP address.\nMake sure you are connected to Wi-Fi.';
        _loading = false;
      });
      return;
    }

    // Enable web companion on the server (idempotent).
    final settings = ref.read(settingsRepositoryProvider);
    final name     = await settings.get(SettingsKeys.ownerName);
    P2pCoordinator.instance.enableWebCompanion(
      deviceName:    (name == null || name.trim().isEmpty) ? 'KashCube' : name.trim(),
      schemaVersion: AppConstants.dbVersion,
    );

    final token = WebSessionService.instance.generateToken();
    final url   = 'http://$ip:$port?token=$token';

    if (mounted) {
      setState(() {
        _url     = url;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open on Laptop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh QR',
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
              'Scan with your laptop camera',
              style: context.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Or type the URL in your browser. Works on the same Wi-Fi only.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_loading)
              const CircularProgressIndicator()
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _buildUrl)
            else ...[
              _QrCard(url: _url!),
              const SizedBox(height: AppSpacing.md),
              _UrlChip(url: _url!),
            ],

            const SizedBox(height: AppSpacing.xl),
            _InfoRow(
              icon: Icons.phone_android_outlined,
              label: 'Keep KashCube open on your phone while using the browser view',
            ),
            _InfoRow(
              icon: Icons.timer_outlined,
              label: 'QR expires in 5 minutes — tap ↻ to refresh',
            ),
            _InfoRow(
              icon: Icons.wifi_outlined,
              label: 'Browser must be on the same Wi-Fi as your phone',
            ),
            _InfoRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Data never leaves your local network',
            ),
            _InfoRow(
              icon: Icons.lock_outline,
              label: 'Single-use token — scan once, then re-generate',
            ),

            const SizedBox(height: AppSpacing.xxl),
            if (_url != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Disconnect browser'),
                onPressed: () {
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

class _QrCard extends StatelessWidget {
  const _QrCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth - AppSpacing.base * 2)
            .clamp(200.0, 320.0);
        return Container(
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.base),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.base),
          child: QrImageView(
            data:                 url,
            version:              QrVersions.auto,
            size:                 size,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            backgroundColor:      Colors.white,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color:    context.colorScheme.primary,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color:           Colors.black87,
            ),
          ),
        );
      },
    );
  }
}

class _UrlChip extends StatefulWidget {
  const _UrlChip({required this.url});
  final String url;
  @override
  State<_UrlChip> createState() => _UrlChipState();
}

class _UrlChipState extends State<_UrlChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.url,
              style: context.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color:      context.colorScheme.onSurfaceVariant,
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
            tooltip:       'Copy URL',
            onPressed:     _copy,
            visualDensity: VisualDensity.compact,
            padding:       EdgeInsets.zero,
            constraints:   const BoxConstraints(minWidth: 32, minHeight: 32),
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
        color:        context.colorScheme.errorContainer,
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
            label: const Text('Enable LAN Sync & Retry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String   label;

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
