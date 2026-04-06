import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../data/models/hsn_entry.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/services/hsn_search_service.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
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
  ConsumerState<ItemCatalogScreen> createState() => _ItemCatalogScreenState();
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
        title: Text(widget.pickMode ? 'Pick Item' : 'Item Catalog'),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.sm,
              AppSpacing.base,
              0,
            ),
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
                ...ItemCategory.values.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(cat.pluralLabel),
                      selected: _categoryFilter == cat,
                      onSelected: (_) => setState(() => _categoryFilter = cat),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: catalogAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                // Apply filters: search + category
                var filtered = items;

                // Search filter
                if (_search.isNotEmpty) {
                  filtered = filtered
                      .where(
                        (i) =>
                            i.name.toLowerCase().contains(
                              _search.toLowerCase(),
                            ) ||
                            (i.description ?? '').toLowerCase().contains(
                              _search.toLowerCase(),
                            ),
                      )
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
                    top: AppSpacing.sm,
                    bottom: 80,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _CatalogTile(
                    item: filtered[i],
                    pickMode: widget.pickMode,
                    onPick: () => Navigator.pop(context, filtered[i]),
                    onEdit: () => _showItemSheet(context, item: filtered[i]),
                    onDelete: () => _confirmDelete(context, ref, filtered[i]),
                    onToggleTracking: () => ref
                        .read(catalogProvider.notifier)
                        .edit(
                          filtered[i].copyWith(
                            trackInventory: !filtered[i].trackInventory,
                            updatedAt: DateTime.now(),
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showItemSheet(BuildContext context, {ItemCatalog? item}) async {
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
    BuildContext context,
    WidgetRef ref,
    ItemCatalog item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Remove Item?'),
        content: Text('"${item.name}" will be removed from the catalog.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(catalogProvider.notifier).remove(item.id!);
    }
  }
}

// ── Catalog Tile ──────────────────────────────────────────────────────────────

class _CatalogTile extends ConsumerWidget {
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

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stock tracking is a Business-tier feature.
            if (ref.read(subscriptionTierProvider).isBusiness)
              ListTile(
                leading: Icon(
                  item.trackInventory
                      ? Icons.inventory_2_outlined
                      : Icons.inventory_2,
                ),
                title: Text(
                  item.trackInventory
                      ? 'Disable Stock Tracking'
                      : 'Enable Stock Tracking',
                ),
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
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final infoLine = [
      if (item.description != null) item.description!,
      item.unit,
      if (item.hsnCode != null) '${item.hsnOrSac}: ${item.hsnCode}',
    ].join(' · ');

    return ListTile(
      onTap: pickMode ? onPick : onEdit,
      isThreeLine: item.trackInventory,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.inventory_2_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: item.trackInventory
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(infoLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs + 2,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _stockColor(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: _stockColor(context).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 10,
                        color: _stockColor(context),
                      ),
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
            )
          : Text(infoLine, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(item.unitPrice),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (item.taxPct > 0)
            Text(
              'GST ${item.taxPct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
        ],
      ),
      onLongPress: pickMode ? null : () => _showActions(context, ref),
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
  late final TextEditingController _brandCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _imagePathCtrl;
  late final TextEditingController _additionalPropsCtrl;
  late final TextEditingController _mrpCtrl;
  late final TextEditingController _dealerPriceCtrl;
  late final TextEditingController _stockQtyCtrl;
  late final TextEditingController _lowStockThresholdCtrl;
  late final TextEditingController _mpnCtrl;
  late final TextEditingController _manufacturerCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _weightValueCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _depthCtrl;
  late final TextEditingController _materialCtrl;
  late final TextEditingController _keywordsCtrl;
  late final TextEditingController _productIdCtrl;
  late final TextEditingController _asinCtrl;
  late final TextEditingController _logoPathCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _sloganCtrl;
  late final TextEditingController _modelNumberCtrl;
  late String _weightUnit;
  late String? _countryOfOrigin;
  DateTime? _releaseDate;
  late String _itemCondition;
  int? _productGroupId;
  late String _hsnOrSac;
  late String _selectedUnit;
  late ItemCategory _category;
  late bool _isFavorite;
  late bool _trackInventory;
  late bool _isBookable;
  late int _durationMinutes;
  late String _availability;
  late String _priceCurrency;
  DateTime? _priceValidUntil;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _descCtrl = TextEditingController(text: item?.description ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? '');
    _selectedUnit = item?.unit ?? 'PCS';
    _priceCtrl = TextEditingController(
      text: item == null ? '' : item.unitPrice.toStringAsFixed(2),
    );
    _taxCtrl = TextEditingController(
      text: item == null
          ? ''
          : (item.taxPct == 0 ? '' : item.taxPct.toStringAsFixed(1)),
    );
    _hsnCtrl = TextEditingController(text: item?.hsnCode ?? '');
    _brandCtrl = TextEditingController(text: item?.brandName ?? '');
    _barcodeCtrl = TextEditingController(text: item?.barcode ?? '');
    _imagePathCtrl = TextEditingController(text: item?.primaryImagePath ?? '');
    _additionalPropsCtrl = TextEditingController(
      text: item?.additionalPropertiesJson ?? '',
    );
    _mrpCtrl = TextEditingController(
      text: item?.mrp == null ? '' : item!.mrp!.toStringAsFixed(2),
    );
    _dealerPriceCtrl = TextEditingController(
      text: item?.dealerPrice == null
          ? ''
          : item!.dealerPrice!.toStringAsFixed(2),
    );
    _stockQtyCtrl = TextEditingController(
      text: item == null ? '' : item.stockQty.toStringAsFixed(2),
    );
    _lowStockThresholdCtrl = TextEditingController(
      text: item == null ? '' : item.lowStockThreshold.toStringAsFixed(2),
    );
    _mpnCtrl = TextEditingController(text: item?.mpn ?? '');
    _manufacturerCtrl = TextEditingController(text: item?.manufacturerName ?? '');
    _colorCtrl = TextEditingController(text: item?.color ?? '');
    _sizeCtrl = TextEditingController(text: item?.size ?? '');
    _weightValueCtrl = TextEditingController(
      text: item?.weightValue != null ? item!.weightValue!.toStringAsFixed(1) : '',
    );
    _widthCtrl = TextEditingController(
      text: item?.widthCm != null ? item!.widthCm!.toStringAsFixed(1) : '',
    );
    _heightCtrl = TextEditingController(
      text: item?.heightCm != null ? item!.heightCm!.toStringAsFixed(1) : '',
    );
    _depthCtrl = TextEditingController(
      text: item?.depthCm != null ? item!.depthCm!.toStringAsFixed(1) : '',
    );
    _materialCtrl = TextEditingController(text: item?.material ?? '');
    _keywordsCtrl = TextEditingController(text: item?.keywords ?? '');
    _productIdCtrl = TextEditingController(text: item?.productId ?? '');
    _asinCtrl = TextEditingController(text: item?.asin ?? '');
    _logoPathCtrl = TextEditingController(text: item?.logoPath ?? '');
    _patternCtrl = TextEditingController(text: item?.pattern ?? '');
    _sloganCtrl = TextEditingController(text: item?.slogan ?? '');
    _modelNumberCtrl = TextEditingController(text: item?.modelNumber ?? '');
    _weightUnit = item?.weightUnit ?? 'g';
    _countryOfOrigin = item?.countryOfOrigin;
    _releaseDate = item?.releaseDate;
    _itemCondition = item?.itemCondition ?? 'NewCondition';
    _productGroupId = item?.productGroupId;
    _category = item?.category ?? ItemCategory.product;
    _hsnOrSac = item?.hsnOrSac ?? _defaultHsnOrSac(_category);
    _isFavorite = item?.isFavorite ?? false;
    _availability = item?.availability ?? 'InStock';
    _priceCurrency = item?.priceCurrency ?? 'INR';
    _priceValidUntil = item?.priceValidUntil;
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
      _hsnCtrl,
      _brandCtrl,
      _barcodeCtrl,
      _imagePathCtrl,
      _additionalPropsCtrl,
      _mrpCtrl,
      _dealerPriceCtrl,
      _stockQtyCtrl,
      _lowStockThresholdCtrl,
      _mpnCtrl,
      _manufacturerCtrl,
      _colorCtrl,
      _sizeCtrl,
      _weightValueCtrl,
      _widthCtrl,
      _heightCtrl,
      _depthCtrl,
      _materialCtrl,
      _keywordsCtrl,
      _productIdCtrl,
      _asinCtrl,
      _logoPathCtrl,
      _patternCtrl,
      _sloganCtrl,
      _modelNumberCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickItemImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null && mounted) {
      final compressed = await compressPickedImage(picked);
      setState(() => _imagePathCtrl.text = compressed);
    }
  }

  Future<void> _pickLogoImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null && mounted) {
      final compressed = await compressPickedImage(picked);
      setState(() => _logoPathCtrl.text = compressed);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final item = ItemCatalog(
      id: widget.item?.id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      unit: _selectedUnit.isEmpty ? 'PCS' : _selectedUnit,
      unitPrice: double.tryParse(_priceCtrl.text) ?? 0,
      taxPct: double.tryParse(_taxCtrl.text) ?? 0,
      hsnCode: _hsnCtrl.text.trim().isEmpty ? null : _hsnCtrl.text.trim(),
      hsnOrSac: _hsnOrSac,
      brandName: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
      primaryImagePath: _imagePathCtrl.text.trim().isEmpty
          ? null
          : _imagePathCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim().isEmpty
          ? null
          : _barcodeCtrl.text.trim(),
      additionalPropertiesJson: _additionalPropsCtrl.text.trim().isEmpty
          ? null
          : _additionalPropsCtrl.text.trim(),
      category: _category,
      isFavorite: _isFavorite,
      trackInventory: _trackInventory,
      stockQty: double.tryParse(_stockQtyCtrl.text) ?? 0,
      lowStockThreshold: double.tryParse(_lowStockThresholdCtrl.text) ?? 5,
      isBookable: _isBookable,
      durationMinutes: _isBookable ? _durationMinutes : null,
      mrp: double.tryParse(_mrpCtrl.text),
      dealerPrice: double.tryParse(_dealerPriceCtrl.text),
      mpn: _mpnCtrl.text.trim().isEmpty ? null : _mpnCtrl.text.trim(),
      availability: _availability,
      priceCurrency: _priceCurrency,
      priceValidUntil: _priceValidUntil,
      manufacturerName: _manufacturerCtrl.text.trim().isEmpty
          ? null
          : _manufacturerCtrl.text.trim(),
      color: _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
      size: _sizeCtrl.text.trim().isEmpty ? null : _sizeCtrl.text.trim(),
      weightValue: double.tryParse(_weightValueCtrl.text),
      weightUnit: _weightUnit,
      widthCm: double.tryParse(_widthCtrl.text),
      heightCm: double.tryParse(_heightCtrl.text),
      depthCm: double.tryParse(_depthCtrl.text),
      material: _materialCtrl.text.trim().isEmpty ? null : _materialCtrl.text.trim(),
      keywords: _keywordsCtrl.text.trim().isEmpty ? null : _keywordsCtrl.text.trim(),
      countryOfOrigin: _countryOfOrigin,
      releaseDate: _releaseDate,
      productId: _productIdCtrl.text.trim().isEmpty ? null : _productIdCtrl.text.trim(),
      asin: _asinCtrl.text.trim().isEmpty ? null : _asinCtrl.text.trim(),
      logoPath: _logoPathCtrl.text.trim().isEmpty ? null : _logoPathCtrl.text.trim(),
      pattern: _patternCtrl.text.trim().isEmpty ? null : _patternCtrl.text.trim(),
      slogan: _sloganCtrl.text.trim().isEmpty ? null : _sloganCtrl.text.trim(),
      itemCondition: _itemCondition,
      modelNumber: _modelNumberCtrl.text.trim().isEmpty ? null : _modelNumberCtrl.text.trim(),
      productGroupId: _productGroupId,
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
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.9;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: sheetHeight,
        child: DefaultTabController(
          length: 5,
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.item == null ? 'Add Item' : 'Edit Item',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Basic'),
                      Tab(text: 'Pricing'),
                      Tab(text: 'Inventory'),
                      Tab(text: 'Media'),
                      Tab(text: 'Advanced'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildBasicTab(),
                        _buildPricingTab(),
                        _buildInventoryTab(),
                        _buildMediaTab(),
                        _buildAdvancedTab(),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.item == null ? 'Add Item' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBasicTab() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Item Name *',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _skuCtrl,
          decoration: InputDecoration(
            labelText: 'SKU / Item Code',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            hintText: 'e.g., PROD-001',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<ItemCategory>(
          initialValue: _category,
          decoration: InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
          ),
          items: ItemCategory.values
              .map(
                (cat) => DropdownMenuItem(value: cat, child: Text(cat.label)),
              )
              .toList(),
          onChanged: (val) async {
            if (val == null) return;
            setState(() {
              _category = val;
              _hsnOrSac = _defaultHsnOrSac(val);
              _trackInventory = _trackInventoryDefault(val);
            });
            if (_isAutoGeneratedSku(_skuCtrl.text)) {
              final newSku = await ref
                  .read(catalogProvider.notifier)
                  .generateNextSku(val);
              if (mounted) {
                _skuCtrl.text = newSku;
              }
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _descCtrl,
          decoration: InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.base),
        _buildAccordion(
          title: 'Brand and Identifiers',
          subtitle: 'Optional commerce profile fields',
          initiallyExpanded: false,
          child: Column(
            children: [
              TextFormField(
                controller: _brandCtrl,
                decoration: InputDecoration(
                  labelText: 'Brand Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _barcodeCtrl,
                decoration: InputDecoration(
                  labelText: 'Barcode / GTIN',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _mpnCtrl,
                decoration: InputDecoration(
                  labelText: 'MPN (Manufacturer Part Number)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _manufacturerCtrl,
                decoration: InputDecoration(
                  labelText: 'Manufacturer',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _productIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Product ID (GTIN)',
                  hintText: 'Global Trade Item Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _modelNumberCtrl,
                decoration: InputDecoration(
                  labelText: 'Model Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Physical Properties',
          subtitle: 'Color, size, and material',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _colorCtrl,
                      decoration: InputDecoration(
                        labelText: 'Color',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _sizeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Size',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _materialCtrl,
                decoration: InputDecoration(
                  labelText: 'Material',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Keywords',
          subtitle: 'Comma-separated tags for search and discovery',
          child: TextFormField(
            controller: _keywordsCtrl,
            decoration: InputDecoration(
              labelText: 'Keywords',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              hintText: 'e.g. cotton, organic, summer',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.base,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      children: [
        Row(
          children: [
            Expanded(
              child: _UnitDropdown(
                value: _selectedUnit,
                onChanged: (v) => setState(() => _selectedUnit = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Selling Price (₹) *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  prefixText: '₹',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
                validator: (v) => (double.tryParse(v ?? '') == null)
                    ? 'Enter valid amount'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        _buildAccordion(
          title: 'Tax and Compliance',
          subtitle: 'GST percentage and HSN/SAC code',
          initiallyExpanded: true,
          child: Column(
            children: [
              TextFormField(
                controller: _taxCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'GST %',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  suffixText: '%',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
              ),
              const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Retail and Trade Pricing',
          subtitle: 'MRP and dealer purchase price',
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _mrpCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'MRP (₹)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    prefixText: '₹',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.base,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: _dealerPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Dealer Price (₹)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    prefixText: '₹',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.base,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Offer Details',
          subtitle: 'Currency and promotional validity',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _priceCurrency,
                decoration: InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
                items: const ['INR', 'USD', 'EUR', 'GBP', 'AED']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _priceCurrency = v ?? 'INR'),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Price Valid Until'),
                subtitle: Text(
                  _priceValidUntil != null
                      ? DateFormat('d MMM yyyy').format(_priceValidUntil!)
                      : 'No expiry set',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_priceValidUntil != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear date',
                        onPressed: () => setState(() => _priceValidUntil = null),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      tooltip: 'Pick date',
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _priceValidUntil ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null && mounted) {
                          setState(() => _priceValidUntil = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Release Date'),
                subtitle: Text(
                  _releaseDate != null
                      ? DateFormat('d MMM yyyy').format(_releaseDate!)
                      : 'No release date',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_releaseDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear date',
                        onPressed: () => setState(() => _releaseDate = null),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      tooltip: 'Pick date',
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _releaseDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null && mounted) {
                          setState(() => _releaseDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _buildInventoryTab() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      children: [
        SwitchListTile(
          value: _trackInventory,
          onChanged: (val) => setState(() => _trackInventory = val),
          title: const Text('Track Inventory'),
          subtitle: const Text('Monitor stock levels and get low-stock alerts'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: _availability,
          decoration: InputDecoration(
            labelText: 'Availability',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'InStock', child: Text('In Stock')),
            DropdownMenuItem(value: 'OutOfStock', child: Text('Out of Stock')),
            DropdownMenuItem(value: 'PreOrder', child: Text('Pre-Order')),
            DropdownMenuItem(value: 'Discontinued', child: Text('Discontinued')),
          ],
          onChanged: (v) => setState(() => _availability = v ?? 'InStock'),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Stock Levels',
          subtitle: _trackInventory
              ? 'Editable stock defaults for this catalog item'
              : 'Enable tracking to use stock alerts and thresholds',
          initiallyExpanded: _trackInventory,
          child: Column(
            children: [
              TextFormField(
                controller: _stockQtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Current Stock Qty',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _lowStockThresholdCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Low Stock Threshold',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Dimensions and Weight',
          subtitle: 'Used for shipping calculations',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightValueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Weight',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  DropdownButton<String>(
                    value: _weightUnit,
                    items: const ['g', 'kg', 'oz', 'lb']
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _weightUnit = v ?? 'g'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _widthCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Width (cm)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _heightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Height (cm)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _depthCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Depth (cm)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.base,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _countryOfOrigin,
                decoration: InputDecoration(
                  labelText: 'Country of Origin',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Not specified')),
                  DropdownMenuItem(value: 'IN', child: Text('India')),
                  DropdownMenuItem(value: 'CN', child: Text('China')),
                  DropdownMenuItem(value: 'US', child: Text('United States')),
                  DropdownMenuItem(value: 'DE', child: Text('Germany')),
                  DropdownMenuItem(value: 'JP', child: Text('Japan')),
                  DropdownMenuItem(value: 'GB', child: Text('United Kingdom')),
                  DropdownMenuItem(value: 'VN', child: Text('Vietnam')),
                  DropdownMenuItem(value: 'BD', child: Text('Bangladesh')),
                  DropdownMenuItem(value: 'TW', child: Text('Taiwan')),
                ],
                onChanged: (v) => setState(() => _countryOfOrigin = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _buildMediaTab() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ItemImagePicker(
          imagePath: _imagePathCtrl.text.isEmpty ? null : _imagePathCtrl.text,
          onPick: _pickItemImage,
          onRemove: () => setState(() => _imagePathCtrl.clear()),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Brand Logo',
          subtitle: 'Separate from product image',
          child: Column(
            children: [
              if (_logoPathCtrl.text.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Image.file(
                    File(_logoPathCtrl.text),
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickLogoImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_logoPathCtrl.text.isEmpty ? 'Pick Logo' : 'Change Logo'),
                    ),
                  ),
                  if (_logoPathCtrl.text.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _logoPathCtrl.clear()),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Future Media',
          subtitle: 'Reserved for gallery/video metadata',
          child: Text(
            'Additional image/video fields will be added under this section as media workflows expand.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _buildAdvancedTab() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      children: [
        SwitchListTile(
          value: _isFavorite,
          onChanged: (val) => setState(() => _isFavorite = val),
          title: const Text('Mark as Favorite'),
          subtitle: const Text('Show this item at the top of the list'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          value: _isBookable,
          onChanged: (val) => setState(() => _isBookable = val),
          title: const Text('Enable Bookings'),
          subtitle: const Text('Allow customers to book this service'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_isBookable) ...[
          const SizedBox(height: AppSpacing.md),
          _buildAccordion(
            title: 'Service Duration',
            subtitle: 'Used when bookings are enabled',
            initiallyExpanded: true,
            child: _DurationPicker(
              initialMinutes: _durationMinutes,
              onChanged: (minutes) =>
                  setState(() => _durationMinutes = minutes),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Marketplace Identifiers',
          subtitle: 'Platform-specific product IDs',
          child: Column(
            children: [
              TextFormField(
                controller: _asinCtrl,
                decoration: InputDecoration(
                  labelText: 'ASIN',
                  hintText: 'Amazon Standard Identification Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Product Marketing',
          subtitle: 'Pattern, slogan, and condition',
          child: Column(
            children: [
              TextFormField(
                controller: _patternCtrl,
                decoration: InputDecoration(
                  labelText: 'Pattern',
                  hintText: 'e.g., Solid, Striped, Checkered',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _sloganCtrl,
                decoration: InputDecoration(
                  labelText: 'Slogan / Tagline',
                  hintText: 'Marketing message',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _itemCondition,
                onChanged: (val) => setState(() => _itemCondition = val ?? 'NewCondition'),
                decoration: InputDecoration(
                  labelText: 'Item Condition',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.base,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'NewCondition', child: Text('New')),
                  DropdownMenuItem(value: 'UsedCondition', child: Text('Used')),
                  DropdownMenuItem(value: 'RefurbishedCondition', child: Text('Refurbished')),
                  DropdownMenuItem(value: 'DamagedCondition', child: Text('Damaged')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'Custom Properties JSON',
          subtitle: 'Long-tail metadata for external commerce schemas',
          child: TextFormField(
            controller: _additionalPropsCtrl,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'additional_properties_json',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              hintText: '{"packaging":"500g","shelf":"A-3"}',
              alignLabelWithHint: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.base,
              ),
            ),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return null;
              final isObject = value.startsWith('{') && value.endsWith('}');
              if (!isObject) return 'Enter valid JSON object';
              return null;
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildAccordion(
          title: 'P3 Advanced Commerce Features',
          subtitle: 'Product variants, relationships, and reviews',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This product supports advanced schema.org/Product features:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildFeatureTile(
                context,
                icon: Icons.palette_outlined,
                title: 'Product Variants',
                description: 'Group color/size variants (e.g., T-shirt in 3 colors × 4 sizes)',
              ),
              _buildFeatureTile(
                context,
                icon: Icons.link_outlined,
                title: 'Product Relationships',
                description: 'Link accessories, spare parts, or related products',
              ),
              _buildFeatureTile(
                context,
                icon: Icons.star_outline,
                title: 'Reviews & Ratings',
                description: 'Aggregate customer ratings and review text',
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'These features will be available in dedicated management screens.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _buildFeatureTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccordion({
    required String title,
    required String subtitle,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.xs,
          ),
          childrenPadding: const EdgeInsets.all(AppSpacing.base),
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.pickMode,
    required this.hasSearch,
    required this.onAdd,
  });
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
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
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
          decoration: const InputDecoration(
            labelText: 'Custom Duration (minutes)',
            border: OutlineInputBorder(),
            hintText: 'e.g., 75',
            helperText:
                'For multi-day services, use minutes (e.g., 2880 = 2 days)',
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
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
        return HsnSearchService.instance.search(q, type: widget.type);
      },
      displayStringForOption: (e) => e.code,
      fieldViewBuilder: (context, ctrl, focusNode, onSubmit) => TextFormField(
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

// ── Item Image Picker ────────────────────────────────────────────────────────

/// Visual image picker for item's primary image, similar to business card picker.
class _ItemImagePicker extends StatelessWidget {
  const _ItemImagePicker({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String? imagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = imagePath != null && imagePath!.isNotEmpty && File(imagePath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, size: 18, color: cs.outline),
            const SizedBox(width: 8),
            Text(
              'Primary Image',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.outline),
            ),
            const Spacer(),
            if (hasImage)
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Image.file(
              File(imagePath!),
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (ctx, error, stack) => _placeholder(context, cs),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Replace Image'),
          ),
        ] else
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(
                    color: cs.outlineVariant, style: BorderStyle.solid, width: 1.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 40, color: cs.primary),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Tap to add item image',
                      style: TextStyle(color: cs.primary, fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(BuildContext context, ColorScheme cs) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Center(
          child: Icon(Icons.broken_image_outlined, size: 48, color: cs.error),
        ),
      );
}
