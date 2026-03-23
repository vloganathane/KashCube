import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/purchase_bill.dart';
import '../../../data/models/transaction.dart';
import '../../providers/bill_provider.dart';
import '../../providers/purchase_bill_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/payment_method_picker_bottom_sheet.dart';
import '../transactions/transaction_detail_screen.dart';
import 'add_purchase_bill_screen.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

class PurchaseBillDetailScreen extends ConsumerWidget {
  const PurchaseBillDetailScreen({super.key, required this.billId});
  final int billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billAsync = ref.watch(purchaseBillsProvider);
    return billAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(), body: Center(child: Text('Error: $e'))),
      data: (bills) {
        final bill =
            bills.where((b) => b.id == billId).firstOrNull;
        if (bill == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Bill not found')),
          );
        }
        return _DetailView(bill: bill);
      },
    );
  }
}

// ── Main view ────────────────────────────────────────────────────────────────

class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({required this.bill});
  final PurchaseBill bill;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  bool _paying = false;

  PurchaseBill get bill => widget.bill;

  // ── Payment sheet ─────────────────────────────────────────────────────────

  Future<void> _showPaymentDialog() async {
    final balanceDue = bill.balanceDue;
    if (balanceDue <= 0) return;
    if (!mounted) return;

    final result = await showPaymentMethodPicker(
      context: context,
      amount: balanceDue,
      title: 'Payment Sent',
      customerName: bill.vendorName,
      partyPrefix: 'to',
      defaultDate: DateTime.now(),
    );

    if (result == null || !mounted) return;

    final paymentMethod = result['method'] as PaymentMethod;
    final paidDate = result['date'] as DateTime;
    final amount = result['amount'] as double;
    if (amount <= 0) return;

    setState(() => _paying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(purchaseBillsProvider.notifier).recordPayment(
            billId: bill.id!,
            amount: amount,
            paidAt: paidDate,
          );

      final txn = Transaction(
        amount: amount,
        date: paidDate,
        type: TransactionType.expense,
        category: 'Purchase',
        paymentMethod: paymentMethod,
        partyName: bill.vendorName,
        partyId: bill.vendorPartyId,
        notes: 'Payment for bill ${bill.billNo}',
        referenceId: bill.billNo,
        businessId: bill.businessId,
        verified: true,
        createdAt: paidDate,
        updatedAt: paidDate,
      );
      final txnId =
          await ref.read(transactionsProvider.notifier).addTransaction(txn);

      // Auto-attach the vendor's scanned invoice to the payment transaction
      if (bill.attachmentPath != null) {
        await ref.read(billNotifierProvider(txnId).notifier).saveBill(
              sourcePath: bill.attachmentPath!,
              originalFileName: bill.attachmentPath!.split('/').last,
            );
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Paid ${CurrencyFormatter.format(amount)} via ${paymentMethod.label}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _deleteBill(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bill?'),
        content: Text(
            'Bill "${bill.billNo}" will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(purchaseBillsProvider.notifier).remove(bill.id!);
    navigator.pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(bill.billNo),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AddPurchaseBillScreen(billId: bill.id),
                ),
              );
              if (result == true && mounted) {
                ref.invalidate(purchaseBillsProvider);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'delete') _deleteBill(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline,
                      color: cs.error, size: 20),
                  const SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: cs.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: bill.status != PurchaseBillStatus.paid
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.sm,
                    AppSpacing.base,
                    AppSpacing.base),
                child: FilledButton.icon(
                  icon: _paying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payments_outlined),
                  label: Text(bill.paidAmount > 0
                      ? 'Record Payment (${CurrencyFormatter.format(bill.balanceDue)} remaining)'
                      : 'Mark as Paid'),
                  onPressed: _paying ? null : _showPaymentDialog,
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _BillHeaderCard(bill: bill),
          const SizedBox(height: AppSpacing.base),
          if (bill.items.isNotEmpty) ...[
            _LineItemsCard(bill: bill),
            const SizedBox(height: AppSpacing.base),
          ],
          _TotalsCard(bill: bill),
          const SizedBox(height: AppSpacing.base),
          _ItcCard(bill: bill),
          _LinkedTransactionsCard(billNo: bill.billNo),
          if (bill.notes != null && bill.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _NotesCard(notes: bill.notes!),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

// ── Header card ──────────────────────────────────────────────────────────────

class _BillHeaderCard extends StatelessWidget {
  const _BillHeaderCard({required this.bill});
  final PurchaseBill bill;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (bill.status) {
      PurchaseBillStatus.paid => const Color(0xFF2E7D32),
      PurchaseBillStatus.unpaid => Theme.of(context).colorScheme.error,
      PurchaseBillStatus.partiallyPaid => const Color(0xFFE65100),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bill.vendorName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    bill.status.label,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(label: 'Bill #', value: bill.billNo),
            _InfoRow(
                label: 'Date',
                value: DateFormatter.formatFull(bill.billDate)),
            if (bill.dueDate != null)
              _InfoRow(
                  label: 'Due',
                  value: DateFormatter.formatFull(bill.dueDate!)),
            if (bill.vendorGstin != null)
              _InfoRow(label: 'GSTIN', value: bill.vendorGstin!),
            if (bill.placeOfSupply != null)
              _InfoRow(
                  label: 'Place of Supply', value: bill.placeOfSupply!),
            if (bill.reverseCharge)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Chip(
                  label: const Text('Reverse Charge (RCM)'),
                  avatar: const Icon(Icons.swap_horiz, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 13)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Line items card ───────────────────────────────────────────────────────────

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard({required this.bill});
  final PurchaseBill bill;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: AppSpacing.base),
            // Header row
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text('Item',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12))),
                  Expanded(
                      child: Text('Qty',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('Amount',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12))),
                ],
              ),
            ),
            ...bill.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              Text(
                                [
                                  if (item.hsnCode != null &&
                                      item.hsnCode!.isNotEmpty)
                                    '${item.hsnOrSac}: ${item.hsnCode}',
                                  '${item.taxPct.toInt()}% GST',
                                  if (item.discountPct > 0)
                                    '${item.discountPct.toInt()}% disc',
                                ].join(' · '),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline),
                              ),
                            ],
                          )),
                      Expanded(
                          child: Text(
                              item.qty == item.qty.truncateToDouble()
                                  ? item.qty.toInt().toString()
                                  : item.qty.toStringAsFixed(2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13))),
                      Expanded(
                          flex: 2,
                          child: Text(
                            CurrencyFormatter.format(item.lineTotal),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          )),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ── Totals card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.bill});
  final PurchaseBill bill;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _TRow('Subtotal', CurrencyFormatter.format(bill.subtotal)),
            if (bill.cgstAmount > 0)
              _TRow('CGST', CurrencyFormatter.format(bill.cgstAmount)),
            if (bill.sgstAmount > 0)
              _TRow('SGST', CurrencyFormatter.format(bill.sgstAmount)),
            if (bill.igstAmount > 0)
              _TRow('IGST', CurrencyFormatter.format(bill.igstAmount)),
            if (bill.cessAmount > 0)
              _TRow('Cess', CurrencyFormatter.format(bill.cessAmount)),
            const Divider(height: AppSpacing.base),
            _TRow('Total', CurrencyFormatter.format(bill.total),
                bold: true),
            if (bill.paidAmount > 0)
              _TRow('Paid', CurrencyFormatter.format(bill.paidAmount),
                  valueColor: const Color(0xFF2E7D32)),
            if (bill.balanceDue > 0)
              _TRow(
                'Balance Due',
                CurrencyFormatter.format(bill.balanceDue),
                bold: true,
                valueColor: Theme.of(context).colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }
}

class _TRow extends StatelessWidget {
  const _TRow(this.label, this.value,
      {this.bold = false, this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                color: valueColor,
                fontFamily: 'RobotoMono',
              )),
        ],
      ),
    );
  }
}

// ── ITC card ──────────────────────────────────────────────────────────────────

class _ItcCard extends StatelessWidget {
  const _ItcCard({required this.bill});
  final PurchaseBill bill;

  @override
  Widget build(BuildContext context) {
    if (bill.itcEligibility == ItcEligibility.ineligible &&
        bill.itcTotal == 0) {
      return const SizedBox.shrink();
    }
    final itcColor = switch (bill.itcEligibility) {
      ItcEligibility.eligible => const Color(0xFF2E7D32),
      ItcEligibility.blocked => Theme.of(context).colorScheme.error,
      ItcEligibility.ineligible => Theme.of(context).colorScheme.outline,
    };
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: itcColor, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Input Tax Credit',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(bill.itcEligibility.label,
                          style: TextStyle(
                              color: itcColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
                if (bill.itcTotal > 0)
                  Text(
                    CurrencyFormatter.format(bill.itcTotal),
                    style: TextStyle(
                      color: itcColor,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                      fontSize: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
      ],
    );
  }
}

// ── Linked transactions card ──────────────────────────────────────────────────

class _LinkedTransactionsCard extends ConsumerWidget {
  const _LinkedTransactionsCard({required this.billNo});
  final String billNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(transactionsProvider).when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (all) {
            final linked = all
                .where((t) => t.referenceId == billNo)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));

            if (linked.isEmpty) return const SizedBox.shrink();

            return Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 20,
                                color:
                                    Theme.of(context).colorScheme.primary),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Payment History',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Chip(
                              label: Text('${linked.length}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ...linked.map((txn) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Theme.of(context)
                                    .colorScheme
                                    .tertiary,
                              ),
                              title: Text(
                                CurrencyFormatter.format(txn.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'RobotoMono',
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormatter.format(txn.date)} · ${txn.paymentMethod.label}',
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailScreen(
                                      transactionId: txn.id!),
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
              ],
            );
          },
        );
  }
}

// ── Notes card ────────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Notes',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(notes,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
