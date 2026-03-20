import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/hsn_entry.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/services/hsn_search_service.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/unit_type_provider.dart';

class ItemCatalogScreen extends ConsumerStatefulWidget {
  /// When [pickMode] is true, tapping an item pops with the selected [ItemCatalog].
  ///
  /// Pass [initialEditItem] to auto-open the edit form for a specific item on load
  /// (e.g. deep-linked from the Inventory screen).
  const ItemCatalogScreen({
    super.key,
    this.pickMode = false,
    this.initialEditItem,
  });
  final bool pickMode;
  final ItemCatalog? initialEditItem;

  @override
  ConsumerState<ItemCatalogScreen> createState() =>
      _ItemCatalogScreenState();
}

class _ItemCatalogScreenState extends ConsumerState<ItemCatalogScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  ItemCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    if (widget.initialEditItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showItemSheet(context, item: widget.initialEditItem);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider);

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.pickMode ? 'Pick Item' : 'Item Catalog'),
        actions: [
          if (widget.pickMode)
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Create New'),
              onPressed: () => _showItemSheet(context),
            )
          else
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Item',
              onPressed: () => _showItemSheet(context),
            ),
        ],
      ),
      floatingActionButton: widget.pickMode
          ? null
          : FloatingActionButton(
              heroTag: 'catalog_fab',
              onPressed: () => _showItemSheet(context),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.base,
                AppSpacing.sm, AppSpacing.base, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          // Category filter chips
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _categoryFilter == null,
                    onSelected: (_) => setState(() => _categoryFilter = null),
                  ),
                ),
                ...ItemCategory.values.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(cat.pluralLabel),
                    selected: _categoryFilter == cat,
                    onSelected: (_) => setState(() => _categoryFilter = cat),
                  ),
                )),
              ],
            ),
          ),
          Expanded(
            child: catalogAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error: $e')),
              data: (items) {
                // Apply filters: search + category
                var filtered = items;
                
                // Search filter
                if (_search.isNotEmpty) {
                  filtered = filtered
                      .where((i) =>
                          i.name.toLowerCase().contains(
                              _search.toLowerCase()) ||
                          (i.description ?? '')
                              .toLowerCase()
                              .contains(_search.toLowerCase()))
                      .toList();
                }
                
                // Category filter
                if (_categoryFilter != null) {
                  filtered = filtered
                      .where((i) => i.category == _categoryFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return _EmptyState(
                    pickMode: widget.pickMode,
                    hasSearch: _search.isNotEmpty,
                    onAdd: () => _showItemSheet(context),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.sm, bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _CatalogTile(
                    item: filtered[i],
                    pickMode: widget.pickMode,
                    onPick: () =>
                        Navigator.pop(context, filtered[i]),
                    onEdit: () =>
                        _showItemSheet(context, item: filtered[i]),
                    onDelete: () => _confirmDelete(
                        context, ref, filtered[i]),
                    onToggleTracking: () => ref
                        .read(catalogProvider.notifier)
                        .edit(filtered[i].copyWith(
                            trackInventory: !filtered[i].trackInventory,
                            updatedAt: DateTime.now())),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showItemSheet(BuildContext context,
      {ItemCatalog? item}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemFormSheet(
        item: item,
        onSave: (updated) async {
          if (item == null) {
            await ref.read(catalogProvider.notifier).add(updated);
          } else {
            await ref.read(catalogProvider.notifier).edit(updated);
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ItemCatalog item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Item?'),
        content: Text(
            '"${item.name}" will be removed from the catalog.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(catalogProvider.notifier).remove(item.id!);
    }
  }
}

// ── Catalog Tile ──────────────────────────────────────────────────────────────

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.item,
    required this.pickMode,
    required this.onPick,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleTracking,
  });

  final ItemCatalog item;
  final bool pickMode;
  final VoidCallback onPick;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleTracking;

  Color _stockColor(BuildContext context) {
    if (item.stockQty <= 0) return Theme.of(context).colorScheme.error;
    if (item.isLowStock) return Colors.orange.shade700;
    return Theme.of(context).colorScheme.secondary;
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                item.trackInventory
                    ? Icons.inventory_2_outlined
                    : Icons.inventory_2,
              ),
              title: Text(item.trackInventory
                  ? 'Disable Stock Tracking'
                  : 'Enable Stock Tracking'),
              onTap: () {
                Navigator.pop(context);
                onToggleTracking();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Item'),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: pickMode ? onPick : onEdit,
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.inventory_2_outlined,
            color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(item.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (item.description != null) item.description!,
          item.unit,
          if (item.hsnCode != null) '${item.hsnOrSac}: ${item.hsnCode}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(item.unitPrice),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (item.taxPct > 0)
            Text(
              'GST ${item.taxPct.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline),
            ),
          if (item.trackInventory)
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + 2, vertical: 1),
              decoration: BoxDecoration(
                color: _stockColor(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                    color: _stockColor(context).withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 10, color: _stockColor(context)),
                  const SizedBox(width: 3),
                  Text(
                    item.stockQty <= 0
                        ? 'Out of stock'
                        : '${item.stockQty % 1 == 0 ? item.stockQty.toInt() : item.stockQty} ${item.unit.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _stockColor(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      onLongPress: pickMode ? null : () => _showActions(context),
    );
  }
}

// ── Item Form Sheet ───────────────────────────────────────────────────────────

class _ItemFormSheet extends ConsumerStatefulWidget {
  const _ItemFormSheet({this.item, required this.onSave});
  final ItemCatalog? item;
  final Future<void> Function(ItemCatalog) onSave;

  @override
  ConsumerState<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends ConsumerState<_ItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _hsnCtrl;
  late String _hsnOrSac;
  late String _selectedUnit;
  late ItemCategory _category;
  late bool _isFavorite;
  late bool _trackInventory;
  late bool _isBookable;
  late int _durationMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _descCtrl =
        TextEditingController(text: item?.description ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? '');
    _selectedUnit = item?.unit ?? 'PCS';
    _priceCtrl = TextEditingController(
        text: item == null ? '' : item.unitPrice.toStringAsFixed(2));
    _taxCtrl = TextEditingController(
        text: item == null
            ? ''
            : (item.taxPct == 0
                ? ''
                : item.taxPct.toStringAsFixed(1)));
    _hsnCtrl = TextEditingController(text: item?.hsnCode ?? '');
    _category = item?.category ?? ItemCategory.product;
    _hsnOrSac = item?.hsnOrSac ?? _defaultHsnOrSac(_category);
    _isFavorite = item?.isFavorite ?? false;
    // For new items, default trackInventory based on category.
    // Existing items preserve whatever the user previously set.
    _trackInventory = item?.trackInventory ?? _trackInventoryDefault(_category);
    _isBookable = item?.isBookable ?? false;
    _durationMinutes = item?.durationMinutes ?? 30;
    
    // Auto-generate SKU for new items
    if (item == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final sku = await ref
            .read(catalogProvider.notifier)
            .generateNextSku(_category);
        if (mounted) {
          _skuCtrl.text = sku;
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _descCtrl,
      _skuCtrl,
      _priceCtrl,
      _taxCtrl,
      _hsnCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final item = ItemCatalog(
      id: widget.item?.id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      sku: _skuCtrl.text.trim().isEmpty
          ? null
          : _skuCtrl.text.trim(),
      unit: _selectedUnit.isEmpty ? 'PCS' : _selectedUnit,
      unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
      taxPct: double.tryParse(_taxCtrl.text) ?? 0,
      hsnCode: _hsnCtrl.text.trim().isEmpty
          ? null
          : _hsnCtrl.text.trim(),
      hsnOrSac: _hsnOrSac,
      category: _category,
      isFavorite: _isFavorite,
      trackInventory: _trackInventory,
      isBookable: _isBookable,
      durationMinutes: _isBookable ? _durationMinutes : null,
      createdAt: widget.item?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.onSave(item);
    if (mounted) Navigator.pop(context);
  }

  /// Returns the default HSN/SAC code type for a given item category.
  String _defaultHsnOrSac(ItemCategory cat) =>
      (cat == ItemCategory.service || cat == ItemCategory.labor)
          ? 'SAC'
          : 'HSN';

  /// Physical categories default to tracking on; intangible ones default off.
  bool _trackInventoryDefault(ItemCategory cat) =>
      cat == ItemCategory.product ||
      cat == ItemCategory.material ||
      cat == ItemCategory.equipment;

  bool _isAutoGeneratedSku(String sku) {
    // Check if SKU matches auto-generated pattern: PREFIX-NNN
    final pattern = RegExp(r'^(PROD|SERV|MATL|LABR|EQUP|OTHR)-\d{3}$');
    return pattern.hasMatch(sku);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item == null ? 'Add Item' : 'Edit Item',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _skuCtrl,
                decoration: const InputDecoration(
                  labelText: 'SKU / Item Code',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., PROD-001',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ItemCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ItemCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat.label),
                  );
                }).toList(),
                onChanged: (val) async {
                  if (val != null) {
                    setState(() {
                      _category = val;
                      // Auto-switch HSN/SAC type based on new category
                      _hsnOrSac = _defaultHsnOrSac(val);
                      // Sync inventory tracking default with new category
                      _trackInventory = _trackInventoryDefault(val);
                    });
                    // Auto-update SKU if it's still in auto-generated format
                    if (_isAutoGeneratedSku(_skuCtrl.text)) {
                      final newSku = await ref
                          .read(catalogProvider.notifier)
                          .generateNextSku(val);
                      if (mounted) {
                        _skuCtrl.text = newSku;
                      }
                    }
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _UnitDropdown(
                      value: _selectedUnit,
                      onChanged: (v) => setState(() => _selectedUnit = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'HSN', label: Text('HSN')),
                            ButtonSegment(value: 'SAC', label: Text('SAC')),
                          ],
                          selected: {_hsnOrSac},
                          onSelectionChanged: (s) => setState(() {
                            _hsnOrSac = s.first;
                            _hsnCtrl.clear();
                          }),
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _HsnSearchField(
                          key: ValueKey(_hsnOrSac),
                          type: _hsnOrSac,
                          initialCode: _hsnCtrl.text,
                          onSelected: (entry) => setState(() {
                            _hsnCtrl.text = entry.code;
                          }),
                        ),
                      ],
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
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Unit Price (₹) *',
                        border: OutlineInputBorder(),
                        prefixText: '₹',
                      ),
                      validator: (v) =>
                          (double.tryParse(v ?? '') == null)
                              ? 'Enter valid amount'
                              : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _taxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'GST %',
                        border: OutlineInputBorder(),
                        suffixText: '%',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _isFavorite,
                onChanged: (val) => setState(() => _isFavorite = val),
                title: const Text('Mark as Favorite'),
                subtitle: const Text('Show this item at the top of the list'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _trackInventory,
                onChanged: (val) => setState(() => _trackInventory = val),
                title: const Text('Track Inventory'),
                subtitle: const Text('Monitor stock levels and get low-stock alerts'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _isBookable,
                onChanged: (val) => setState(() => _isBookable = val),
                title: const Text('Enable Bookings'),
                subtitle: const Text('Allow customers to book this service'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_isBookable) ...[
                const SizedBox(height: AppSpacing.sm),
                _DurationPicker(
                  initialMinutes: _durationMinutes,
                  onChanged: (minutes) => setState(() => _durationMinutes = minutes),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.item == null ? 'Add Item' : 'Save'),
              ),
              const SizedBox(height: AppSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.pickMode,
      required this.hasSearch,
      required this.onAdd});
  final bool pickMode;
  final bool hasSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text(
              hasSearch ? 'No items found' : 'Catalog is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasSearch
                  ? 'Try a different search.'
                  : pickMode
                      ? 'Create your first item to get started.'
                      : 'Add products or services you frequently bill.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(pickMode ? 'Create Item' : 'Add First Item'),
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Duration Picker ───────────────────────────────────────────────────────────

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.initialMinutes,
    required this.onChanged,
  });

  final int initialMinutes;
  final ValueChanged<int> onChanged;

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else if (minutes % 60 == 0) {
      return '${minutes ~/ 60} hr${minutes > 60 ? 's' : ''}';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Common preset durations
    final presets = [15, 30, 45, 60, 90, 120, 180, 240];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Service Duration',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: presets.map((minutes) {
            final isSelected = initialMinutes == minutes;
            return ChoiceChip(
              label: Text(_formatDuration(minutes)),
              selected: isSelected,
              onSelected: (_) => onChanged(minutes),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          initialValue: presets.contains(initialMinutes) 
              ? '' 
              : initialMinutes.toString(),
          decoration: InputDecoration(
            labelText: 'Custom Duration (minutes)',
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: 'e.g., 75',
            helperText: 'For multi-day services, use minutes (e.g., 2880 = 2 days)',
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            final minutes = int.tryParse(value);
            if (minutes != null && minutes > 0) {
              onChanged(minutes);
            }
          },
        ),
      ],
    );
  }
}

// Public helper — call from anywhere (e.g. speed-dial FAB)
/// Opens the Add Item bottom-sheet without navigating to [ItemCatalogScreen].
Future<void> showAddItemSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ItemFormSheet(
      onSave: (item) => ref.read(catalogProvider.notifier).add(item),
    ),
  );
}

// ── HSN / SAC Search Field ───────────────────────────────────────────────────

/// Autocomplete text field that searches [hsn_master] as the user types.
///
/// On selection the [onSelected] callback receives the chosen [HsnEntry].
/// The field always shows the [initialCode] as its starting text.
class _HsnSearchField extends StatefulWidget {
  const _HsnSearchField({
    super.key,
    required this.type,
    required this.onSelected,
    this.initialCode = '',
  });

  /// 'HSN' or 'SAC'
  final String type;
  final ValueChanged<HsnEntry> onSelected;
  final String initialCode;

  @override
  State<_HsnSearchField> createState() => _HsnSearchFieldState();
}

class _HsnSearchFieldState extends State<_HsnSearchField> {
  @override
  Widget build(BuildContext context) {
    return Autocomplete<HsnEntry>(
      initialValue: TextEditingValue(text: widget.initialCode),
      optionsBuilder: (textEditingValue) async {
        final q = textEditingValue.text.trim();
        if (q.isEmpty) return [];
        return HsnSearchService.instance
            .search(q, type: widget.type);
      },
      displayStringForOption: (e) => e.code,
      fieldViewBuilder: (context, ctrl, focusNode, onSubmit) =>
          TextFormField(
            controller: ctrl,
            focusNode: focusNode,
            onFieldSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: '${widget.type} Code',
              border: const OutlineInputBorder(),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        ctrl.clear();
                        // Propagate empty selection back to parent.
                        widget.onSelected(
                          HsnEntry(
                            code: '',
                            description: '',
                            isSac: widget.type == 'SAC',
                          ),
                        );
                      },
                    )
                  : null,
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final entry = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      entry.code,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      entry.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(entry),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: widget.onSelected,
    );
  }
}

// ── Unit Dropdown ─────────────────────────────────────────────────────────────

/// Dropdown that lists managed unit types from [unitTypesProvider].
/// If [value] is not in the list (legacy item), it's added as a dynamic option.
class _UnitDropdown extends ConsumerWidget {
  const _UnitDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitTypesProvider);
    // storageValue = code for GST units, label for non-GST
    final values = units.map((u) => u.storageValue).toList();
    final displays = units.map((u) => u.displayLabel).toList();

    // If existing item has a unit not in the managed list (legacy), surface it
    if (value.isNotEmpty && !values.contains(value)) {
      values.insert(0, value);
      displays.insert(0, value);
    }

    // Fallback if provider hasn't loaded yet
    if (values.isEmpty) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final safeValue = values.contains(value) ? value : values.first;

    return DropdownButtonFormField<String>(
      key: ValueKey(safeValue),
      initialValue: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Unit',
        border: OutlineInputBorder(),
      ),
      items: List.generate(
        values.length,
        (i) => DropdownMenuItem(value: values[i], child: Text(displays[i])),
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
