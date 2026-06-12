import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/services/database_helper.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/category_helper.dart';
import '../../providers/category_provider.dart';

/// Manage expense and income categories — view system categories and
/// add / delete custom ones.
class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Expense'),
            Tab(text: 'Income'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CategoryTab(type: 'expense', accentColor: colors.expense),
          _CategoryTab(type: 'income', accentColor: colors.income),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final typeKey = _tabController.index == 0 ? 'expense' : 'income';
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'New ${typeKey == 'expense' ? 'expense' : 'income'} category',
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Pets, Gym, Charity',
              prefixIcon: Icon(Icons.label_outline),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a name';
              if (v.trim().length > 40) return 'Too long (max 40 chars)';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    if (result == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final added = await ref
          .read(customCategoriesProvider.notifier)
          .addCategory(result, typeKey);
      if (!mounted) return;
      if (!added) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('"$result" already exists'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }
}

// ── Per-type tab ────────────────────────────────────────────────────────────

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.type, required this.accentColor});

  final String type; // 'expense' | 'income'
  final Color accentColor;

  List<String> get _systemList => type == 'income'
      ? AppConstants.incomeCategories
      : AppConstants.defaultCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(customCategoriesProvider);
    final customList = type == 'income' ? custom.income : custom.expense;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        // ── System categories (read-only) ──────────────────────────────
        _SectionHeader(
          label: 'Built-in',
          subtitle: '${_systemList.length} categories',
        ),
        for (final name in _systemList)
          _SystemCategoryTile(name: name, accentColor: accentColor),

        // ── Custom categories (deletable) ──────────────────────────────
        _SectionHeader(
          label: 'Custom',
          subtitle: customList.isEmpty
              ? 'None added yet'
              : '${customList.length} ${customList.length == 1 ? 'category' : 'categories'}',
        ),
        if (customList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.lg,
            ),
            child: Text(
              'Tap + Add category to create your own.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final name in customList)
            _CustomCategoryTile(
              name: name,
              accentColor: accentColor,
              onDelete: () => _confirmDelete(context, ref, name),
            ),

        // Bottom padding for FAB
        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    // Count linked transactions before showing the dialog.
    final txnCount = await DatabaseHelper.instance.countTransactionsByCategory(
      name,
    );
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$name" will be removed from the category list.'),
            if (txnCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$txnCount existing '
                        '${txnCount == 1 ? 'transaction uses' : 'transactions use'} '
                        'this category. '
                        'They will keep the category name but it will '
                        'no longer appear in dropdowns.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No transactions are using this category.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(customCategoriesProvider.notifier).removeCategory(name);
    }
  }
}

// ── Tiles ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.subtitle});
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.lg,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '· $subtitle',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemCategoryTile extends StatelessWidget {
  const _SystemCategoryTile({required this.name, required this.accentColor});
  final String name;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final icon = CategoryHelper.getIcon(name);
    final color = CategoryHelper.getColor(name);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(name),
      trailing: Tooltip(
        message: 'Built-in category',
        child: Icon(
          Icons.lock_outline,
          size: 16,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _CustomCategoryTile extends StatelessWidget {
  const _CustomCategoryTile({
    required this.name,
    required this.accentColor,
    required this.onDelete,
  });
  final String name;
  final Color accentColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('custom_$name'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // provider rebuild handles list removal
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.12),
          child: Icon(Icons.label_outline, color: accentColor, size: 20),
        ),
        title: Text(name),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
