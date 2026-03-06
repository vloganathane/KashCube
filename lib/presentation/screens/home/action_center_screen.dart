// ---------------------------------------------------------------------------
// Action Center Screen
// ---------------------------------------------------------------------------
// A single screen that surfaces all overdue and upcoming financial items:
//   • Invoices to collect
//   • Dues (udhar / credits) to collect or pay
//   • Loan EMIs to pay or collect
//   • Scheduled bills to pay
//
// Items are grouped by urgency (Overdue → Due Today → This Week → This Month)
// and sorted by priority within each group.
//
// 100% on-device — no network calls. All data from local SQLite.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/action_item.dart';
import '../../providers/action_center_provider.dart';
import '../invoices/invoice_detail_screen.dart';
import '../ledger/credits_screen.dart';
import '../loans/loans_screen.dart';

class ActionCenterScreen extends ConsumerWidget {
  const ActionCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(actionCenterProvider);
    final toCollect = ref.watch(actionCenterToCollectProvider);
    final toPay = ref.watch(actionCenterToPayProvider);
    final overdueCount = ref.watch(actionCenterOverdueCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Action Center'),
        actions: [
          if (overdueCount > 0)
            Padding(
              padding:
                  const EdgeInsets.only(right: AppSpacing.base),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$overdueCount overdue',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onError,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: itemsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load items: $e')),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState();
          }
          return CustomScrollView(
            slivers: [
              // Summary strip
              SliverToBoxAdapter(
                child: _SummaryStrip(
                  toCollect: toCollect,
                  toPay: toPay,
                ),
              ),

              // Urgency sections
              ..._buildSections(context, ref, items),

              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxxl)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSections(
    BuildContext context,
    WidgetRef ref,
    List<ActionItem> items,
  ) {
    final overdue =
        items.where((i) => i.urgency == ActionUrgency.overdue).toList();
    final dueToday =
        items.where((i) => i.urgency == ActionUrgency.dueToday).toList();
    final dueThisWeek =
        items.where((i) => i.urgency == ActionUrgency.dueThisWeek).toList();
    final dueThisMonth =
        items.where((i) => i.urgency == ActionUrgency.dueThisMonth).toList();

    final sections = <Widget>[];

    if (overdue.isNotEmpty) {
      sections.add(_SectionHeader(
        label: 'Overdue',
        count: overdue.length,
        color: context.colorScheme.error,
      ));
      sections.add(_itemSliver(context, ref, overdue));
    }

    if (dueToday.isNotEmpty || dueThisWeek.isNotEmpty) {
      final urgentItems = [...dueToday, ...dueThisWeek];
      sections.add(_SectionHeader(
        label: 'Due This Week',
        count: urgentItems.length,
        color: const Color(0xFFF57C00),
      ));
      sections.add(_itemSliver(context, ref, urgentItems));
    }

    if (dueThisMonth.isNotEmpty) {
      sections.add(_SectionHeader(
        label: 'Due This Month',
        count: dueThisMonth.length,
        color: context.colorScheme.primary,
      ));
      sections.add(_itemSliver(context, ref, dueThisMonth));
    }

    return sections;
  }

  Widget _itemSliver(
    BuildContext context,
    WidgetRef ref,
    List<ActionItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _ActionItemTile(item: items[index]),
          childCount: items.length,
        ),
      ),
    );
  }
}

// ── Summary Strip ─────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.toCollect,
    required this.toPay,
  });

  final double toCollect;
  final double toPay;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.sm),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'To Collect',
                amount: toCollect,
                icon: Icons.arrow_downward_rounded,
                color: colors.income,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SummaryCard(
                label: 'To Pay',
                amount: toPay,
                icon: Icons.arrow_upward_rounded,
                color: colors.expense,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final double amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(amount),
            style: context.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label.toUpperCase(),
              style: context.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: context.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Item Tile ──────────────────────────────────────────────────────────

class _ActionItemTile extends ConsumerWidget {
  const _ActionItemTile({required this.item});

  final ActionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final urgencyColor = _urgencyColor(context, item.urgency);
    final typeColor = item.direction == ActionItemDirection.toCollect
        ? colors.income
        : colors.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSource(context, item),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _typeIcon(item.type),
                  color: typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    _DueDateChip(item: item, urgencyColor: urgencyColor),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Amount + action
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (item.direction == ActionItemDirection.toCollect
                            ? '+'
                            : '-') +
                        CurrencyFormatter.format(item.amount),
                    style: context.textTheme.titleSmall?.copyWith(
                      color: typeColor,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ActionButton(item: item),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _urgencyColor(BuildContext context, ActionUrgency urgency) {
    return switch (urgency) {
      ActionUrgency.overdue     => context.colorScheme.error,
      ActionUrgency.dueToday    => const Color(0xFFE65100),
      ActionUrgency.dueThisWeek => const Color(0xFFF57C00),
      ActionUrgency.dueThisMonth => context.colorScheme.primary,
    };
  }

  IconData _typeIcon(ActionItemType type) {
    return switch (type) {
      ActionItemType.invoice  => Icons.receipt_long_outlined,
      ActionItemType.dues     => Icons.handshake_outlined,
      ActionItemType.bill     => Icons.payments_outlined,
      ActionItemType.loanEmi  => Icons.account_balance_outlined,
    };
  }

  void _navigateToSource(BuildContext context, ActionItem item) {
    switch (item.type) {
      case ActionItemType.invoice:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: item.sourceId),
        ));
      case ActionItemType.dues:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const CreditsScreen(),
        ));
      case ActionItemType.loanEmi:
      case ActionItemType.bill:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LoansScreen(),
        ));
    }
  }
}

// ── Due Date Chip ─────────────────────────────────────────────────────────────

class _DueDateChip extends StatelessWidget {
  const _DueDateChip({required this.item, required this.urgencyColor});

  final ActionItem item;
  final Color urgencyColor;

  @override
  Widget build(BuildContext context) {
    final label = _dueDateLabel(item);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: urgencyColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: urgencyColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _dueDateLabel(ActionItem item) {
    return switch (item.urgency) {
      ActionUrgency.overdue => item.daysOverdue == 1
          ? '1 day overdue'
          : '${item.daysOverdue} days overdue',
      ActionUrgency.dueToday => 'Due today',
      ActionUrgency.dueThisWeek => () {
          final days = -item.daysOverdue;
          return days == 1 ? 'Due tomorrow' : 'Due in $days days';
        }(),
      ActionUrgency.dueThisMonth => () {
          if (item.dueDate == null) return 'Due this month';
          final days = -item.daysOverdue;
          return 'Due in $days days';
        }(),
    };
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends ConsumerWidget {
  const _ActionButton({required this.item});

  final ActionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (item.type) {
      case ActionItemType.invoice:
        return _chip(
          context,
          icon: Icons.arrow_forward_ios_rounded,
          label: 'View',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    InvoiceDetailScreen(invoiceId: item.sourceId)),
          ),
        );
      case ActionItemType.dues:
        return _chip(
          context,
          icon: Icons.arrow_forward_ios_rounded,
          label: 'View',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreditsScreen()),
          ),
        );
      case ActionItemType.loanEmi:
      case ActionItemType.bill:
        return _chip(
          context,
          icon: Icons.arrow_forward_ios_rounded,
          label: 'View',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoansScreen()),
          ),
        );
    }
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(icon, size: 10),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 72,
              color: context.kashColors.income,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'All clear!',
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No overdue invoices, dues, bills, or loan EMIs in the next 30 days.',
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
