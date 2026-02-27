import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/transaction.dart';
import '../../providers/bill_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/bill_picker.dart';
import '../invoices/invoice_detail_screen.dart';
import 'add_edit_transaction_screen.dart';
import 'bill_viewer_screen.dart';

/// Displays full details of a single transaction.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
  });

  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return transactionsAsync.when(
      data: (transactions) {
        final txn = transactions.where((t) => t.id == transactionId).firstOrNull;
        if (txn == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Transaction')),
            body: const Center(child: Text('Transaction not found')),
          );
        }
        return _TransactionDetailContent(transaction: txn);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _TransactionDetailContent extends ConsumerWidget {
  const _TransactionDetailContent({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final isIncome = transaction.isIncome;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '-';
    final bgColor = isIncome ? colors.incomeBackground : colors.expenseBackground;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Amount Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xxl,
              horizontal: AppSpacing.base,
            ),
            color: bgColor,
            child: Column(
              children: [
                Text(
                  '$prefix${CurrencyFormatter.format(transaction.amount, showDecimals: true)}',
                  style: context.textTheme.displaySmall?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'RobotoMono',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Chip(
                  label: Text(transaction.type.label),
                  avatar: Icon(
                    isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 16,
                    color: amountColor,
                  ),
                  side: BorderSide(color: amountColor.withValues(alpha: 0.3)),
                ),
              ],
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  value: transaction.category,
                ),
                if (transaction.partyName != null)
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Party',
                    value: transaction.partyName!,
                  ),
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: DateFormatter.formatFull(transaction.date),
                ),
                _DetailRow(
                  icon: Icons.access_time_outlined,
                  label: 'Time',
                  value: DateFormatter.formatTime(transaction.date),
                ),
                _DetailRow(
                  icon: Icons.payment_outlined,
                  label: 'Payment Method',
                  value: transaction.paymentMethod.label,
                ),
                _DetailRow(
                  icon: Icons.work_outline,
                  label: 'Mode',
                  value: transaction.mode.label,
                ),
                if (transaction.upiApp != null)
                  _DetailRow(
                    icon: Icons.phone_android,
                    label: 'UPI App',
                    value: transaction.upiApp!,
                  ),
                if (transaction.upiRefNo != null)
                  _DetailRow(
                    icon: Icons.tag,
                    label: 'UPI Ref',
                    value: transaction.upiRefNo!,
                  ),
                if (transaction.referenceId != null && transaction.referenceId != transaction.upiRefNo)
                  _DetailRow(
                    icon: Icons.confirmation_number_outlined,
                    label: 'Reference',
                    value: transaction.referenceId!,
                  ),
                if (transaction.notes != null && transaction.notes!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.note_outlined,
                    label: 'Notes',
                    value: transaction.notes!,
                  ),
                if (transaction.tags != null && transaction.tags!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.label_outline,
                    label: 'Tags',
                    value: transaction.tags!.join(', '),
                  ),

                // Linked Records (Invoice/Booking)
                if (transaction.linkedInvoiceId != null ||
                    transaction.linkedBookingId != null) ...[
                  const Divider(height: AppSpacing.xxl),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Linked Records',
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (transaction.linkedInvoiceId != null)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: Icon(
                          Icons.receipt_long_outlined,
                          color: context.colorScheme.primary,
                        ),
                        title: const Text('Invoice Payment'),
                        subtitle: Text('Invoice ID: ${transaction.linkedInvoiceId}'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InvoiceDetailScreen(
                                invoiceId: transaction.linkedInvoiceId!,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (transaction.linkedBookingId != null)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.event_available_outlined,
                          color: context.colorScheme.secondary,
                        ),
                        title: const Text('Booking Payment'),
                        subtitle: Text('Booking ID: ${transaction.linkedBookingId}'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // TODO: Navigate to booking detail screen when implemented
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Booking detail screen coming soon'),
                            ),
                          );
                        },
                      ),
                    ),
                ],

                // Auto-detected badge
                if (transaction.autoDetected) ...[
                  const Divider(height: AppSpacing.xxl),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: AppSpacing.iconMd,
                        color: context.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Auto-detected from SMS',
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (transaction.verified)
                        Chip(
                          label: const Text('Verified'),
                          avatar: const Icon(Icons.check_circle, size: 16),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],

                // Bill Attachment
                if (transaction.id != null) ...[
                  const Divider(height: AppSpacing.xxl),
                  _BillSection(transactionId: transaction.id!),
                ],

                // SMS Body (if auto-detected)
                if (transaction.smsBody != null) ...[
                  const Divider(height: AppSpacing.xxl),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Original SMS',
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      transaction.smsBody!,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ),
                ],

                // Metadata
                const SizedBox(height: AppSpacing.xxl),
                if (transaction.createdAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Created ${DateFormatter.formatDateTime(transaction.createdAt!)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.outline,
                      ),
                    ),
                  ),
                if (transaction.updatedAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Updated ${DateFormatter.formatDateTime(transaction.updatedAt!)}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditTransactionScreen(transaction: transaction),
      ),
    );
    if (result == true && context.mounted) {
      // Pop back since data refreshes automatically via Riverpod
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // Check if transaction is linked to invoice or booking
    final bool isLinked = transaction.linkedInvoiceId != null ||
        transaction.linkedBookingId != null;

    String title = 'Delete Transaction';
    String content = 'Are you sure you want to delete this transaction? '
        'This action cannot be undone.';

    if (isLinked) {
      title = 'Delete Linked Transaction';
      final linkedTo = <String>[];
      if (transaction.linkedInvoiceId != null) {
        linkedTo.add('an invoice');
      }
      if (transaction.linkedBookingId != null) {
        linkedTo.add('a booking');
      }
      content = 'This transaction is linked to ${linkedTo.join(' and ')}. '
          'Deleting it will affect payment records and may cause data inconsistencies.\\n\\n'
          'Are you sure you want to proceed?';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(transactionsProvider.notifier)
          .deleteTransaction(transaction.id!);
      ref.read(dashboardSummaryProvider.notifier).loadSummary();
      ref.read(recentTransactionsProvider.notifier).loadRecent();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// A single detail row with icon, label, and value.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: AppSpacing.iconMd,
            color: context.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: context.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the bill attachment for a transaction.
class _BillSection extends ConsumerWidget {
  const _BillSection({required this.transactionId});

  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billAsync = ref.watch(billForTransactionProvider(transactionId));

    return billAsync.when(
      data: (bill) {
        if (bill == null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No bill attached',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.outline,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bill / Receipt',
              style: context.textTheme.labelLarge?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            BillPreviewCard(
              filePath: bill.filePath,
              fileName: bill.fileName,
              isPdf: bill.isPdf,
              fileSize: bill.fileSize,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BillViewerScreen(
                      filePath: bill.filePath,
                      fileName: bill.fileName,
                      isPdf: bill.isPdf,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
