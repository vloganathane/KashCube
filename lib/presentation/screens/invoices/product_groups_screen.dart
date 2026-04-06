import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/item_catalog.dart';
import '../../../data/models/product_group.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/product_group_provider.dart';

/// Product Groups management screen.
///
/// Lists all variant families (e.g., "T-Shirt Classic" with color/size variants).
/// Users can create groups, edit metadata, and view member products.
class ProductGroupsScreen extends ConsumerStatefulWidget {
  const ProductGroupsScreen({super.key});

  @override
  ConsumerState<ProductGroupsScreen> createState() => _ProductGroupsScreenState();
}

class _ProductGroupsScreenState extends ConsumerState<ProductGroupsScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(productGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Group',
            onPressed: () => _showGroupSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGroupSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
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
                hintText: 'Search product groups…',
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
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (groups) {
                var filtered = groups;

                // Search filter
                if (_search.isNotEmpty) {
                  filtered = filtered
                      .where((g) =>
                          g.name.toLowerCase().contains(_search.toLowerCase()) ||
                          (g.description ?? '')
                              .toLowerCase()
                              .contains(_search.toLowerCase()))
                      .toList();
                }

                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasSearch: _search.isNotEmpty,
                    onAdd: () => _showGroupSheet(context),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _GroupTile(
                    group: filtered[i],
                    onEdit: () => _showGroupSheet(context, group: filtered[i]),
                    onDelete: () => _deleteGroup(filtered[i]),
                    onViewMembers: () => _viewGroupMembers(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupSheet(BuildContext context, {ProductGroup? group}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GroupFormSheet(
        group: group,
        onSave: (g) => group == null
            ? ref.read(productGroupsProvider.notifier).add(g)
            : ref.read(productGroupsProvider.notifier).edit(g),
      ),
    );
  }

  Future<void> _deleteGroup(ProductGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text('"${group.name}" and its variant configuration will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(productGroupsProvider.notifier).remove(group.id!);
    }
  }

  Future<void> _viewGroupMembers(ProductGroup group) async {
    final catalogAsync = ref.read(catalogProvider);
    final allItems = catalogAsync.valueOrNull ?? [];
    final members = allItems.where((item) => item.productGroupId == group.id).toList();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GroupMembersSheet(
        group: group,
        members: members,
      ),
    );
  }
}

// ══ Empty State ══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch, required this.onAdd});

  final bool hasSearch;
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
              hasSearch ? Icons.search_off : Icons.palette_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              hasSearch ? 'No Groups Found' : 'No Product Groups',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hasSearch
                  ? 'Try a different search term'
                  : 'Create variant families to organize products by color, size, or other attributes.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            if (!hasSearch) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Create First Group'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ══ Group Tile ═══════════════════════════════════════════════════════════════

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.group,
    required this.onEdit,
    required this.onDelete,
    required this.onViewMembers,
  });

  final ProductGroup group;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewMembers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Count member products
    final catalogAsync = ref.watch(catalogProvider);
    final memberCount = catalogAsync.whenOrNull(
          data: (items) =>
              items.where((item) => item.productGroupId == group.id).length,
        ) ??
        0;

    final variesBy = group.variesByList;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.palette_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (group.description != null) ...[
              const SizedBox(height: 4),
              Text(
                group.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (variesBy.isNotEmpty)
                  ...variesBy.map((attr) => _AttributeChip(attribute: attr)),
                _InfoChip(
                  icon: Icons.inventory_2_outlined,
                  label: '$memberCount ${memberCount == 1 ? 'variant' : 'variants'}',
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view_members',
              child: Row(
                children: [
                  Icon(Icons.list, size: 20),
                  SizedBox(width: AppSpacing.sm),
                  Text('View Variants'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 20),
                  SizedBox(width: AppSpacing.sm),
                  Text('Edit Group'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Delete',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              onEdit();
            } else if (value == 'delete') {
              onDelete();
            } else if (value == 'view_members') {
              onViewMembers();
            }
          },
        ),
      ),
    );
  }
}

// ══ Attribute Chip ═══════════════════════════════════════════════════════════

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.attribute});

  final String attribute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForAttribute(attribute),
            size: 12,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            attribute,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForAttribute(String attr) {
    final lower = attr.toLowerCase();
    if (lower.contains('color')) return Icons.palette;
    if (lower.contains('size')) return Icons.straighten;
    if (lower.contains('material')) return Icons.category;
    if (lower.contains('pattern')) return Icons.texture;
    return Icons.label;
  }
}

// ══ Info Chip ════════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ══ Group Form Sheet ═════════════════════════════════════════════════════════

class _GroupFormSheet extends StatefulWidget {
  const _GroupFormSheet({this.group, required this.onSave});

  final ProductGroup? group;
  final Future<void> Function(ProductGroup) onSave;

  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _variesByCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameCtrl = TextEditingController(text: group?.name ?? '');
    _descCtrl = TextEditingController(text: group?.description ?? '');
    _variesByCtrl = TextEditingController(
      text: group?.variesByList.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _variesByCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.group == null ? 'New Product Group' : 'Edit Product Group',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Group Name *',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., T-Shirt Classic',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'Optional description',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _variesByCtrl,
                decoration: const InputDecoration(
                  labelText: 'Varies By *',
                  border: OutlineInputBorder(),
                  hintText: 'color, size',
                  helperText: 'Comma-separated attributes (e.g., color, size, material)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final attrs = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  if (attrs.isEmpty) return 'Enter at least one attribute';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
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
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final variesBy = _variesByCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Encode list as JSON array string
    final variesByJson = '["${variesBy.join('","')}"]';

    final group = ProductGroup(
      id: widget.group?.id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      variesBy: variesByJson,
      createdAt: widget.group?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await widget.onSave(group);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// ══ Group Members Sheet ══════════════════════════════════════════════════════

class _GroupMembersSheet extends StatelessWidget {
  const _GroupMembersSheet({required this.group, required this.members});

  final ProductGroup group;
  final List<ItemCatalog> members;

  @override
  Widget build(BuildContext context) {
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
                  color:
                      Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
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
                            group.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${members.length} ${members.length == 1 ? 'variant' : 'variants'}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                child: members.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_outlined,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: AppSpacing.base),
                              Text(
                                'No Variants Yet',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Link items to this group by setting their Product Group ID in the item editor.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: members.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final item = members[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              title: Text(item.name),
                              subtitle: _buildVariantDetails(context, item),
                              trailing: Text(
                                '₹${item.unitPrice.toStringAsFixed(0)}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
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
      },
    );
  }

  Widget? _buildVariantDetails(BuildContext context, ItemCatalog item) {
    final details = <String>[];
    if (item.color != null) details.add('Color: ${item.color}');
    if (item.size != null) details.add('Size: ${item.size}');
    if (item.material != null) details.add('Material: ${item.material}');
    if (item.pattern != null) details.add('Pattern: ${item.pattern}');

    if (details.isEmpty) return null;

    return Text(
      details.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
