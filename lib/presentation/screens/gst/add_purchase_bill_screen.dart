import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/indian_states.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/purchase_bill.dart';
import '../../../data/services/gst_calculator.dart';
import '../../providers/business_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/purchase_bill_provider.dart';
import '../../widgets/party_picker_field.dart';
import '../../../data/models/item_catalog.dart';

// ── Local line-item state ─────────────────────────────────────────────────────

class _LineItem {
  _LineItem({
    String? itemName,
    double qty = 1,
    double unitPrice = 0,
    double taxPct = 18,
    double discountPct = 0,
    String hsnCode = '',
    String unit = 'PCS',
    String hsnOrSac = 'HSN',
  })  : itemNameCtrl = TextEditingController(text: itemName ?? ''),
        qtyCtrl = TextEditingController(text: qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString()),
        unitPriceCtrl = TextEditingController(text: unitPrice == 0 ? '' : unitPrice.toString()),
        taxPctCtrl = TextEditingController(text: taxPct == taxPct.truncateToDouble() ? taxPct.toInt().toString() : taxPct.toString()),
        discountPctCtrl = TextEditingController(text: discountPct == 0 ? '' : discountPct.toString()),
        hsnCodeCtrl = TextEditingController(text: hsnCode),
        unitCtrl = TextEditingController(text: unit),
        _hsnOrSac = hsnOrSac;

  final TextEditingController itemNameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController unitPriceCtrl;
  final TextEditingController taxPctCtrl;
  final TextEditingController discountPctCtrl;
  final TextEditingController hsnCodeCtrl;
  final TextEditingController unitCtrl;
  final String _hsnOrSac;

  double get qty => double.tryParse(qtyCtrl.text) ?? 1;
  double get unitPrice => double.tryParse(unitPriceCtrl.text) ?? 0;
  double get taxPct => double.tryParse(taxPctCtrl.text) ?? 0;
  double get discountPct => double.tryParse(discountPctCtrl.text) ?? 0;
  double get taxableAmount => _round2(qty * unitPrice * (1 - discountPct / 100));

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  void dispose() {
    itemNameCtrl.dispose();
    qtyCtrl.dispose();
    unitPriceCtrl.dispose();
    taxPctCtrl.dispose();
    discountPctCtrl.dispose();
    hsnCodeCtrl.dispose();
    unitCtrl.dispose();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AddPurchaseBillScreen extends ConsumerStatefulWidget {
  const AddPurchaseBillScreen({super.key, this.billId});

  /// When non-null, screen loads the existing bill for editing.
  final int? billId;

  @override
  ConsumerState<AddPurchaseBillScreen> createState() =>
      _AddPurchaseBillScreenState();
}

class _AddPurchaseBillScreenState
    extends ConsumerState<AddPurchaseBillScreen> {
  // ── Form key ────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  // ── Header controllers ───────────────────────────────────────────────────────
  late final TextEditingController _billNoCtrl;
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _vendorGstinCtrl;
  late final TextEditingController _notesCtrl;

  // ── Header state ─────────────────────────────────────────────────────────────
  int? _selectedBusinessId;
  int? _vendorPartyId;
  DateTime _billDate = DateTime.now();
  DateTime? _dueDate;
  String? _placeOfSupply;
  bool _reverseCharge = false;
  ItcEligibility _itcEligibility = ItcEligibility.eligible;
  ItcBlockReason? _itcBlockReason;

  // ── Line items ───────────────────────────────────────────────────────────────
  final List<_LineItem> _items = [];

  // ── Save state ───────────────────────────────────────────────────────────────
  bool _isSaving = false;

  // ── GST rate presets ─────────────────────────────────────────────────────────
  static const _gstRates = [0.0, 5.0, 12.0, 18.0, 28.0];

  @override
  void initState() {
    super.initState();
    _billNoCtrl = TextEditingController();
    _vendorCtrl = TextEditingController();
    _vendorGstinCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _items.add(_LineItem()); // start with one empty line
    // Auto-fill place of supply from business registration state.
    // User can still override it for inter-state purchases.
    _selectedBusinessId = ref.read(activeBusinessProvider)?.id;
    _placeOfSupply ??= ref.read(activeBusinessProvider)?.state;
  }

  @override
  void dispose() {
    _billNoCtrl.dispose();
    _vendorCtrl.dispose();
    _vendorGstinCtrl.dispose();
    _notesCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // ── Derived totals ──────────────────────────────────────────────────────────

  String? get _businessState {
    final businesses = ref.read(businessesProvider).valueOrNull ?? [];
    return businesses
        .where((b) => b.id == _selectedBusinessId)
        .firstOrNull
        ?.state;
  }

  ({
    double subtotal,
    double igst,
    double cgst,
    double sgst,
    double total,
  }) get _totals {
    double subtotal = 0, igst = 0, cgst = 0, sgst = 0;
    for (final item in _items) {
      final taxable = item.taxableAmount;
      subtotal += taxable;
      final split = GstCalculator.calculate(
        sellerState: _placeOfSupply,
        buyerState: _businessState,
        taxableAmount: taxable,
        gstPct: item.taxPct,
      );
      igst += split.igst;
      cgst += split.cgst;
      sgst += split.sgst;
    }
    return (
      subtotal: _r2(subtotal),
      igst: _r2(igst),
      cgst: _r2(cgst),
      sgst: _r2(sgst),
      total: _r2(subtotal + igst + cgst + sgst),
    );
  }

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty ||
        _items.every((i) => i.itemNameCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item.')),
      );
      return;
    }

    final businesses = ref.read(businessesProvider).valueOrNull ?? [];
    final business =
        businesses.where((b) => b.id == _selectedBusinessId).firstOrNull;
    if (business == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No active business. Set up your business first.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final t = _totals;
      final now = DateTime.now();
      final bill = PurchaseBill(
        businessId: business.id!,
        billNo: _billNoCtrl.text.trim(),
        vendorPartyId: _vendorPartyId,
        vendorName: _vendorCtrl.text.trim(),
        vendorGstin:
            _vendorGstinCtrl.text.trim().isEmpty ? null : _vendorGstinCtrl.text.trim(),
        billDate: _billDate,
        dueDate: _dueDate,
        placeOfSupply: _placeOfSupply,
        reverseCharge: _reverseCharge,
        subtotal: t.subtotal,
        igstAmount: t.igst,
        cgstAmount: t.cgst,
        sgstAmount: t.sgst,
        cessAmount: 0,
        taxTotal: t.igst + t.cgst + t.sgst,
        total: t.total,
        paidAmount: 0,
        itcEligibility: _itcEligibility,
        itcBlockReason: _itcBlockReason,
        itcAvailed: false,
        status: PurchaseBillStatus.unpaid,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdAt: now,
        updatedAt: now,
      );

      final billItems = <PurchaseBillItem>[];
      for (final item in _items) {
        final name = item.itemNameCtrl.text.trim();
        if (name.isEmpty) continue;
        final taxable = item.taxableAmount;
        final split = GstCalculator.calculate(
          sellerState: _placeOfSupply,
          buyerState: _businessState,
          taxableAmount: taxable,
          gstPct: item.taxPct,
        );
        billItems.add(PurchaseBillItem(
          billId: 0,
          itemName: name,
          qty: item.qty,
          unitPrice: item.unitPrice,
          taxPct: item.taxPct,
          discountPct: item.discountPct,
          lineTotal: taxable,
          igstAmount: split.igst,
          cgstAmount: split.cgst,
          sgstAmount: split.sgst,
          hsnCode:
              item.hsnCodeCtrl.text.trim().isEmpty ? null : item.hsnCodeCtrl.text.trim(),
          unit: item.unitCtrl.text.trim().isEmpty ? 'PCS' : item.unitCtrl.text.trim(),
          hsnOrSac: item._hsnOrSac,
        ));
      }

      await ref
          .read(purchaseBillsProvider.notifier)
          .add(bill, billItems);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving bill: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Date pickers ────────────────────────────────────────────────────────────

  Future<void> _pickBillDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _billDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _billDate.add(const Duration(days: 30)),
      firstDate: _billDate,
      lastDate: DateTime(2099),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KashCubeColors>()!;
    final allBusinesses = ref.watch(businessesProvider).valueOrNull ?? [];
    final catalog = ref.watch(catalogProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.billId == null ? 'Add Purchase Bill' : 'Edit Purchase Bill'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.base),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('SAVE'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // ── Business selector ─────────────────────────────────────────
            if (allBusinesses.isNotEmpty) ...[
              DropdownButtonFormField<int>(
                initialValue: _selectedBusinessId,
                decoration: const InputDecoration(
                  labelText: 'Business',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                items: allBusinesses.map((biz) {
                  return DropdownMenuItem(
                    value: biz.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(biz.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        if (biz.gstNo != null)
                          Text(
                            'GST: ${biz.gstNo}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
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
                    // Update place of supply to match the new business's state
                    final biz = allBusinesses
                        .where((b) => b.id == value)
                        .firstOrNull;
                    if (biz != null) _placeOfSupply = biz.state;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.base),
            ],

            // ── Bill header ────────────────────────────────────────────────
            _SectionHeader(label: 'Bill Details'),
            const SizedBox(height: AppSpacing.sm),

            // Bill number
            TextFormField(
              controller: _billNoCtrl,
              decoration: const InputDecoration(
                labelText: 'Bill / Invoice Number *',
                hintText: 'e.g. INV-2024-001',
                prefixIcon: Icon(Icons.receipt_outlined),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.base),

            // Vendor picker
            PartyPickerField(
              controller: _vendorCtrl,
              labelText: 'Vendor / Supplier *',
              hintText: 'Select or type vendor name',
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              onSelected: (_) => setState(() {}),
              onPartySelected: (party) => setState(() {
                _vendorPartyId = party.id;
                if (party.gstin != null && party.gstin!.isNotEmpty) {
                  _vendorGstinCtrl.text = party.gstin!;
                }
              }),
            ),
            const SizedBox(height: AppSpacing.base),

            // Vendor GSTIN
            TextFormField(
              controller: _vendorGstinCtrl,
              decoration: const InputDecoration(
                labelText: 'Vendor GSTIN (optional)',
                hintText: 'e.g. 27AAAAA0000A1Z5',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              textInputAction: TextInputAction.next,
              buildCounter: (_, {currentLength = 0, maxLength, isFocused = false}) => null,
            ),
            const SizedBox(height: AppSpacing.base),

            // Bill date + Due date row
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: 'Bill Date *',
                    date: _billDate,
                    onTap: _pickBillDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DateTile(
                    label: 'Due Date',
                    date: _dueDate,
                    onTap: _pickDueDate,
                    suffix: _dueDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _dueDate = null),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),

            // Place of Supply
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Place of Supply',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              value: _placeOfSupply,
              hint: const Text('(auto from business state)'),
              isExpanded: true,
              items: kIndianStates
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _placeOfSupply = v),
            ),
            const SizedBox(height: AppSpacing.base),

            // Reverse charge toggle
            _ToggleTile(
              label: 'Reverse Charge (RCM)',
              subtitle: 'You pay GST instead of vendor',
              value: _reverseCharge,
              onChanged: (v) => setState(() => _reverseCharge = v),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Line items ─────────────────────────────────────────────────
            Row(
              children: [
                _SectionHeader(label: 'Line Items'),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                  onPressed: () => setState(() => _items.add(_LineItem())),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _LineItemCard(
                key: ValueKey(item),
                item: item,
                index: index,
                gstRates: _gstRates,
                businessState: _businessState,
                placeOfSupply: _placeOfSupply,
                catalog: catalog,
                onChanged: () => setState(() {}),
                onCatalogApply: (ci) {
                  item.itemNameCtrl.text = ci.name;
                  if (ci.unitPrice > 0) {
                    item.unitPriceCtrl.text = ci.unitPrice
                        .toStringAsFixed(ci.unitPrice == ci.unitPrice.truncateToDouble() ? 0 : 2);
                  }
                  item.taxPctCtrl.text = ci.taxPct == ci.taxPct.truncateToDouble()
                      ? ci.taxPct.toInt().toString()
                      : ci.taxPct.toString();
                  item.hsnCodeCtrl.text = ci.hsnCode ?? '';
                  item.unitCtrl.text = ci.unit.toUpperCase();
                  setState(() {});
                },
                onRemove: _items.length > 1
                    ? () => setState(() {
                          item.dispose();
                          _items.removeAt(index);
                        })
                    : null,
              );
            }),

            const SizedBox(height: AppSpacing.xl),

            // ── Totals strip ───────────────────────────────────────────────
            _TotalsCard(totals: _totals, colors: colors),

            const SizedBox(height: AppSpacing.xl),

            // ── ITC section ────────────────────────────────────────────────
            _SectionHeader(label: 'Input Tax Credit (ITC)'),
            const SizedBox(height: AppSpacing.sm),

            // ITC eligibility
            DropdownButtonFormField<ItcEligibility>(
              decoration: const InputDecoration(
                labelText: 'ITC Eligibility',
                prefixIcon: Icon(Icons.verified_outlined),
              ),
              value: _itcEligibility,
              items: const [
                DropdownMenuItem(
                  value: ItcEligibility.eligible,
                  child: Text('Eligible'),
                ),
                DropdownMenuItem(
                  value: ItcEligibility.blocked,
                  child: Text('Blocked (Sec. 17(5))'),
                ),
                DropdownMenuItem(
                  value: ItcEligibility.ineligible,
                  child: Text('Ineligible'),
                ),
              ],
              onChanged: (v) => setState(() {
                _itcEligibility = v ?? ItcEligibility.eligible;
                if (_itcEligibility != ItcEligibility.blocked) {
                  _itcBlockReason = null;
                }
              }),
            ),

            // Block reason (only when blocked)
            if (_itcEligibility == ItcEligibility.blocked) ...[
              const SizedBox(height: AppSpacing.base),
              DropdownButtonFormField<ItcBlockReason>(
                decoration: const InputDecoration(
                  labelText: 'Block Reason *',
                  prefixIcon: Icon(Icons.block_outlined),
                ),
                value: _itcBlockReason,
                hint: const Text('Select reason'),
                validator: (v) => v == null ? 'Required when blocked' : null,
                items: ItcBlockReason.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(_blockReasonLabel(r)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _itcBlockReason = v),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Notes ──────────────────────────────────────────────────────
            _SectionHeader(label: 'Notes'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                hintText: 'Internal notes (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  String _blockReasonLabel(ItcBlockReason r) {
    switch (r) {
      case ItcBlockReason.motorVehicle:
        return 'Motor vehicle / conveyance';
      case ItcBlockReason.foodBeverages:
        return 'Food, beverages & outdoor catering';
      case ItcBlockReason.clubMembership:
        return 'Club & health centre membership';
      case ItcBlockReason.personalUse:
        return 'Personal use';
      case ItcBlockReason.construction:
        return 'Construction of immovable property';
      case ItcBlockReason.worksContract:
        return 'Works contract for immovable property';
      case ItcBlockReason.other:
        return 'Other';
    }
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
    this.suffix,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          suffix: suffix,
          contentPadding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        ),
        child: Text(
          date != null ? DateFormatter.formatFull(date!) : '—',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: SwitchListTile(
        title: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
        dense: true,
      ),
    );
  }
}

// ── Line item card ────────────────────────────────────────────────────────────

class _LineItemCard extends StatelessWidget {
  const _LineItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.gstRates,
    required this.businessState,
    required this.placeOfSupply,
    required this.catalog,
    required this.onChanged,
    required this.onCatalogApply,
    this.onRemove,
  });

  final _LineItem item;
  final int index;
  final List<double> gstRates;
  final String? businessState;
  final String? placeOfSupply;
  final List<ItemCatalog> catalog;
  final VoidCallback onChanged;
  final ValueChanged<ItemCatalog> onCatalogApply;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final taxable = item.taxableAmount;
    final split = GstCalculator.calculate(
      sellerState: placeOfSupply,
      buyerState: businessState,
      taxableAmount: taxable,
      gstPct: item.taxPct,
    );
    final theme = Theme.of(context);

    return Card.outlined(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: item # + catalog picker + remove button
            Row(
              children: [
                Text('Item ${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (catalog.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.library_books_outlined, size: 20),
                    tooltip: 'Pick from Item Catalog',
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.secondary,
                    onPressed: () async {
                      final picked = await showModalBottomSheet<ItemCatalog>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(AppSpacing.radiusLg)),
                        ),
                        builder: (_) => _CatalogPickerSheet(catalog: catalog),
                      );
                      if (picked != null) onCatalogApply(picked);
                    },
                  ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Item name
            TextFormField(
              controller: item.itemNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Item / Service Name *',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.sm),

            // Qty × Unit Price row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: item.qtyCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Qty', isDense: true),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,3}'))
                    ],
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: item.unitPriceCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Unit Price ₹', isDense: true),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'))
                    ],
                    onChanged: (_) => onChanged(),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: item.discountPctCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Disc %', isDense: true),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'))
                    ],
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // GST rate row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<double>(
                    decoration: const InputDecoration(
                        labelText: 'GST %', isDense: true),
                    value: gstRates.contains(item.taxPct) ? item.taxPct : null,
                    hint: const Text('Custom'),
                    isExpanded: true,
                    items: gstRates
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text('${r.toInt()}%'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        item.taxPctCtrl.text = v.toInt().toString();
                        onChanged();
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: item.hsnCodeCtrl,
                    decoration: const InputDecoration(
                        labelText: 'HSN/SAC', isDense: true),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: item.unitCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Unit', isDense: true),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Line totals chip row
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _AmountChip(
                    label: 'Taxable', amount: taxable, color: theme.colorScheme.primary),
                if (split.cgst > 0) ...[
                  _AmountChip(
                      label: 'CGST', amount: split.cgst, color: Colors.blue.shade700),
                  _AmountChip(
                      label: 'SGST', amount: split.sgst, color: Colors.teal.shade700),
                ],
                if (split.igst > 0)
                  _AmountChip(
                      label: 'IGST', amount: split.igst, color: Colors.deepPurple),
                _AmountChip(
                    label: 'Line Total',
                    amount: taxable + split.total,
                    color: theme.colorScheme.onSurface,
                    bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.amount,
    required this.color,
    this.bold = false,
  });

  final String label;
  final double amount;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
                text: CurrencyFormatter.format(amount, showDecimals: true),
                style: const TextStyle(fontFamily: 'RobotoMono')),
          ],
        ),
      ),
    );
  }
}

// ── Totals card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.colors});

  final ({
    double subtotal,
    double igst,
    double cgst,
    double sgst,
    double total,
  }) totals;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasIgst = totals.igst > 0;
    final hasCgstSgst = totals.cgst > 0;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _TotalRow(
                label: 'Subtotal (taxable)',
                amount: totals.subtotal,
                style: theme.textTheme.bodyMedium),
            if (hasCgstSgst) ...[
              _TotalRow(
                  label: 'CGST',
                  amount: totals.cgst,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.blue.shade700)),
              _TotalRow(
                  label: 'SGST',
                  amount: totals.sgst,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.teal.shade700)),
            ],
            if (hasIgst)
              _TotalRow(
                  label: 'IGST',
                  amount: totals.igst,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.deepPurple)),
            const Divider(),
            _TotalRow(
              label: 'Total',
              amount: totals.total,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount, this.style});
  final String label;
  final double amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(CurrencyFormatter.format(amount, showDecimals: true),
              style: style?.copyWith(fontFamily: 'RobotoMono')),
        ],
      ),
    );
  }
}

// ── Catalog picker bottom sheet ───────────────────────────────────────────────

class _CatalogPickerSheet extends StatefulWidget {
  const _CatalogPickerSheet({required this.catalog});
  final List<ItemCatalog> catalog;

  @override
  State<_CatalogPickerSheet> createState() => _CatalogPickerSheetState();
}

class _CatalogPickerSheetState extends State<_CatalogPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.catalog
        .where((c) => c.isActive)
        .where((c) =>
            _query.isEmpty ||
            c.name.toLowerCase().contains(_query.toLowerCase()) ||
            (c.hsnCode?.contains(_query) ?? false))
        .toList()
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Text('Pick from Item Catalog',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          // List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No items found',
                        style: TextStyle(color: theme.colorScheme.outline)),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Icon(
                            item.category == ItemCategory.service ||
                                    item.category == ItemCategory.labor
                                ? Icons.design_services_outlined
                                : Icons.inventory_2_outlined,
                            size: 18,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                        title: Text(item.name,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          [
                            if (item.hsnCode != null && item.hsnCode!.isNotEmpty)
                              '${item.hsnOrSac}: ${item.hsnCode}',
                            '${item.taxPct.toInt()}% GST',
                            item.unit.toUpperCase(),
                          ].join(' · '),
                          style: TextStyle(
                              color: theme.colorScheme.outline, fontSize: 12),
                        ),
                        trailing: Text(
                          CurrencyFormatter.format(item.unitPrice),
                          style: TextStyle(
                              fontFamily: 'RobotoMono',
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary),
                        ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
