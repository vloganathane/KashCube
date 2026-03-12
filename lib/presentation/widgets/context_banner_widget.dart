import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/context_provider.dart';

/// Persistent banner shown at the top of the screen (below the status bar)
/// whenever the user is viewing a linked business session context.
///
/// Amber/orange tint clearly differentiates the linked context from the
/// personal context.  Hidden completely when [activeContextProvider] is null.
///
/// Includes a one-tap "Back to Personal" button to exit the linked context.
class ContextBannerWidget extends ConsumerWidget {
  const ContextBannerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeContextProvider);
    if (activeId == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(linkedSessionsProvider);
    final sessions = sessionsAsync.valueOrNull ?? [];
    final match = sessions.where((s) => s.id == activeId).firstOrNull;
    final businessName = match?.businessName ?? 'Linked Business';
    final isReadOnly = match?.isReadOnly ?? false;

    final theme = Theme.of(context);
    final bannerColor = theme.brightness == Brightness.dark
        ? const Color(0xFF3E2723)   // dark amber-brown
        : const Color(0xFFFFF8E1);  // light amber-50
    final onBannerColor = theme.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)   // amber-300
        : const Color(0xFFE65100);  // deep-orange-900

    return ColoredBox(
      color: bannerColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, size: 14, color: onBannerColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                businessName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onBannerColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isReadOnly) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_outline, size: 12, color: onBannerColor),
              const SizedBox(width: 2),
              Text(
                'Read-only',
                style: TextStyle(fontSize: 11, color: onBannerColor),
              ),
            ],
            const SizedBox(width: 8),
            InkWell(
              onTap: () =>
                  ref.read(activeContextProvider.notifier).state = null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 12, color: onBannerColor),
                    const SizedBox(width: 3),
                    Text(
                      'Personal',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: onBannerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
