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
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/models/party.dart';
import '../../../data/models/party_address.dart';
import '../../../data/models/quote.dart';
import '../../../data/services/delivery_challan_pdf_service.dart';
import '../../../data/services/fiscal_year_service.dart';
import '../../../data/services/invoice_number_service.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_address_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/party_picker_field.dart';
import '../../widgets/delivery_address_picker.dart';
import 'invoice_detail_screen.dart';
import 'item_catalog_screen.dart';

enum DocumentType { quote, invoice, deliveryChallan }

class QuoteBuilderScreen extends ConsumerStatefulWidget {
  const QuoteBuilderScreen({
    super.key,
    this.quoteId,
    this.invoiceId,
    this.challanId,
    this.docType = DocumentType.quote,
  });
  final int? quoteId;
  final int? invoiceId;
  final int? challanId;
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
  double _freightAmt = 0;
  double _insuranceAmt = 0;
  double _packingAmt = 0;
  final _notesController = TextEditingController();
  late final TextEditingController _customerCtrl;
  late final TextEditingController _documentNoCtrl;
  late final TextEditingController _freightCtrl;
  late final TextEditingController _insuranceCtrl;
  late final TextEditingController _packingCtrl;

  Quote? _existingQuote;
  Invoice? _existingInvoice;
  DeliveryChallan? _existingChallan;
  // DC-specific state
  ChallanPurpose _challanPurpose = ChallanPurpose.supply;
  DateTime _challanDate = DateTime.now();
  DateTime? _expectedReturnDate;
  String _transportMode = '1'; // '1'=Road, '2'=Rail, '3'=Air, '4'=Ship
  late final TextEditingController _vehicleNoCtrl;
  late final TextEditingController _transporterCtrl;
  late final TextEditingController _distanceCtrl;
  late final TextEditingController _ewbNoCtrl;
  late final TextEditingController _custGstinCtrl;
  late final TextEditingController _placeOfSupplyCtrl;
  bool _isSaving = false;
  // Delivery address snapshot (null = no delivery address)
  PartyAddress? _selectedDeliveryAddress;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController();
    _documentNoCtrl = TextEditingController();
    _freightCtrl = TextEditingController();
    _insuranceCtrl = TextEditingController();
    _packingCtrl = TextEditingController();
    _vehicleNoCtrl = TextEditingController();
    _transporterCtrl = TextEditingController();
    _distanceCtrl = TextEditingController();
    _ewbNoCtrl = TextEditingController();
    _custGstinCtrl = TextEditingController();
    _placeOfSupplyCtrl = TextEditingController();
    if (widget.docType == DocumentType.invoice) {
      if (widget.invoiceId != null) {
        _loadInvoice();
      } else {
        _dueDate = DateTime.now().add(const Duration(days: 30));
        _items.add(const _LineItem());
        _initDocumentNumber();
      }
    } else if (widget.docType == DocumentType.deliveryChallan) {
      if (widget.challanId != null) {
        _loadChallan();
      } else {
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
        : widget.docType == DocumentType.deliveryChallan
            ? await FiscalYearService.instance.nextChallanNo()
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
      _freightAmt = quote.freightAmt;
      _insuranceAmt = quote.insuranceAmt;
      _packingAmt = quote.packingAmt;
      _freightCtrl.text = quote.freightAmt > 0 ? quote.freightAmt.toStringAsFixed(2) : '';
      _insuranceCtrl.text = quote.insuranceAmt > 0 ? quote.insuranceAmt.toStringAsFixed(2) : '';
      _packingCtrl.text = quote.packingAmt > 0 ? quote.packingAmt.toStringAsFixed(2) : '';
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
      _freightAmt = invoice.freightAmt;
      _insuranceAmt = invoice.insuranceAmt;
      _packingAmt = invoice.packingAmt;
      _freightCtrl.text = invoice.freightAmt > 0 ? invoice.freightAmt.toStringAsFixed(2) : '';
      _insuranceCtrl.text = invoice.insuranceAmt > 0 ? invoice.insuranceAmt.toStringAsFixed(2) : '';
      _packingCtrl.text = invoice.packingAmt > 0 ? invoice.packingAmt.toStringAsFixed(2) : '';
      // Restore delivery address snapshot from existing invoice
      if (invoice.deliveryAddress != null ||
          invoice.deliveryCity != null ||
          invoice.deliveryState != null) {
        _selectedDeliveryAddress = PartyAddress(
          partyId: invoice.customerPartyId ?? 0,
          label: 'Delivery Address',
          address: invoice.deliveryAddress,
          city: invoice.deliveryCity,
          state: invoice.deliveryState,
          pincode: invoice.deliveryPincode,
          gstin: invoice.deliveryGstin,
          createdAt: DateTime.now(),
        );
      }
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

  Future<void> _loadChallan() async {
    final challan = await ref
        .read(deliveryChallanRepositoryProvider)
        .getById(widget.challanId!);
    if (challan == null) return;
    if (!mounted) return;
    setState(() {
      _existingChallan = challan;
      _customerName = challan.customerName;
      _customerCtrl.text = challan.customerName;
      _documentNoCtrl.text = challan.challanNo;
      _customerPartyId = challan.customerPartyId;
      _selectedBusinessId = challan.businessId;
      _challanDate = challan.challanDate;
      _expectedReturnDate = challan.expectedReturnDate;
      _challanPurpose = challan.purpose;
      _transportMode = challan.transportMode ?? '1';
      _vehicleNoCtrl.text = challan.vehicleNo ?? '';
      _transporterCtrl.text = challan.transporterName ?? '';
      _distanceCtrl.text = challan.distanceKm?.toString() ?? '';
      _ewbNoCtrl.text = challan.ewbNo ?? '';
      _custGstinCtrl.text = challan.customerGstin ?? '';
      _placeOfSupplyCtrl.text = challan.placeOfSupply ?? '';
      _notesController.text = challan.notes ?? '';
      // Restore delivery address snapshot from existing challan
      if (challan.deliveryAddress != null ||
          challan.deliveryCity != null ||
          challan.deliveryState != null) {
        _selectedDeliveryAddress = PartyAddress(
          partyId: challan.customerPartyId ?? 0,
          label: 'Delivery Address',
          address: challan.deliveryAddress,
          city: challan.deliveryCity,
          state: challan.deliveryState,
          pincode: challan.deliveryPincode,
          gstin: challan.deliveryGstin,
          createdAt: DateTime.now(),
        );
      }
      _items.clear();
      _items.addAll(challan.items.map(
        (ci) => _LineItem(
          itemName: ci.itemName,
          description: ci.description ?? '',
          qty: ci.qty,
          unitPrice: ci.unitPrice,
          hsnCode: ci.hsnCode,
          unit: ci.unit,
          hsnOrSac: ci.hsnOrSac,
        ),
      ));
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customerCtrl.dispose();
    _documentNoCtrl.dispose();
    _freightCtrl.dispose();
    _insuranceCtrl.dispose();
    _packingCtrl.dispose();
    _vehicleNoCtrl.dispose();
    _transporterCtrl.dispose();
    _distanceCtrl.dispose();
    _ewbNoCtrl.dispose();
    _custGstinCtrl.dispose();
    _placeOfSupplyCtrl.dispose();
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

  double get _total => _subtotal + _taxTotal - _discountAmt + _freightAmt + _insuranceAmt + _packingAmt;

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

  List<ChallanItem> get _challanItems => _items
      .map((li) => ChallanItem(
            challanId: 0,
            itemName: li.itemName,
            description: li.description.isEmpty ? null : li.description,
            qty: li.qty,
            unit: li.unit,
            unitPrice: li.unitPrice,
            hsnCode: li.hsnCode,
            hsnOrSac: li.hsnOrSac,
          ))
      .toList();

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
      } else if (widget.docType == DocumentType.deliveryChallan) {
        await _saveChallan();
      } else {
        await _saveQuote(send: send);
      }
      if (mounted && !send) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
      freightAmt: _freightAmt,
      insuranceAmt: _insuranceAmt,
      packingAmt: _packingAmt,
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
    if (mounted) setState(() => _existingQuote = quote.copyWith(id: savedId));
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
          final quoteTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.quoteTerms);
          return InvoicePdfService.instance.generateQuotePdf(
            quote,
            business: business,
            customerParty: customerParty,
            termsAndConditions: quoteTerms,
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
      freightAmt: _freightAmt,
      insuranceAmt: _insuranceAmt,
      packingAmt: _packingAmt,
      paidAmount: _existingInvoice?.paidAmount ?? 0,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      deliveryAddress: _selectedDeliveryAddress?.address,
      deliveryCity: _selectedDeliveryAddress?.city,
      deliveryState: _selectedDeliveryAddress?.state,
      deliveryPincode: _selectedDeliveryAddress?.pincode,
      deliveryGstin: _selectedDeliveryAddress?.gstin,
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
    if (mounted) setState(() => _existingInvoice = invoice.copyWith(id: savedId));
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
          final invoiceTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.invoiceTerms);
          return InvoicePdfService.instance.generateInvoicePdf(
            invoice,
            business: business,
            customerParty: customerParty,
            termsAndConditions: invoiceTerms ?? SettingsKeys.defaultInvoiceTerms,
          );
        },
      );
    }
  }

  Future<void> _saveChallan() async {
    final activeBusiness = ref.read(activeBusinessProvider);
    final businessId = _selectedBusinessId ?? activeBusiness?.id;
    final subtotal =
        _items.fold<double>(0, (s, i) => s + i.qty * i.unitPrice);
    final challan = DeliveryChallan(
      id: _existingChallan?.id,
      challanNo: _documentNoCtrl.text.trim().isEmpty
          ? await FiscalYearService.instance.nextChallanNo()
          : _documentNoCtrl.text.trim(),
      businessId: businessId,
      customerPartyId: _customerPartyId,
      customerName: _customerName,
      status: _existingChallan?.status ?? ChallanStatus.draft,
      challanDate: _challanDate,
      expectedReturnDate: _expectedReturnDate,
      purpose: _challanPurpose,
      subtotal: subtotal,
      vehicleNo: _vehicleNoCtrl.text.trim().isEmpty
          ? null
          : _vehicleNoCtrl.text.trim(),
      transporterName: _transporterCtrl.text.trim().isEmpty
          ? null
          : _transporterCtrl.text.trim(),
      transportMode: _transportMode,
      distanceKm: int.tryParse(_distanceCtrl.text),
      ewbNo:
          _ewbNoCtrl.text.trim().isEmpty ? null : _ewbNoCtrl.text.trim(),
      customerGstin: _custGstinCtrl.text.trim().isEmpty
          ? null
          : _custGstinCtrl.text.trim(),
      placeOfSupply: _placeOfSupplyCtrl.text.trim().isEmpty
          ? null
          : _placeOfSupplyCtrl.text.trim(),
      deliveryAddress: _selectedDeliveryAddress?.address,
      deliveryCity: _selectedDeliveryAddress?.city,
      deliveryState: _selectedDeliveryAddress?.state,
      deliveryPincode: _selectedDeliveryAddress?.pincode,
      deliveryGstin: _selectedDeliveryAddress?.gstin,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      items: _challanItems,
      createdAt: _existingChallan?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final int savedId;
    if (_existingChallan != null) {
      await ref.read(challansProvider.notifier).edit(challan);
      savedId = challan.id!;
    } else {
      final saved = await ref.read(challansProvider.notifier).add(challan);
      savedId = saved.id!;
    }
    if (mounted) {
      setState(() => _existingChallan = challan.copyWith(id: savedId));
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
      final quoteTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.quoteTerms);
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        _existingQuote!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: quoteTerms ?? SettingsKeys.defaultQuoteTerms,
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
      final quoteTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.quoteTerms);
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        _existingQuote!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: quoteTerms ?? SettingsKeys.defaultQuoteTerms,
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
      final invoiceTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.invoiceTerms);
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        _existingInvoice!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: invoiceTerms ?? SettingsKeys.defaultInvoiceTerms,
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
      final invoiceTerms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.invoiceTerms);
      final pdfFile = await InvoicePdfService.instance.generateInvoicePdf(
        _existingInvoice!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: invoiceTerms ?? SettingsKeys.defaultInvoiceTerms,
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

  Future<void> _previewChallan() async {
    if (_existingChallan == null) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      Business? business;
      if (_existingChallan!.businessId != null) {
        business = await ref
            .read(businessRepositoryProvider)
            .getById(_existingChallan!.businessId!);
      }
      Party? customerParty;
      if (_existingChallan!.customerPartyId != null) {
        customerParty = await ref
            .read(partyRepositoryProvider)
            .getById(_existingChallan!.customerPartyId!);
      }
      final pdfFile = await DeliveryChallanPdfService.instance.generateChallanPdf(
        _existingChallan!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: (await ref.read(settingsRepositoryProvider).get(SettingsKeys.challanTerms)) ?? SettingsKeys.defaultChallanTerms,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final result = await OpenFile.open(pdfFile.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _shareChallanPdf() async {
    if (_existingChallan == null) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      Business? business;
      if (_existingChallan!.businessId != null) {
        business = await ref
            .read(businessRepositoryProvider)
            .getById(_existingChallan!.businessId!);
      }
      Party? customerParty;
      if (_existingChallan!.customerPartyId != null) {
        customerParty = await ref
            .read(partyRepositoryProvider)
            .getById(_existingChallan!.customerPartyId!);
      }
      final pdfFile = await DeliveryChallanPdfService.instance.generateChallanPdf(
        _existingChallan!,
        business: business,
        customerParty: customerParty,
        termsAndConditions: (await ref.read(settingsRepositoryProvider).get(SettingsKeys.challanTerms)) ?? SettingsKeys.defaultChallanTerms,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final businessName = business?.name ?? 'My Business';
      final message = 'Hi ${_existingChallan!.customerName},\n\n'
          'Delivery Challan ${_existingChallan!.challanNo} '
          '(${_existingChallan!.items.length} item(s)).\n\n'
          '— $businessName';
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: 'Delivery Challan ${_existingChallan!.challanNo}',
        text: message,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _convertChallanToInvoice() async {
    if (_existingChallan?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Invoice?'),
        content: const Text(
            'This will create a new invoice from this challan and mark it as converted.'),
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
    if (ok != true || !mounted) return;
    try {
      final invoiceNo = await FiscalYearService.instance.nextInvoiceNo();
      final invoice = await ref
          .read(deliveryChallanRepositoryProvider)
          .convertToInvoice(_existingChallan!.id!, invoiceNo);
      ref.read(challansProvider.notifier).invalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice ${invoice.invoiceNo} created')),
        );
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conversion failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvoice = widget.docType == DocumentType.invoice;
    final isDC = widget.docType == DocumentType.deliveryChallan;
    final isEdit = isInvoice
        ? _existingInvoice != null
        : isDC
            ? _existingChallan != null
            : _existingQuote != null;
    String title;
    if (isInvoice) {
      title = isEdit ? 'Edit Invoice' : 'New Invoice';
    } else if (isDC) {
      title = isEdit ? _existingChallan!.challanNo : 'New Challan';
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
              onPressed: isDC
                  ? _previewChallan
                  : isInvoice
                      ? _previewInvoice
                      : _previewQuote,
            ),
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share PDF',
              onPressed: isDC
                  ? _shareChallanPdf
                  : isInvoice
                      ? _shareInvoicePdf
                      : _shareQuotePdf,
            ),
          if (!isInvoice &&
              !isDC &&
              isEdit &&
              _existingQuote?.status != QuoteStatus.accepted)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Invoice'),
              onPressed: _convertToInvoice,
            ),
          if (isDC &&
              isEdit &&
              _existingChallan?.status != ChallanStatus.converted)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Invoice'),
              onPressed: _convertChallanToInvoice,
            ),
          if (!isDC)
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
                  // Clear stale delivery address from previous customer
                  _selectedDeliveryAddress = null;
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
                  // Auto-populate delivery address from party's default address
                  if (party.id != null && widget.docType != DocumentType.quote) {
                    final addresses = await ref
                        .read(partyAddressRepositoryProvider)
                        .getByPartyId(party.id!);
                    final defaultAddr = addresses.where((a) => a.isDefault).firstOrNull ??
                        (addresses.isNotEmpty ? addresses.first : null);
                    if (mounted && defaultAddr != null) {
                      setState(() => _selectedDeliveryAddress = defaultAddr);
                    }
                  }
                }
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Delivery Address (Invoice + DC only)
            if (widget.docType != DocumentType.quote) ...[
              _DeliveryAddressTile(
                selectedAddress: _selectedDeliveryAddress,
                partyId: _customerPartyId,
                onTap: () async {
                  await showDeliveryAddressPicker(
                    context: context,
                    partyId: _customerPartyId,
                    current: _selectedDeliveryAddress,
                    onSelected: (addr) {
                      if (mounted) {
                        setState(() => _selectedDeliveryAddress = addr);
                      }
                    },
                  );
                },
                onClear: () =>
                    setState(() => _selectedDeliveryAddress = null),
              ),
              const SizedBox(height: AppSpacing.base),
            ],

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
                labelText: isInvoice
                    ? 'Invoice Number'
                    : isDC
                        ? 'Challan Number'
                        : 'Quote Number',
                hintText: isInvoice
                    ? 'INV-2026-001'
                    : isDC
                        ? 'DC-25-26-0001'
                        : 'QUO-2026-001',
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter ${isInvoice ? 'invoice' : isDC ? 'challan' : 'quote'} number';
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
            ] else if (isDC) ...[  
              _DateField(
                label: 'Challan Date',
                value: _challanDate,
                onChanged: (d) => setState(() => _challanDate = d),
              ),
              const SizedBox(height: AppSpacing.base),
              _OptionalDateField(
                label: 'Expected Return Date (optional)',
                value: _expectedReturnDate,
                onChanged: (d) => setState(() => _expectedReturnDate = d),
              ),
            ] else
              _DateField(
                label: 'Valid Until',
                value: _validUntil,
                onChanged: (d) => setState(() => _validUntil = d),
              ),
            const SizedBox(height: AppSpacing.base),

            // DC-specific: Purpose + Transport
            if (isDC) ...[  
              DropdownButtonFormField<ChallanPurpose>(
                value: _challanPurpose,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Purpose',
                  prefixIcon: Icon(Icons.category_outlined),
                  border: OutlineInputBorder(),
                ),
                items: ChallanPurpose.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _challanPurpose = v!),
              ),
              const SizedBox(height: AppSpacing.base),
              _SectionHeader('Transport Details'),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _vehicleNoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle No. (optional)',
                        hintText: 'KA01AB1234',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _transportMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Mode',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '1', child: Text('Road')),
                        DropdownMenuItem(value: '2', child: Text('Rail')),
                        DropdownMenuItem(value: '3', child: Text('Air')),
                        DropdownMenuItem(value: '4', child: Text('Ship')),
                      ],
                      onChanged: (v) => setState(() => _transportMode = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _transporterCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Transporter (optional)',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _distanceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Distance (km)',
                        prefixIcon: Icon(Icons.straighten_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _ewbNoCtrl,
                decoration: const InputDecoration(
                  labelText: 'EWB No. (optional)',
                  hintText: 'e-Way Bill Number',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _custGstinCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Customer GSTIN (optional)',
                        prefixIcon: Icon(Icons.numbers_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _placeOfSupplyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Place of Supply (optional)',
                        hintText: '29 - Karnataka',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),
            ],

            // Line items
            _LineItemsSection(
              items: _items,
              onChanged: () => setState(() {}),
              showTaxDiscount: !isDC,
              onAddFromCatalog: (item) {
                final catalogItem = _LineItem(
                  itemName: item.name,
                  description: item.description ?? '',
                  unitPrice: item.unitPrice,
                  taxPct: isDC ? 0 : item.taxPct,
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
                    if (!isDC && _taxTotal > 0)
                      _TotalsRow('Tax', CurrencyFormatter.format(_taxTotal)),
                    if (!isDC && _discountAmt > 0)
                      _TotalsRow(
                          'Discount', '-${CurrencyFormatter.format(_discountAmt)}'),
                    _ChargeInputRow(
                      label: 'Freight',
                      controller: _freightCtrl,
                      onChanged: (v) => setState(() => _freightAmt = v),
                    ),
                    _ChargeInputRow(
                      label: 'Insurance',
                      controller: _insuranceCtrl,
                      onChanged: (v) => setState(() => _insuranceAmt = v),
                    ),
                    _ChargeInputRow(
                      label: 'Packing & Fwdg',
                      controller: _packingCtrl,
                      onChanged: (v) => setState(() => _packingAmt = v),
                    ),
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
                  : Text(isInvoice ? 'Save Invoice' : isDC ? 'Save Challan' : 'Save as Draft'),
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
    this.showTaxDiscount = true,
  });

  final List<_LineItem> items;
  final VoidCallback onChanged;
  final ValueChanged<ItemCatalog> onAddFromCatalog;
  final bool showTaxDiscount;

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
                    showTaxDiscount: showTaxDiscount,
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
      this.onRemove,
      this.showTaxDiscount = true});
  final int index;
  final _LineItem item;
  final ValueChanged<_LineItem> onChanged;
  final VoidCallback? onRemove;
  final bool showTaxDiscount;

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
          if (widget.showTaxDiscount) ...[  
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

/// A compact editable charge row shown inside the totals card.
/// Renders a label on the left and a slim amount [TextField] on the right.
/// Passes 0 when the field is empty or invalid.
class _ChargeInputRow extends StatelessWidget {
  const _ChargeInputRow({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          SizedBox(
            width: 110,
            height: 36,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(color: Colors.grey),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                onChanged(double.tryParse(text) ?? 0);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

// ── Delivery Address Tile ─────────────────────────────────────────────────────

class _DeliveryAddressTile extends StatelessWidget {
  const _DeliveryAddressTile({
    required this.selectedAddress,
    required this.partyId,
    required this.onTap,
    required this.onClear,
  });

  final PartyAddress? selectedAddress;
  final int? partyId;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAddress = selectedAddress != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasAddress ? cs.primary.withValues(alpha: 0.6) : cs.outline,
          ),
          borderRadius: BorderRadius.circular(12),
          color: hasAddress
              ? cs.primaryContainer.withValues(alpha: 0.12)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              hasAddress
                  ? Icons.local_shipping_outlined
                  : Icons.add_location_alt_outlined,
              color: hasAddress ? cs.primary : cs.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: hasAddress
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery: ${selectedAddress!.label}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (selectedAddress!.displayLine.isNotEmpty)
                          Text(
                            selectedAddress!.displayLine,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    )
                  : Text(
                      'Add delivery address (optional)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
            ),
            if (hasAddress)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
