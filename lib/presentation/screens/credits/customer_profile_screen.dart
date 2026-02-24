import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/credit_record.dart';
import '../../../domain/repositories/credit_repository.dart';
import '../../providers/credit_provider.dart';
import 'add_edit_credit_screen.dart';
import 'credit_detail_screen.dart';

/// Displays a customer's full credit profile — summary, active credits,
/// and history.
class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({super.key, required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(customerSummaryProvider(customerName));
    final creditsAsync = ref.watch(creditsByCustomerProvider(customerName));

    return Scaffold(
      appBar: AppBar(
        title: Text(customerName),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCredit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Credit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // Customer summary card
          _buildSummaryCard(context, summaryAsync),
          const SizedBox(height: AppSpacing.lg),

          // Credits list
          Text(
            'Credit Records',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildCreditsList(context, creditsAsync),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    AsyncValue<CustomerCreditSummary?> summaryAsync,
  ) {
    final colors = context.kashColors;

    return summaryAsync.when(
      data: (summary) {
        if (summary == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: Text('No data')),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              children: [
                // Avatar + name
                CircleAvatar(
                  radius: 32,
                  backgroundColor: summary.overdueCount > 0
                      ? colors.overdueBackground
                      : colors.creditBackground,
                  child: Text(
                    customerName[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 28,
                      color: summary.overdueCount > 0
                          ? colors.overdue
                          : colors.credit,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  customerName,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (summary.phoneNumber != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary.phoneNumber!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.base),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Total Given',
                      value: CurrencyFormatter.format(summary.totalGiven),
                      color: colors.expense,
                    ),
                    _StatItem(
                      label: 'Total Received',
                      value: CurrencyFormatter.format(summary.totalReceived),
                      color: colors.income,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Pending',
                      value: CurrencyFormatter.format(summary.totalPending),
                      color: colors.credit,
                    ),
                    _StatItem(
                      label: 'Records',
                      value:
                          '${summary.pendingCount} active · ${summary.clearedCount} cleared',
                      color: context.colorScheme.onSurface,
                    ),
                  ],
                ),
                if (summary.overdueCount > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.overdue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: colors.overdue,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${summary.overdueCount} overdue',
                          style: context.textTheme.labelMedium?.copyWith(
                            color: colors.overdue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildCreditsList(
    BuildContext context,
    AsyncValue<List<CreditRecord>> creditsAsync,
  ) {
    return creditsAsync.when(
      data: (credits) {
        if (credits.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color: context.colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No credit records',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Separate pending and cleared
        final pending = credits.where((c) => !c.isCleared).toList();
        final cleared = credits.where((c) => c.isCleared).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pending credits
            if (pending.isNotEmpty) ...[
              _buildSectionHeader(context, 'Active', pending.length),
              ...pending.map((c) => _buildCreditTile(context, c)),
            ],
            // Cleared credits
            if (cleared.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _buildSectionHeader(context, 'Cleared', cleared.length),
              ...cleared.map((c) => _buildCreditTile(context, c)),
            ],
            // Give room for FAB
            const SizedBox(height: 80),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: context.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditTile(BuildContext context, CreditRecord credit) {
    final colors = context.kashColors;
    final isOverdue = credit.computedOverdue;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreditDetailScreen(creditId: credit.id!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Direction icon
              Icon(
                credit.isGiven ? Icons.arrow_upward : Icons.arrow_downward,
                color: credit.isGiven ? colors.expense : colors.income,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          credit.direction.shortLabel,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: credit.isGiven
                                ? colors.expense
                                : colors.income,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '· ${DateFormatter.format(credit.creditDate)}',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (credit.notes != null && credit.notes!.isNotEmpty)
                      Text(
                        credit.notes!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Progress bar for pending credits
                    if (!credit.isCleared && credit.paidAmount > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: credit.repaymentProgress,
                          minHeight: 3,
                          backgroundColor:
                              context.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(colors.income),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(
                      credit.isCleared
                          ? credit.totalAmount
                          : credit.pendingAmount,
                    ),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'RobotoMono',
                      color: credit.isCleared
                          ? colors.income
                          : isOverdue
                              ? colors.overdue
                              : colors.credit,
                    ),
                  ),
                  if (isOverdue)
                    Text(
                      'OVERDUE',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.overdue,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (credit.isCleared)
                    Text(
                      'CLEARED',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.income,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCredit(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditCreditScreen(
          credit: CreditRecord(
            customerName: customerName,
            totalAmount: 0,
            pendingAmount: 0,
            creditDate: DateTime.now(),
          ),
        ),
      ),
    );
    if (result == true) {
      ref.invalidate(creditsByCustomerProvider(customerName));
      ref.invalidate(customerSummaryProvider(customerName));
      ref.invalidate(pendingCreditsProvider);
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Stat item widget
// ---------------------------------------------------------------------------

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
