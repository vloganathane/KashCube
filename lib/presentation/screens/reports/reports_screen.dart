import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../providers/booking_provider.dart';
import '../../providers/report_provider.dart';
import '../../providers/settings_provider.dart';
import '../bookings/bookings_screen.dart';

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
        _PnLCard(pnl: pnl),
        const SizedBox(height: AppSpacing.base),
        if (pnl.expenseByCat.isNotEmpty) ...[
          _CategoryPieCard(
            title: 'Expense Breakdown',
            data: pnl.expenseByCat,
            total: pnl.totalExpense,
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        if (pnl.incomeByCat.isNotEmpty) ...[
          _CategoryPieCard(
            title: 'Income Breakdown',
            data: pnl.incomeByCat,
            total: pnl.totalIncome,
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        const _MonthlyTrendCard(),
        const SizedBox(height: AppSpacing.base),
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
  const _PnLCard({required this.pnl});

  final MonthlyPnL pnl;

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
                  ),
                ),
                Expanded(
                  child: _PnLItem(
                    label: 'Expense',
                    amount: pnl.totalExpense,
                    color: colors.expense,
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isProfit ? 'Net Profit' : 'Net Loss',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

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
  });

  final String title;
  final Map<String, double> data;
  final double total;

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
            // Category amounts list
            ...display.map((e) {
              final pct =
                  (e.value / total * 100).toStringAsFixed(1);
              return Padding(
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

/// Monthly trend bar chart for the last 6 months.
class _MonthlyTrendCard extends ConsumerWidget {
  const _MonthlyTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalsAsync = ref.watch(monthlyTotalsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Trend',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.outline,
                        ),
                      ),
                    ),
                  );
                }
                return _TrendChart(totals: totals);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.totals});

  final List<MonthlyTotal> totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final maxVal = totals.fold<double>(
      0,
      (prev, t) => math.max(prev, math.max(t.income, t.expense)),
    );
    // Round up to nice interval
    final interval = maxVal > 0 ? (maxVal / 4).ceilToDouble() : 1.0;

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal > 0 ? maxVal * 1.15 : 100,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gIdx, rod, rIdx) {
                final label = rIdx == 0 ? 'Income' : 'Expense';
                return BarTooltipItem(
                  '$label\n${CurrencyFormatter.formatCompact(rod.toY)}',
                  TextStyle(
                    color: rod.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= totals.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      totals[idx].label,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                      ),
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
                  return Text(
                    CurrencyFormatter.formatCompact(value),
                    style: context.textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: interval,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.colorScheme.outlineVariant
                  .withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(totals.length, (i) {
            final t = totals[i];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: t.income,
                  color: colors.income,
                  width: 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusSm),
                  ),
                ),
                BarChartRodData(
                  toY: t.expense,
                  color: colors.expense,
                  width: 12,
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
                          color: context
                              .colorScheme.onSurfaceVariant,
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
                          LinearProgressIndicator(
                            value: maxAmount > 0
                                ? p.totalAmount / maxAmount
                                : 0,
                            backgroundColor: context.colorScheme
                                .surfaceContainerHighest,
                            color: context.colorScheme.primary,
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
                            color: context
                                .colorScheme.onSurfaceVariant,
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
