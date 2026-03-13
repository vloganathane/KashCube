import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../providers/web_server_provider.dart';

/// Settings → KashCube Web
///
/// Shows a QR code the user scans from any browser on the same Wi-Fi to
/// access their KashCube data. No internet, no cloud — phone is the server.
class KashCubeWebScreen extends ConsumerWidget {
  const KashCubeWebScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webServerProvider);
    final notifier = ref.read(webServerProvider.notifier);
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KashCube Web'),
        actions: [
          if (state.isRunning)
            IconButton(
              tooltip: 'New QR / Revoke current session',
              icon: const Icon(Icons.refresh),
              onPressed: notifier.revokeSession,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── How it works ────────────────────────────────────────────────
            _HowItWorksCard(),
            const SizedBox(height: AppSpacing.lg),

            // ── Main control card ────────────────────────────────────────────
            if (!state.isRunning) ...[
              _StartCard(
                error: state.error,
                onStart: notifier.start,
              ),
            ] else ...[
              _ActiveCard(
                qrPayload: state.qrPayload!,
                localUrl: state.localUrl!,
                onStop: notifier.stop,
                onRevoke: notifier.revokeSession,
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Privacy note ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: cs.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'All data stays on your phone and local Wi-Fi network. '
                      'No internet connection is used. Closing this screen stops the server.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── How it works ─────────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        ...[
          (Icons.wifi, 'Connect your phone and PC/laptop to the same Wi-Fi'),
          (Icons.qr_code_scanner, 'Tap Start — scan the QR code from your browser'),
          (Icons.dashboard_outlined, 'View transactions, invoices & credits on the big screen'),
        ].map((e) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(e.$1, size: 16, color: cs.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(e.$2, style: tt.bodyMedium)),
                ],
              ),
            )),
      ],
    );
  }
}

// ── Start card ────────────────────────────────────────────────────────────────

class _StartCard extends StatefulWidget {
  const _StartCard({this.error, required this.onStart});
  final String? error;
  final VoidCallback onStart;

  @override
  State<_StartCard> createState() => _StartCardState();
}

class _StartCardState extends State<_StartCard> {
  bool _loading = false;

  Future<void> _handleStart() async {
    setState(() => _loading = true);
    widget.onStart();
    // State update from provider will rebuild and replace this widget
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.computer, size: 64, color: cs.primary.withAlpha(180)),
            const SizedBox(height: AppSpacing.md),
            Text('KashCube Web is not running',
                style: tt.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Start the server to access your data from any browser on the same Wi-Fi.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (widget.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(widget.error!,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _loading ? null : _handleStart,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Start KashCube Web'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Active card ───────────────────────────────────────────────────────────────

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    required this.qrPayload,
    required this.localUrl,
    required this.onStop,
    required this.onRevoke,
  });

  final String qrPayload;
  final String localUrl;
  final VoidCallback onStop;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            // Status chip
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('Server running',
                    style: tt.labelMedium?.copyWith(color: cs.primary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // URL display
            Text(
              localUrl,
              style: tt.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // QR code
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            Text(
              'Scan with your browser on the same Wi-Fi',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('New QR'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onStop,
                    style: FilledButton.styleFrom(
                        backgroundColor: cs.errorContainer,
                        foregroundColor: cs.onErrorContainer),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
