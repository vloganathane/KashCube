import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/business.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/models/party.dart';
import '../../../data/models/quote.dart';
import '../../../data/services/invoice_number_service.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../widgets/party_picker_field.dart';
import 'item_catalog_screen.dart';

enum DocumentType { quote, invoice }

class QuoteBuilderScreen extends ConsumerStatefulWidget {
  const QuoteBuilderScreen({
    super.key,
    this.quoteId,
    this.invoiceId,
    this.docType = DocumentType.quote,
  });
  final int? quoteId;
  final int? invoiceId;
  final DocumentType docType;

  @override
  ConsumerState<QuoteBuilderScreen> createState() =>
      _QuoteBuilderScreenState();
}

class _QuoteBuilderScreenState extends ConsumerState<QuoteBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  String _customerName = '';
  int? _customerPartyId;
  int? _selectedBusinessId;
  // Quote fields
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  // Invoice fields
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;

  final List<_LineItem> _items = [];
  final _notesController = TextEditingController();
  late final TextEditingController _customerCtrl;
  late final TextEditingController _documentNoCtrl;

  Quote? _existingQuote;
  Invoice? _existingInvoice;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController();
    _documentNoCtrl = TextEditingController();
    if (widget.docType == DocumentType.invoice) {
      if (widget.invoiceId != null) {
        _loadInvoice();
      } else {
        _dueDate = DateTime.now().add(const Duration(days: 30));
        _items.add(const _LineItem());
        _initDocumentNumber();
      }
    } else {
      if (widget.quoteId != null) {
        _loadQuote();
      } else {
        _items.add(const _LineItem());
        _initDocumentNumber();
      }
    }
  }

  Future<void> _initDocumentNumber() async {
    final number = widget.docType == DocumentType.invoice
        ? await InvoiceNumberService.instance.nextInvoiceNo()
        : await InvoiceNumberService.instance.nextQuoteNo();
    if (mounted) {
      _documentNoCtrl.text = number;
    }
  }

  Future<void> _loadQuote() async {
    final quote =
        await ref.read(quoteRepositoryProvider).getById(widget.quoteId!);
    if (quote == null) return;
    if (!mounted) return;
    setState(() {
      _existingQuote = quote;
      _customerName = quote.customerName;
      _customerCtrl.text = quote.customerName;
      _documentNoCtrl.text = quote.quoteNo;
      _customerPartyId = quote.customerPartyId;
      _selectedBusinessId = quote.businessId;
      _validUntil = quote.validUntil ??
          DateTime.now().add(const Duration(days: 30));
      _notesController.text = quote.notes ?? '';
      _items.clear();
      _items.addAll(quote.items.map(
        (qi) => _LineItem(
          itemName: qi.itemName,
          description: qi.description ?? '',
          qty: qi.qty,
          unitPrice: qi.unitPrice,
          taxPct: qi.taxPct,
          discountPct: qi.discountPct,
          hsnCode: qi.hsnCode,
          unit: qi.unit,
          hsnOrSac: qi.hsnOrSac,
        ),
      ));
    });
  }

  Future<void> _loadInvoice() async {
    final invoice =
        await ref.read(invoiceRepositoryProvider).getById(widget.invoiceId!);
    if (invoice == null) return;
    if (!mounted) return;
    
    // Prevent editing paid or partially paid invoices
    if (invoice.status == InvoiceStatus.paid ||
        invoice.status == InvoiceStatus.partiallyPaid) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Edit Invoice'),
          content: Text(
            'Invoice ${invoice.invoiceNo} is ${invoice.status == InvoiceStatus.paid ? 'paid' : 'partially paid'} '
            'and cannot be edited. This protects the integrity of linked transactions.\n\n'
            'To make changes, you can duplicate this invoice instead.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    
    setState(() {
      _existingInvoice = invoice;
      _customerName = invoice.customerName;
      _customerCtrl.text = invoice.customerName;
      _documentNoCtrl.text = invoice.invoiceNo;
      _customerPartyId = invoice.customerPartyId;
      _selectedBusinessId = invoice.businessId;
      _issueDate = invoice.issueDate;
      _dueDate = invoice.dueDate;
      _notesController.text = invoice.notes ?? '';
      _items.clear();
      _items.addAll(invoice.items.map(
        (ii) => _LineItem(
          itemName: ii.itemName,
          description: ii.description ?? '',
          qty: ii.qty,
          unitPrice: ii.unitPrice,
          taxPct: ii.taxPct,
          discountPct: ii.discountPct,
          hsnCode: ii.hsnCode,
          unit: ii.unit,
          hsnOrSac: ii.hsnOrSac,
        ),
      ));
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customerCtrl.dispose();
    _documentNoCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0.0, (s, i) => s + i.qty * i.unitPrice);

  double get _taxTotal => _items.fold(
      0.0,
      (s, i) =>
          s + i.qty * i.unitPrice * (i.taxPct / 100));

  double get _discountAmt => _items.fold(
      0.0,
      (s, i) =>
          s +
          i.qty *
              i.unitPrice *
              (1 + i.taxPct / 100) *
              (i.discountPct / 100));

  double get _total => _subtotal + _taxTotal - _discountAmt;

  List<QuoteItem> get _quoteItems => _items.map((li) {
        final lineTotal = QuoteItem.computeLineTotal(
          qty: li.qty,
          unitPrice: li.unitPrice,
          taxPct: li.taxPct,
          discountPct: li.discountPct,
        );
        return QuoteItem(
          quoteId: 0,
          itemName: li.itemName,
          description: li.description.isEmpty ? null : li.description,
          qty: li.qty,
          unitPrice: li.unitPrice,
          taxPct: li.taxPct,
          discountPct: li.discountPct,
          lineTotal: lineTotal,
          hsnCode: li.hsnCode,
          unit: li.unit,
          hsnOrSac: li.hsnOrSac,
        );
      }).toList();

  List<InvoiceItem> get _invoiceItems => _items.map((li) {
        final lt = li.qty *
            li.unitPrice *
            (1 + li.taxPct / 100) *
            (1 - li.discountPct / 100);
        return InvoiceItem(
          invoiceId: 0,
          itemName: li.itemName,
          description: li.description.isEmpty ? null : li.description,
          qty: li.qty,
          unitPrice: li.unitPrice,
          taxPct: li.taxPct,
          discountPct: li.discountPct,
          lineTotal: lt,
          hsnCode: li.hsnCode,
          unit: li.unit,
          hsnOrSac: li.hsnOrSac,
        );
      }).toList();

  Future<void> _save({bool send = false}) async {
    if (!_formKey.currentState!.validate()) return;
    _customerName = _customerCtrl.text.trim();
    if (_customerName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_items.isEmpty ||
        _items.every((i) => i.itemName.trim().isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (widget.docType == DocumentType.invoice) {
        await _saveInvoice(send: send);
      } else {
        await _saveQuote(send: send);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveQuote({bool send = false}) async {
    // When sending, save with the current status (or draft for new records).
    // Status is promoted to 'sent' only after the user confirms sharing.
    final status = _existingQuote?.status ?? QuoteStatus.draft;
    final activeBusiness = ref.read(activeBusinessProvider);
    final businessId = _selectedBusinessId ?? activeBusiness?.id;
    final quote = Quote(
      id: _existingQuote?.id,
      quoteNo: _documentNoCtrl.text.trim().isEmpty
          ? await InvoiceNumberService.instance.nextQuoteNo()
          : _documentNoCtrl.text.trim(),
      businessId: businessId,
      customerPartyId: _customerPartyId,
      customerName: _customerName,
      status: status,
      validUntil: _validUntil,
      subtotal: _subtotal,
      taxTotal: _taxTotal,
      discountPct: 0,
      total: _total,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      items: _quoteItems,
      createdAt: _existingQuote?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final int savedId;
    if (_existingQuote != null) {
      await ref.read(quotesProvider.notifier).edit(quote, _quoteItems);
      savedId = quote.id!;
    } else {
      savedId = await ref.read(quotesProvider.notifier).add(quote, _quoteItems);
    }
    if (send) {
      final bizName =
          ref.read(activeBusinessProvider)?.name ?? 'My Business';
      final msg = 'Hi $_customerName,\n\n'
          'Quote #${quote.quoteNo} for ${CurrencyFormatter.format(_total)}.\n'
          'Valid till ${DateFormatter.format(_validUntil)}.\n\n'
          '— $bizName';
      final capturedBusinessId = businessId;
      await _showSendPreviewSheet(
        subject: 'Quote ${quote.quoteNo}',
        message: msg,
        onSent: () => ref.read(quotesProvider.notifier).markSent(savedId),
        generatePdf: () async {
          Business? business;
          if (capturedBusinessId != null) {
            business = await ref
                .read(businessRepositoryProvider)
                .getById(capturedBusinessId);
          }
          Party? customerParty;
          if (_customerPartyId != null) {
            customerParty = await ref
                .read(partyRepositoryProvider)
                .getById(_customerPartyId!);
          }
          return InvoicePdfService.instance.generateQuotePdf(
            quote,
            business: business,
            customerParty: customerParty,
          );
        },
      );
    }
  }

  Future<void> _saveInvoice({bool send = false}) async {
    // Defensive check: prevent saving paid/partially paid invoices
    if (_existingInvoice != null &&
        (_existingInvoice!.status == InvoiceStatus.paid ||
            _existingInvoice!.status == InvoiceStatus.partiallyPaid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot save: invoice is paid and locked from editing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    final status = _existingInvoice?.status ?? InvoiceStatus.draft;
    final activeBusiness = ref.read(activeBusinessProvider);
    final businessId = _selectedBusinessId ?? activeBusiness?.id;
    final invoice = Invoice(
      id: _existingInvoice?.id,
      invoiceNo: _documentNoCtrl.text.trim().isEmpty
          ? await InvoiceNumberService.instance.nextInvoiceNo()
          : _documentNoCtrl.text.trim(),
      businessId: businessId,
      customerPartyId: _customerPartyId,
      customerName: _customerName,
      status: status,
      issueDate: _issueDate,
      dueDate: _dueDate,
      subtotal: _subtotal,
      taxTotal: _taxTotal,
      discountPct: 0,
      total: _total,
      paidAmount: _existingInvoice?.paidAmount ?? 0,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      items: _invoiceItems,
      createdAt: _existingInvoice?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final int savedId;
    if (_existingInvoice != null) {
      await ref.read(invoicesProvider.notifier).edit(invoice, _invoiceItems);
      savedId = invoice.id!;
    } else {
      savedId = await ref.read(invoicesProvider.notifier).add(invoice, _invoiceItems);
    }
    if (send) {
      final bizName =
          ref.read(activeBusinessProvider)?.name ?? 'My Business';
      final msg = 'Hi $_customerName,\n\n'
          'Invoice #${invoice.invoiceNo} for ${CurrencyFormatter.format(_total)}.'
          '${_dueDate != null ? '\nDue ${DateFormatter.format(_dueDate!)}.' : ''}\n\n'
          '— $bizName';
      final capturedBusinessId = businessId;
      await _showSendPreviewSheet(
        subject: 'Invoice ${invoice.invoiceNo}',
        message: msg,
        onSent: () => ref.read(invoicesProvider.notifier).markSent(savedId),
        generatePdf: () async {
          Business? business;
          if (capturedBusinessId != null) {
            business = await ref
                .read(businessRepositoryProvider)
                .getById(capturedBusinessId);
          }
          Party? customerParty;
          if (_customerPartyId != null) {
            customerParty = await ref
                .read(partyRepositoryProvider)
                .getById(_customerPartyId!);
          }
          return InvoicePdfService.instance.generateInvoicePdf(
            invoice,
            business: business,
            customerParty: customerParty,
          );
        },
      );
    }
  }

  /// Shows a bottom sheet with a message preview and a "Send PDF + Message"
  /// button. If the user confirms, delegates to [_generateAndShare].
  Future<void> _showSendPreviewSheet({
    required String subject,
    required String message,
    required Future<File> Function() generatePdf,
    required Future<void> Function() onSent,
  }) async {
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final colorScheme = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.lg,
              AppSpacing.base,
              AppSpacing.base + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────
                Row(
                  children: [
                    Icon(Icons.send_outlined, color: colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        subject,
                        style: Theme.of(sheetCtx).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Message preview ─────────────────────────────────────
                Text(
                  'Message preview',
                  style: Theme.of(sheetCtx).textTheme.labelMedium?.copyWith(
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
                      style: Theme.of(sheetCtx).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),

                // ── Copy message ─────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy message'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message));
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Hint ─────────────────────────────────────────────────
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
                        'Pick WhatsApp, Email, SMS and more from '
                        'the share sheet.',
                        style: Theme.of(sheetCtx).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.outline),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Actions ──────────────────────────────────────────────
                FilledButton.icon(
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send PDF + Message'),
                  onPressed: () => Navigator.pop(sheetCtx, true),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetCtx, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      await _generateAndShare(
        subject: subject,
        message: message,
        generatePdf: generatePdf,
        onSent: onSent,
      );
    }
  }

  /// Generates a PDF via [generatePdf], opens the system share sheet,
  /// then calls [onSent] to mark the record as sent in the database.
  Future<void> _generateAndShare({
    required String subject,
    required String message,
    required Future<File> Function() generatePdf,
    required Future<void> Function() onSent,
  }) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final pdfFile = await generatePdf();
      if (!mounted) return;
      Navigator.pop(context);
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: subject,
        text: message,
      );
      // Mark as sent only after the share sheet has been opened successfully.
      await onSent();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _convertToInvoice() async {
    if (_existingQuote?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Invoice?'),
        content: const Text(
            'This will create a new invoice from this quote and mark the quote as Accepted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Convert')),
        ],
      ),
    );
    if (ok != true) return;
    final invoice = await ref
        .read(quotesProvider.notifier)
        .convertToInvoice(_existingQuote!.id!);
    if (invoice != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Invoice ${invoice.invoiceNo} created')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _previewQuote() async {
    if (_existingQuote == null) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (_existingQuote!.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(_existingQuote!.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (_existingQuote!.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(_existingQuote!.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        _existingQuote!,
        business: business,
        customerParty: customerParty,
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Open PDF in system viewer
      final result = await OpenFile.open(pdfFile.path);
      
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _shareQuotePdf() async {
    if (_existingQuote == null) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (_existingQuote!.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(_existingQuote!.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (_existingQuote!.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(_existingQuote!.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        _existingQuote!,
        business: business,
        customerParty: customerParty,
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      final businessName = business?.name ?? 'My Business';
      
      // Show share options
      final due = _existingQuote!.validUntil;
      final message = 'Hi ${_existingQuote!.customerName},\n\n'
          'Quote ${_existingQuote!.quoteNo} for ${CurrencyFormatter.format(_existingQuote!.total)}'
          '${due != null ? '\nValid till ${DateFormatter.format(due)}' : ''}'
          '\n\n— $businessName';
      
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: 'Quote ${_existingQuote!.quoteNo}',
        text: message,
      );
      // Mark as sent now that the user has actively shared the PDF.
      await ref.read(quotesProvider.notifier).markSent(_existingQuote!.id!);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _shareInvoicePdf() async {
    if (_existingInvoice == null) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (_existingInvoice!.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(_existingInvoice!.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (_existingInvoice!.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(_existingInvoice!.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        _existingInvoice!,
        business: business,
        customerParty: customerParty,
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      final businessName = business?.name ?? 'My Business';
      
      // Show share options
      final due = _existingInvoice!.dueDate;
      final message = 'Hi ${_existingInvoice!.customerName},\n\n'
          'Invoice ${_existingInvoice!.invoiceNo} for ${CurrencyFormatter.format(_existingInvoice!.total)}'
          '${due != null ? '\nDue ${DateFormatter.format(due)}' : ''}'
          '\n\n— $businessName';
      
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: 'Invoice ${_existingInvoice!.invoiceNo}',
        text: message,
      );
      // Mark as sent now that the user has actively shared the PDF.
      await ref.read(invoicesProvider.notifier).markSent(_existingInvoice!.id!);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _previewInvoice() async {
    if (_existingInvoice == null) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch business if businessId is set
      Business? business;
      if (_existingInvoice!.businessId != null) {
        business = await ref.read(businessRepositoryProvider).getById(_existingInvoice!.businessId!);
      }
      
      // Fetch customer party if customerPartyId is set
      Party? customerParty;
      if (_existingInvoice!.customerPartyId != null) {
        customerParty = await ref.read(partyRepositoryProvider).getById(_existingInvoice!.customerPartyId!);
      }
      
      // Generate PDF
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        _existingInvoice!,
        business: business,
        customerParty: customerParty,
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Open PDF in system viewer
      final result = await OpenFile.open(pdfFile.path);
      
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvoice = widget.docType == DocumentType.invoice;
    final isEdit = isInvoice ? _existingInvoice != null : _existingQuote != null;
    String title;
    if (isInvoice) {
      title = isEdit ? 'Edit Invoice' : 'New Invoice';
    } else {
      title = isEdit ? 'Edit Quote' : 'New Quote';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview PDF',
              onPressed: () => isInvoice ? _previewInvoice() : _previewQuote(),
            ),
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share PDF',
              onPressed: () => isInvoice ? _shareInvoicePdf() : _shareQuotePdf(),
            ),
          if (!isInvoice &&
              isEdit &&
              _existingQuote?.status != QuoteStatus.accepted)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Invoice'),
              onPressed: _convertToInvoice,
            ),
          TextButton(
            onPressed: _isSaving ? null : () => _save(send: true),
            child: const Text('Send'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Customer
            PartyPickerField(
              controller: _customerCtrl,
              labelText: 'Customer',
              onSelected: (name) async {
                setState(() {
                  _customerName = name;
                });
                // Look up party by name to get party ID
                final parties = await ref.read(partyRepositoryProvider).getAll();
                final party = parties.cast<Party?>().firstWhere(
                  (p) => p!.name.trim().toLowerCase() == name.trim().toLowerCase(),
                  orElse: () => null,
                );
                if (party != null && mounted) {
                  setState(() {
                    _customerPartyId = party.id;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Business selector
            Consumer(
              builder: (context, ref, child) {
                final businessesAsync = ref.watch(businessesProvider);
                return businessesAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (businesses) {
                    if (businesses.isEmpty) return const SizedBox.shrink();
                    // If only one business, don't show selector
                    if (businesses.length == 1) {
                      // Auto-select if not already set
                      if (_selectedBusinessId == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _selectedBusinessId = businesses.first.id;
                            });
                          }
                        });
                      }
                      return const SizedBox.shrink();
                    }

                    // Multiple businesses - show dropdown
                    final activeBusiness = ref.watch(activeBusinessProvider);
                    final selectedId = _selectedBusinessId ?? activeBusiness?.id;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: selectedId,
                          decoration: const InputDecoration(
                            labelText: 'Business',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          items: businesses.map((biz) {
                            return DropdownMenuItem(
                              value: biz.id,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    biz.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (biz.gstNo != null)
                                    Text(
                                      'GST: ${biz.gstNo}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedBusinessId = value;
                            });
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'Please select a business';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.base),
                      ],
                    );
                  },
                );
              },
            ),

            // Document number
            TextFormField(
              controller: _documentNoCtrl,
              decoration: InputDecoration(
                labelText: isInvoice ? 'Invoice Number' : 'Quote Number',
                hintText: isInvoice ? 'INV-2026-001' : 'QUO-2026-001',
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter ${isInvoice ? 'invoice' : 'quote'} number';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Date fields
            if (isInvoice) ...[  
              _DateField(
                label: 'Issue Date',
                value: _issueDate,
                onChanged: (d) => setState(() => _issueDate = d),
              ),
              const SizedBox(height: AppSpacing.base),
              _OptionalDateField(
                label: 'Due Date (optional)',
                value: _dueDate,
                onChanged: (d) => setState(() => _dueDate = d),
              ),
            ] else
              _DateField(
                label: 'Valid Until',
                value: _validUntil,
                onChanged: (d) => setState(() => _validUntil = d),
              ),
            const SizedBox(height: AppSpacing.base),

            // Line items
            _LineItemsSection(
              items: _items,
              onChanged: () => setState(() {}),
              onAddFromCatalog: (item) {
                final catalogItem = _LineItem(
                  itemName: item.name,
                  description: item.description ?? '',
                  unitPrice: item.unitPrice,
                  taxPct: item.taxPct,
                  hsnCode: item.hsnCode,
                  unit: item.unit.toUpperCase(),
                  hsnOrSac: item.hsnOrSac,
                );
                setState(() {
                  // If first item is empty, replace it instead of adding new one
                  if (_items.length == 1 && 
                      _items[0].itemName.isEmpty && 
                      _items[0].unitPrice == 0) {
                    _items[0] = catalogItem;
                  } else {
                    // Otherwise add as new item
                    _items.add(catalogItem);
                  }
                });
                // Track usage for smart sorting
                if (item.id != null) {
                  ref
                      .read(catalogProvider.notifier)
                      .trackUsage(item.id!);
                }
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Totals
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  children: [
                    _TotalsRow('Subtotal', CurrencyFormatter.format(_subtotal)),
                    if (_taxTotal > 0)
                      _TotalsRow('Tax', CurrencyFormatter.format(_taxTotal)),
                    if (_discountAmt > 0)
                      _TotalsRow(
                          'Discount', '-${CurrencyFormatter.format(_discountAmt)}'),
                    const Divider(height: AppSpacing.base),
                    _TotalsRow('Total', CurrencyFormatter.format(_total),
                        bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Save button — inside scroll so keyboard never hides it
            FilledButton(
              onPressed: _isSaving ? null : () => _save(),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isInvoice ? 'Save Invoice' : 'Save as Draft'),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Line items section ────────────────────────────────────────────────────────

class _LineItemsSection extends StatelessWidget {
  const _LineItemsSection({
    required this.items,
    required this.onChanged,
    required this.onAddFromCatalog,
  });

  final List<_LineItem> items;
  final VoidCallback onChanged;
  final ValueChanged<ItemCatalog> onAddFromCatalog;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Items',
                    style: Theme.of(context).textTheme.titleMedium),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: const Text('Catalog'),
                      onPressed: () => _pickFromCatalog(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add Item',
                      onPressed: () {
                        items.add(const _LineItem());
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: AppSpacing.sm),
            ...items.asMap().entries.map(
                  (e) => _LineItemRow(
                    index: e.key,
                    item: e.value,
                    onChanged: (updated) {
                      items[e.key] = updated;
                      onChanged();
                    },
                    onRemove: items.length > 1
                        ? () {
                            items.removeAt(e.key);
                            onChanged();
                          }
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCatalog(BuildContext context) async {
    final picked = await Navigator.push<ItemCatalog>(
      context,
      MaterialPageRoute(
          builder: (_) => const ItemCatalogScreen(pickMode: true)),
    );
    if (picked != null) onAddFromCatalog(picked);
  }
}

@immutable
class _LineItem {
  const _LineItem({
    this.itemName = '',
    this.description = '',
    this.qty = 1,
    this.unitPrice = 0.0,
    this.taxPct = 0.0,
    this.discountPct = 0.0,
    this.hsnCode,
    this.unit = 'PCS',
    this.hsnOrSac = 'HSN',
  });

  final String itemName;
  final String description;
  final double qty;
  final double unitPrice;
  final double taxPct;
  final double discountPct;
  /// HSN or SAC code copied from item catalog.
  final String? hsnCode;
  /// GST UOM code (e-Way Bill master), e.g. 'KGS', 'NOS'.
  final String unit;
  /// 'HSN' for products/materials/equipment, 'SAC' for services/labour.
  final String hsnOrSac;

  _LineItem copyWith({
    String? itemName,
    String? description,
    double? qty,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
    String? hsnCode,
    String? unit,
    String? hsnOrSac,
  }) =>
      _LineItem(
        itemName: itemName ?? this.itemName,
        description: description ?? this.description,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        taxPct: taxPct ?? this.taxPct,
        discountPct: discountPct ?? this.discountPct,
        hsnCode: hsnCode ?? this.hsnCode,
        unit: unit ?? this.unit,
        hsnOrSac: hsnOrSac ?? this.hsnOrSac,
      );
}

class _LineItemRow extends StatefulWidget {
  const _LineItemRow(
      {required this.index,
      required this.item,
      required this.onChanged,
      this.onRemove});
  final int index;
  final _LineItem item;
  final ValueChanged<_LineItem> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_LineItemRow> createState() => _LineItemRowState();
}

class _LineItemRowState extends State<_LineItemRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _discCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.itemName);
    _qtyCtrl =
        TextEditingController(text: widget.item.qty.toString());
    _priceCtrl = TextEditingController(
        text: widget.item.unitPrice == 0
            ? ''
            : widget.item.unitPrice.toStringAsFixed(2));
    _taxCtrl = TextEditingController(
        text: widget.item.taxPct == 0
            ? ''
            : widget.item.taxPct.toStringAsFixed(1));
    _discCtrl = TextEditingController(
        text: widget.item.discountPct == 0
            ? ''
            : widget.item.discountPct.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _taxCtrl.dispose();
    _discCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_LineItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers when item changes (e.g., from catalog selection)
    if (oldWidget.item != widget.item) {
      _nameCtrl.text = widget.item.itemName;
      _qtyCtrl.text = widget.item.qty.toString();
      _priceCtrl.text = widget.item.unitPrice == 0
          ? ''
          : widget.item.unitPrice.toStringAsFixed(2);
      _taxCtrl.text = widget.item.taxPct == 0
          ? ''
          : widget.item.taxPct.toStringAsFixed(1);
      _discCtrl.text = widget.item.discountPct == 0
          ? ''
          : widget.item.discountPct.toStringAsFixed(1);
    }
  }

  void _emit() {
    widget.onChanged(widget.item.copyWith(
      itemName: _nameCtrl.text,
      qty: double.tryParse(_qtyCtrl.text) ?? 1,
      unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
      taxPct: double.tryParse(_taxCtrl.text) ?? 0,
      discountPct: double.tryParse(_discCtrl.text) ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lineTotal = QuoteItem.computeLineTotal(
      qty: double.tryParse(_qtyCtrl.text) ?? 1,
      unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
      taxPct: double.tryParse(_taxCtrl.text) ?? 0,
      discountPct: double.tryParse(_discCtrl.text) ?? 0,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Item ${widget.index + 1}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                CurrencyFormatter.format(lineTotal),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (widget.onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Item name',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _NumField(
                    ctrl: _qtyCtrl,
                    label: 'Qty',
                    onChanged: (_) => _emit()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: _NumField(
                    ctrl: _priceCtrl,
                    label: 'Unit Price (₹)',
                    onChanged: (_) => _emit()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _NumField(
                    ctrl: _taxCtrl,
                    label: 'Tax %',
                    onChanged: (_) => _emit()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumField(
                    ctrl: _discCtrl,
                    label: 'Discount %',
                    onChanged: (_) => _emit()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField(
      {required this.ctrl,
      required this.label,
      required this.onChanged});
  final TextEditingController ctrl;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label,
      required this.value,
      required this.onChanged});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(DateFormatter.format(value)),
      ),
    );
  }
}

/// Nullable date field — shows a placeholder when no date is set.
class _OptionalDateField extends StatelessWidget {
  const _OptionalDateField(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                  padding: EdgeInsets.zero,
                ),
              const Icon(Icons.calendar_today_outlined),
            ],
          ),
        ),
        child: Text(
          value != null ? DateFormatter.format(value!) : 'Not set',
          style: value == null
              ? TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4))
              : null,
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
          Text(value,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }
}
