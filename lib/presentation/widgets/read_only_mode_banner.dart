import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sync_provider.dart';

/// Shown as a persistent banner when the device session's offline grace period
/// has been exceeded and all write operations are locked until the device
/// syncs with the primary.
class ReadOnlyModeBanner extends ConsumerWidget {
  const ReadOnlyModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(activeDeviceSessionProvider);
    return sessionAsync.maybeWhen(
      data: (session) {
        if (session == null || !session.isReadOnlyForced) {
          return const SizedBox.shrink();
        }
        return ColoredBox(
          color: Colors.deepOrange.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                children: const [
                  Icon(Icons.lock_outline, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Read-only mode — sync with primary device to restore access.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
