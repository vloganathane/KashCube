import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/transaction_provider.dart';
import 'transaction_detail_screen.dart';

/// Screen showing the full list of transactions with search and filters.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement filters
            },
          ),
        ],
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final txn = transactions[index];
              final colors = context.kashColors;
              final amountColor = txn.isIncome ? colors.income : colors.expense;
              final prefix = txn.isIncome ? '+' : '-';

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
                  '${DateFormatter.format(txn.date)} · ${txn.paymentMethod.label}',
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
                        builder: (_) => TransactionDetailScreen(
                          transactionId: txn.id!,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
