// ---------------------------------------------------------------------------
// Action Center Screen — P2.4 (multi-select support)
// ---------------------------------------------------------------------------
// A single screen that surfaces all overdue and upcoming financial items:
//   • Invoices to collect
//   • Dues (udhar / credits) to collect or pay
//   • Loan EMIs to pay or collect
//   • Scheduled bills to pay
//
// Long-press any tile enters multi-select mode.
// Selection bar: "Remind All (N)" | "Mark Paid (N)" | Cancel.
//
// 100% on-device — no network calls. All data from local SQLite.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/action_item.dart';
import '../../../data/models/lifecycle_info.dart';
import '../../../data/services/bulk_reminder_service.dart';
import '../../providers/action_center_provider.dart';
import '../../providers/party_provider.dart';
import '../../widgets/lifecycle_tag.dart';
import '../invoices/invoice_detail_screen.dart';
import '../ledger/credits_screen.dart';
import '../bills/bills_and_payments_screen.dart';
import '../loans/loans_screen.dart';
import '../parties/party_360_screen.dart';
import '../search/search_screen.dart';

/// Default stale threshold — items with no action for this many days are
/// shown under the "Stale" filter chip.
const int kDefaultStallThreshold = 7;

enum _ActionFilter { all, toCollect, toPay, stale }

class ActionCenterScreen extends ConsumerStatefulWidget {
  const ActionCenterScreen({super.key});

  @override
  ConsumerState<ActionCenterScreen> createState() => _ActionCenterScreenState();
}

class _ActionCenterScreenState extends ConsumerState<ActionCenterScreen> {
  final Set<int> _selectedIds = {};
  bool _isSelecting = false;
  _ActionFilter _filter = _ActionFilter.all;

  void _enterSelectMode(int firstId) {
    setState(() {
      _isSelecting = true;
      _selectedIds
        ..clear()
        ..add(firstId);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelecting = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  List<ActionItem> _applyFilter(List<ActionItem> items, _ActionFilter filter) {
    return switch (filter) {
      _ActionFilter.all => items,
      _ActionFilter.toCollect =>
        items
            .where((i) => i.direction == ActionItemDirection.toCollect)
            .toList(),
      _ActionFilter.toPay =>
        items.where((i) => i.direction == ActionItemDirection.toPay).toList(),
      _ActionFilter.stale =>
        items
            .where(
              (i) =>
                  i.lifecycleInfo?.isStale(threshold: kDefaultStallThreshold) ??
                  false,
            )
            .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(actionCenterProvider);
    final toCollect = ref.watch(actionCenterToCollectProvider);
    final toPay = ref.watch(actionCenterToPayProvider);
    final overdueCount = ref.watch(actionCenterOverdueCountProvider);
    final n = _selectedIds.length;

    return Scaffold(
      appBar: AppBar(
        title: _isSelecting ? Text('$n selected') : const Text('Action Center'),
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
                tooltip: 'Cancel selection',
              )
            : null,
        actions: [
          if (!_isSelecting)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search invoices',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const SearchScreen(initialFilter: SearchFilter.invoices),
                ),
              ),
            ),
          if (!_isSelecting && overdueCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.base),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
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
          if (_isSelecting)
            TextButton(onPressed: _exitSelectMode, child: const Text('Cancel')),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load items: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          final filtered = _applyFilter(items, _filter);
          final staleCount = items
              .where(
                (i) =>
                    i.lifecycleInfo?.isStale(
                      threshold: kDefaultStallThreshold,
                    ) ??
                    false,
              )
              .length;
          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  if (!_isSelecting)
                    SliverToBoxAdapter(
                      child: _SummaryStrip(toCollect: toCollect, toPay: toPay),
                    ),
                  if (!_isSelecting)
                    SliverToBoxAdapter(
                      child: _FilterChipRow(
                        selected: _filter,
                        staleCount: staleCount,
                        onChanged: (f) => setState(() => _filter = f),
                      ),
                    ),
                  ..._buildSections(context, filtered),
                  if (filtered.isEmpty && items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxl),
                          child: Text(
                            'No items match this filter.',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
              if (_isSelecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MultiSelectBar(
                    selectedCount: n,
                    selectedIds: Set.unmodifiable(_selectedIds),
                    allItems: items,
                    onDone: _exitSelectMode,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context, List<ActionItem> items) {
    // Leaking chains get their own dedicated section (E5)
    final leaking = items
        .where((i) => i.type == ActionItemType.leakingChain)
        .toList();
    final rest = items
        .where((i) => i.type != ActionItemType.leakingChain)
        .toList();

    final overdue = rest
        .where((i) => i.urgency == ActionUrgency.overdue)
        .toList();
    final dueToday = rest
        .where((i) => i.urgency == ActionUrgency.dueToday)
        .toList();
    final dueThisWeek = rest
        .where((i) => i.urgency == ActionUrgency.dueThisWeek)
        .toList();
    final dueThisMonth = rest
        .where((i) => i.urgency == ActionUrgency.dueThisMonth)
        .toList();

    final sections = <Widget>[
      if (leaking.isNotEmpty) ...[
        // Leaking Revenue section always at top
        _SectionHeader(
          label: 'Leaking Revenue',
          count: leaking.length,
          color: const Color(0xFFF57C00),
        ),
        _itemSliver(leaking),
      ],
    ];

    if (overdue.isNotEmpty) {
      sections
        ..add(
          _SectionHeader(
            label: 'Overdue',
            count: overdue.length,
            color: context.colorScheme.error,
          ),
        )
        ..add(_itemSliver(overdue));
    }
    if (dueToday.isNotEmpty || dueThisWeek.isNotEmpty) {
      final urgent = [...dueToday, ...dueThisWeek];
      sections
        ..add(
          _SectionHeader(
            label: 'Due This Week',
            count: urgent.length,
            color: const Color(0xFFF57C00),
          ),
        )
        ..add(_itemSliver(urgent));
    }
    if (dueThisMonth.isNotEmpty) {
      sections
        ..add(
          _SectionHeader(
            label: 'Due This Month',
            count: dueThisMonth.length,
            color: context.colorScheme.primary,
          ),
        )
        ..add(_itemSliver(dueThisMonth));
    }

    return sections;
  }

  Widget _itemSliver(List<ActionItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return _ActionItemTile(
            item: item,
            isSelecting: _isSelecting,
            isSelected: _selectedIds.contains(item.sourceId),
            onLongPress: () => _enterSelectMode(item.sourceId),
            onToggle: () => _toggleSelection(item.sourceId),
          );
        }, childCount: items.length),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select bottom bar (P2.4)
// ---------------------------------------------------------------------------

class _MultiSelectBar extends ConsumerWidget {
  const _MultiSelectBar({
    required this.selectedCount,
    required this.selectedIds,
    required this.allItems,
    required this.onDone,
  });

  final int selectedCount;
  final Set<int> selectedIds;
  final List<ActionItem> allItems;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = allItems
        .where((i) => selectedIds.contains(i.sourceId))
        .toList();

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            color: Colors.black.withAlpha(25),
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.send_outlined, size: 16),
              label: Text('Remind ($selectedCount)'),
              onPressed: selectedCount == 0
                  ? null
                  : () async {
                      final service = ref.read(bulkReminderServiceProvider);
                      await service.remindAll(context, selected);
                      onDone();
                    },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (selectedCount == 1)
            OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Mark Paid'),
              onPressed: () {
                _navigateToSource(context, ref, selected.first);
                onDone();
              },
            ),
        ],
      ),
    );
  }

  void _navigateToSource(BuildContext context, WidgetRef ref, ActionItem item) {
    switch (item.type) {
      case ActionItemType.invoice:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: item.sourceId),
          ),
        );
      case ActionItemType.dues:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreditsScreen()));
      case ActionItemType.loanEmi:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoansScreen()));
      case ActionItemType.bill:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BillsAndPaymentsScreen()),
        );
      case ActionItemType.leakingChain:
        ref.read(partyRepositoryProvider).getById(item.sourceId).then((party) {
          if (!context.mounted || party == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => Party360Screen(party: party)),
          );
        });
    }
  }
}

// __ Summary Strip _____________________________________________________________

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.toCollect, required this.toPay});

  final double toCollect;
  final double toPay;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.sm,
      ),
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
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
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

// __ Section Header ____________________________________________________________

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
          AppSpacing.base,
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.xs,
        ),
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
                horizontal: AppSpacing.xs,
                vertical: 1,
              ),
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

// __ Action Item Tile __________________________________________________________

class _ActionItemTile extends ConsumerWidget {
  const _ActionItemTile({
    required this.item,
    this.isSelecting = false,
    this.isSelected = false,
    this.onLongPress,
    this.onToggle,
  });

  final ActionItem item;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final urgencyColor = _urgencyColor(context, item.urgency);
    final typeColor = item.direction == ActionItemDirection.toCollect
        ? colors.income
        : colors.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: isSelected
          ? context.colorScheme.primaryContainer.withAlpha(80)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: isSelecting ? null : onLongPress,
        onTap: isSelecting
            ? onToggle
            : () => _navigateToSource(context, ref, item),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelecting)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggle?.call(),
                    shape: const CircleBorder(),
                    activeColor: context.colorScheme.primary,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Container(
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
                ),
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
                    if (item.lifecycleInfo != null &&
                        !item.lifecycleInfo!.stage.isTerminal) ...[
                      const SizedBox(height: AppSpacing.xs),
                      LifecycleTag(info: item.lifecycleInfo!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!isSelecting)
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
                )
              else
                Text(
                  CurrencyFormatter.format(item.amount),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _urgencyColor(BuildContext context, ActionUrgency urgency) =>
      switch (urgency) {
        ActionUrgency.overdue => context.colorScheme.error,
        ActionUrgency.dueToday => const Color(0xFFE65100),
        ActionUrgency.dueThisWeek => const Color(0xFFF57C00),
        ActionUrgency.dueThisMonth => context.colorScheme.primary,
      };

  IconData _typeIcon(ActionItemType type) => switch (type) {
    ActionItemType.invoice => Icons.receipt_long_outlined,
    ActionItemType.dues => Icons.handshake_outlined,
    ActionItemType.bill => Icons.payments_outlined,
    ActionItemType.loanEmi => Icons.account_balance_outlined,
    ActionItemType.leakingChain => Icons.warning_amber_outlined,
  };

  void _navigateToSource(BuildContext context, WidgetRef ref, ActionItem item) {
    switch (item.type) {
      case ActionItemType.invoice:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: item.sourceId),
          ),
        );
      case ActionItemType.dues:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreditsScreen()));
      case ActionItemType.loanEmi:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LoansScreen()));
      case ActionItemType.bill:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BillsAndPaymentsScreen()),
        );
      case ActionItemType.leakingChain:
        _navigateToParty360(context, ref, item.sourceId);
    }
  }

  /// Navigate to Party360Screen for the given [partyId].
  Future<void> _navigateToParty360(
    BuildContext context,
    WidgetRef ref,
    int partyId,
  ) async {
    final party = await ref.read(partyRepositoryProvider).getById(partyId);
    if (!context.mounted) return;
    if (party == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => Party360Screen(party: party)));
  }
}

// __ Due Date Chip _____________________________________________________________

class _DueDateChip extends StatelessWidget {
  const _DueDateChip({required this.item, required this.urgencyColor});

  final ActionItem item;
  final Color urgencyColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: urgencyColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _dueDateLabel(item),
        style: context.textTheme.labelSmall?.copyWith(
          color: urgencyColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _dueDateLabel(ActionItem item) => switch (item.urgency) {
    ActionUrgency.overdue =>
      item.daysOverdue == 1
          ? '1 day overdue'
          : '${item.daysOverdue} days overdue',
    ActionUrgency.dueToday => 'Due today',
    ActionUrgency.dueThisWeek => () {
      final days = -item.daysOverdue;
      return days == 1 ? 'Due tomorrow' : 'Due in $days days';
    }(),
    ActionUrgency.dueThisMonth => () {
      if (item.dueDate == null) return 'Due this month';
      return 'Due in ${-item.daysOverdue} days';
    }(),
  };
}

// __ Action Button _____________________________________________________________

class _ActionButton extends ConsumerWidget {
  const _ActionButton({required this.item});

  final ActionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget dest() => switch (item.type) {
      ActionItemType.invoice => InvoiceDetailScreen(invoiceId: item.sourceId),
      ActionItemType.dues => const CreditsScreen(),
      ActionItemType.bill => const BillsAndPaymentsScreen(),
      ActionItemType.loanEmi => const LoansScreen(),
      ActionItemType.leakingChain => const SizedBox.shrink(), // async nav below
    };

    return InkWell(
      onTap: () {
        if (item.type == ActionItemType.leakingChain) {
          ref.read(partyRepositoryProvider).getById(item.sourceId).then((
            party,
          ) {
            if (context.mounted && party != null) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => Party360Screen(party: party)),
              );
            }
          });
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest()));
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: _buttonColor(context, item).withAlpha(22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _buttonColor(context, item).withAlpha(60),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _buttonLabel(item),
              style: context.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _buttonColor(context, item),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 10,
              color: _buttonColor(context, item),
            ),
          ],
        ),
      ),
    );
  }

  /// Context-aware label — LC5.
  String _buttonLabel(ActionItem item) {
    // Leaking chain always shows a fixed CTA regardless of lifecycle stage
    if (item.type == ActionItemType.leakingChain) return 'Raise Invoice';
    final stage = item.lifecycleInfo?.stage;
    final days = item.lifecycleInfo?.daysInStage ?? 0;
    if (stage == LifecycleStage.overdue) {
      return item.direction == ActionItemDirection.toCollect
          ? 'Collect Now'
          : 'Pay Now';
    }
    if (stage == LifecycleStage.partiallyPaid) return 'Record Balance';
    if (stage == LifecycleStage.reminded && days > 3) return 'Follow Up';
    if (stage == LifecycleStage.sent && days > 7) return 'Remind';
    return 'View';
  }

  /// Button foreground colour — LC5.
  Color _buttonColor(BuildContext context, ActionItem item) {
    if (item.type == ActionItemType.leakingChain) {
      return const Color(0xFFF57C00); // amber — revenue at risk
    }
    final stage = item.lifecycleInfo?.stage;
    final days = item.lifecycleInfo?.daysInStage ?? 0;
    if (stage == LifecycleStage.overdue) return context.colorScheme.error;
    if (stage == LifecycleStage.reminded && days > 3) {
      return const Color(0xFFE65100); // orange
    }
    if (stage == LifecycleStage.sent && days > 7) {
      return const Color(0xFFF57C00); // amber
    }
    if (stage == LifecycleStage.partiallyPaid) {
      return context.colorScheme.primary;
    }
    return context.colorScheme.onSurfaceVariant;
  }
}

// __ Filter Chip Row (P3.10) ___________________________________________________

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.selected,
    required this.staleCount,
    required this.onChanged,
  });

  final _ActionFilter selected;
  final int staleCount;
  final ValueChanged<_ActionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            isSelected: selected == _ActionFilter.all,
            onTap: () => onChanged(_ActionFilter.all),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip(
            label: 'To Collect',
            isSelected: selected == _ActionFilter.toCollect,
            onTap: () => onChanged(_ActionFilter.toCollect),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip(
            label: 'To Pay',
            isSelected: selected == _ActionFilter.toPay,
            onTap: () => onChanged(_ActionFilter.toPay),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip(
            label: 'Stale',
            badge: staleCount > 0 ? '$staleCount' : null,
            isSelected: selected == _ActionFilter.stale,
            badgeColor: const Color(0xFFF57C00),
            onTap: () => onChanged(_ActionFilter.stale),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? context.colorScheme.primary
        : context.colorScheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer
              : context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? context.colorScheme.primary
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: (badgeColor ?? context.colorScheme.error).withAlpha(
                    200,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// __ Empty State _______________________________________________________________

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
