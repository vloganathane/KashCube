import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/lifecycle_classifier.dart';
import '../../../data/models/business.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/ewb_transport_details.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../widgets/lifecycle_tag.dart';
import '../../../data/models/quote.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/eway_bill_service.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../../data/services/payment_preferences_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../../data/models/reminder_item.dart';
import '../../widgets/payment_method_picker_bottom_sheet.dart';
import '../../widgets/reminder_bottom_sheet.dart';
import '../bookings/booking_detail_screen.dart';
import '../../../data/models/delivery_challan.dart';
import '../../providers/delivery_challan_provider.dart';
import 'delivery_challan_detail_screen.dart';

import '../transactions/transaction_detail_screen.dart';
import 'ewb_preview_screen.dart';
import 'quote_builder_screen.dart';
import 'quote_detail_screen.dart';

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
          // Send Reminder — only for unpaid / overdue invoices
          if (invoice.status == InvoiceStatus.sent ||
              invoice.status == InvoiceStatus.overdue ||
              invoice.status == InvoiceStatus.partiallyPaid)
            IconButton(
              icon: const Icon(Icons.send_outlined),
              tooltip: 'Send Reminder',
              onPressed: () => _showReminderSheet(context, ref, businessName),
            ),
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
                case 'eway_bill':
                  _showEwayBillSheet(context, invoice, ref);
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
              const PopupMenuItem(
                value: 'eway_bill',
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined),
                    SizedBox(width: 12),
                    Text('e-Way Bill'),
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
          // EWB status badge
          if (invoice.hasEwb) ...[
            const SizedBox(height: AppSpacing.sm),
            _EwbStatusBadge(invoice: invoice),
          ],
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
          if (invoice.quoteId != null) ...[
            const SizedBox(height: AppSpacing.base),
            _LinkedQuoteCard(quoteId: invoice.quoteId!),
          ],
          if (invoice.id != null) ...[
            const SizedBox(height: AppSpacing.base),
            _LinkedBookingCard(invoiceId: invoice.id!),
          ],
          if (invoice.id != null) ...[
            const SizedBox(height: AppSpacing.base),
            _LinkedChallanCard(invoiceId: invoice.id!),
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

      // Read default invoice terms from settings
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.invoiceTerms);
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        invoice,
        business: business,
        customerParty: customerParty,
        termsAndConditions: terms ?? SettingsKeys.defaultInvoiceTerms,
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

      // Read default invoice terms from settings
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.invoiceTerms);
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        invoice,
        business: business,
        customerParty: customerParty,
        termsAndConditions: terms ?? SettingsKeys.defaultInvoiceTerms,
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
          onSent: () => ref.read(invoicesProvider.notifier).markSent(invoice.id!),
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

  void _showReminderSheet(
      BuildContext context, WidgetRef ref, String businessName) {
    // Try to look up party contact details for pre-filling the reminder
    final parties = ref.read(partyRepositoryProvider);
    Future<void> open() async {
      String? phone;
      String? email;
      if (invoice.customerPartyId != null) {
        final party = await parties.getById(invoice.customerPartyId!);
        phone = party?.phoneNumber;
        email = party?.email;
      }
      if (!context.mounted) return;

      final item = ReminderItem.fromInvoice(
        invoice,
        partyPhone: phone,
        partyEmail: email,
      );

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReminderBottomSheet(
          item: item,
          onReminderSent: () {
            ref
                .read(invoicesProvider.notifier)
                .markReminderSent(invoice.id!);
          },
        ),
      );
    }

    open();
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

  void _showEwayBillSheet(
    BuildContext context,
    Invoice invoice,
    WidgetRef ref,
  ) {
    final business = ref.read(activeBusinessProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EwayBillSheet(
        invoice: invoice,
        business: business,
        onExported: (_) => ref.read(invoicesProvider.notifier).load(),
      ),
    );
  }
}

// ── e-Way Bill Sheet ──────────────────────────────────────────────────────────

class _EwayBillSheet extends StatefulWidget {
  const _EwayBillSheet({
    required this.invoice,
    this.business,
    this.onExported,
  });

  final Invoice invoice;
  final Business? business;
  /// Called with the updated [Invoice] (EWB fields filled) after a successful
  /// export. The caller should use this to refresh the provider.
  final void Function(Invoice updatedInvoice)? onExported;

  @override
  State<_EwayBillSheet> createState() => _EwayBillSheetState();
}

class _EwayBillSheetState extends State<_EwayBillSheet> {
  final _formKey = GlobalKey<FormState>();

  String _mode = '1'; // Road default
  final _vehicleCtrl = TextEditingController();
  final _transporterNameCtrl = TextEditingController();
  final _transporterGstinCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _docNoCtrl = TextEditingController();
  final _docDateCtrl = TextEditingController();

  List<Map<String, dynamic>> _frequentTransporters = [];
  bool _exporting = false;

  static const _modes = [
    ('1', 'Road'),
    ('2', 'Rail'),
    ('3', 'Air'),
    ('4', 'Ship'),
  ];

  static const _vehicleRegex =
      r'^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$';

  @override
  void initState() {
    super.initState();
    // Pre-fill from invoice if EWB was previously generated.
    if (widget.invoice.transportMode != null) {
      _mode = widget.invoice.transportMode!;
    }
    if (widget.invoice.vehicleNo != null) {
      _vehicleCtrl.text = widget.invoice.vehicleNo!;
    }
    if (widget.invoice.transporterName != null) {
      _transporterNameCtrl.text = widget.invoice.transporterName!;
    }
    if (widget.invoice.transporterGstin != null) {
      _transporterGstinCtrl.text = widget.invoice.transporterGstin!;
    }
    if (widget.invoice.distanceKm != null) {
      _distanceCtrl.text = widget.invoice.distanceKm.toString();
    }
    _loadFrequentTransporters();
  }

  Future<void> _loadFrequentTransporters() async {
    final db = DatabaseHelper.instance;
    final rows = await db.getTransporters();
    if (mounted) setState(() => _frequentTransporters = rows);
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _transporterNameCtrl.dispose();
    _transporterGstinCtrl.dispose();
    _distanceCtrl.dispose();
    _docNoCtrl.dispose();
    _docDateCtrl.dispose();
    super.dispose();
  }

  int? get _validityDays {
    final km = int.tryParse(_distanceCtrl.text.trim());
    if (km == null || km <= 0) return null;
    return km < 100 ? 1 : (km / 100).floor();
  }

  Future<void> _export() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _exporting = true);

    final transport = EwbTransportDetails(
      mode: _mode,
      vehicleNo: _vehicleCtrl.text.trim().isEmpty ? null : _vehicleCtrl.text.trim(),
      transporterName: _transporterNameCtrl.text.trim().isEmpty
          ? null
          : _transporterNameCtrl.text.trim(),
      transporterGstin: _transporterGstinCtrl.text.trim().isEmpty
          ? null
          : _transporterGstinCtrl.text.trim(),
      distanceKm: int.tryParse(_distanceCtrl.text.trim()),
      transDocNo: _docNoCtrl.text.trim().isEmpty ? null : _docNoCtrl.text.trim(),
      transDocDate:
          _docDateCtrl.text.trim().isEmpty ? null : _docDateCtrl.text.trim(),
    );

    try {
      final result = await EwayBillService.instance.buildJsonFile(
        widget.invoice,
        business: widget.business,
        transport: transport,
      );

      // ── Write EWB fields back to the invoice ─────────────────────────────
      if (widget.invoice.id != null) {
        await DatabaseHelper.instance.updateEwbFields(
          widget.invoice.id!,
          ewbGeneratedAt: result.generatedAt,
          ewbValidUntil: result.validUntil,
          vehicleNo: transport.vehicleNo,
          transporterName: transport.transporterName,
          transporterGstin: transport.transporterGstin,
          transportMode: transport.mode,
          distanceKm: transport.distanceKm,
        );
        final updated = widget.invoice.copyWith(
          ewbGeneratedAt: result.generatedAt,
          ewbValidUntil: result.validUntil,
          vehicleNo: transport.vehicleNo,
          transporterName: transport.transporterName,
          transporterGstin: transport.transporterGstin,
          transportMode: transport.mode,
          distanceKm: transport.distanceKm,
        );
        widget.onExported?.call(updated);
      }

      // Persist frequent transporter if name was provided.
      if (transport.transporterName != null) {
        await DatabaseHelper.instance.saveTransporter(
          name: transport.transporterName!,
          gstin: transport.transporterGstin,
        );
      }

      if (mounted) {
        // Close the sheet then push the preview screen.
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EwbPreviewScreen(
              result: result,
              docNo: widget.invoice.invoiceNo,
              transport: transport,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBelowThreshold =
        EwayBillService.instance.isBelowThreshold(widget.invoice);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // ── handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'e-Way Bill',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Invoice ${widget.invoice.invoiceNo}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── threshold warning
            if (isBelowThreshold) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: theme.colorScheme.secondary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Invoice total is below ₹50,000. EWB is optional for this consignment.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── existing EWB badge
            if (widget.invoice.hasEwb) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'EWB already generated: ${widget.invoice.ewbNo ?? ''}'
                        '${widget.invoice.ewbValidUntil != null ? '\nValid until ${DateFormatter.format(widget.invoice.ewbValidUntil!)}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── transport mode selector
            Text('Transport Mode', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<String>(
              segments: [
                for (final (code, label) in _modes)
                  ButtonSegment(value: code, label: Text(label)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── vehicle number
            if (_mode == '1' || _mode == '4') ...[
              TextFormField(
                controller: _vehicleCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Number',
                  hintText: 'MH12AB1234',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return null; // optional
                  if (!RegExp(_vehicleRegex).hasMatch(val)) {
                    return 'Format: MH12AB1234 (state + RTO + alpha + serial)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── transporter name (with autocomplete)
            Autocomplete<String>(
              optionsBuilder: (v) {
                if (v.text.isEmpty) return const [];
                return _frequentTransporters
                    .map((r) => r['name'] as String)
                    .where((n) =>
                        n.toLowerCase().contains(v.text.toLowerCase()));
              },
              onSelected: (name) {
                _transporterNameCtrl.text = name;
                final match = _frequentTransporters
                    .firstWhere((r) => r['name'] == name,
                        orElse: () => {});
                if (match['gstin'] != null) {
                  _transporterGstinCtrl.text = match['gstin'] as String;
                }
              },
              fieldViewBuilder:
                  (context, ctrl, focusNode, onEditingComplete) {
                // Keep our controller in sync.
                ctrl.text = _transporterNameCtrl.text;
                ctrl.addListener(() => _transporterNameCtrl.text = ctrl.text);
                return TextFormField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Transporter Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // ── transporter GSTIN
            TextFormField(
              controller: _transporterGstinCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Transporter GSTIN (optional)',
                hintText: '22AAAAA0000A1Z5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── distance + live validity preview
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Distance (km)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return null;
                      if (int.tryParse(val) == null) return 'Enter a number';
                      if (int.parse(val) <= 0) return 'Must be > 0';
                      return null;
                    },
                  ),
                ),
                if (_validityDays != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: Text(
                      'Valid $_validityDays day${_validityDays == 1 ? '' : 's'}',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── export button
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Export JSON'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── EWB Status Badge ─────────────────────────────────────────────────────────

class _EwbStatusBadge extends StatelessWidget {
  const _EwbStatusBadge({required this.invoice});
  final Invoice invoice;

  static const _portalUrl = 'https://ewaybillgst.gov.in';

  String _fmt(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _openPortal(BuildContext context) async {
    final uri = Uri.parse(_portalUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isValid = invoice.ewbIsValid ?? false;
    final validUntil = invoice.ewbValidUntil;

    return InkWell(
      onTap: () => _openPortal(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isValid
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isValid ? Icons.local_shipping_outlined : Icons.warning_amber_rounded,
              size: 18,
              color: isValid
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isValid ? 'e-Way Bill Generated' : 'e-Way Bill Expired',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isValid
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  if (validUntil != null)
                    Text(
                      isValid
                          ? 'Valid until ${_fmt(validUntil)}'
                          : 'Expired on ${_fmt(validUntil)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isValid
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: isValid
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
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
            const SizedBox(height: AppSpacing.xs),
            // Lifecycle stage tag — LC4
            LifecycleTag(
              info: LifecycleClassifier.forInvoice(
                invoice,
                lastReminderAt: invoice.reminderSentAt,
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

// ── Linked Quote Card ───────────────────────────────────────────────────────

class _LinkedQuoteCard extends ConsumerWidget {
  const _LinkedQuoteCard({required this.quoteId});
  final int quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(quoteFromListByIdProvider(quoteId));
    if (quote == null) return const SizedBox.shrink();

    final statusColor = switch (quote.status) {
      QuoteStatus.draft => Theme.of(context).colorScheme.outline,
      QuoteStatus.sent => Colors.blue,
      QuoteStatus.accepted => Theme.of(context).colorScheme.primary,
      QuoteStatus.rejected => Theme.of(context).colorScheme.error,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuoteDetailScreen(quoteId: quote.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source Quote',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quote.quoteNo,
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
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  quote.status.label,
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

// ── Linked Challan Card ───────────────────────────────────────────────────────

class _LinkedChallanCard extends ConsumerWidget {
  const _LinkedChallanCard({required this.invoiceId});
  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challan = ref.watch(challanByInvoiceIdProvider(invoiceId));
    if (challan == null) return const SizedBox.shrink();

    final statusColor = switch (challan.status) {
      ChallanStatus.draft => Theme.of(context).colorScheme.outline,
      ChallanStatus.dispatched => Colors.blue,
      ChallanStatus.returned => Theme.of(context).colorScheme.primary,
      ChallanStatus.converted => Theme.of(context).colorScheme.primary,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeliveryChallanDetailScreen(challanId: challan.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source Delivery Challan',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      challan.challanNo,
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
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  challan.status.label,
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
    required this.onSent,
  });

  final Invoice invoice;
  final String businessName;
  final dynamic pdfFile; // File
  /// Called after the share sheet is opened to mark the invoice as sent.
  final Future<void> Function() onSent;

  @override
  Widget build(BuildContext context) {
    final message = _generateMessage();
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.send_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Share Invoice',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Message preview ─────────────────────────────────────────────
            Text(
              'Message preview',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // ── Copy message button ──────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy message'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Helper text ─────────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'The PDF and message will be shared together. '
                    'Pick WhatsApp, Email, SMS and more from the share sheet.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Primary action ───────────────────────────────────────────────
            FilledButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send PDF + Message'),
              onPressed: () async {
                Navigator.pop(context);
                await Share.shareXFiles(
                  [XFile(pdfFile.path)],
                  subject: 'Invoice ${invoice.invoiceNo}',
                  text: message,
                );
                // Mark as sent after the share sheet is opened successfully.
                await onSent();
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── Cancel ──────────────────────────────────────────────────────
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