import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../providers/budget_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/report_provider.dart';
import '../bills/bills_and_payments_screen.dart';
import '../ledger/ledger_screen.dart';
import '../loans/loans_screen.dart';
import '../reports/budget_screen.dart';
import '../reports/reports_screen.dart';
import 'category_management_screen.dart';
import 'transactions_screen.dart';

/// Transactions hub — entry point for all money-movement screens.
class TransactionsHubScreen extends ConsumerWidget {
  const TransactionsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HubSection(
            title: 'Activity',
            tiles: [
              _HubTile(
                icon: Icons.receipt_long_outlined,
                label: 'Transactions',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text =
                        r.watch(dashboardSummaryProvider).whenOrNull(
                              data: (s) =>
                                  '${CurrencyFormatter.formatCompact(s.totalIncome)} in'
                                  ' · ${CurrencyFormatter.formatCompact(s.totalExpense)} out',
                            ) ??
                        'All income & expenses';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF1B5E20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TransactionsScreen(),
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.menu_book_outlined,
                label: 'Ledger',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text = r.watch(partiesProvider).whenOrNull(
                              data: (list) =>
                                  '${list.length} ${list.length == 1 ? 'party' : 'parties'}',
                            ) ??
                        'Party-wise account book';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF006064),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LedgerScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Obligations',
            tiles: [
              _HubTile(
                icon: Icons.payments_outlined,
                label: 'Bills Payable',
                subtitle:
                    const _StaticSubtitle('Personal dues & subscriptions'),
                color: const Color(0xFF6A1B9A),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BillsAndPaymentsScreen(
                      billContext: 'personal',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Credit',
            tiles: [
              _HubTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Loans & Credits',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final lentAmt =
                        r.watch(totalPendingLentProvider).valueOrNull;
                    final borrAmt =
                        r.watch(totalPendingBorrowedProvider).valueOrNull;
                    final text = (lentAmt != null || borrAmt != null)
                        ? '${CurrencyFormatter.formatCompact(lentAmt ?? 0)} lent'
                            ' · ${CurrencyFormatter.formatCompact(borrAmt ?? 0)} owed'
                        : 'Lent, borrowed & dues';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFFE65100),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoansScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Manage',
            tiles: [
              _HubTile(
                icon: Icons.category_outlined,
                label: 'Categories',
                subtitle: const _StaticSubtitle(
                    'View & manage transaction categories'),
                color: const Color(0xFF00695C),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CategoryManagementScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Reports',
            tiles: [
              _HubTile(
                icon: Icons.bar_chart_outlined,
                label: 'P&L & Analytics',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text =
                        r.watch(dashboardSummaryProvider).whenOrNull(
                              data: (s) =>
                                  'Net ${CurrencyFormatter.formatCompact(s.balance)} this month',
                            ) ??
                        'Income vs expense analysis';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF1565C0),
                onTap: () {
                  ref.read(reportPeriodModeProvider.notifier).state = 'month';
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsScreen()),
                  );
                },
              ),
              _HubTile(
                icon: Icons.donut_large_outlined,
                label: 'Budgets',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text =
                        r.watch(currentMonthBudgetsProvider).whenOrNull(
                              data: (list) => list.isEmpty
                                  ? 'No budgets set'
                                  : '${list.length} budget${list.length == 1 ? '' : 's'} active',
                            ) ??
                        'Monthly spend limits';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF6A1B9A),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BudgetScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers (mirrors ContactsHubScreen for visual consistency)
// ---------------------------------------------------------------------------

class _HubSection extends StatelessWidget {
  const _HubSection({required this.title, required this.tiles});
  final String title;
  final List<_HubTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.outline,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i < tiles.length - 1)
                  Divider(
                    height: 1,
                    indent: AppSpacing.base + 40 + AppSpacing.base,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Widget subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Icon(icon, color: color, size: AppSpacing.iconMd),
      ),
      title: Text(label,
          style: context.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right,
          color: context.colorScheme.outlineVariant),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
    );
  }
}

class _StaticSubtitle extends StatelessWidget {
  const _StaticSubtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: context.textTheme.bodySmall
            ?.copyWith(color: context.colorScheme.outline));
  }
}
