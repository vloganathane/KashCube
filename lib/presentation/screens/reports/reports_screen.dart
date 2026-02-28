import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/budget.dart';
import '../../../data/models/transaction.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../providers/booking_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/report_provider.dart';
import '../../providers/settings_provider.dart';
import '../bookings/bookings_screen.dart';
import 'budget_screen.dart';

/// Reports screen with monthly P&L, category breakdowns, trends, and top parties.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);
    final mode = ref.watch(reportModeProvider);
    final pnlAsync = ref.watch(monthlyPnLProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: Column(
        children: [
          _MonthSelector(month: month),
          _ModeFilter(selectedMode: mode),
          Expanded(
            child: pnlAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (pnl) => _ReportsBody(pnl: pnl),
            ),
          ),
        ],
      ),
    );
  }
}

/// Personal / Business / All filter chips.
class _ModeFilter extends ConsumerWidget {
  const _ModeFilter({required this.selectedMode});

  final String? selectedMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Row(
        children: [
          _ModeChip(
            label: 'All',
            selected: selectedMode == null,
            onSelected: () => ref.read(reportModeProvider.notifier).state = null,
          ),
          const SizedBox(width: AppSpacing.sm),
          _ModeChip(
            label: 'Personal',
            selected: selectedMode == 'personal',
            onSelected: () =>
                ref.read(reportModeProvider.notifier).state = 'personal',
          ),
          const SizedBox(width: AppSpacing.sm),
          _ModeChip(
            label: 'Business',
            selected: selectedMode == 'business',
            onSelected: () =>
                ref.read(reportModeProvider.notifier).state = 'business',
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}

/// Month forward/back selector.
class _MonthSelector extends ConsumerWidget {
  const _MonthSelector({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final label = DateFormat('MMMM yyyy').format(month);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(reportMonthProvider.notifier).state =
                  DateTime(month.year, month.month - 1);
            },
          ),
          Text(
            label,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth
                ? null
                : () {
                    ref.read(reportMonthProvider.notifier).state =
                        DateTime(month.year, month.month + 1);
                  },
          ),
        ],
      ),
    );
  }
}

/// Main scrollable reports body.
class _ReportsBody extends ConsumerWidget {
  const _ReportsBody({required this.pnl});

  final MonthlyPnL pnl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasData = pnl.totalIncome > 0 || pnl.totalExpense > 0;
    final isBusiness = ref.watch(businessModeProvider);
    final month = ref.watch(reportMonthProvider);
    final bookingStats = isBusiness
        ? ref.watch(bookingMonthStatsProvider(month))
        : null;
    final budgets =
        ref.watch(currentMonthBudgetsProvider).valueOrNull ?? const [];

    // Previous month for month-over-month comparison
    final prevYear = month.month == 1 ? month.year - 1 : month.year;
    final prevMonthNum = month.month == 1 ? 12 : month.month - 1;
    final prevMonth = DateTime(prevYear, prevMonthNum);
    final prevPnl = ref.watch(pnlForMonthProvider(prevMonth)).valueOrNull;

    // YTD summary
    final ytdAsync = ref.watch(ytdSummaryProvider(month));
    final ytd = ytdAsync.valueOrNull;

    // Days elapsed in the selected month (for avg daily spend)
    final now = DateTime.now();
    final isCurrentMonth =
        now.year == month.year && now.month == month.month;
    final daysElapsed = isCurrentMonth
        ? now.day.toDouble()
        : DateTime(month.year, month.month + 1, 0).day.toDouble();

    // Payment method split for the selected month
    final payMethodData =
        ref.watch(paymentMethodSplitProvider(month)).valueOrNull ?? const {};

    // All-time investment totals for investment summary card
    final allTimeInv =
        ref.watch(allTimeInvestmentProvider).valueOrNull;

    if (!hasData) {
      // Even with no transactions, show booking overview if business mode is on
      if (bookingStats != null) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            _BookingsOverviewCard(stats: bookingStats),
          ],
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 64,
              color: context.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'No transactions this month',
              style: context.textTheme.titleMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add transactions to see your financial reports',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        if (ytd != null &&
            (ytd.totalIncome > 0 || ytd.totalExpense > 0)) ...[  
          _YtdSummaryRow(ytd: ytd, month: month),
          const SizedBox(height: AppSpacing.base),
        ],
        _PnLCard(pnl: pnl, prevPnl: prevPnl),
        const SizedBox(height: AppSpacing.base),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SavingsRateCard(
                pnl: pnl,
                prevRate: prevPnl?.savingsRate,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _AvgDailySpendCard(
                pnl: pnl,
                prevPnl: prevPnl,
                daysElapsed: daysElapsed,
                month: month,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        _BudgetVsActualCard(budgets: budgets),
        const SizedBox(height: AppSpacing.base),
        if (pnl.expenseByCat.isNotEmpty) ...[
          _CategoryPieCard(
            title: 'Expense Breakdown',
            data: pnl.expenseByCat,
            total: pnl.totalExpense,
            month: month,
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        if (pnl.incomeByCat.isNotEmpty) ...[
          _CategoryPieCard(
            title: 'Income Breakdown',
            data: pnl.incomeByCat,
            total: pnl.totalIncome,
            month: month,
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        const _MonthlyTrendCard(),
        const SizedBox(height: AppSpacing.base),
        const _WeeklyPatternCard(),
        const SizedBox(height: AppSpacing.base),
        if (payMethodData.isNotEmpty) ...[
          _PaymentMethodCard(data: payMethodData),
          const SizedBox(height: AppSpacing.base),
        ],
        if (pnl.largestTransactions.isNotEmpty) ...[  
          _LargestTransactionsCard(transactions: pnl.largestTransactions),
          const SizedBox(height: AppSpacing.base),
        ],
        if (pnl.totalInvested > 0 || pnl.totalRedeemed > 0) ...[
          _InvestmentSummaryCard(pnl: pnl, allTime: allTimeInv),
          const SizedBox(height: AppSpacing.base),
        ],
        if (bookingStats != null) ...[
          _BookingsOverviewCard(stats: bookingStats),
          const SizedBox(height: AppSpacing.base),
        ],
        if (pnl.topParties.isNotEmpty) ...[
          _TopPartiesCard(parties: pnl.topParties),
          const SizedBox(height: AppSpacing.base),
        ],
      ],
    );
  }
}

/// Profit & Loss summary card.
class _PnLCard extends StatelessWidget {
  const _PnLCard({required this.pnl, this.prevPnl});

  final MonthlyPnL pnl;
  final MonthlyPnL? prevPnl;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isProfit = pnl.netProfitLoss >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profit & Loss',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _PnLItem(
                    label: 'Income',
                    amount: pnl.totalIncome,
                    color: colors.income,
                    icon: Icons.arrow_downward,
                    prevAmount: prevPnl?.totalIncome,
                    isGoodWhenUp: true,
                  ),
                ),
                Expanded(
                  child: _PnLItem(
                    label: 'Expense',
                    amount: pnl.totalExpense,
                    color: colors.expense,
                    icon: Icons.arrow_upward,
                    prevAmount: prevPnl?.totalExpense,
                    isGoodWhenUp: false,
                  ),
                ),
              ],
            ),
            if (pnl.totalInvested > 0 || pnl.totalRedeemed > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _PnLItem(
                      label: 'Invested',
                      amount: pnl.totalInvested,
                      color: context.colorScheme.primary,
                      icon: Icons.savings_outlined,
                    ),
                  ),
                  Expanded(
                    child: _PnLItem(
                      label: 'Redeemed',
                      amount: pnl.totalRedeemed,
                      color: context.colorScheme.tertiary,
                      icon: Icons.account_balance_outlined,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProfit ? 'Net Profit' : 'Net Loss',
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (prevPnl != null && prevPnl!.netProfitLoss != 0)
                      _DeltaTag(
                        current: pnl.netProfitLoss,
                        prev: prevPnl!.netProfitLoss,
                        isGoodWhenUp: true,
                      ),
                  ],
                ),
                Text(
                  CurrencyFormatter.formatSigned(pnl.netProfitLoss),
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'RobotoMono',
                    color: isProfit ? colors.income : colors.expense,
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

class _PnLItem extends StatelessWidget {
  const _PnLItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.prevAmount,
    this.isGoodWhenUp = true,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final double? prevAmount;
  final bool isGoodWhenUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpacing.iconSm, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          CurrencyFormatter.format(amount),
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'RobotoMono',
            color: color,
          ),
        ),
        if (prevAmount != null && prevAmount! > 0) ...
          [
            const SizedBox(height: 2),
            _DeltaTag(
              current: amount,
              prev: prevAmount!,
              isGoodWhenUp: isGoodWhenUp,
            ),
          ],
      ],
    );
  }
}

/// Shows a % delta vs the previous period with colour-coded trend icon.
class _DeltaTag extends StatelessWidget {
  const _DeltaTag({
    required this.current,
    required this.prev,
    required this.isGoodWhenUp,
  });

  final double current;
  final double prev;
  final bool isGoodWhenUp;

  @override
  Widget build(BuildContext context) {
    final delta = (current - prev) / prev;
    final isUp = delta >= 0;
    final isGood = isGoodWhenUp ? isUp : !isUp;
    final color =
        isGood ? context.kashColors.income : context.kashColors.expense;
    final sign = isUp ? '+' : '';
    final pct = '$sign${(delta * 100).toStringAsFixed(1)}%';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.trending_up : Icons.trending_down,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '$pct vs prev',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Pie chart for category breakdown (income or expense).
class _CategoryPieCard extends StatelessWidget {
  const _CategoryPieCard({
    required this.title,
    required this.data,
    required this.total,
    required this.month,
  });

  final String title;
  final Map<String, double> data;
  final double total;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Take top 6 categories, lump rest into "Other"
    final display = <MapEntry<String, double>>[];
    double otherTotal = 0;
    for (var i = 0; i < sortedEntries.length; i++) {
      if (i < 6) {
        display.add(sortedEntries[i]);
      } else {
        otherTotal += sortedEntries[i].value;
      }
    }
    if (otherTotal > 0) {
      display.add(MapEntry('Other', otherTotal));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: display.map((e) {
                          final pct = (e.value / total * 100);
                          return PieChartSectionData(
                            value: e.value,
                            color: CategoryHelper.getColor(e.key),
                            radius: 50,
                            title: pct >= 8
                                ? '${pct.toStringAsFixed(0)}%'
                                : '',
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: display.map((e) {
                        final pct =
                            (e.value / total * 100).toStringAsFixed(1);
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color:
                                      CategoryHelper.getColor(e.key),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: context.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: context.textTheme.bodySmall
                                    ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'RobotoMono',
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Category amounts list — tap to drill down
            ...display.map((e) {
              final pct =
                  (e.value / total * 100).toStringAsFixed(1);
              final tappable = e.key != 'Other';
              return InkWell(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusSm),
                onTap: tappable
                    ? () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => _CategoryDrillDownSheet(
                            category: e.key,
                            month: month,
                            categoryTotal: e.value,
                          ),
                        )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        CategoryHelper.getIcon(e.key),
                        size: AppSpacing.iconSm,
                        color: CategoryHelper.getColor(e.key),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.key,
                              style: context.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            LinearProgressIndicator(
                              value: e.value / total,
                              backgroundColor: context.colorScheme
                                  .surfaceContainerHighest,
                              color:
                                  CategoryHelper.getColor(e.key),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: [
                          Text(
                            CurrencyFormatter.formatCompact(
                                e.value),
                            style: context.textTheme.bodyMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: context.textTheme.bodySmall
                                ?.copyWith(
                              color: context
                                  .colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (tappable)
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: context.colorScheme.outlineVariant,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Monthly trend bar chart for the last 6 months.
class _MonthlyTrendCard extends ConsumerStatefulWidget {
  const _MonthlyTrendCard();

  @override
  ConsumerState<_MonthlyTrendCard> createState() => _MonthlyTrendCardState();
}

class _MonthlyTrendCardState extends ConsumerState<_MonthlyTrendCard> {
  int _count = 6;

  @override
  Widget build(BuildContext context) {
    final totalsAsync = ref.watch(monthlyTotalsForCountProvider(_count));
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Monthly Trend',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                _CountToggle(
                  count: _count,
                  onChanged: (c) => setState(() => _count = c),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Legend
            Row(
              children: [
                _TrendLegendDot(color: colors.income, label: 'Income'),
                const SizedBox(width: AppSpacing.md),
                _TrendLegendDot(color: colors.expense, label: 'Expense'),
                const SizedBox(width: AppSpacing.md),
                _TrendLegendDot(color: cs.primary, label: 'Net', dashed: true),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            totalsAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 200,
                child: Center(child: Text('Error: $e')),
              ),
              data: (totals) {
                if (totals.isEmpty) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        'No data yet',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return _TrendLineChart(totals: totals);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CountToggle extends StatelessWidget {
  const _CountToggle({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [6, 12].map((c) {
        final selected = count == c;
        return GestureDetector(
          onTap: () => onChanged(c),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              '${c}M',
              style: tt.labelSmall?.copyWith(
                color: selected
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TrendLegendDot extends StatelessWidget {
  const _TrendLegendDot(
      {required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            children: [
              Container(width: 5, height: 2, color: color),
              const SizedBox(width: 2),
              Container(width: 5, height: 2, color: color),
            ],
          )
        else
          Container(width: 12, height: 2, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({required this.totals});

  final List<MonthlyTotal> totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final maxVal = totals.fold<double>(
        0, (m, t) => math.max(m, math.max(t.income, t.expense)));
    final minNet =
        totals.fold<double>(0, (m, t) => math.min(m, t.net));
    final interval = maxVal > 0 ? (maxVal / 3).ceilToDouble() : 1.0;
    final minY = minNet < 0 ? (minNet * 1.2).floorToDouble() : 0.0;
    final maxY = maxVal > 0 ? maxVal * 1.15 : 100.0;

    LineChartBarData makeLine({
      required List<FlSpot> spots,
      required Color color,
      double width = 2.5,
      List<int>? dashArray,
    }) {
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.35,
        color: color,
        barWidth: width,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, _, _, _) => FlDotCirclePainter(
            radius: 3,
            color: color,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(show: false),
        dashArray: dashArray,
      );
    }

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                const labels = ['Income', 'Expense', 'Net'];
                return touchedSpots.map((s) {
                  return LineTooltipItem(
                    '${labels[s.barIndex]}\n${CurrencyFormatter.formatCompact(s.y)}',
                    TextStyle(
                      color: s.bar.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= totals.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      totals[idx].label,
                      style: context.textTheme.bodySmall
                          ?.copyWith(fontSize: 9),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  if (value == minY && minY != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    CurrencyFormatter.formatCompact(value),
                    style:
                        context.textTheme.bodySmall?.copyWith(fontSize: 9),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            makeLine(
              spots: [
                for (int i = 0; i < totals.length; i++)
                  FlSpot(i.toDouble(), totals[i].income)
              ],
              color: colors.income,
            ),
            makeLine(
              spots: [
                for (int i = 0; i < totals.length; i++)
                  FlSpot(i.toDouble(), totals[i].expense)
              ],
              color: colors.expense,
            ),
            makeLine(
              spots: [
                for (int i = 0; i < totals.length; i++)
                  FlSpot(i.toDouble(), totals[i].net)
              ],
              color: cs.primary,
              width: 2.0,
              dashArray: [4, 4],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly Pattern Card (item 13)
// ---------------------------------------------------------------------------

class _WeeklyPatternCard extends ConsumerWidget {
  const _WeeklyPatternCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyTotalsProvider);
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_view_week_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weekly Pattern',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Avg spend by day',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            dailyAsync.when(
              loading: () => const SizedBox(
                  height: 160, child: Center(child: CircularProgressIndicator())),
              error: (e, _) =>
                  SizedBox(height: 160, child: Center(child: Text('Error: $e'))),
              data: (days) {
                if (days.isEmpty) {
                  return SizedBox(
                    height: 160,
                    child: Center(
                      child: Text(
                        'No data for this month',
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                // Group by weekday (0=Mon..6=Sun), collect all expense values
                final sums = List<double>.filled(7, 0.0);
                final counts = List<int>.filled(7, 0);
                for (final d in days) {
                  if (d.expense > 0) {
                    final idx = d.date.weekday - 1;
                    sums[idx] += d.expense;
                    counts[idx]++;
                  }
                }
                final avgs = [
                  for (int i = 0; i < 7; i++)
                    counts[i] > 0 ? sums[i] / counts[i] : 0.0
                ];
                final maxAvg = avgs.fold<double>(0.0, math.max);
                if (maxAvg == 0) {
                  return SizedBox(
                    height: 160,
                    child: Center(
                      child: Text(
                        'No expense data',
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return _WeeklyBarChart(avgs: avgs, maxAvg: maxAvg);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.avgs, required this.maxAvg});

  final List<double> avgs;
  final double maxAvg;

  static const _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final interval = (maxAvg / 3).ceilToDouble().clamp(1.0, double.infinity);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxAvg * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${_dayLabels[group.x]}\n${CurrencyFormatter.formatCompact(rod.toY)}',
                TextStyle(
                  color: rod.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  final isWeekend = i >= 5;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _dayLabels[i],
                      style: context.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: isWeekend ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: isWeekend
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: interval,
                getTitlesWidget: (value, meta) => Text(
                  CurrencyFormatter.formatCompact(value),
                  style: context.textTheme.bodySmall?.copyWith(fontSize: 9),
                ),
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            final isWeekend = i >= 5;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: avgs[i],
                  color: isWeekend
                      ? colors.expense.withValues(alpha: 0.6)
                      : colors.expense,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusSm),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Top parties by transaction volume.
class _TopPartiesCard extends StatelessWidget {
  const _TopPartiesCard({required this.parties});

  final List<PartyTotal> parties;

  @override
  Widget build(BuildContext context) {
    final maxAmount = parties.fold<double>(
        0, (prev, p) => math.max(prev, p.totalAmount));
    final colors = context.kashColors;
    final cs = context.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Parties',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...parties.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final hasInEx = p.income > 0 || p.expense > 0;
              return Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style:
                            context.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.partyName,
                            style: context.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          if (hasInEx)
                            _StackedPartyBar(
                              income: p.income,
                              expense: p.expense,
                              maxAmount: maxAmount,
                            )
                          else
                            LinearProgressIndicator(
                              value: maxAmount > 0
                                  ? p.totalAmount / maxAmount
                                  : 0,
                              backgroundColor:
                                  cs.surfaceContainerHighest,
                              color: cs.primary,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        if (p.income > 0)
                          Text(
                            '+${CurrencyFormatter.formatCompact(p.income)}',
                            style: context.textTheme.bodySmall
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                              color: colors.income,
                            ),
                          ),
                        if (p.expense > 0)
                          Text(
                            '-${CurrencyFormatter.formatCompact(p.expense)}',
                            style: context.textTheme.bodySmall
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                              color: colors.expense,
                            ),
                          ),
                        if (!hasInEx)
                          Text(
                            CurrencyFormatter.formatCompact(
                                p.totalAmount),
                            style: context.textTheme.bodyMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                            ),
                          ),
                        Text(
                          '${p.transactionCount} txns',
                          style: context.textTheme.bodySmall
                              ?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// A small stacked bar showing income (green) and expense (red) segments.
class _StackedPartyBar extends StatelessWidget {
  const _StackedPartyBar({
    required this.income,
    required this.expense,
    required this.maxAmount,
  });

  final double income;
  final double expense;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    if (maxAmount == 0) return const SizedBox.shrink();
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final incomeW = income / maxAmount;
    final expenseW = expense / maxAmount;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            if (incomeW > 0)
              Flexible(
                flex: (incomeW * 1000).round(),
                child: Container(color: colors.income),
              ),
            if (expenseW > 0)
              Flexible(
                flex: (expenseW * 1000).round(),
                child: Container(color: colors.expense),
              ),
            Flexible(
              flex: math.max(
                  0,
                  ((1 - incomeW - expenseW) * 1000)
                      .round()
                      .clamp(0, 1000)),
              child:
                  Container(color: cs.surfaceContainerHighest),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bookings Overview Card ───────────────────────────────────────────────────

class _BookingsOverviewCard extends StatelessWidget {
  const _BookingsOverviewCard({required this.stats});

  final BookingMonthStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final colors = context.kashColors;

    final pipeline = stats.confirmedCount + stats.pendingCount;
    final totalBookings = stats.completedCount + pipeline + stats.noShowCount;
    final noShowRate = totalBookings > 0
        ? (stats.noShowCount / totalBookings * 100).toStringAsFixed(0)
        : '0';

    if (!stats.hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookingsCardHeader(cs: cs, tt: tt),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.base),
                  child: Text(
                    'No bookings this month',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookingsCardHeader(cs: cs, tt: tt),
            const SizedBox(height: AppSpacing.md),

            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _BookingStat(
                    label: 'Completed',
                    value: '${stats.completedCount}',
                    sub: CurrencyFormatter.formatCompact(stats.completedRevenue),
                    icon: Icons.check_circle_outline,
                    color: colors.income,
                    tt: tt,
                  ),
                ),
                Expanded(
                  child: _BookingStat(
                    label: 'Pipeline',
                    value: '$pipeline',
                    sub: '${stats.confirmedCount} confirmed',
                    icon: Icons.pending_outlined,
                    color: cs.primary,
                    tt: tt,
                  ),
                ),
                Expanded(
                  child: _BookingStat(
                    label: 'No-shows',
                    value: '${stats.noShowCount}',
                    sub: '$noShowRate% rate',
                    icon: Icons.person_off_outlined,
                    color: colors.expense,
                    tt: tt,
                  ),
                ),
              ],
            ),

            // Top service
            if (stats.topService != null) ...[
              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  Icon(Icons.star_outline,
                      size: AppSpacing.iconSm, color: cs.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Top service: ',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Expanded(
                    child: Text(
                      stats.topService!,
                      style:
                          tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookingsCardHeader extends StatelessWidget {
  const _BookingsCardHeader({required this.cs, required this.tt});
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.calendar_month_outlined,
            size: AppSpacing.iconSm, color: cs.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Bookings Overview',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BookingsScreen()),
          ),
          child: const Text('View All'),
        ),
      ],
    );
  }
}

class _BookingStat extends StatelessWidget {
  const _BookingStat({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
    required this.tt,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'RobotoMono',
            color: color,
          ),
        ),
        Text(
          label,
          style: tt.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          sub,
          style: tt.bodySmall
              ?.copyWith(fontSize: 10, color: context.colorScheme.outline),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Budget Overview Card — compact summary shown inside Reports
// ---------------------------------------------------------------------------

// _BudgetOverviewCard removed (replaced by _BudgetVsActualCard)
// ignore: unused_element
class _BudgetOverviewCard extends StatelessWidget {
  const _BudgetOverviewCard({required this.budgets});
  final List<Budget> budgets;

  @override
  Widget build(BuildContext context) {
    // Safely cast at use
    final typedBudgets = budgets;

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BudgetScreen()),
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_outlined, size: AppSpacing.iconMd),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Monthly Budgets',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    'Manage →',
                    style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (typedBudgets.isEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                Row(
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: AppSpacing.iconSm,
                        color: context.colorScheme.outline),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Set spending limits for each category',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: context.colorScheme.outline),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
                ...typedBudgets
                    .take(3)
                    .map<Widget>((b) => _MiniBudgetRow(budget: b)),
                if (typedBudgets.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '+ ${typedBudgets.length - 3} more categories',
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: context.colorScheme.outline),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBudgetRow extends StatelessWidget {
  const _MiniBudgetRow({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final pct = budget.spentPercentage.clamp(0.0, 1.0);
    final isOver = budget.isOverBudget;
    final barColor = isOver
        ? colors.expense
        : budget.isNearLimit ? Colors.orange : colors.income;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CategoryHelper.getIcon(budget.category),
                size: AppSpacing.iconSm,
                color: context.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  budget.category,
                  style: context.textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${CurrencyFormatter.format(budget.spentAmount)}'
                ' / ${CurrencyFormatter.format(budget.budgetAmount)}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: isOver ? colors.expense : context.colorScheme.outline,
                  fontFamily: 'RobotoMono',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: context.colorScheme.surfaceContainerHighest,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YTD Summary Row
// ---------------------------------------------------------------------------

class _YtdSummaryRow extends StatelessWidget {
  const _YtdSummaryRow({required this.ytd, required this.month});

  final MonthlyPnL ytd;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final savings = ytd.totalIncome - ytd.totalExpense;
    final monthName = DateFormat('MMM').format(month);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'YTD  Jan\u2013$monthName ${month.year}',
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _YtdStat(
                      label: 'Income',
                      amount: ytd.totalIncome,
                      color: colors.income,
                      tt: tt,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: cs.outlineVariant,
                  ),
                  Expanded(
                    child: _YtdStat(
                      label: 'Expense',
                      amount: ytd.totalExpense,
                      color: colors.expense,
                      tt: tt,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: cs.outlineVariant,
                  ),
                  Expanded(
                    child: _YtdStat(
                      label: 'Saved',
                      amount: savings,
                      color: savings >= 0 ? colors.income : colors.expense,
                      tt: tt,
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

class _YtdStat extends StatelessWidget {
  const _YtdStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.tt,
  });

  final String label;
  final double amount;
  final Color color;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelSmall
                ?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            CurrencyFormatter.formatCompact(amount),
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'RobotoMono',
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Savings Rate Card
// ---------------------------------------------------------------------------

class _SavingsRateCard extends StatelessWidget {
  const _SavingsRateCard({required this.pnl, this.prevRate});

  final MonthlyPnL pnl;
  final double? prevRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final rate = pnl.savingsRate;
    const target = 0.20;
    final isAboveTarget = rate >= target;
    final rateColor = isAboveTarget ? colors.income : cs.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Savings Rate',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1,
                      backgroundColor: Colors.transparent,
                      color: cs.surfaceContainerHighest,
                      strokeWidth: 10,
                    ),
                    CircularProgressIndicator(
                      value: rate,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: rateColor,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Text(
                        '${(rate * 100).toStringAsFixed(0)}%',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'RobotoMono',
                          color: rateColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAboveTarget
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    size: 12,
                    color: isAboveTarget ? colors.income : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Target: 20%',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (prevRate != null && prevRate! > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: _DeltaTag(
                  current: rate,
                  prev: prevRate!,
                  isGoodWhenUp: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avg Daily Spend Card
// ---------------------------------------------------------------------------

class _AvgDailySpendCard extends StatelessWidget {
  const _AvgDailySpendCard({
    required this.pnl,
    required this.daysElapsed,
    required this.month,
    this.prevPnl,
  });

  final MonthlyPnL pnl;
  final MonthlyPnL? prevPnl;
  final double daysElapsed;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final totalDays =
        DateTime(month.year, month.month + 1, 0).day.toDouble();
    final avgSpend =
        daysElapsed > 0 ? pnl.totalExpense / daysElapsed : 0.0;
    final prevMonthDays = prevPnl != null
        ? DateTime(month.year, month.month, 0).day.toDouble()
        : 30.0;
    final prevAvg = (prevPnl != null && prevMonthDays > 0)
        ? prevPnl!.totalExpense / prevMonthDays
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avg Daily Spend',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              CurrencyFormatter.format(avgSpend),
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'RobotoMono',
                color: colors.expense,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${daysElapsed.toInt()} / ${totalDays.toInt()} days',
              style:
                  tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (prevAvg != null && prevAvg > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              _DeltaTag(
                current: avgSpend,
                prev: prevAvg,
                isGoodWhenUp: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Largest Transactions Card
// ---------------------------------------------------------------------------

class _LargestTransactionsCard extends StatelessWidget {
  const _LargestTransactionsCard({required this.transactions});

  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Largest Transactions',
                  style:
                      tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...transactions.map((t) {
              Color typeColor;
              IconData typeIcon;
              switch (t.type) {
                case TransactionType.income:
                case TransactionType.receivedBack:
                case TransactionType.redeemed:
                  typeColor = colors.income;
                  typeIcon = Icons.arrow_downward_rounded;
                case TransactionType.expense:
                case TransactionType.paidBack:
                  typeColor = colors.expense;
                  typeIcon = Icons.arrow_upward_rounded;
                case TransactionType.invested:
                  typeColor = cs.primary;
                  typeIcon = Icons.savings_outlined;
                case TransactionType.lent:
                  typeColor = colors.credit;
                  typeIcon = Icons.call_made_outlined;
                case TransactionType.borrowed:
                  typeColor = cs.tertiary;
                  typeIcon = Icons.call_received_outlined;
                default:
                  typeColor = cs.onSurfaceVariant;
                  typeIcon = Icons.swap_horiz;
              }
              final label = (t.partyName != null && t.partyName!.isNotEmpty)
                  ? t.partyName!
                  : t.category;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm),
                      ),
                      child: Icon(typeIcon, size: 16, color: typeColor),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: tt.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            DateFormat('d MMM').format(t.date),
                            style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(t.amount),
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'RobotoMono',
                        color: typeColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment Method Split Card
// ---------------------------------------------------------------------------

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.data});

  final Map<String, ({double income, double expense})> data;

  static IconData _iconFor(String key) {
    final m = PaymentMethod.fromDb(key);
    switch (m) {
      case PaymentMethod.upi:
        return Icons.phone_android_outlined;
      case PaymentMethod.cash:
        return Icons.payments_outlined;
      case PaymentMethod.creditCard:
        return Icons.credit_card;
      case PaymentMethod.debitCard:
        return Icons.credit_card_outlined;
      case PaymentMethod.netBanking:
        return Icons.account_balance_outlined;
      case PaymentMethod.wallet:
        return Icons.account_balance_wallet_outlined;
      case PaymentMethod.cheque:
        return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;

    final entries = data.entries
        .map((e) => (
              key: e.key,
              income: e.value.income,
              expense: e.value.expense,
              total: e.value.income + e.value.expense,
            ))
        .where((e) => e.total > 0)
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (entries.isEmpty) return const SizedBox.shrink();

    final maxTotal = entries.first.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_score_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Payment Methods',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...entries.map((e) {
              final incomeW = maxTotal > 0 ? e.income / maxTotal : 0.0;
              final expenseW = maxTotal > 0 ? e.expense / maxTotal : 0.0;
              final method = PaymentMethod.fromDb(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Icon(_iconFor(e.key), size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            method.label,
                            style: tt.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            child: SizedBox(
                              height: 6,
                              child: Row(
                                children: [
                                  if (incomeW > 0)
                                    Flexible(
                                      flex: (incomeW * 1000).round(),
                                      child: Container(color: colors.income),
                                    ),
                                  if (expenseW > 0)
                                    Flexible(
                                      flex: (expenseW * 1000).round(),
                                      child: Container(color: colors.expense),
                                    ),
                                  Flexible(
                                    flex: math.max(
                                        0,
                                        ((1 - incomeW - expenseW) * 1000)
                                            .round()
                                            .clamp(0, 1000)),
                                    child: Container(
                                        color: cs.surfaceContainerHighest),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (e.income > 0)
                          Text(
                            CurrencyFormatter.formatCompact(e.income),
                            style: tt.bodySmall?.copyWith(
                              color: colors.income,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                            ),
                          ),
                        if (e.expense > 0)
                          Text(
                            CurrencyFormatter.formatCompact(e.expense),
                            style: tt.bodySmall?.copyWith(
                              color: colors.expense,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Category Drill-Down Bottom Sheet (item 7)
// ---------------------------------------------------------------------------

class _CategoryDrillDownSheet extends ConsumerWidget {
  const _CategoryDrillDownSheet({
    required this.category,
    required this.month,
    required this.categoryTotal,
  });

  final String category;
  final DateTime month;
  final double categoryTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      category: category,
      year: month.year,
      month: month.month,
    );
    final txAsync = ref.watch(categoryTransactionsProvider(key));
    final colors = context.kashColors;
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(CategoryHelper.getIcon(category),
                      size: AppSpacing.iconMd,
                      color: CategoryHelper.getColor(category)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category,
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          DateFormat('MMMM yyyy').format(month),
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(categoryTotal),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                      color: CategoryHelper.getColor(category),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Transaction list
            Expanded(
              child: txAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error: $e')),
                data: (txList) {
                  if (txList.isEmpty) {
                    return Center(
                      child: Text(
                        'No transactions in this category',
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm),
                    itemCount: txList.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 56, endIndent: 16),
                    itemBuilder: (context, i) {
                      final tx = txList[i];
                      final isIncome = tx.type == TransactionType.income ||
                          tx.type == TransactionType.receivedBack ||
                          tx.type == TransactionType.redeemed;
                      final amtColor =
                          isIncome ? colors.income : colors.expense;
                      final label = (tx.partyName != null &&
                              tx.partyName!.isNotEmpty)
                          ? tx.partyName!
                          : tx.category;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              CategoryHelper.getColor(tx.category)
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            CategoryHelper.getIcon(tx.category),
                            size: 16,
                            color: CategoryHelper.getColor(tx.category),
                          ),
                        ),
                        title: Text(label,
                            style: tt.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          DateFormat('d MMM, h:mm a').format(tx.date),
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        trailing: Text(
                          CurrencyFormatter.format(tx.amount),
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'RobotoMono',
                            color: amtColor,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Investment Summary Card (item 8)
// ---------------------------------------------------------------------------

class _InvestmentSummaryCard extends StatelessWidget {
  const _InvestmentSummaryCard({required this.pnl, this.allTime});

  final MonthlyPnL pnl;
  final ({double invested, double net, double redeemed})? allTime;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final netThisMonth = pnl.totalInvested - pnl.totalRedeemed;
    final allTimeNet = allTime?.net;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Investments',
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // This-month row
            Row(
              children: [
                Expanded(
                  child: _InvStat(
                    label: 'Invested',
                    amount: pnl.totalInvested,
                    color: cs.primary,
                    icon: Icons.arrow_circle_up_outlined,
                    tt: tt,
                  ),
                ),
                Expanded(
                  child: _InvStat(
                    label: 'Redeemed',
                    amount: pnl.totalRedeemed,
                    color: cs.tertiary,
                    icon: Icons.arrow_circle_down_outlined,
                    tt: tt,
                  ),
                ),
                Expanded(
                  child: _InvStat(
                    label: 'Net',
                    amount: netThisMonth,
                    color: netThisMonth >= 0 ? cs.primary : cs.error,
                    icon: netThisMonth >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    tt: tt,
                  ),
                ),
              ],
            ),
            if (allTime != null) ...[
              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  Icon(Icons.account_balance_outlined,
                      size: AppSpacing.iconSm,
                      color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Portfolio (all-time)',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    allTimeNet! >= 0
                        ? '+${CurrencyFormatter.formatCompact(allTimeNet)}'
                        : CurrencyFormatter.formatCompact(allTimeNet),
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                      color: allTimeNet >= 0 ? cs.primary : cs.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvStat extends StatelessWidget {
  const _InvStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    required this.tt,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: AppSpacing.xs),
        Text(
          CurrencyFormatter.formatCompact(amount.abs()),
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'RobotoMono',
            color: color,
          ),
        ),
        Text(label,
            style: tt.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Budget vs Actual Card (item 9)
// ---------------------------------------------------------------------------

class _BudgetVsActualCard extends StatelessWidget {
  const _BudgetVsActualCard({required this.budgets});

  final List<Budget> budgets;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;
    final colors = context.kashColors;

    if (budgets.isEmpty) {
      return Card(
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BudgetScreen()),
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Icon(Icons.bar_chart_outlined,
                    size: AppSpacing.iconMd,
                    color: cs.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Set budgets to track spending vs limits',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Text('Set up',
                    style: tt.labelSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    final maxBudget = budgets.fold<double>(
        0, (m, b) => math.max(m, b.budgetAmount));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.waterfall_chart_outlined,
                    size: AppSpacing.iconSm, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Budget vs Actual',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BudgetScreen()),
                  ),
                  child: const Text('Manage'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Legend
            Row(
              children: [
                _BudgetLegend(color: cs.surfaceContainerHighest, label: 'Budget'),
                const SizedBox(width: AppSpacing.base),
                _BudgetLegend(color: colors.income, label: 'Spent (ok)'),
                const SizedBox(width: AppSpacing.base),
                _BudgetLegend(color: colors.expense, label: 'Over budget'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...budgets.map((b) {
              final isOver = b.isOverBudget;
              final barColor = isOver ? colors.expense : colors.income;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(CategoryHelper.getIcon(b.category),
                            size: AppSpacing.iconSm,
                            color: CategoryHelper.getColor(b.category)),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(b.category,
                              style: tt.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(
                          '${CurrencyFormatter.formatCompact(b.spentAmount)} / ${CurrencyFormatter.formatCompact(b.budgetAmount)}',
                          style: tt.labelSmall?.copyWith(
                            fontFamily: 'RobotoMono',
                            color: isOver ? colors.expense : cs.onSurfaceVariant,
                            fontWeight:
                                isOver ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fullW = constraints.maxWidth;
                        final budgetW =
                            (b.budgetAmount / maxBudget * fullW)
                                .clamp(0.0, fullW);
                        final spentW =
                            (b.spentAmount / maxBudget * fullW)
                                .clamp(0.0, fullW);
                        return SizedBox(
                          height: 10,
                          child: Stack(
                            children: [
                              // Budget track (grey)
                              Positioned(
                                left: 0,
                                child: Container(
                                  width: budgetW,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm),
                                  ),
                                ),
                              ),
                              // Spent fill
                              Positioned(
                                left: 0,
                                child: Container(
                                  width: spentW.clamp(0.0, budgetW),
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm),
                                  ),
                                ),
                              ),
                              // Over-budget overflow
                              if (isOver)
                                Positioned(
                                  left: budgetW,
                                  child: Container(
                                    width: (spentW - budgetW).clamp(
                                        0.0, fullW - budgetW),
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color:
                                          colors.expense.withValues(alpha: 0.7),
                                      borderRadius: const BorderRadius.only(
                                        topRight:
                                            Radius.circular(AppSpacing.radiusSm),
                                        bottomRight:
                                            Radius.circular(AppSpacing.radiusSm),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BudgetLegend extends StatelessWidget {
  const _BudgetLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}