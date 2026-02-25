import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/transaction.dart';
import '../../providers/loan_provider.dart';
import '../../providers/transaction_provider.dart';
import '../ledger/ledger_screen.dart';
import '../transactions/transaction_detail_screen.dart';

/// Global search across transactions and ledger entries.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search transactions, ledger, parties...',
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: AppSpacing.iconSm),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: _query.length < 2
          ? _buildHint(context)
          : _SearchResults(query: _query),
    );
  }

  Widget _buildHint(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Type at least 2 characters to search',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays combined search results from transactions and ledger entries.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final loansAsync = ref.watch(activeLoansProvider);

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (transactions) {
        final q = query.toLowerCase();

        // Filter transactions
        final matchedTxns = transactions.where((t) {
          final party = t.partyName?.toLowerCase() ?? '';
          final category = t.category.toLowerCase();
          final notes = t.notes?.toLowerCase() ?? '';
          final amount = CurrencyFormatter.format(t.amount).toLowerCase();
          return party.contains(q) ||
              category.contains(q) ||
              notes.contains(q) ||
              amount.contains(q);
        }).toList();

        // Filter ledger entries
        final loans = loansAsync.valueOrNull ?? <Loan>[];
        final matchedLoans = loans.where((l) {
          final name = l.lenderName.toLowerCase();
          final phone = l.phoneNumber?.toLowerCase() ?? '';
          final notes = l.notes?.toLowerCase() ?? '';
          return name.contains(q) || phone.contains(q) || notes.contains(q);
        }).toList();

        final totalResults = matchedTxns.length + matchedLoans.length;

        if (totalResults == 0) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: context.colorScheme.outlineVariant,
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'No results for "$query"',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Transactions section
            if (matchedTxns.isNotEmpty) ...[
              _SectionHeader(
                title: 'Transactions',
                count: matchedTxns.length,
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...matchedTxns.take(20).map((txn) => _TransactionTile(txn: txn)),
              if (matchedTxns.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '+ ${matchedTxns.length - 20} more transactions',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: AppSpacing.base),
            ],

            // Ledger section
            if (matchedLoans.isNotEmpty) ...[
              _SectionHeader(
                title: 'Ledger',
                count: matchedLoans.length,
                icon: Icons.account_balance_wallet,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...matchedLoans.take(20).map((l) => _LedgerTile(loan: l)),
              if (matchedLoans.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '+ ${matchedLoans.length - 20} more entries',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: context.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: context.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            '$count',
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isIncome = txn.isIncome;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '-';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(
          CategoryHelper.getIcon(txn.category),
          color: context.colorScheme.onPrimaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: Text(
        txn.partyName ?? txn.category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${DateFormatter.format(txn.date)} · ${txn.category}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Text(
        '$prefix${CurrencyFormatter.format(txn.amount)}',
        style: context.textTheme.titleSmall?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFamily: 'RobotoMono',
        ),
      ),
      onTap: () {
        if (txn.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transactionId: txn.id!),
            ),
          );
        }
      },
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final directionColor = loan.isLent ? colors.credit : colors.expense;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: directionColor.withValues(alpha: 0.12),
        child: Icon(
          loan.isLent ? Icons.arrow_upward : Icons.arrow_downward,
          color: directionColor,
          size: AppSpacing.iconMd,
        ),
      ),
      title: Text(
        loan.lenderName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${loan.isLent ? "Lent" : "Borrowed"} · ${DateFormatter.format(loan.loanDate)}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(loan.pendingAmount),
            style: context.textTheme.titleSmall?.copyWith(
              color: directionColor,
              fontWeight: FontWeight.w600,
              fontFamily: 'RobotoMono',
            ),
          ),
          Text(
            loan.isCleared ? 'Cleared' : 'Pending',
            style: context.textTheme.bodySmall?.copyWith(
              color: loan.isCleared
                  ? colors.income
                  : context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () {
        // Navigate to ledger entry edit
        if (loan.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddLedgerEntryScreen(loan: loan),
            ),
          );
        }
      },
    );
  }
}
