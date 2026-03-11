import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/models/item_catalog.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/upgrade_prompt_sheet.dart' show showUpgradePromptSheet;
import '../invoices/item_catalog_screen.dart';

/// Inventory management screen — lists all tracked products with stock levels.
///
/// Gated behind [SubscriptionTier.business].
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _showLowStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionTierProvider);
    if (tier != SubscriptionTier.business) {
      return _GatedPlaceholder(tier: tier);
    }

    final inventoryAsync = ref.watch(inventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        centerTitle: false,
        actions: [
          Consumer(
            builder: (_, r, _) {
              final count = r.watch(lowStockCountProvider);
              return count > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: context.kashColors.expense,
                        ),
                        label: Text(
                          '$count low',
                          style: TextStyle(color: context.kashColors.expense),
                        ),
                        onPressed: () =>
                            setState(() => _showLowStockOnly = !_showLowStockOnly),
                        backgroundColor: context.kashColors.expense
                            .withValues(alpha: 0.08),
                        side: BorderSide(
                          color: context.kashColors.expense.withValues(alpha: 0.3),
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: inventoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          final displayed = _showLowStockOnly
              ? items.where((i) => i.isLowStock).toList()
              : items;

          if (displayed.isEmpty) {
            return _EmptyState(hasItems: items.isNotEmpty);
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(inventoryProvider.notifier).load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.base),
              itemCount: displayed.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _ItemTile(
                item: displayed[i],
                onAdjust: (type) =>
                    _showAdjustDialog(displayed[i], type),
                onViewHistory: () =>
                    _showMovementsSheet(displayed[i]),
                onEditCatalog: () =>
                    _openCatalogEdit(displayed[i]),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTrackedItemInfo,
        icon: const Icon(Icons.add),
        label: const Text('Enable Tracking'),
      ),
    );
  }

  Future<void> _showAdjustDialog(
    ItemCatalog item,
    _AdjustType type,
  ) async {
    if (type == _AdjustType.history) {
      _showMovementsSheet(item);
      return;
    }
    final result = await showDialog<(double, String?)>(
      context: context,
      builder: (_) => _AdjustDialog(item: item, type: type),
    );
    if (result == null || !mounted) return;
    final (qty, notes) = result;
    final notifier = ref.read(inventoryProvider.notifier);
    if (type == _AdjustType.add) {
      await notifier.addStock(item.id!, qty, notes: notes);
    } else if (type == _AdjustType.deduct) {
      await notifier.deductStock(item.id!, qty, notes: notes);
    } else {
      await notifier.setStock(item.id!, qty, notes: notes);
    }
  }

  void _showMovementsSheet(ItemCatalog item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MovementsSheet(item: item),
    );
  }

  void _showAddTrackedItemInfo() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ItemCatalogScreen()),
    );
  }

  Future<void> _openCatalogEdit(ItemCatalog item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ItemCatalogScreen(initialEditItem: item),
      ),
    );
    if (mounted) ref.read(inventoryProvider.notifier).load();
  }
}

// ── Tier gate placeholder ──────────────────────────────────────────────────────

class _GatedPlaceholder extends ConsumerWidget {
  const _GatedPlaceholder({required this.tier});
  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 64, color: context.colorScheme.outline),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Inventory tracking is a\nBusiness tier feature',
                textAlign: TextAlign.center,
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Track stock levels, get low-stock alerts, and manage\nproduct quantities.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colorScheme.outline),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () => showUpgradePromptSheet(context, featureName: 'Inventory'),
                icon: const Icon(Icons.star_outline),
                label: const Text('Upgrade to Business'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasItems});
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_outlined,
                size: 64, color: context.colorScheme.outline),
            const SizedBox(height: AppSpacing.lg),
            Text(
              hasItems
                  ? 'No low-stock items — all good!'
                  : 'No items with tracking enabled',
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasItems
                  ? 'All your tracked products are well stocked.'
                  : 'Go to Item Catalog and enable "Track Inventory"\nfor products you want to monitor.',
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item tile ──────────────────────────────────────────────────────────────────

enum _AdjustType { add, deduct, set, history }

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.onAdjust,
    required this.onViewHistory,
    required this.onEditCatalog,
  });

  final ItemCatalog item;
  final void Function(_AdjustType) onAdjust;
  final VoidCallback onViewHistory;
  final VoidCallback onEditCatalog;

  @override
  Widget build(BuildContext context) {
    final isLow = item.isLowStock;
    final colors = context.kashColors;
    final stockColor = isLow ? colors.expense : colors.income;

    return Card(
      child: ListTile(
        onTap: onEditCatalog,
        contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: context.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLow)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'LOW',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: colors.expense,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Stock: ',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colorScheme.outline),
                ),
                Text(
                  '${item.stockQty.toStringAsFixed(item.stockQty % 1 == 0 ? 0 : 1)} ${item.unit}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: stockColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '  ·  Reorder at ${item.lowStockThreshold.toStringAsFixed(item.lowStockThreshold % 1 == 0 ? 0 : 1)}',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<_AdjustType>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Adjust stock',
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _AdjustType.add,
              child: Row(children: [
                Icon(Icons.add_circle_outline, size: 18),
                SizedBox(width: 8),
                Text('Add Stock'),
              ]),
            ),
            const PopupMenuItem(
              value: _AdjustType.deduct,
              child: Row(children: [
                Icon(Icons.remove_circle_outline, size: 18),
                SizedBox(width: 8),
                Text('Deduct Stock'),
              ]),
            ),
            const PopupMenuItem(
              value: _AdjustType.set,
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 8),
                Text('Set Stock'),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _AdjustType.history,
              child: Row(children: [
                Icon(Icons.history_outlined, size: 18),
                SizedBox(width: 8),
                Text('View History'),
              ]),
            ),
          ],
          onSelected: onAdjust,
        ),
      ),
    );
  }
}

// ── Adjust dialog ─────────────────────────────────────────────────────────────

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.item, required this.type});
  final ItemCatalog item;
  final _AdjustType type;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.type == _AdjustType.set) {
      _qtyCtrl.text = widget.item.stockQty
          .toStringAsFixed(widget.item.stockQty % 1 == 0 ? 0 : 2);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.type) {
        _AdjustType.add => 'Add Stock',
        _AdjustType.deduct => 'Deduct Stock',
        _AdjustType.set => 'Set Stock',
        _AdjustType.history => 'View History',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item.name,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.outline),
            ),
            const SizedBox(height: AppSpacing.base),
            TextFormField(
              controller: _qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: widget.type == _AdjustType.set
                    ? 'New stock quantity'
                    : 'Quantity (${widget.item.unit})',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a quantity';
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final qty = double.parse(_qtyCtrl.text);
            final notes =
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
            Navigator.pop(context, (qty, notes));
          },
          child: Text(_title),
        ),
      ],
    );
  }
}

// ── Movements history sheet ────────────────────────────────────────────────────

class _MovementsSheet extends ConsumerWidget {
  const _MovementsSheet({required this.item});
  final ItemCatalog item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(stockMovementsProvider(item.id!));
    final dateFormat = DateFormat('dd MMM yyyy, h:mm a');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.name} — Stock History',
                    style: context.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: movementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (movements) {
                if (movements.isEmpty) {
                  return const Center(
                    child: Text('No stock movements yet.'),
                  );
                }
                return ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: movements.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = movements[i];
                    final isIn = m.qty > 0;
                    final color = isIn
                        ? context.kashColors.income
                        : context.kashColors.expense;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.1),
                        child: Icon(
                          isIn ? Icons.add : Icons.remove,
                          color: color,
                          size: 18,
                        ),
                      ),
                      title: Text(m.movementType.label),
                      subtitle: Text(dateFormat.format(m.createdAt),
                          style: context.textTheme.bodySmall),
                      trailing: Text(
                        '${isIn ? '+' : ''}${m.qty.toStringAsFixed(m.qty % 1 == 0 ? 0 : 1)}  →  ${m.stockAfter.toStringAsFixed(m.stockAfter % 1 == 0 ? 0 : 1)}',
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: color, fontWeight: FontWeight.w600),
                      ),
                      isThreeLine: m.notes != null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
