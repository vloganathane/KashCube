import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../providers/web_sync_provider.dart';
import 'web_connect_screen.dart';

/// Persistent banner shown on all screens when the browser's WebSocket
/// connection to the phone is lost.
///
/// Only visible when running as `kIsWeb`.
///
/// Placement: wrap the body of each top-level screen with this widget,
/// or add it as a [persistentFooterWidgets] / [bottomNavigationBar] sibling
/// in [AppShell].
class WebConnectionBanner extends ConsumerWidget {
  const WebConnectionBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(webSyncProvider);
    final connected = sync.state == WsConnState.connected;

    return Column(
      children: [
        Expanded(child: child),
        if (connected)
          _ConnectedBanner(deviceName: sync.deviceName)
        else
          _DisconnectedBanner(deviceName: sync.deviceName),
      ],
    );
  }
}

class _ConnectedBanner extends ConsumerWidget {
  const _ConnectedBanner({this.deviceName});
  final String? deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = deviceName ?? 'Phone';
    return Material(
      color: context.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.lan,
              size: 16,
              color: context.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Connected to $name',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(webSyncProvider.notifier).logout();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const WebConnectScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: context.colorScheme.onPrimaryContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner({this.deviceName});
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical:   AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off,
              size: 16,
              color: context.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Disconnected. Open KashCube on your phone, then reconnect.',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const WebConnectScreen(),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: context.colorScheme.onErrorContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Reconnect'),
            ),
          ],
        ),
      ),
    );
  }
}
