import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/services/fiscal_year_service.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/party_provider.dart';

/// Mutable local state for each line item while editing.
class _ChallanLineItem {
  _ChallanLineItem({
    this.id,
    this.itemName = '',
    this.description = '',
    this.qty = 1,
    this.unit = 'PCS',
    this.unitPrice = 0,
    this.hsnCode = '',
  });

  int? id;
  String itemName;
  String description;
  double qty;
  String unit;
  double unitPrice;
  String hsnCode;

  double get lineTotal => qty * unitPrice;

  ChallanItem toChallanItem(int challanId) => ChallanItem(
        id: id,
        challanId: challanId,
        itemName: itemName,
        description: description.isEmpty ? null : description,
        qty: qty,
        unit: unit,
        unitPrice: unitPrice,
        hsnCode: hsnCode.isEmpty ? null : hsnCode,
      );
}

/// Create / edit screen for Delivery Challans.
class DeliveryChallanFormScreen extends ConsumerStatefulWidget {
  const DeliveryChallanFormScreen({super.key, this.existing});

  /// Pass an existing challan to edit it; null = create new.
  final DeliveryChallan? existing;

  @override
  ConsumerState<DeliveryChallanFormScreen> createState() =>
      _DeliveryChallanFormScreenState();
}

class _DeliveryChallanFormScreenState
    extends ConsumerState<DeliveryChallanFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ─────────────────────────────────────────────────────────────
  late final TextEditingController _challanNoCtrl;
  late final TextEditingController _customerNameCtrl;
  late final TextEditingController _notesCtrl;
  // Transport
  late final TextEditingController _vehicleNoCtrl;
  late final TextEditingController _transporterCtrl;
  late final TextEditingController _distanceCtrl;
  late final TextEditingController _ewbNoCtrl;
  late final TextEditingController _customerGstinCtrl;
  late final TextEditingController _placeOfSupplyCtrl;

  // ── State ──────────────────────────────────────────────────────────────────
  DateTime _challanDate = DateTime.now();
  DateTime? _dispatchDate;
  DateTime? _expectedReturnDate;
  ChallanPurpose _purpose = ChallanPurpose.supply;
  String _transportMode = '1';
  int? _customerPartyId;
  List<_ChallanLineItem> _items = [_ChallanLineItem()];
  bool _saving = false;
  bool _showTransport = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _challanNoCtrl = TextEditingController(text: e?.challanNo ?? '');
    _customerNameCtrl = TextEditingController(text: e?.customerName ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _vehicleNoCtrl = TextEditingController(text: e?.vehicleNo ?? '');
    _transporterCtrl =
        TextEditingController(text: e?.transporterName ?? '');
    _distanceCtrl =
        TextEditingController(text: e?.distanceKm?.toString() ?? '');
    _ewbNoCtrl = TextEditingController(text: e?.ewbNo ?? '');
    _customerGstinCtrl =
        TextEditingController(text: e?.customerGstin ?? '');
    _placeOfSupplyCtrl =
        TextEditingController(text: e?.placeOfSupply ?? '');

    if (e != null) {
      _challanDate = e.challanDate;
      _dispatchDate = e.dispatchDate;
      _expectedReturnDate = e.expectedReturnDate;
      _purpose = e.purpose;
      _transportMode = e.transportMode ?? '1';
      _customerPartyId = e.customerPartyId;
      _items = e.items
          .map((i) => _ChallanLineItem(
                id: i.id,
                itemName: i.itemName,
                description: i.description ?? '',
                qty: i.qty,
                unit: i.unit,
                unitPrice: i.unitPrice,
                hsnCode: i.hsnCode ?? '',
              ))
          .toList();
      _showTransport = e.vehicleNo != null ||
          e.transporterName != null ||
          e.distanceKm != null;
    } else {
      // Auto-fill challan number for new challans
      _initChallanNo();
    }
  }

  Future<void> _initChallanNo() async {
    final no = await FiscalYearService.instance.nextChallanNo();
    if (mounted) setState(() => _challanNoCtrl.text = no);
  }

  @override
  void dispose() {
    _challanNoCtrl.dispose();
    _customerNameCtrl.dispose();
    _notesCtrl.dispose();
    _vehicleNoCtrl.dispose();
    _transporterCtrl.dispose();
    _distanceCtrl.dispose();
    _ewbNoCtrl.dispose();
    _customerGstinCtrl.dispose();
    _placeOfSupplyCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, i) => sum + i.lineTotal);

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Challan' : 'New Delivery Challan'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            _SectionHeader('Challan Info'),
            const SizedBox(height: AppSpacing.sm),
            _buildHeader(),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader('Customer'),
            const SizedBox(height: AppSpacing.sm),
            _buildCustomer(),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader('Items'),
            const SizedBox(height: AppSpacing.sm),
            _buildItems(),
            const SizedBox(height: AppSpacing.base),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
              onPressed: () =>
                  setState(() => _items.add(_ChallanLineItem())),
            ),
            const SizedBox(height: AppSpacing.base),
            _buildSubtotalRow(),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _SectionHeader('Transport Details'),
                const Spacer(),
                Switch(
                  value: _showTransport,
                  onChanged: (v) =>
                      setState(() => _showTransport = v),
                ),
              ],
            ),
            if (_showTransport) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildTransport(),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader('Notes'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                hintText: 'Optional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _saving
          ? const LinearProgressIndicator()
          : null,
    );
  }

  // ── Section: header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        TextFormField(
          controller: _challanNoCtrl,
          decoration: const InputDecoration(
            labelText: 'Challan No. *',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.base),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Challan Date *',
                value: _challanDate,
                onChanged: (d) => setState(() => _challanDate = d),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: _PurposeDropdown(
                value: _purpose,
                onChanged: (p) => setState(() => _purpose = p!),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Dispatch Date',
                value: _dispatchDate,
                onChanged: (d) => setState(() => _dispatchDate = d),
                optional: true,
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: _DateField(
                label: 'Expected Return',
                value: _expectedReturnDate,
                onChanged: (d) =>
                    setState(() => _expectedReturnDate = d),
                optional: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Section: customer ────────────────────────────────────────────────────────

  Widget _buildCustomer() {
    final partiesAsync = ref.watch(partiesProvider);
    return Column(
      children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _customerNameCtrl.text),
          optionsBuilder: (v) {
            final q = v.text.toLowerCase();
            if (q.isEmpty) return const Iterable.empty();
            return partiesAsync.whenOrNull(
                  data: (list) => list
                      .map((p) => p.name)
                      .where((n) => n.toLowerCase().contains(q)),
                ) ??
                const Iterable.empty();
          },
          onSelected: (name) {
            _customerNameCtrl.text = name;
            final match = partiesAsync.whenOrNull(
              data: (list) => list
                  .where((p) => p.name == name)
                  .firstOrNull,
            );
            if (match != null) {
              setState(() => _customerPartyId = match.id);
            }
          },
          fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
            // Sync external controller changes
            ctrl.text = _customerNameCtrl.text;
            ctrl.addListener(() => _customerNameCtrl.text = ctrl.text);
            return TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            );
          },
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          controller: _customerGstinCtrl,
          decoration: const InputDecoration(
            labelText: 'Customer GSTIN (optional)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          controller: _placeOfSupplyCtrl,
          decoration: const InputDecoration(
            labelText: 'Place of Supply',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  // ── Section: items ───────────────────────────────────────────────────────────

  Widget _buildItems() {
    return Column(
      children: _items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        return _LineItemRow(
          key: ValueKey(idx),
          item: item,
          index: idx,
          onRemove: _items.length > 1
              ? () => setState(() => _items.removeAt(idx))
              : null,
          onChanged: () => setState(() {}),
        );
      }).toList(),
    );
  }

  Widget _buildSubtotalRow() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Subtotal (ex-tax)',
              style: context.textTheme.titleSmall),
          Text(
            '₹${_subtotal.toStringAsFixed(2)}',
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: context.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: transport ───────────────────────────────────────────────────────

  Widget _buildTransport() {
    const modes = {
      '1': 'Road',
      '2': 'Rail',
      '3': 'Air',
      '4': 'Ship',
    };

    return Column(
      children: [
        TextFormField(
          controller: _vehicleNoCtrl,
          decoration: const InputDecoration(
            labelText: 'Vehicle / LR No.',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          controller: _transporterCtrl,
          decoration: const InputDecoration(
            labelText: 'Transporter Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _transportMode,
                decoration: const InputDecoration(
                  labelText: 'Mode',
                  border: OutlineInputBorder(),
                ),
                items: modes.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _transportMode = v ?? '1'),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: TextFormField(
                controller: _distanceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          controller: _ewbNoCtrl,
          decoration: const InputDecoration(
            labelText: 'e-Way Bill No.',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty || _items.every((i) => i.itemName.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one item')));
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final subtotal = _subtotal;

      final challan = DeliveryChallan(
        id: widget.existing?.id,
        challanNo: _challanNoCtrl.text.trim(),
        customerPartyId: _customerPartyId,
        customerName: _customerNameCtrl.text.trim(),
        status: widget.existing?.status ?? ChallanStatus.draft,
        challanDate: _challanDate,
        dispatchDate: _dispatchDate,
        expectedReturnDate: _expectedReturnDate,
        purpose: _purpose,
        subtotal: subtotal,
        notes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        customerGstin: _customerGstinCtrl.text.trim().isEmpty
            ? null
            : _customerGstinCtrl.text.trim(),
        placeOfSupply: _placeOfSupplyCtrl.text.trim().isEmpty
            ? null
            : _placeOfSupplyCtrl.text.trim(),
        vehicleNo: _showTransport && _vehicleNoCtrl.text.trim().isNotEmpty
            ? _vehicleNoCtrl.text.trim()
            : null,
        transporterName:
            _showTransport && _transporterCtrl.text.trim().isNotEmpty
                ? _transporterCtrl.text.trim()
                : null,
        transportMode: _showTransport ? _transportMode : null,
        distanceKm: _showTransport && _distanceCtrl.text.isNotEmpty
            ? int.tryParse(_distanceCtrl.text)
            : null,
        ewbNo:
            _showTransport && _ewbNoCtrl.text.trim().isNotEmpty
                ? _ewbNoCtrl.text.trim()
                : null,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
        items: [], // items attached after insert
      );

      if (widget.existing == null) {
        final created = await ref
            .read(challansProvider.notifier)
            .add(challan);
        // Attach items with the real challanId
        final withItems = created.copyWith(
          items: _items
              .where((i) => i.itemName.trim().isNotEmpty)
              .map((i) => i.toChallanItem(created.id!))
              .toList(),
        );
        await ref.read(challansProvider.notifier).edit(withItems);
      } else {
        final withItems = challan.copyWith(
          items: _items
              .where((i) => i.itemName.trim().isNotEmpty)
              .map((i) => i.toChallanItem(widget.existing!.id!))
              .toList(),
        );
        await ref.read(challansProvider.notifier).edit(withItems);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Line item row ─────────────────────────────────────────────────────────────

class _LineItemRow extends StatefulWidget {
  const _LineItemRow({
    super.key,
    required this.item,
    required this.index,
    this.onRemove,
    required this.onChanged,
  });

  final _ChallanLineItem item;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  State<_LineItemRow> createState() => _LineItemRowState();
}

class _LineItemRowState extends State<_LineItemRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _hsnCtrl;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i.itemName);
    _descCtrl = TextEditingController(text: i.description);
    _qtyCtrl = TextEditingController(
        text: i.qty == 1 ? '1' : i.qty.toString());
    _unitCtrl = TextEditingController(text: i.unit);
    _priceCtrl = TextEditingController(
        text: i.unitPrice == 0 ? '' : i.unitPrice.toString());
    _hsnCtrl = TextEditingController(text: i.hsnCode);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _hsnCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    widget.item.itemName = _nameCtrl.text;
    widget.item.description = _descCtrl.text;
    widget.item.qty = double.tryParse(_qtyCtrl.text) ?? 1;
    widget.item.unit = _unitCtrl.text.isEmpty ? 'PCS' : _unitCtrl.text;
    widget.item.unitPrice = double.tryParse(_priceCtrl.text) ?? 0;
    widget.item.hsnCode = _hsnCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Item Name *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _sync(),
                    validator: (v) => (widget.index == 0 &&
                            (v == null || v.trim().isEmpty))
                        ? 'Required'
                        : null,
                  ),
                ),
                if (widget.onRemove != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: context.colorScheme.error,
                    onPressed: widget.onRemove,
                    tooltip: 'Remove item',
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _sync(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Qty *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,3}')),
                    ],
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _unitCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rate *',
                      prefixText: '₹',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    controller: _hsnCtrl,
                    decoration: const InputDecoration(
                      labelText: 'HSN',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Line Total: ₹${widget.item.lineTotal.toStringAsFixed(2)}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Utility widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: context.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: context.colorScheme.primary,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.optional = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: AbsorbPointer(
        child: TextFormField(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
          ),
          controller: TextEditingController(
            text: value != null
                ? DateFormatter.formatFull(value!)
                : (optional ? '' : DateFormatter.formatFull(DateTime.now())),
          ),
          validator: optional
              ? null
              : (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
        ),
      ),
    );
  }
}

class _PurposeDropdown extends StatelessWidget {
  const _PurposeDropdown({required this.value, required this.onChanged});

  final ChallanPurpose value;
  final ValueChanged<ChallanPurpose?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ChallanPurpose>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'Purpose',
        border: OutlineInputBorder(),
      ),
      items: ChallanPurpose.values
          .map((p) =>
              DropdownMenuItem(value: p, child: Text(p.label)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
