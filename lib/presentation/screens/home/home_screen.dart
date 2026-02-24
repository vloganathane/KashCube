import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';
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
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Kash Cube'),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.base),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Dashboard Summary Cards
                  dashboardAsync.when(
                    data: (summary) => _DashboardCards(summary: summary),
                    loading: () => const _DashboardCardsLoading(),
                    error: (e, _) => Center(
                      child: Text('Error: $e', style: TextStyle(color: context.colorScheme.error)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

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
                          // Navigate handled by parent shell
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

class _DashboardCards extends StatelessWidget {
  final DashboardSummary summary;
  const _DashboardCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;

    return Column(
      children: [
        // Balance Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Text(
                  DateFormatter.formatMonthYear(DateTime.now()),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  CurrencyFormatter.format(summary.balance),
                  style: context.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'RobotoMono',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Balance',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Income / Expense Row
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_downward, color: colors.income, size: AppSpacing.iconMd),
                          const SizedBox(width: AppSpacing.xs),
                          Text('Income', style: context.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        CurrencyFormatter.formatCompact(summary.totalIncome),
                        style: context.textTheme.titleLarge?.copyWith(
                          color: colors.income,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'RobotoMono',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_upward, color: colors.expense, size: AppSpacing.iconMd),
                          const SizedBox(width: AppSpacing.xs),
                          Text('Expense', style: context.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        CurrencyFormatter.formatCompact(summary.totalExpense),
                        style: context.textTheme.titleLarge?.copyWith(
                          color: colors.expense,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'RobotoMono',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
