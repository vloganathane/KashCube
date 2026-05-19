import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/models/product_relationship.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/product_relationship_provider.dart';
import 'item_catalog_screen.dart';

/// Bottom sheet for managing product relationships.
///
/// Shows all related products (accessories, spare parts, consumables, related items)
/// for the given [item]. Users can add new relationships or remove existing ones.
class RelatedProductsSheet extends ConsumerWidget {
  const RelatedProductsSheet({super.key, required this.item});

  final ItemCatalog item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.id == null) {
      return const SizedBox.shrink();
    }

    final relationshipsAsync = ref.watch(
      productRelationshipsProvider(item.id!),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusLg),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Related Products',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: relationshipsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Error: $e',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  data: (relationships) {
                    if (relationships.isEmpty) {
                      return _EmptyState(
                        onAdd: () =>
                            _showAddRelationshipSheet(context, ref, item.id!),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(AppSpacing.base),
                      itemCount: relationships.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final relationship = relationships[index];
                        return _RelationshipTile(
                          relationship: relationship,
                          productId: item.id!,
                          onRemove: () => _removeRelationship(
                            context,
                            ref,
                            item.id!,
                            relationship.id!,
                          ),
                          onChangeType: (newType) => _changeRelationshipType(
                            ref,
                            item.id!,
                            relationship.id!,
                            newType,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Add button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: FilledButton.icon(
                    onPressed: () =>
                        _showAddRelationshipSheet(context, ref, item.id!),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Related Product'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddRelationshipSheet(
    BuildContext context,
    WidgetRef ref,
    int productId,
  ) async {
    final result = await showModalBottomSheet<_AddRelationshipResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddRelationshipSheet(currentProductId: productId),
    );

    if (result != null && context.mounted) {
      await ref
          .read(productRelationshipsProvider(productId).notifier)
          .add(relatedProductId: result.relatedProductId, type: result.type);
    }
  }

  Future<void> _removeRelationship(
    BuildContext context,
    WidgetRef ref,
    int productId,
    int relationshipId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Relationship?'),
        content: const Text('This will unlink the related product.'),
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

    if (confirmed == true && context.mounted) {
      await ref
          .read(productRelationshipsProvider(productId).notifier)
          .remove(relationshipId);
    }
  }

  Future<void> _changeRelationshipType(
    WidgetRef ref,
    int productId,
    int relationshipId,
    ProductRelationshipType newType,
  ) async {
    await ref
        .read(productRelationshipsProvider(productId).notifier)
        .updateType(relationshipId, newType);
  }
}

// ══ Empty State ══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'No Related Products',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Link accessories, spare parts, or related items to help with cross-selling.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══ Relationship Tile ════════════════════════════════════════════════════════

class _RelationshipTile extends ConsumerWidget {
  const _RelationshipTile({
    required this.relationship,
    required this.productId,
    required this.onRemove,
    required this.onChangeType,
  });

  final ProductRelationship relationship;
  final int productId;
  final VoidCallback onRemove;
  final ValueChanged<ProductRelationshipType> onChangeType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider);

    return catalogAsync.when(
      loading: () => const Card(
        child: ListTile(
          leading: CircularProgressIndicator(),
          title: Text('Loading...'),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (allItems) {
        final relatedItem = allItems.firstWhere(
          (item) => item.id == relationship.relatedProductId,
          orElse: () => ItemCatalog(
            name: 'Unknown Item',
            unitPrice: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                _iconForType(relationship.relationshipType),
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            title: Text(relatedItem.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                _RelationshipTypeBadge(type: relationship.relationshipType),
                if (relatedItem.unitPrice > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.format(relatedItem.unitPrice),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'change_type',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 20),
                      SizedBox(width: AppSpacing.sm),
                      Text('Change Type'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Remove',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'remove') {
                  onRemove();
                } else if (value == 'change_type') {
                  _showTypePickerDialog(context);
                }
              },
            ),
          ),
        );
      },
    );
  }

  IconData _iconForType(ProductRelationshipType type) {
    return switch (type) {
      ProductRelationshipType.accessory => Icons.extension_outlined,
      ProductRelationshipType.sparePart => Icons.build_outlined,
      ProductRelationshipType.consumable => Icons.repeat_outlined,
      ProductRelationshipType.relatedProduct => Icons.link,
    };
  }

  Future<void> _showTypePickerDialog(BuildContext context) async {
    final newType = await showDialog<ProductRelationshipType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change Relationship Type'),
        children: ProductRelationshipType.values.map((type) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, type),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(_iconForType(type), size: 20),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          type.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );

    if (newType != null) {
      onChangeType(newType);
    }
  }
}

// ══ Relationship Type Badge ══════════════════════════════════════════════════

class _RelationshipTypeBadge extends StatelessWidget {
  const _RelationshipTypeBadge({required this.type});

  final ProductRelationshipType type;

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(context, type);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForType(type), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            type.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(ProductRelationshipType type) {
    return switch (type) {
      ProductRelationshipType.accessory => Icons.extension_outlined,
      ProductRelationshipType.sparePart => Icons.build_outlined,
      ProductRelationshipType.consumable => Icons.repeat_outlined,
      ProductRelationshipType.relatedProduct => Icons.link,
    };
  }

  Color _colorForType(BuildContext context, ProductRelationshipType type) {
    return switch (type) {
      ProductRelationshipType.accessory => const Color(0xFF1976D2), // Blue
      ProductRelationshipType.sparePart => const Color(0xFFE65100), // Orange
      ProductRelationshipType.consumable => const Color(0xFF7B1FA2), // Purple
      ProductRelationshipType.relatedProduct => const Color(
        0xFF388E3C,
      ), // Green
    };
  }
}

// ══ Add Relationship Sheet ═══════════════════════════════════════════════════

class _AddRelationshipResult {
  const _AddRelationshipResult({
    required this.relatedProductId,
    required this.type,
  });

  final int relatedProductId;
  final ProductRelationshipType type;
}

class _AddRelationshipSheet extends ConsumerStatefulWidget {
  const _AddRelationshipSheet({required this.currentProductId});

  final int currentProductId;

  @override
  ConsumerState<_AddRelationshipSheet> createState() =>
      _AddRelationshipSheetState();
}

class _AddRelationshipSheetState extends ConsumerState<_AddRelationshipSheet> {
  ItemCatalog? _selectedProduct;
  ProductRelationshipType _selectedType = ProductRelationshipType.accessory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add Related Product',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.base),

            // Product picker
            OutlinedButton.icon(
              onPressed: _pickProduct,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(
                _selectedProduct == null
                    ? 'Select Product'
                    : _selectedProduct!.name,
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(AppSpacing.base),
              ),
            ),

            const SizedBox(height: AppSpacing.base),

            // Relationship type selector
            Text(
              'Relationship Type',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),

            ...ProductRelationshipType.values.map((type) {
              return RadioListTile<ProductRelationshipType>(
                value: type,
                // ignore: deprecated_member_use
                groupValue: _selectedType,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedType = value);
                  }
                },
                title: Row(
                  children: [
                    Icon(_iconForType(type), size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text(type.label),
                  ],
                ),
                subtitle: Text(type.description),
                contentPadding: EdgeInsets.zero,
              );
            }),

            const SizedBox(height: AppSpacing.base),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedProduct == null ? null : _submit,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(ProductRelationshipType type) {
    return switch (type) {
      ProductRelationshipType.accessory => Icons.extension_outlined,
      ProductRelationshipType.sparePart => Icons.build_outlined,
      ProductRelationshipType.consumable => Icons.repeat_outlined,
      ProductRelationshipType.relatedProduct => Icons.link,
    };
  }

  Future<void> _pickProduct() async {
    final picked = await Navigator.push<ItemCatalog>(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemCatalogScreen(pickMode: true),
      ),
    );

    if (picked != null) {
      // Prevent self-referencing
      if (picked.id == widget.currentProductId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot add a product as related to itself'),
            ),
          );
        }
        return;
      }

      setState(() => _selectedProduct = picked);
    }
  }

  void _submit() {
    if (_selectedProduct?.id == null) return;

    Navigator.pop(
      context,
      _AddRelationshipResult(
        relatedProductId: _selectedProduct!.id!,
        type: _selectedType,
      ),
    );
  }
}
