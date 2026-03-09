// ---------------------------------------------------------------------------
// CustomizeHomeScreen
// ---------------------------------------------------------------------------
// Lets the user reorder and show/hide sections on the Home screen.
// Access: Home AppBar → tune icon  OR  Settings → Customise Home
// Uses ReorderableListView (Flutter built-in, zero extra packages).
// All changes are persisted locally via homeWidgetProvider.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/models/home_widget_config.dart';
import '../../providers/home_widget_provider.dart';

class CustomizeHomeScreen extends ConsumerWidget {
  const CustomizeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config  = ref.watch(homeWidgetProvider);
    final notifier = ref.read(homeWidgetProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customise Home'),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Reset to defaults?'),
                  content: const Text(
                      'All sections will be restored to their default '
                      'order and visibility.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Reset')),
                  ],
                ),
              );
              if (confirm == true) await notifier.resetToDefaults();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Pinned header (non-draggable) ────────────────────────────
          _PinnedTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Balance Card',
            subtitle: 'Always visible — cannot be removed',
          ),
          const Divider(height: 1),

          // ── Instruction row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: context.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Drag   to reorder  ·  Toggle switch to show/hide',
                    style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),

          // ── Draggable list ───────────────────────────────────────────
          Expanded(
            child: ReorderableListView.builder(
              padding:
                  const EdgeInsets.only(bottom: AppSpacing.xxxl),
              itemCount: config.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                notifier.reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final cfg = config[index];
                return _WidgetTile(
                  key: ValueKey(cfg.id),
                  index: index,
                  config: cfg,
                  onToggle: () => notifier.toggle(cfg.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pinned tile (Balance Card — always on) ───────────────────────────────────

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final IconData icon;
  final String   label;
  final String   subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant)),
      trailing: Icon(Icons.lock_outline, size: 16,
          color: scheme.onSurfaceVariant),
      tileColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    );
  }
}

// ─── Draggable widget tile ────────────────────────────────────────────────────

class _WidgetTile extends StatelessWidget {
  const _WidgetTile({
    super.key,
    required this.index,
    required this.config,
    required this.onToggle,
  });

  final int              index;
  final HomeWidgetConfig config;
  final VoidCallback     onToggle;

  static IconData _iconFor(String id) {
    return switch (id) {
      HomeWidgetId.todayCashflow      => Icons.swap_horiz_rounded,
      HomeWidgetId.upcoming           => Icons.schedule_outlined,
      HomeWidgetId.upcomingBookings   => Icons.event_available_outlined,
      HomeWidgetId.alerts             => Icons.notifications_active_outlined,
      HomeWidgetId.budgets            => Icons.pie_chart_outline_rounded,
      HomeWidgetId.reportsShortcut    => Icons.bar_chart_outlined,
      HomeWidgetId.recentTransactions => Icons.receipt_long_outlined,
      _                               => Icons.widgets_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final label = HomeWidgetId.labels[config.id] ?? config.id;
    final scheme = context.colorScheme;

    return Material(
      color: scheme.surface,
      child: ListTile(
        // Drag handle on the left
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_handle_rounded,
              color: scheme.onSurfaceVariant),
        ),
        title: Row(
          children: [
            Icon(_iconFor(config.id),
                size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: config.enabled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant)),
          ],
        ),
        trailing: Switch(
          value: config.enabled,
          onChanged: (_) => onToggle(),
        ),
      ),
    );
  }
}
