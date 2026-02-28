import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/scheduled_payment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/upcoming_provider.dart';
import '../../app_shell.dart';
import '../../../data/models/booking.dart';
import '../bills/bills_and_payments_screen.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/bookings_screen.dart';
import '../ledger/ledger_screen.dart';
import '../loans/loans_screen.dart';
import '../invoices/invoices_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../../providers/settings_provider.dart';

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
          ref.invalidate(totalOutstandingLentProvider);
          ref.invalidate(totalOutstandingBorrowedProvider);
          ref.invalidate(totalMonthlyScheduledExpenseProvider);
          ref.invalidate(todayCashflowProvider);
          ref.invalidate(upcomingBookingsProvider);
          ref.invalidate(invoicesProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Row(
                children: [
                  Image.asset(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'assets/logo-white.png'
                        : 'assets/logo.png',
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
                if (ref.watch(businessModeProvider))
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More',
                    onSelected: (value) {
                      if (value == 'invoices') {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const InvoicesScreen(),
                        ));
                      } else if (value == 'bookings') {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const BookingsScreen(),
                        ));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'invoices',
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('Invoices & Quotes'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bookings',
                        child: ListTile(
                          leading: Icon(Icons.calendar_month_outlined),
                          title: Text('Bookings'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
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
                  const SizedBox(height: AppSpacing.sm),

                  // Today's cashflow bar
                  const _TodayCashflowBar(),
                  const SizedBox(height: AppSpacing.lg),

                  // Upcoming payments — loan EMIs / due dates + bills
                  const _UpcomingSection(),

                  // Upcoming bookings — next 3 pending/confirmed
                  const _UpcomingBookingsSection(),

                  // Alerts — overdue invoices + pending credits
                  const _AlertsSection(),

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
                        children: transactions.take(5).map((txn) => _TransactionTile(
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
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final colors = context.kashColors;

    final lent     = ref.watch(totalOutstandingLentProvider).valueOrNull ?? 0.0;
    final borrowed = ref.watch(totalOutstandingBorrowedProvider).valueOrNull ?? 0.0;
    final hasLoans = lent > 0 || borrowed > 0;

    // Actual = cash physically in hand (borrowed money is in pocket; lent money has left)
    final actualBalance = summary.balance + borrowed - lent;
    // Net worth = what you truly own (lent money is still your receivable)
    final netBalance = summary.balance + lent - borrowed;

    return Card(
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
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
              // Label + chevron
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Actual Balance',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: context.colorScheme.outline,
                    ),
                  ),
                ],
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

              // Swipeable cards — only when expanded
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                child: _expanded
                    ? Column(
                        children: [
                          const SizedBox(height: AppSpacing.xs),
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
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
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
    final monthlyScheduledAsync = ref.watch(totalMonthlyScheduledExpenseProvider);
    // Total outstanding = outstanding lent (to receive) + outstanding borrowed (to pay)
    final lentOutstanding     = ref.watch(totalOutstandingLentProvider).valueOrNull ?? 0.0;
    final borrowedOutstanding = ref.watch(totalOutstandingBorrowedProvider).valueOrNull ?? 0.0;
    final totalOutstanding = lentOutstanding + borrowedOutstanding;

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
          icon: Icons.event_repeat, label: 'Bills & Pay',
          value: monthlyScheduledAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillsAndPaymentsScreen())),
        ),
        _CardFooterTile(
          icon: Icons.handshake_outlined, label: 'Loans',
          value: CurrencyFormatter.formatCompact(totalOutstanding),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoansScreen())),
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
    final monthlyScheduledAsync = ref.watch(totalMonthlyScheduledExpenseProvider);
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
          icon: Icons.event_repeat, label: 'Bills & Pay',
          value: monthlyScheduledAsync.maybeWhen(
            data: (v) => CurrencyFormatter.formatCompact(v), orElse: () => '…'),
          suffix: '/mo',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BillsAndPaymentsScreen())),
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
    final lentAsync = ref.watch(totalOutstandingLentProvider);
    final borrowedAsync = ref.watch(totalOutstandingBorrowedProvider);
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

// ---------------------------------------------------------------------------
// _TodayCashflowBar — today's income & expense summary
// ---------------------------------------------------------------------------

class _TodayCashflowBar extends ConsumerWidget {
  const _TodayCashflowBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayCashflowProvider);
    final colors = context.kashColors;

    return todayAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (today) {
        final net = today.income - today.expense;
        final hasActivity = today.income > 0 || today.expense > 0;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _CashflowPill(
                icon: Icons.south_rounded,
                label: 'In',
                value: CurrencyFormatter.formatCompact(today.income),
                color: colors.income,
              ),
              const SizedBox(width: AppSpacing.sm),
              _CashflowPill(
                icon: Icons.north_rounded,
                label: 'Out',
                value: CurrencyFormatter.formatCompact(today.expense),
                color: colors.expense,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Today',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (hasActivity)
                    Text(
                      '${net >= 0 ? '+' : ''}${CurrencyFormatter.formatCompact(net)}',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: net >= 0 ? colors.income : colors.expense,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'RobotoMono',
                      ),
                    )
                  else
                    Text(
                      'No activity',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CashflowPill extends StatelessWidget {
  const _CashflowPill({
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          '$label ',
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: context.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontFamily: 'RobotoMono',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _UpcomingBookingsSection — next pending/confirmed bookings (max 3)
// ---------------------------------------------------------------------------

class _UpcomingBookingsSection extends ConsumerWidget {
  const _UpcomingBookingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(upcomingBookingsProvider);

    return bookingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (bookings) {
        final active = bookings
            .where((b) =>
                b.status == BookingStatus.pending ||
                b.status == BookingStatus.confirmed)
            .take(3)
            .toList();
        if (active.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bookings',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BookingsScreen(),
                    ),
                  ),
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...active.map((b) => _BookingTimelineTile(booking: b)),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }
}

class _BookingTimelineTile extends StatelessWidget {
  const _BookingTimelineTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isPersonal = booking.bookingType == BookingType.personal;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bookingDay = DateTime(
      booking.startDatetime.year,
      booking.startDatetime.month,
      booking.startDatetime.day,
    );
    final isToday = bookingDay == today;
    final isTomorrow = bookingDay == today.add(const Duration(days: 1));

    const shortMonths = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final shortMonth = shortMonths[booking.startDatetime.month];

    final Color statusColor = switch (booking.status) {
      BookingStatus.confirmed => colors.income,
      BookingStatus.pending   => context.colorScheme.primary,
      _                       => context.colorScheme.outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (booking.id != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookingDetailScreen(bookingId: booking.id!),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              // Date block
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      booking.startDatetime.day.toString(),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.colorScheme.onPrimaryContainer,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      isToday ? 'Today' : isTomorrow ? 'Tmrw' : shortMonth,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.7),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Title + time/service
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPersonal ? booking.serviceName : booking.customerName,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${DateFormatter.formatTime(booking.startDatetime)} · ${booking.serviceName}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Status badge + amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      booking.status.label,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!isPersonal && booking.totalAmount > 0) ...[  
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(booking.totalAmount),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AlertsSection — overdue invoices + pending credits calls-to-action
// ---------------------------------------------------------------------------

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessMode = ref.watch(businessModeProvider);
    final overdueSummary = ref.watch(overdueInvoicesSummaryProvider);
    final lent = ref.watch(totalOutstandingLentProvider).valueOrNull ?? 0.0;

    final overdueCount = overdueSummary?.count ?? 0;
    final overdueTotal = overdueSummary?.totalDue ?? 0.0;
    final hasOverdue = businessMode && overdueCount > 0;
    final hasCredits = lent > 0;

    if (!hasOverdue && !hasCredits) return const SizedBox.shrink();

    return Column(
      children: [
        if (hasOverdue)
          _AlertActionTile(
            icon: Icons.receipt_long_outlined,
            label: '$overdueCount unpaid invoice${overdueCount > 1 ? 's' : ''}',
            value: CurrencyFormatter.format(overdueTotal),
            color: context.colorScheme.error,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InvoicesScreen()),
            ),
          ),
        if (hasCredits)
          _AlertActionTile(
            icon: Icons.handshake_outlined,
            label: 'Lent out (pending)',
            value: CurrencyFormatter.format(lent),
            color: context.kashColors.credit,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LedgerScreen()),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _AlertActionTile extends StatelessWidget {
  const _AlertActionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'RobotoMono',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _UpcomingSection — swipeable upcoming loan + bill reminders
// ---------------------------------------------------------------------------

class _UpcomingSection extends ConsumerStatefulWidget {
  const _UpcomingSection();

  @override
  ConsumerState<_UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends ConsumerState<_UpcomingSection> {
  static const _previewCount = 5;
  bool _expanded = false;
  /// Keys of items the user has already swiped — remove immediately so the
  /// Dismissible widget leaves the tree before the provider refreshes.
  final Set<String> _dismissedKeys = {};

  @override
  Widget build(BuildContext context) {
    final upcomingAsync = ref.watch(upcomingItemsProvider);

    return upcomingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        // Clear keys that are no longer in the provider list (already removed)
        final incomingKeys = items.map((item) {
          if (item is LoanUpcomingItem) return 'loan_${item.loan.id}';
          return 'sched_${(item as ScheduledUpcomingItem).payment.id}';
        }).toSet();
        _dismissedKeys.removeWhere((k) => !incomingKeys.contains(k));

        // Filter out already-dismissed items (pending async provider refresh)
        final visible = items.where((item) {
          final String k;
          if (item is LoanUpcomingItem) {
            k = 'loan_${item.loan.id}';
          } else {
            k = 'sched_${(item as ScheduledUpcomingItem).payment.id}';
          }
          return !_dismissedKeys.contains(k);
        }).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        final overdueCount = visible.where((i) => i.isOverdue).length;
        final displayed =
            _expanded ? visible : visible.take(_previewCount).toList();
        final extra = visible.length - _previewCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Upcoming',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (overdueCount > 0) ...
                    [
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$overdueCount overdue',
                          style: context.textTheme.labelSmall?.copyWith(
                            color: context.colorScheme.onError,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (visible.length > _previewCount)
                  TextButton(
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? 'Show less' : 'See $extra more',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Items
            ...displayed.map((item) {
              final String key;
              if (item is LoanUpcomingItem) {
                key = 'loan_${item.loan.id}';
              } else {
                key = 'sched_${(item as ScheduledUpcomingItem).payment.id}';
              }
              return Dismissible(
                key: ValueKey(key),
                direction: DismissDirection.startToEnd,
                background: Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  padding: const EdgeInsets.only(left: AppSpacing.lg),
                  alignment: Alignment.centerLeft,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Mark Paid',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) {
                  // Remove from local set immediately so the item leaves the
                  // tree before the async provider refresh completes.
                  setState(() => _dismissedKeys.add(key));
                  _onMarkPaid(item);
                },
                child: _UpcomingItemTile(item: item),
              );
            }),

            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    );
  }

  Future<void> _onMarkPaid(UpcomingItem item) async {
    if (item is ScheduledUpcomingItem) {
      await ref
          .read(scheduledPaymentsProvider.notifier)
          .markPaid(item.payment);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.payment.name} marked as paid'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => ref
                .read(scheduledPaymentsProvider.notifier)
                .markUnpaid(item.payment),
          ),
        ),
      );
    } else if (item is LoanUpcomingItem) {
      final amt = item.paymentAmount;
      await ref
          .read(activeLoansProvider.notifier)
          .recordPayment(item.loan.id!, amt);
      ref.invalidate(totalOutstandingLentProvider);
      ref.invalidate(totalOutstandingBorrowedProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${CurrencyFormatter.format(amt)} paid · ${item.loan.lenderName}',
          ),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// _UpcomingItemTile
// ---------------------------------------------------------------------------

class _UpcomingItemTile extends StatelessWidget {
  const _UpcomingItemTile({required this.item});

  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final days = item.daysUntilDue;

    final String title;
    final String subtitle;
    final double amount;
    final Color accentColor;
    final IconData iconData;

    if (item is LoanUpcomingItem) {
      final l = item as LoanUpcomingItem;
      title = l.loan.lenderName;
      subtitle = l.loan.isLent ? 'Collect' : 'Pay back';
      amount = l.paymentAmount;
      accentColor = l.loan.isLent ? colors.income : colors.expense;
      iconData = l.loan.isLent ? Icons.call_received : Icons.send;
    } else {
      final b = item as ScheduledUpcomingItem;
      title = b.payment.name;
      subtitle = b.payment.category;
      amount = b.payment.amount;
      accentColor = b.payment.isIncome ? colors.income : colors.expense;
      iconData = b.payment.isOneTime ? Icons.event : Icons.event_repeat;
    }

    final dueLabel = switch (days) {
      0 => 'Due today',
      1 => 'Tomorrow',
      final d when d < 0 => '${d.abs()}d overdue',
      final d => 'in ${d}d',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: accentColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$subtitle · $dueLabel',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: days < 0
                          ? context.colorScheme.error
                          : context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(amount),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'RobotoMono',
                  ),
                ),
                Icon(
                  Icons.swipe_right_outlined,
                  size: 12,
                  color: context.colorScheme.outlineVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
