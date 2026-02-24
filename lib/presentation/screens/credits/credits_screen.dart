import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../providers/credit_provider.dart';

/// Screen showing credit/udhar records with pending and overdue sections.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(pendingCreditsProvider);
    final totalPendingAsync = ref.watch(totalPendingCreditProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credits (Udhar)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Card
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          'Total Pending',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        totalPendingAsync.when(
                          data: (total) => Text(
                            CurrencyFormatter.format(total),
                            style: context.textTheme.titleLarge?.copyWith(
                              color: context.kashColors.credit,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'RobotoMono',
                            ),
                          ),
                          loading: () => const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, _) => const Text('--'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Credits List
          Expanded(
            child: creditsAsync.when(
              data: (credits) {
                if (credits.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.handshake_outlined,
                          size: 64,
                          color: context.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: AppSpacing.base),
                        Text(
                          'No pending credits',
                          style: context.textTheme.titleMedium?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap + to give credit to a customer',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  itemCount: credits.length,
                  itemBuilder: (context, index) {
                    final credit = credits[index];
                    final isOverdue = credit.computedOverdue;

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOverdue
                              ? context.kashColors.overdueBackground
                              : context.kashColors.creditBackground,
                          child: Text(
                            credit.customerName[0].toUpperCase(),
                            style: TextStyle(
                              color: isOverdue
                                  ? context.kashColors.overdue
                                  : context.kashColors.credit,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(credit.customerName),
                        subtitle: Text(
                          'Pending: ${CurrencyFormatter.format(credit.pendingAmount)}',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isOverdue ? context.kashColors.overdue : null,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(credit.totalAmount),
                              style: context.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'RobotoMono',
                              ),
                            ),
                            if (isOverdue)
                              Text(
                                'OVERDUE',
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: context.kashColors.overdue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          // TODO: Navigate to credit detail
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
