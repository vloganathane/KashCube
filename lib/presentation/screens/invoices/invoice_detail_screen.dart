import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/invoice.dart';
import '../../providers/business_provider.dart';
import '../../providers/invoice_provider.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    return invoiceAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(), body: Center(child: Text('Error: $e'))),
      data: (invoice) {
        if (invoice == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Invoice not found')));
        }
        return _InvoiceDetailView(invoice: invoice);
      },
    );
  }
}

class _InvoiceDetailView extends ConsumerWidget {
  const _InvoiceDetailView({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessName =
        ref.watch(activeBusinessProvider)?.name ?? 'My Business';

    return Scaffold(
      appBar: AppBar(
        title: Text(invoice.invoiceNo),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => _shareInvoice(context, businessName),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HeaderCard(invoice: invoice),
          const SizedBox(height: AppSpacing.base),
          _LineItemsCard(invoice: invoice),
          const SizedBox(height: AppSpacing.base),
          _TotalsCard(invoice: invoice),
          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _NotesCard(notes: invoice.notes!),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
      bottomNavigationBar:
          invoice.status != InvoiceStatus.paid
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      AppSpacing.sm,
                      AppSpacing.base,
                      AppSpacing.xl),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record Payment'),
                    onPressed: () =>
                        _showPaymentDialog(context, ref),
                  ),
                )
              : null,
    );
  }

  Future<void> _showPaymentDialog(
      BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: invoice.balanceDue.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Balance Due: ${CurrencyFormatter.format(invoice.balanceDue)}'),
            const SizedBox(height: AppSpacing.base),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount Received (₹)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final amount = double.tryParse(controller.text);
      if (amount != null && amount > 0) {
        await ref
            .read(invoicesProvider.notifier)
            .recordPayment(invoice.id!, amount);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Payment of ${CurrencyFormatter.format(amount)} recorded')),
          );
          Navigator.pop(context);
        }
      }
    }
  }

  void _shareInvoice(BuildContext context, String businessName) {
    final due = invoice.dueDate != null ? DateFormatter.format(invoice.dueDate!) : '';
    final dueStr = due.isNotEmpty ? ' due $due.' : '.';
    final msg = 'Hi ${invoice.customerName}, '
        'invoice #${invoice.invoiceNo} for ${CurrencyFormatter.format(invoice.total)}'
        '$dueStr — $businessName';
    Share.share(msg, subject: 'Invoice ${invoice.invoiceNo}');
  }
}

// ── Header Card ───────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => const Color(0xFF2E7D32),
      InvoiceStatus.overdue => const Color(0xFFC62828),
      InvoiceStatus.sent => Theme.of(context).colorScheme.primary,
      InvoiceStatus.partiallyPaid => const Color(0xFFE65100),
      InvoiceStatus.draft => Theme.of(context).colorScheme.outline,
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
                    invoice.customerName,
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
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    invoice.status.label,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(label: 'Invoice #', value: invoice.invoiceNo),
            _InfoRow(
                label: 'Issued',
                value: DateFormatter.format(invoice.issueDate)),
            if (invoice.dueDate != null)
              _InfoRow(
                  label: 'Due',
                  value: DateFormatter.format(invoice.dueDate!)),
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
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Line Items ────────────────────────────────────────────────────────────────

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard({required this.invoice});
  final Invoice invoice;

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
            _ItemHeader(),
            ...invoice.items.map((item) => _ItemRow(item: item)),
          ],
        ),
      ),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
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
              child: Text('Total',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12))),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final InvoiceItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.itemName,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  if (item.description != null)
                    Text(item.description!,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              )),
          Expanded(
              child: Text(item.qty.toString(),
                  textAlign: TextAlign.center)),
          Expanded(
              flex: 2,
              child: Text(
                CurrencyFormatter.format(item.lineTotal),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              )),
        ],
      ),
    );
  }
}

// ── Totals Card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _TotalsRow(
                label: 'Subtotal',
                value: CurrencyFormatter.format(invoice.subtotal)),
            if (invoice.taxTotal > 0)
              _TotalsRow(
                  label: 'Tax',
                  value: CurrencyFormatter.format(invoice.taxTotal)),
            if (invoice.discountPct > 0)
              _TotalsRow(
                  label: 'Discount',
                  value: '-${invoice.discountPct.toStringAsFixed(1)}%'),
            const Divider(height: AppSpacing.base),
            _TotalsRow(
              label: 'Total',
              value: CurrencyFormatter.format(invoice.total),
              bold: true,
            ),
            if (invoice.paidAmount > 0)
              _TotalsRow(
                  label: 'Paid',
                  value: CurrencyFormatter.format(invoice.paidAmount),
                  valueColor: const Color(0xFF2E7D32)),
            if (invoice.balanceDue > 0)
              _TotalsRow(
                label: 'Balance Due',
                value: CurrencyFormatter.format(invoice.balanceDue),
                bold: true,
                valueColor: const Color(0xFFC62828),
              ),
          ],
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow(
      {required this.label,
      required this.value,
      this.bold = false,
      this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notes Card ────────────────────────────────────────────────────────────────

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
            Text('Notes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(notes),
          ],
        ),
      ),
    );
  }
}
