import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/item_catalog.dart';
import '../../providers/invoice_provider.dart';

class ItemCatalogScreen extends ConsumerStatefulWidget {
  /// When [pickMode] is true, tapping an item pops with the selected [ItemCatalog].
  const ItemCatalogScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  ConsumerState<ItemCatalogScreen> createState() =>
      _ItemCatalogScreenState();
}

class _ItemCatalogScreenState extends ConsumerState<ItemCatalogScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  ItemCategory? _categoryFilter;

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
                    label: Text(_categoryLabel(cat)),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(ItemCategory cat) {
    switch (cat) {
      case ItemCategory.product:
        return 'Products';
      case ItemCategory.service:
        return 'Services';
      case ItemCategory.material:
        return 'Materials';
      case ItemCategory.labor:
        return 'Labor';
      case ItemCategory.equipment:
        return 'Equipment';
      case ItemCategory.other:
        return 'Other';
    }
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
  });

  final ItemCatalog item;
  final bool pickMode;
  final VoidCallback onPick;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
          if (item.hsnCode != null) 'HSN: ${item.hsnCode}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
                  color:
                      Theme.of(context).colorScheme.outline),
            ),
        ],
      ),
      onLongPress: pickMode ? null : onDelete,
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
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _hsnCtrl;
  late ItemCategory _category;
  late bool _isFavorite;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _descCtrl =
        TextEditingController(text: item?.description ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? '');
    _unitCtrl = TextEditingController(text: item?.unit ?? '');
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
    _isFavorite = item?.isFavorite ?? false;
    
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
      _unitCtrl,
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
      unit: _unitCtrl.text.trim().isEmpty
          ? 'pcs'
          : _unitCtrl.text.trim(),
      unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
      taxPct: double.tryParse(_taxCtrl.text) ?? 0,
      hsnCode: _hsnCtrl.text.trim().isEmpty
          ? null
          : _hsnCtrl.text.trim(),
      category: _category,
      isFavorite: _isFavorite,
      createdAt: widget.item?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.onSave(item);
    if (mounted) Navigator.pop(context);
  }

  String _categoryDisplayName(ItemCategory cat) {
    switch (cat) {
      case ItemCategory.product:
        return 'Product';
      case ItemCategory.service:
        return 'Service';
      case ItemCategory.material:
        return 'Material';
      case ItemCategory.labor:
        return 'Labor';
      case ItemCategory.equipment:
        return 'Equipment';
      case ItemCategory.other:
        return 'Other';
    }
  }

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
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ItemCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(_categoryDisplayName(cat)),
                  );
                }).toList(),
                onChanged: (val) async {
                  if (val != null) {
                    setState(() => _category = val);
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
                    child: TextFormField(
                      controller: _unitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unit (pcs, kg…)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _hsnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'HSN Code',
                        border: OutlineInputBorder(),
                      ),
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
