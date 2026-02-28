import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/business.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../../data/services/payment_preferences_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/payment_method_picker_bottom_sheet.dart';
import '../bookings/booking_detail_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import 'quote_builder_screen.dart';

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
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Preview PDF',
            onPressed: () => _previewInvoice(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => _shareInvoice(context, businessName, ref),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editInvoice(context);
                case 'void':
                  _voidInvoice(context, ref);
                case 'duplicate':
                  _duplicateInvoice(context, ref);
              }
            },
            itemBuilder: (context) => [
              if (invoice.status == InvoiceStatus.draft)
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 12),
                      Text('Edit'),
                    ],
                  ),
                ),
              if (invoice.status == InvoiceStatus.sent ||
                  invoice.status == InvoiceStatus.overdue)
                const PopupMenuItem(
                  value: 'void',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined),
                      SizedBox(width: 12),
                      Text('Void Invoice'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'duplicate',
                child: Row(
                  children: [
                    Icon(Icons.content_copy_outlined),
                    SizedBox(width: 12),
                    Text('Duplicate'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HeaderCard(invoice: invoice),
          // Lock indicator for paid/partially paid invoices
          if (invoice.status == InvoiceStatus.paid ||
              invoice.status == InvoiceStatus.partiallyPaid) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outlined,
                    color: const Color(0xFF2E7D32),
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'This invoice is ${invoice.status == InvoiceStatus.paid ? 'paid' : 'partially paid'} and locked from editing to protect transaction integrity.',
                      style: TextStyle(
                        color: const Color(0xFF1B5E20),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.base),
          _LineItemsCard(invoice: invoice),
          const SizedBox(height: AppSpacing.base),
          _TotalsCard(invoice: invoice),
          if (invoice.status == InvoiceStatus.paid ||
              invoice.status == InvoiceStatus.partiallyPaid) ...[
            const SizedBox(height: AppSpacing.base),
            _PaymentHistoryCard(invoiceId: invoice.id!),
          ],
          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _NotesCard(notes: invoice.notes!),
          ],
          if (invoice.id != null) ...[
            const SizedBox(height: AppSpacing.base),
            _LinkedBookingCard(invoiceId: invoice.id!),
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
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(invoice.status == InvoiceStatus.partiallyPaid
                        ? 'Record Payment (${CurrencyFormatter.format(invoice.balanceDue)} remaining)'
                        : 'Mark as Paid'),
                    onPressed: () => _markAsPaid(context, ref),
                  ),
                )
              : null,
    );
  }

  Future<void> _markAsPaid(BuildContext context, WidgetRef ref) async {
    // Load last used payment method for this customer
    final lastUsedMethod = await PaymentPreferencesService.getLastUsedMethod(
      invoice.customerPartyId,
    );

    // Show payment method picker
    if (!context.mounted) return;
    final result = await showPaymentMethodPicker(
      context: context,
      amount: invoice.balanceDue,
      customerName: invoice.customerName,
      lastUsedMethod: lastUsedMethod,
      defaultDate: DateTime.now(),
    );

    if (result == null) return; // User cancelled

    final paymentMethod = result['method'] as PaymentMethod;
    final paidDate = result['date'] as DateTime;
    final amount = result['amount'] as double;

    // Show loading
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Call markAsPaid - this auto-creates transaction
      final transactionId = await ref.read(invoicesProvider.notifier).markAsPaid(
            invoice: invoice,
            paymentMethod: paymentMethod,
            paidDate: paidDate,
            partialAmount: amount,
          );

      // Invalidate providers to force reload with updated data
      ref.invalidate(invoiceByIdProvider(invoice.id!));
      ref.invalidate(transactionsProvider);

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading

      // Save payment method preference for this customer
      await PaymentPreferencesService.saveLastUsedMethod(
        invoice.customerPartyId,
        paymentMethod,
      );

      // Show success message
      if (!context.mounted) return;
      // Capture both before the pop - NavigatorState remains valid after pop
      // because the shell Navigator outlives any individual route.
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      // Pop first so the parent screen is visible when the snackbar appears
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Payment recorded: ${CurrencyFormatter.format(amount)} via ${paymentMethod.label}',
          ),
          action: SnackBarAction(
            label: 'View Transaction',
            onPressed: () {
              if (nav.canPop() || true) {
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => TransactionDetailScreen(transactionId: transactionId),
                  ),
                );
              }
            },
          ),
        ),
      );

    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recording payment: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _previewInvoice(BuildContext context, WidgetRef ref) async {
    // Show loading indicator
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (invoice.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(invoice.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (invoice.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(invoice.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        invoice,
        business: business,
        customerParty: customerParty,
      );
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Open PDF in system viewer
      final result = await OpenFile.open(pdfFile.path);
      
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _shareInvoice(BuildContext context, String businessName, WidgetRef ref) async {
    // Show loading indicator
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (invoice.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(invoice.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (invoice.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(invoice.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        invoice,
        business: business,
        customerParty: customerParty,
      );
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show share options bottom sheet
      await showModalBottomSheet(
         context: context,
        builder: (ctx) => _ShareOptionsSheet(
          invoice: invoice,
          businessName: businessName,
          pdfFile: pdfFile,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  void _editInvoice(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuoteBuilderScreen(
          invoiceId: invoice.id!,
          docType: DocumentType.invoice,
        ),
      ),
    ).then((_) {
      if (context.mounted) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _voidInvoice(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Invoice?'),
        content: Text(
          'This will void invoice ${invoice.invoiceNo}. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Void'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(invoicesProvider.notifier).remove(invoice.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice ${invoice.invoiceNo} voided')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _duplicateInvoice(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    
    final now = DateTime.now();
    final newInvoice = invoice.copyWith(
      id: null,
      invoiceNo: '', // Will be auto-generated
      status: InvoiceStatus.draft,
      issueDate: now,
      dueDate: now.add(const Duration(days: 30)),
      paidAmount: 0,
      createdAt: now,
      updatedAt: now,
    );

    final newId = await ref.read(invoicesProvider.notifier).add(newInvoice, invoice.items);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice duplicated as draft')),
      );
      // Navigate to the new draft invoice for editing
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuoteBuilderScreen(
            invoiceId: newId,
            docType: DocumentType.invoice,
          ),
        ),
      );
    }
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
                    color: statusColor.withValues(alpha: 0.12),
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

// ── Linked Booking Card ───────────────────────────────────────────────────────

class _LinkedBookingCard extends ConsumerWidget {
  const _LinkedBookingCard({required this.invoiceId});
  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingByInvoiceIdProvider(invoiceId));
    if (booking == null) return const SizedBox.shrink();

    final statusColor = switch (booking.status) {
      BookingStatus.confirmed => Colors.green,
      BookingStatus.pending => Colors.orange,
      BookingStatus.completed => Theme.of(context).colorScheme.primary,
      BookingStatus.cancelled => Theme.of(context).colorScheme.outline,
      BookingStatus.noShow => Theme.of(context).colorScheme.error,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookingDetailScreen(bookingId: booking.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Linked Booking',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.bookingRef ?? 'Booking'} · ${booking.serviceName}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  booking.status.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share Options Sheet ───────────────────────────────────────────────────────

class _ShareOptionsSheet extends StatelessWidget {
  const _ShareOptionsSheet({
    required this.invoice,
    required this.businessName,
    required this.pdfFile,
  });

  final Invoice invoice;
  final String businessName;
  final dynamic pdfFile; // File

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share Invoice',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            
            // Share PDF via system share sheet
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share PDF'),
              subtitle: const Text('Share via any app'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles(
                  [XFile(pdfFile.path)],
                  subject: 'Invoice ${invoice.invoiceNo}',
                  text: _generateMessage(),
                );
              },
            ),
            
            const Divider(),
            
            // WhatsApp - Share PDF + message
            ListTile(
              leading: const Icon(Icons.chat_outlined, color: Colors.green),
              title: const Text('WhatsApp'),
              subtitle: const Text('Send PDF via WhatsApp'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles(
                  [XFile(pdfFile.path)],
                  subject: 'Invoice ${invoice.invoiceNo}',
                  text: _generateMessage(),
                  sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
                );
              },
            ),
            
            // SMS - Share PDF + message
            ListTile(
              leading: const Icon(Icons.sms_outlined, color: Colors.blue),
              title: const Text('SMS'),
              subtitle: const Text('Send PDF via text message'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles(
                  [XFile(pdfFile.path)],
                  subject: 'Invoice ${invoice.invoiceNo}',
                  text: _generateMessage(),
                  sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
                );
              },
            ),
            
            // Email - Share PDF + message
            ListTile(
              leading: const Icon(Icons.email_outlined, color: Colors.orange),
              title: const Text('Email'),
              subtitle: const Text('Send PDF via email'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles(
                  [XFile(pdfFile.path)],
                  subject: 'Invoice ${invoice.invoiceNo}',
                  text: _generateMessage(),
                  sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
                );
              },
            ),
            
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  String _generateMessage() {
    final due = invoice.dueDate != null 
        ? DateFormatter.format(invoice.dueDate!) 
        : '';
    final dueStr = due.isNotEmpty ? ' due $due' : '';
    return 'Hi ${invoice.customerName},\n\n'
        'Invoice #${invoice.invoiceNo} for ${CurrencyFormatter.format(invoice.total)}'
        '$dueStr.\n\n'
        'Thank you for your business!\n'
        '— $businessName';
  }
}
// ── Payment History ───────────────────────────────────────────────────────────

class _PaymentHistoryCard extends ConsumerWidget {
  const _PaymentHistoryCard({required this.invoiceId});
  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return transactionsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (allTransactions) {
        // Filter transactions linked to this invoice
        final linkedTransactions = allTransactions
            .where((t) => t.linkedInvoiceId == invoiceId)
            .toList();

        if (linkedTransactions.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.payment_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Payment History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${linkedTransactions.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ...linkedTransactions.map((txn) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Theme.of(context).colorScheme.tertiary,
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
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TransactionDetailScreen(
                              transactionId: txn.id!,
                            ),
                          ),
                        );
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}