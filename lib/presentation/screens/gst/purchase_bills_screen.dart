import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/purchase_bill.dart';
import '../../providers/purchase_bill_provider.dart';
import 'purchase_bill_detail_screen.dart';
import '../search/search_screen.dart';
import 'add_purchase_bill_screen.dart';

class PurchaseBillsScreen extends ConsumerStatefulWidget {
  const PurchaseBillsScreen({super.key});

  @override
  ConsumerState<PurchaseBillsScreen> createState() =>
      _PurchaseBillsScreenState();
}

class _PurchaseBillsScreenState
    extends ConsumerState<PurchaseBillsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KashCubeColors>()!;
    final itcSummary = ref.watch(purchaseItcSummaryProvider);
    final billsAsync = ref.watch(filteredPurchaseBillsProvider);
    final statusFilter = ref.watch(purchaseBillStatusFilterProvider);
    final itcFilter = ref.watch(purchaseBillItcFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Bills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SearchScreen(
                  initialFilter: SearchFilter.purchaseBills),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filters',
            onPressed: () => _showFilters(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddPurchaseBillScreen()),
          );
          if (added == true) {
            ref.invalidate(purchaseBillsProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Bill'),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.read(purchaseBillsProvider.notifier).load(),
        child: CustomScrollView(
          slivers: [
            // ── ITC Summary strip ────────────────────────────────────────
            SliverToBoxAdapter(
              child: _ItcSummaryCard(itcSummary: itcSummary, colors: colors),
            ),

            // ── Filter chips ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _FilterBar(
                statusFilter: statusFilter,
                itcFilter: itcFilter,
                onStatusChanged: (v) =>
                    ref.read(purchaseBillStatusFilterProvider.notifier).state =
                        v,
                onItcChanged: (v) =>
                    ref.read(purchaseBillItcFilterProvider.notifier).state = v,
              ),
            ),

            // ── Bills list ───────────────────────────────────────────────
            billsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('Error: $e')),
              ),
              data: (bills) => bills.isEmpty
                  ? SliverFillRemaining(
                      child: _EmptyState(
                        hasFilter: statusFilter != null || itcFilter != null,
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.base, 0, AppSpacing.base, 80),
                      sliver: SliverList.separated(
                        itemCount: bills.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (_, i) => _BillTile(
                          bill: bills[i],
                          colors: colors,
                          onTap: () => _openDetail(bills[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(PurchaseBill bill) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseBillDetailScreen(billId: bill.id!),
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _FilterSheet(),
    );
  }
}

// ── ITC Summary card ──────────────────────────────────────────────────────────

class _ItcSummaryCard extends StatelessWidget {
  const _ItcSummaryCard({
    required this.itcSummary,
    required this.colors,
  });

  final PurchaseItcSummary itcSummary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible = itcSummary.cgstEligible + itcSummary.sgstEligible + itcSummary.igstEligible;
    final blocked = itcSummary.cgstBlocked + itcSummary.sgstBlocked + itcSummary.igstBlocked;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Input Tax Credit Summary',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _ItcCell(
                    label: 'Eligible ITC',
                    amount: eligible,
                    color: colors.income,
                    detail: itcSummary.totalBills > 0
                        ? '${itcSummary.totalBills} bills'
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ItcCell(
                    label: 'Blocked ITC',
                    amount: blocked,
                    color: colors.expense,
                    detail: blocked > 0 ? 'Sec. 17(5)' : null,
                  ),
                ),
              ],
            ),
            if (eligible > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  if (itcSummary.cgstEligible > 0)
                    _TaxChip(
                        label: 'CGST',
                        amount: itcSummary.cgstEligible,
                        color: Colors.blue),
                  if (itcSummary.sgstEligible > 0)
                    _TaxChip(
                        label: 'SGST',
                        amount: itcSummary.sgstEligible,
                        color: Colors.teal),
                  if (itcSummary.igstEligible > 0)
                    _TaxChip(
                        label: 'IGST',
                        amount: itcSummary.igstEligible,
                        color: Colors.deepPurple),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItcCell extends StatelessWidget {
  const _ItcCell({
    required this.label,
    required this.amount,
    required this.color,
    this.detail,
  });

  final String label;
  final double amount;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(amount, showDecimals: true),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontFamily: 'RobotoMono'),
          ),
          if (detail != null)
            Text(detail!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TaxChip extends StatelessWidget {
  const _TaxChip(
      {required this.label, required this.amount, required this.color});

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        '$label: ${CurrencyFormatter.format(amount, showDecimals: true)}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: color, fontFamily: 'RobotoMono'),
      ),
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.statusFilter,
    required this.itcFilter,
    required this.onStatusChanged,
    required this.onItcChanged,
  });

  final PurchaseBillStatus? statusFilter;
  final ItcEligibility? itcFilter;
  final ValueChanged<PurchaseBillStatus?> onStatusChanged;
  final ValueChanged<ItcEligibility?> onItcChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Status chips
          _FilterChip2(
            label: 'All',
            selected: statusFilter == null,
            onTap: () => onStatusChanged(null),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip2(
            label: 'Unpaid',
            selected: statusFilter == PurchaseBillStatus.unpaid,
            onTap: () => onStatusChanged(statusFilter == PurchaseBillStatus.unpaid
                ? null
                : PurchaseBillStatus.unpaid),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip2(
            label: 'Paid',
            selected: statusFilter == PurchaseBillStatus.paid,
            onTap: () => onStatusChanged(
                statusFilter == PurchaseBillStatus.paid ? null : PurchaseBillStatus.paid),
          ),
          const SizedBox(width: AppSpacing.sm),
          const VerticalDivider(width: 1, indent: 4, endIndent: 4),
          const SizedBox(width: AppSpacing.sm),
          // ITC eligibility chips
          _FilterChip2(
            label: 'Eligible ITC',
            selected: itcFilter == ItcEligibility.eligible,
            onTap: () => onItcChanged(
                itcFilter == ItcEligibility.eligible ? null : ItcEligibility.eligible),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterChip2(
            label: 'Blocked',
            selected: itcFilter == ItcEligibility.blocked,
            onTap: () => onItcChanged(
                itcFilter == ItcEligibility.blocked ? null : ItcEligibility.blocked),
          ),
        ],
      ),
    );
  }
}

class _FilterChip2 extends StatelessWidget {
  const _FilterChip2(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant, width: 1),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
    );
  }
}

// ── Bill tile ─────────────────────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  const _BillTile({
    required this.bill,
    required this.colors,
    required this.onTap,
  });

  final PurchaseBill bill;
  final KashCubeColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card.outlined(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        leading: Container(
          width: AppSpacing.xl,
          height: AppSpacing.xl,
          decoration: BoxDecoration(
            color: _itcColor(bill.itcEligibility, colors).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _itcIcon(bill.itcEligibility),
            size: AppSpacing.iconMd,
            color: _itcColor(bill.itcEligibility, colors),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                bill.vendorName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              CurrencyFormatter.format(bill.total, showDecimals: true),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  bill.billNo,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('·', style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  DateFormatter.formatFull(bill.billDate),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                _StatusBadge(status: bill.status),
              ],
            ),
            if (bill.itcEligibility != ItcEligibility.ineligible &&
                bill.itcTotal > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'ITC: ${CurrencyFormatter.format(bill.itcTotal, showDecimals: true)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _itcColor(bill.itcEligibility, colors),
                  fontFamily: 'RobotoMono',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _itcColor(ItcEligibility e, KashCubeColors colors) {
    switch (e) {
      case ItcEligibility.eligible:
        return colors.income;
      case ItcEligibility.blocked:
        return colors.expense;
      case ItcEligibility.ineligible:
        return colors.credit;
    }
  }

  IconData _itcIcon(ItcEligibility e) {
    switch (e) {
      case ItcEligibility.eligible:
        return Icons.verified_outlined;
      case ItcEligibility.blocked:
        return Icons.block_outlined;
      case ItcEligibility.ineligible:
        return Icons.remove_circle_outline;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PurchaseBillStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PurchaseBillStatus.paid => ('Paid', Colors.green),
      PurchaseBillStatus.partiallyPaid => ('Partial', Colors.orange),
      PurchaseBillStatus.unpaid => ('Unpaid', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.hasFilter = false});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64,
                color:
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: AppSpacing.base),
            Text(
              hasFilter ? 'No bills match your filters' : 'No purchase bills yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasFilter
                  ? 'Try clearing filters to see all bills'
                  : 'Tap "Add Bill" to record a purchase invoice',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter bottom sheet ───────────────────────────────────────────────────────

class _FilterSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(purchaseBillStatusFilterProvider);
    final itcFilter = ref.watch(purchaseBillItcFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.base),
          Text('Payment Status',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final s in PurchaseBillStatus.values)
                FilterChip(
                  label: Text(s.label),
                  selected: statusFilter == s,
                  onSelected: (v) {
                    ref.read(purchaseBillStatusFilterProvider.notifier).state =
                        v ? s : null;
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Text('ITC Eligibility',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final e in ItcEligibility.values)
                FilterChip(
                  label: Text(e.label),
                  selected: itcFilter == e,
                  onSelected: (v) {
                    ref.read(purchaseBillItcFilterProvider.notifier).state =
                        v ? e : null;
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  ref.read(purchaseBillStatusFilterProvider.notifier).state =
                      null;
                  ref.read(purchaseBillItcFilterProvider.notifier).state = null;
                },
                child: const Text('Clear all'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
