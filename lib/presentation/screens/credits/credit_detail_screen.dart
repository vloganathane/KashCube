import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/credit_record.dart';
import '../../providers/credit_provider.dart';
import 'add_edit_credit_screen.dart';
import 'record_payment_screen.dart';

/// Detailed view of a single credit record with payment history.
class CreditDetailScreen extends ConsumerWidget {
  const CreditDetailScreen({super.key, required this.creditId});

  final int creditId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(creditByIdProvider(creditId));
    final paymentsAsync = ref.watch(creditPaymentsProvider(creditId));

    return creditAsync.when(
      data: (credit) {
        if (credit == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Credit Detail')),
            body: const Center(child: Text('Credit not found')),
          );
        }
        return _CreditDetailBody(
          credit: credit,
          paymentsAsync: paymentsAsync,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Credit Detail')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Credit Detail')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _CreditDetailBody extends ConsumerWidget {
  const _CreditDetailBody({
    required this.credit,
    required this.paymentsAsync,
  });

  final CreditRecord credit;
  final AsyncValue<List<CreditPayment>> paymentsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final isOverdue = credit.computedOverdue;

    return Scaffold(
      appBar: AppBar(
        title: Text(credit.customerName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editCredit(context, ref),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'delete') _deleteCredit(context, ref);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outlined, color: Colors.red),
                    SizedBox(width: AppSpacing.sm),
                    Text('Delete'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: credit.isCleared
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _recordPayment(context, ref),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record Payment'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // Amount card
          _buildAmountCard(context, isOverdue, colors),
          const SizedBox(height: AppSpacing.base),

          // Progress card
          _buildProgressCard(context, colors),
          const SizedBox(height: AppSpacing.base),

          // Details card
          _buildDetailsCard(context, colors, isOverdue),
          const SizedBox(height: AppSpacing.lg),

          // Payment history
          Text(
            'Payment History',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildPaymentHistory(context, colors),
        ],
      ),
    );
  }

  Widget _buildAmountCard(
    BuildContext context,
    bool isOverdue,
    KashCubeColors colors,
  ) {
    return Card(
      color: isOverdue
          ? colors.overdueBackground
          : credit.isCleared
              ? colors.income.withValues(alpha: 0.08)
              : colors.creditBackground,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  credit.isGiven
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: isOverdue ? colors.overdue : colors.credit,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  credit.direction.label,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: isOverdue ? colors.overdue : colors.credit,
                  ),
                ),
                if (isOverdue) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.overdue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'OVERDUE',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.overdue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (credit.isCleared) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.income.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CLEARED',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.income,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              CurrencyFormatter.format(credit.pendingAmount),
              style: context.textTheme.headlineMedium?.copyWith(
                color: isOverdue ? colors.overdue : colors.credit,
                fontWeight: FontWeight.bold,
                fontFamily: 'RobotoMono',
              ),
            ),
            Text(
              'pending of ${CurrencyFormatter.format(credit.totalAmount)}',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context, KashCubeColors colors) {
    final progress = credit.repaymentProgress;
    final percentage = (progress * 100).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Repayment Progress',
                  style: context.textTheme.labelLarge,
                ),
                Text(
                  '$percentage%',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: colors.income,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: context.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(colors.income),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid: ${CurrencyFormatter.format(credit.paidAmount)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.income,
                  ),
                ),
                Text(
                  'Remaining: ${CurrencyFormatter.format(credit.pendingAmount)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.credit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(
    BuildContext context,
    KashCubeColors colors,
    bool isOverdue,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _DetailRow(
              label: 'Customer',
              value: credit.customerName,
              icon: Icons.person_outline,
            ),
            if (credit.phoneNumber != null)
              _DetailRow(
                label: 'Phone',
                value: credit.phoneNumber!,
                icon: Icons.phone_outlined,
              ),
            _DetailRow(
              label: 'Credit Date',
              value: DateFormatter.formatFull(credit.creditDate),
              icon: Icons.calendar_today_outlined,
            ),
            if (credit.dueDate != null)
              _DetailRow(
                label: 'Due Date',
                value: DateFormatter.formatFull(credit.dueDate!),
                valueColor: isOverdue ? colors.overdue : null,
                icon: Icons.event_outlined,
                trailing: credit.daysUntilDue != null
                    ? Text(
                        credit.daysUntilDue! < 0
                            ? '${-credit.daysUntilDue!}d overdue'
                            : '${credit.daysUntilDue!}d left',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: isOverdue ? colors.overdue : colors.income,
                        ),
                      )
                    : null,
              ),
            if (credit.clearedDate != null)
              _DetailRow(
                label: 'Cleared Date',
                value: DateFormatter.formatFull(credit.clearedDate!),
                valueColor: colors.income,
                icon: Icons.check_circle_outline,
              ),
            if (credit.notes != null && credit.notes!.isNotEmpty)
              _DetailRow(
                label: 'Notes',
                value: credit.notes!,
                icon: Icons.notes_outlined,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistory(BuildContext context, KashCubeColors colors) {
    return paymentsAsync.when(
      data: (payments) {
        if (payments.isEmpty) {
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
                      'No payments recorded yet',
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

        return Column(
          children: payments.map((payment) {
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.income.withValues(alpha: 0.12),
                  radius: 18,
                  child: Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: colors.income,
                  ),
                ),
                title: Text(
                  CurrencyFormatter.format(payment.amount),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'RobotoMono',
                    color: colors.income,
                  ),
                ),
                subtitle: Text(
                  DateFormatter.formatDateTime(payment.paymentDate),
                  style: context.textTheme.bodySmall,
                ),
                trailing: payment.paymentMethod != null
                    ? Chip(
                        label: Text(
                          payment.paymentMethod!,
                          style: context.textTheme.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _editCredit(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditCreditScreen(credit: credit),
      ),
    );
    if (result == true) {
      ref.invalidate(creditByIdProvider(credit.id!));
      ref.invalidate(creditPaymentsProvider(credit.id!));
      ref.invalidate(pendingCreditsProvider);
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
    }
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(credit: credit),
      ),
    );
    if (result == true) {
      ref.invalidate(creditByIdProvider(credit.id!));
      ref.invalidate(creditPaymentsProvider(credit.id!));
      ref.invalidate(pendingCreditsProvider);
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
    }
  }

  Future<void> _deleteCredit(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Credit'),
        content: Text(
          'Delete credit of ${CurrencyFormatter.format(credit.totalAmount)} '
          'for ${credit.customerName}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(pendingCreditsProvider.notifier).deleteCredit(credit.id!);
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Detail row widget
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: valueColor,
                      ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
