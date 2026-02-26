import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/models/quote.dart';
import '../../../data/services/invoice_number_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../widgets/party_picker_field.dart';
import 'item_catalog_screen.dart';

class QuoteBuilderScreen extends ConsumerStatefulWidget {
  const QuoteBuilderScreen({super.key, this.quoteId});
  final int? quoteId;

  @override
  ConsumerState<QuoteBuilderScreen> createState() =>
      _QuoteBuilderScreenState();
}

class _QuoteBuilderScreenState extends ConsumerState<QuoteBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  String _customerName = '';
  int? _customerPartyId;
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  final List<_LineItem> _items = [];
  final _notesController = TextEditingController();
  late final TextEditingController _customerCtrl;

  Quote? _existingQuote;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController();
    if (widget.quoteId != null) {
      _loadQuote();
    } else {
      _items.add(const _LineItem());
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
      _customerPartyId = quote.customerPartyId;
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
        ),
      ));
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customerCtrl.dispose();
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
          quoteId: 0, // set by repository on insert
          itemName: li.itemName,
          description: li.description.isEmpty ? null : li.description,
          qty: li.qty,
          unitPrice: li.unitPrice,
          taxPct: li.taxPct,
          discountPct: li.discountPct,
          lineTotal: lineTotal,
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
      final status =
          send ? QuoteStatus.sent : QuoteStatus.draft;
      final quote = Quote(
        id: _existingQuote?.id,
        quoteNo: _existingQuote?.quoteNo ??
            await InvoiceNumberService.instance.nextQuoteNo(),
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

      if (_existingQuote != null) {
        await ref
            .read(quotesProvider.notifier)
            .edit(quote, _quoteItems);
      } else {
        await ref
            .read(quotesProvider.notifier)
            .add(quote, _quoteItems);
      }

      if (send) {
        final bizName =
            ref.read(activeBusinessProvider)?.name ?? 'My Business';
        final msg =
            'Hi $_customerName, quote #${quote.quoteNo} for ${CurrencyFormatter.format(_total)}. '
            'Valid till ${DateFormatter.format(_validUntil)}. — $bizName';
        Share.share(msg, subject: 'Quote ${quote.quoteNo}');
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    final isEdit = _existingQuote != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Quote' : 'New Quote'),
        actions: [
          if (isEdit &&
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
              onSelected: (name) => setState(() {
                _customerName = name;
              }),
            ),
            const SizedBox(height: AppSpacing.base),

            // Valid Until
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
              onAddFromCatalog: (item) => setState(() {
                _items.add(_LineItem(
                  itemName: item.name,
                  description: item.description ?? '',
                  unitPrice: item.unitPrice,
                  taxPct: item.taxPct,
                ));
              }),
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
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xl),
        child: FilledButton(
          onPressed: _isSaving ? null : () => _save(),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save as Draft'),
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
  });

  final String itemName;
  final String description;
  final double qty;
  final double unitPrice;
  final double taxPct;
  final double discountPct;

  _LineItem copyWith({
    String? itemName,
    String? description,
    double? qty,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
  }) =>
      _LineItem(
        itemName: itemName ?? this.itemName,
        description: description ?? this.description,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        taxPct: taxPct ?? this.taxPct,
        discountPct: discountPct ?? this.discountPct,
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
          const SizedBox(height: AppSpacing.xs),
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
                    label: 'Price (₹)',
                    onChanged: (_) => _emit()),
              ),
              const SizedBox(width: AppSpacing.sm),
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
                    label: 'Disc %',
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
          firstDate: DateTime.now(),
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
