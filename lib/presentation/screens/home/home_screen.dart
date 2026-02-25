import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/bill_schedule_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/recurring_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../app_shell.dart';
import '../bills/bills_screen.dart';
import '../recurring/recurring_transactions_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';

/// Home screen with dashboard summary and recent transactions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardSummaryProvider);
    final recentAsync = ref.watch(recentTransactionsProvider);
    final totalPendingLoans = ref.watch(totalPendingLoanProvider).valueOrNull ?? 0.0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(dashboardSummaryProvider.notifier).loadSummary();
          ref.read(recentTransactionsProvider.notifier).loadRecent();
          ref.invalidate(totalPendingLoanProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Row(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 28,
                    width: 28,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Kash Cube'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.base),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Dashboard Card Deck
                  dashboardAsync.when(
                    data: (summary) => _DashboardDeck(
                      summary: summary,
                      totalPendingLoans: totalPendingLoans,
                      ref: ref,
                    ),
                    loading: () => const _DashboardCardsLoading(),
                    error: (e, _) => Center(
                      child: Text('Error: $e', style: TextStyle(color: context.colorScheme.error)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Recent Transactions Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Transactions',
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Switch to Transactions tab (index 1)
                          ref.read(currentTabIndexProvider.notifier).state = 1;
                        },
                        child: const Text('See All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Recent Transactions List
                  recentAsync.when(
                    data: (transactions) {
                      if (transactions.isEmpty) {
                        return const _EmptyState();
                      }
                      return Column(
                        children: transactions.map((txn) => _TransactionTile(
                          transactionId: txn.id,
                          category: txn.category,
                          partyName: txn.partyName,
                          amount: txn.amount,
                          isIncome: txn.isIncome,
                          date: txn.date,
                          paymentMethod: txn.paymentMethod.label,
                        )).toList(),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Text('Error loading transactions: $e'),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable card-deck dashboard.
///
/// **Collapsed:** Balance + compact summary row (Income / Expense / Invest).
/// **Expanded:** Full Income/Expense/Invest cards + Loans/Recurring cards.
class _DashboardDeck extends StatefulWidget {
  final DashboardSummary summary;
  final double totalPendingLoans;
  final WidgetRef ref;

  const _DashboardDeck({
    required this.summary,
    required this.totalPendingLoans,
    required this.ref,
  });

  @override
  State<_DashboardDeck> createState() => _DashboardDeckState();
}

class _DashboardDeckState extends State<_DashboardDeck>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final summary = widget.summary;
    final balance = summary.balance + widget.totalPendingLoans;

    return Card(
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            children: [
              // ── Top: Month + Balance ──
              Text(
                DateFormatter.formatMonthYear(DateTime.now()),
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                CurrencyFormatter.format(balance),
                style: context.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'RobotoMono',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Balance',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: AppSpacing.iconMd,
                      color: context.colorScheme.outline,
                    ),
                  ),
                ],
              ),

              // ── Collapsed: compact summary pills ──
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: _CollapsedSummary(
                  summary: summary,
                  totalPendingLoans: widget.totalPendingLoans,
                  colors: colors,
                ),
                secondChild: _ExpandedDetails(
                  summary: summary,
                  totalPendingLoans: widget.totalPendingLoans,
                  colors: colors,
                  ref: widget.ref,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact single-row summary shown when the card deck is collapsed.
class _CollapsedSummary extends StatelessWidget {
  final DashboardSummary summary;
  final double totalPendingLoans;
  final KashCubeColors colors;

  const _CollapsedSummary({
    required this.summary,
    required this.totalPendingLoans,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MiniMetric(
            icon: Icons.arrow_downward,
            color: colors.income,
            value: CurrencyFormatter.formatCompact(summary.totalIncome),
          ),
          _MiniMetric(
            icon: Icons.arrow_upward,
            color: colors.expense,
            value: CurrencyFormatter.formatCompact(summary.totalExpense),
          ),
          if (summary.totalInvestment > 0)
            _MiniMetric(
              icon: Icons.trending_up,
              color: colors.investment,
              value: CurrencyFormatter.formatCompact(summary.totalInvestment),
            ),
          if (totalPendingLoans > 0)
            _MiniMetric(
              icon: Icons.account_balance,
              color: colors.expense,
              value: CurrencyFormatter.formatCompact(totalPendingLoans),
            ),
        ],
      ),
    );
  }
}

/// Small icon + value used in the collapsed summary row.
class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;

  const _MiniMetric({
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          value,
          style: context.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFamily: 'RobotoMono',
          ),
        ),
      ],
    );
  }
}

/// Full detail view shown when the card deck is expanded.
class _ExpandedDetails extends StatelessWidget {
  final DashboardSummary summary;
  final double totalPendingLoans;
  final KashCubeColors colors;
  final WidgetRef ref;

  const _ExpandedDetails({
    required this.summary,
    required this.totalPendingLoans,
    required this.colors,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final totalLoanAsync = ref.watch(totalPendingLoanProvider);
    final recurringSummary = ref.watch(recurringMonthlySummaryProvider);
    final recurringNet = recurringSummary.expense + recurringSummary.income;
    final totalBillsAsync = ref.watch(totalMonthlyBillsProvider);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [
          // Income / Expense / Invest
          Row(
            children: [
              _DetailTile(
                icon: Icons.arrow_downward,
                label: 'Income',
                value: CurrencyFormatter.formatCompact(summary.totalIncome),
                color: colors.income,
              ),
              _DetailTile(
                icon: Icons.arrow_upward,
                label: 'Expense',
                value: CurrencyFormatter.formatCompact(summary.totalExpense),
                color: colors.expense,
              ),
              _DetailTile(
                icon: Icons.trending_up,
                label: 'Invest',
                value: CurrencyFormatter.formatCompact(summary.totalInvestment),
                color: colors.investment,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Loans / Bills / Recurring
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.account_balance_wallet,
                  label: 'Ledger',
                  value: totalLoanAsync.when(
                    data: (v) => CurrencyFormatter.formatCompact(v),
                    loading: () => '…',
                    error: (e, st) => '–',
                  ),
                  color: colors.expense,
                  onTap: () {
                    // Switch to Ledger tab (index 2)
                    ref.read(currentTabIndexProvider.notifier).state = 2;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: Icons.receipt_long,
                  label: 'Bills',
                  value: totalBillsAsync.when(
                    data: (v) => CurrencyFormatter.formatCompact(v),
                    loading: () => '…',
                    error: (e, st) => '–',
                  ),
                  suffix: '/mo',
                  color: context.colorScheme.tertiary,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BillsScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionTile(
                  icon: Icons.repeat,
                  label: 'Recurring',
                  value: CurrencyFormatter.formatCompact(recurringNet),
                  suffix: '/mo',
                  color: context.colorScheme.primary,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecurringTransactionsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single metric tile used in the expanded 3-column row.
class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: color),
          const SizedBox(height: 2),
          Text(label, style: context.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFamily: 'RobotoMono',
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable action tile for Loans / Recurring in the expanded view.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surfaceContainerHighest.withAlpha(80),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppSpacing.iconSm, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.textTheme.labelSmall),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            style: context.textTheme.titleSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'RobotoMono',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (suffix != null)
                          Text(
                            suffix!,
                            style: context.textTheme.labelSmall?.copyWith(
                              color: context.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AppSpacing.iconSm,
                color: context.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCardsLoading extends StatelessWidget {
  const _DashboardCardsLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Container(
            height: 120,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: Card(child: Container(height: 80))),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Card(child: Container(height: 80))),
          ],
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final int? transactionId;
  final String category;
  final String? partyName;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final String paymentMethod;

  const _TransactionTile({
    this.transactionId,
    required this.category,
    this.partyName,
    required this.amount,
    required this.isIncome,
    required this.date,
    required this.paymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '-';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(
          CategoryHelper.getIcon(category),
          color: context.colorScheme.onPrimaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: Text(
        partyName ?? category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${DateFormatter.format(date)} · $paymentMethod',
        style: context.textTheme.bodySmall,
      ),
      trailing: Text(
        '$prefix${CurrencyFormatter.format(amount)}',
        style: context.textTheme.titleSmall?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFamily: 'RobotoMono',
        ),
      ),
      onTap: transactionId != null
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransactionDetailScreen(
                    transactionId: transactionId!,
                  ),
                ),
              );
            }
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'No transactions yet',
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap + to add your first transaction',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}


