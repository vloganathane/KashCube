import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/context_provider.dart';

/// App-bar action that lets the user switch between their personal context
/// and any linked business session.
///
/// Usage — add to [AppBar.actions]:
/// ```dart
/// actions: const [ContextSwitcherWidget()],
/// ```
///
/// Hidden automatically when there are no linked sessions.
class ContextSwitcherWidget extends ConsumerWidget {
  const ContextSwitcherWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(linkedSessionsProvider);
    final sessions = sessionsAsync.valueOrNull ?? [];
    if (sessions.isEmpty) return const SizedBox.shrink();

    final activeId = ref.watch(activeContextProvider);
    final theme = Theme.of(context);

    String currentLabel;
    if (activeId == null) {
      currentLabel = 'Personal';
    } else {
      final match = sessions.where((s) => s.id == activeId).firstOrNull;
      currentLabel = match?.businessName ?? 'Business';
    }

    return PopupMenuButton<int?>(
      tooltip: 'Switch context',
      offset: const Offset(0, 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeId == null
                  ? Icons.person_outline
                  : Icons.storefront_outlined,
              size: 18,
              color: activeId == null
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              currentLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: activeId == null
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: activeId == null
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
      onSelected: (id) {
        ref.read(activeContextProvider.notifier).state = id;
      },
      itemBuilder: (_) => [
        // Personal entry
        PopupMenuItem<int?>(
          value: null,
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Personal')),
              if (activeId == null) const Icon(Icons.check, size: 16),
            ],
          ),
        ),
        if (sessions.isNotEmpty) const PopupMenuDivider(),
        ...sessions.map(
          (s) => PopupMenuItem<int?>(
            value: s.id,
            child: Row(
              children: [
                Icon(
                  s.isReadOnly ? Icons.storefront_outlined : Icons.storefront,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.businessName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.isReadOnly)
                        Text(
                          'Read-only',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                        ),
                    ],
                  ),
                ),
                if (activeId == s.id) const Icon(Icons.check, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
