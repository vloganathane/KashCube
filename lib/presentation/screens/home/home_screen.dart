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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(dashboardSummaryProvider.notifier).loadSummary();
          ref.read(recentTransactionsProvider.notifier).loadRecent();
          ref.invalidate(totalPendingLoanProvider);
          ref.invalidate(totalPendingLentProvider);
          ref.invalidate(totalPendingBorrowedProvider);
          ref.invalidate(totalMonthlyBillsProvider);
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
                    data: (summary) => _DashboardDeck(summary: summary),
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

/// Dashboard card deck — swipeable PageView: Overview / Personal / Business.
class _DashboardDeck extends ConsumerStatefulWidget {
  final DashboardSummary summary;

  const _DashboardDeck({required this.summary});

  @override
  ConsumerState<_DashboardDeck> createState() => _DashboardDeckState();
}

class _DashboardDeckState extends ConsumerState<_DashboardDeck> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final colors = context.kashColors;

    final lent     = ref.watch(totalPendingLentProvider).valueOrNull ?? 0.0;
    final borrowed = ref.watch(totalPendingBorrowedProvider).valueOrNull ?? 0.0;
    final hasLoans = lent > 0 || borrowed > 0;

    // Actual = cash physically in hand (borrowed money is in pocket; lent money has left)
    final actualBalance = summary.balance + borrowed - lent;
    // Net worth = what you truly own (lent money is still your receivable)
    final netBalance = summary.balance + lent - borrowed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            // Month
            Text(
              DateFormatter.formatMonthYear(DateTime.now()),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),

            // Primary: Actual Balance (cash in hand)
            Text(
              CurrencyFormatter.format(actualBalance),
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'RobotoMono',
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Actual Balance',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),

            // Secondary: Net Balance + breakdown — only when loans exist
            if (hasLoans) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Net worth ',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.outline,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.formatCompact(netBalance),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: netBalance >= 0 ? colors.income : colors.expense,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                    _BalanceDot(),
                    if (lent > 0) ...[
                      _BalanceChip(
                        label: 'lent',
                        value: CurrencyFormatter.formatCompact(lent),
                        color: colors.income,
                      ),
                      _BalanceDot(),
                    ],
                    if (borrowed > 0)
                      _BalanceChip(
                        label: 'owed',
                        value: CurrencyFormatter.formatCompact(borrowed),
                        color: colors.expense,
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xs),

            // Swipeable cards
            SizedBox(
              height: 130,
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _OverviewCard(summary: summary, colors: colors),
                  _PersonalCard(summary: summary, colors: colors),
                  _BusinessCard(summary: summary, colors: colors),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xs),
            // Page dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: active
                        ? context.colorScheme.primary
                        : context.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card 1: Overview ────────────────────────────────────────────────────────

class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.summary, required this.colors});
  final DashboardSummary summary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBillsAsync = ref.watch(totalMonthlyBillsProvider);
    final recurringSummary = ref.watch(recurringMonthlySummaryProvider);
    final totalLoanAsync = ref.watch(totalPendingLoanProvider);

    return _SwipeCard(
      label: 'Overview',
      icon: Icons.grid_view_rounded,
      color: context.colorScheme.primaryContainer,
      onLabelColor: context.colorScheme.onPrimaryContainer,
      statsRow: [
        _CardStat(
          icon: Icons.arrow_downward, label: 'Income',
          value: CurrencyFormatter.formatCompact(summary.totalIncome),
          color: colors.income,
        ),
        _CardStat(
          icon: Icons.arrow_upward, label: 'Expense',
          value: CurrencyFormatter.formatCompact(summary.totalExpense),
          color: colors.expense,
        ),
        _CardStat(
          icon: Icons.trending_up, label: 'Invest',
          value: CurrencyFormatter.formatCompact(summary.totalInvestment),
          color: colors.investment,
        ),
      ],
      footerTiles: [
        _CardFooterTile(
          icon: Icons.receipt_long, label: 'Bills',
          value: totalBillsAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillsScreen())),
        ),
        _CardFooterTile(
          icon: Icons.repeat, label: 'Recurring',
          value: CurrencyFormatter.formatCompact(
              (recurringSummary.expense + recurringSummary.income).abs()),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RecurringTransactionsScreen())),
        ),
        _CardFooterTile(
          icon: Icons.account_balance_wallet, label: 'Ledger',
          value: totalLoanAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          onTap: () => ref.read(currentTabIndexProvider.notifier).state = 2,
        ),
      ],
    );
  }
}

// ─── Card 2: Personal ────────────────────────────────────────────────────────

class _PersonalCard extends ConsumerWidget {
  const _PersonalCard({required this.summary, required this.colors});
  final DashboardSummary summary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBillsAsync = ref.watch(totalMonthlyBillsProvider);
    final recurringSummary = ref.watch(recurringMonthlySummaryProvider);
    final income = summary.personalIncome ?? 0;
    final expense = summary.personalExpense ?? 0;
    final pnl = summary.personalPnl;
    final pnlColor = pnl >= 0 ? colors.income : colors.expense;
    final pnlPrefix = pnl >= 0 ? '+' : '';

    return _SwipeCard(
      label: 'Personal',
      icon: Icons.person_outline,
      color: context.colorScheme.secondaryContainer,
      onLabelColor: context.colorScheme.onSecondaryContainer,
      statsRow: [
        _CardStat(
          icon: Icons.arrow_downward, label: 'Income',
          value: CurrencyFormatter.formatCompact(income),
          color: colors.income,
        ),
        _CardStat(
          icon: Icons.arrow_upward, label: 'Expense',
          value: CurrencyFormatter.formatCompact(expense),
          color: colors.expense,
        ),
        _CardStat(
          icon: Icons.balance, label: 'Net',
          value: '$pnlPrefix${CurrencyFormatter.formatCompact(pnl.abs())}',
          color: pnlColor,
        ),
      ],
      footerTiles: [
        _CardFooterTile(
          icon: Icons.receipt_long, label: 'Bills',
          value: totalBillsAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillsScreen())),
        ),
        _CardFooterTile(
          icon: Icons.repeat, label: 'Recurring',
          value: CurrencyFormatter.formatCompact(
              (recurringSummary.expense + recurringSummary.income).abs()),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RecurringTransactionsScreen())),
        ),
      ],
    );
  }
}

// ─── Card 3: Business ────────────────────────────────────────────────────────

class _BusinessCard extends ConsumerWidget {
  const _BusinessCard({required this.summary, required this.colors});
  final DashboardSummary summary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lentAsync = ref.watch(totalPendingLentProvider);
    final borrowedAsync = ref.watch(totalPendingBorrowedProvider);
    final income = summary.businessIncome ?? 0;
    final expense = summary.businessExpense ?? 0;
    final pnl = summary.businessPnl;
    final pnlColor = pnl >= 0 ? colors.income : colors.expense;
    final pnlPrefix = pnl >= 0 ? '+' : '';

    return _SwipeCard(
      label: 'Business',
      icon: Icons.business_center_outlined,
      color: context.colorScheme.tertiaryContainer,
      onLabelColor: context.colorScheme.onTertiaryContainer,
      statsRow: [
        _CardStat(
          icon: Icons.arrow_downward, label: 'Income',
          value: CurrencyFormatter.formatCompact(income),
          color: colors.income,
        ),
        _CardStat(
          icon: Icons.arrow_upward, label: 'Expense',
          value: CurrencyFormatter.formatCompact(expense),
          color: colors.expense,
        ),
        _CardStat(
          icon: Icons.balance, label: 'Net',
          value: '$pnlPrefix${CurrencyFormatter.formatCompact(pnl.abs())}',
          color: pnlColor,
        ),
      ],
      footerTiles: [
        _CardFooterTile(
          icon: Icons.call_made, label: 'Lent out',
          value: lentAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          onTap: () => ref.read(currentTabIndexProvider.notifier).state = 2,
        ),
        _CardFooterTile(
          icon: Icons.call_received, label: 'Borrowed',
          value: borrowedAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          onTap: () => ref.read(currentTabIndexProvider.notifier).state = 2,
        ),
      ],
    );
  }
}

// ─── Shared card shell ────────────────────────────────────────────────────────

class _SwipeCard extends StatelessWidget {
  const _SwipeCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onLabelColor,
    required this.statsRow,
    required this.footerTiles,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color onLabelColor;
  final List<_CardStat> statsRow;
  final List<_CardFooterTile> footerTiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Card label
            Row(
              children: [
                Icon(icon, size: 12, color: onLabelColor.withAlpha(180)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: onLabelColor.withAlpha(200),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: statsRow,
            ),

            const SizedBox(height: AppSpacing.xs),
            Divider(height: 1, color: onLabelColor.withAlpha(40)),
            const SizedBox(height: AppSpacing.xs),

            // Footer tiles
            Row(
              mainAxisAlignment: footerTiles.length <= 2
                  ? MainAxisAlignment.spaceEvenly
                  : MainAxisAlignment.spaceAround,
              children: footerTiles,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color.withAlpha(200)),
            const SizedBox(width: 2),
            Text(
              label,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: color.withAlpha(180)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontFamily: 'RobotoMono',
          ),
        ),
      ],
    );
  }
}

class _CardFooterTile extends StatelessWidget {
  const _CardFooterTile({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: context.textTheme.labelMedium?.copyWith(
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (suffix != null)
                      TextSpan(
                        text: suffix,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small labelled chip used in the balance breakdown row.
class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
          TextSpan(
            text: value,
            style: context.textTheme.labelSmall?.copyWith(
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

class _BalanceDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        '·',
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colorScheme.outlineVariant,
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


