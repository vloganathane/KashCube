import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/budget.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/report_provider.dart';

/// Full-page budget management screen.
///
/// Shows per-category monthly budgets with progress bars and lets the user
/// create / edit / delete budgets via a bottom sheet.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);
    final budgetsAsync = ref.watch(currentMonthBudgetsProvider);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Budgets'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Budget options',
            onSelected: (v) async {
              if (v == 'copy') {
                final notifier =
                    ref.read(currentMonthBudgetsProvider.notifier);
                final count = await notifier.copyFromPreviousMonth();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(count == 0
                          ? 'No new budgets to copy (all categories already set)'
                          : 'Copied $count budget${count == 1 ? '' : 's'} from last month'),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.content_copy_outlined),
                  title: Text('Copy from last month'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _MonthBar(month: month, isCurrentMonth: isCurrentMonth),
        ),
      ),
      body: budgetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (budgets) => _BudgetBody(budgets: budgets, month: month),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditSheet(context, ref, month, null),
        tooltip: 'Add Budget',
        child: const Icon(Icons.add),
      ),
    );
  }

  static Future<void> _showAddEditSheet(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
    Budget? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEditBudgetSheet(
        month: month,
        existing: existing,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month navigation bar
// ---------------------------------------------------------------------------

class _MonthBar extends ConsumerWidget {
  const _MonthBar({required this.month, required this.isCurrentMonth});
  final DateTime month;
  final bool isCurrentMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(reportMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1),
          ),
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth
                ? null
                : () => ref.read(reportMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — summary row + list
// ---------------------------------------------------------------------------

class _BudgetBody extends ConsumerWidget {
  const _BudgetBody({required this.budgets, required this.month});
  final List<Budget> budgets;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (budgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.savings_outlined,
                size: 72, color: context.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text(
              'No budgets set',
              style: context.textTheme.titleMedium
                  ?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap + to set spending limits for each category',
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final totalBudget =
        budgets.fold(0.0, (s, b) => s + b.budgetAmount);
    final totalSpent = budgets.fold(0.0, (s, b) => s + b.spentAmount);
    final overCount = budgets.where((b) => b.isOverBudget).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.base, 96),
      children: [
        // Summary card
        _SummaryCard(
            totalBudget: totalBudget,
            totalSpent: totalSpent,
            overCount: overCount),
        const SizedBox(height: AppSpacing.base),

        // Sort: over budget first, then near limit, then others
        ...([...budgets]
            ..sort((a, b) {
              if (a.isOverBudget && !b.isOverBudget) return -1;
              if (!a.isOverBudget && b.isOverBudget) return 1;
              if (a.isNearLimit && !b.isNearLimit) return -1;
              if (!a.isNearLimit && b.isNearLimit) return 1;
              return a.category.compareTo(b.category);
            }))
            .map((budget) => _BudgetCard(
                  budget: budget,
                  month: month,
                  onEdit: () => BudgetScreen._showAddEditSheet(
                      context, ref, month, budget),
                  onDelete: () async {
                    final confirmed = await _confirmDelete(context);
                    if (confirmed && budget.id != null) {
                      await ref
                          .read(currentMonthBudgetsProvider.notifier)
                          .delete(budget.id!);
                    }
                  },
                )),
      ],
    );
  }

  static Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete budget?'),
            content: const Text(
                'This removes the spending limit for this category.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.error),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalBudget,
    required this.totalSpent,
    required this.overCount,
  });
  final double totalBudget;
  final double totalSpent;
  final int overCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final remaining = totalBudget - totalSpent;
    final pct = totalBudget > 0
        ? (totalSpent / totalBudget).clamp(0.0, 1.0)
        : 0.0;
    final isOver = totalSpent > totalBudget;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Total Budget',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (overCount > 0) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.colorScheme.errorContainer,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      '$overCount over budget',
                      style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCol(
                    label: 'Budgeted',
                    value: CurrencyFormatter.format(totalBudget),
                    color: context.colorScheme.onSurface),
                _StatCol(
                    label: 'Spent',
                    value: CurrencyFormatter.format(totalSpent),
                    color: colors.expense),
                _StatCol(
                    label: isOver ? 'Over by' : 'Remaining',
                    value: CurrencyFormatter.format(remaining.abs()),
                    color: isOver ? colors.expense : colors.income),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor:
                    context.colorScheme.surfaceContainerHighest,
                color: isOver ? colors.expense : colors.income,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${(pct * 100).toStringAsFixed(0)}% of budget used',
              style: context.textTheme.labelSmall
                  ?.copyWith(color: context.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: context.colorScheme.outline)),
          Text(value,
              style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'RobotoMono')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Individual budget card with progress bar
// ---------------------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.month,
    required this.onEdit,
    required this.onDelete,
  });
  final Budget budget;
  final DateTime month;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final pct = budget.spentPercentage;
    final barColor = budget.isOverBudget
        ? colors.expense
        : budget.isNearLimit
            ? Colors.orange
            : colors.income;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        context.colorScheme.primaryContainer,
                    child: Icon(
                      CategoryHelper.getIcon(budget.category),
                      size: AppSpacing.iconMd,
                      color: context.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(budget.category,
                            style:
                                context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                        Text(
                          _statusLabel(budget),
                          style: context.textTheme.labelSmall
                              ?.copyWith(color: barColor),
                        ),
                      ],
                    ),
                  ),
                  // Amounts on the right
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(budget.spentAmount),
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'RobotoMono',
                          color: budget.isOverBudget
                              ? colors.expense
                              : context.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'of ${CurrencyFormatter.format(budget.budgetAmount)}',
                        style: context.textTheme.labelSmall?.copyWith(
                            color: context.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: AppSpacing.iconMd),
                    tooltip: 'Delete budget',
                    color: context.colorScheme.error,
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusFull),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor:
                      context.colorScheme.surfaceContainerHighest,
                  color: barColor,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(pct * 100).toStringAsFixed(0)}% used',
                    style: context.textTheme.labelSmall
                        ?.copyWith(color: context.colorScheme.outline),
                  ),
                  Text(
                    budget.isOverBudget
                        ? 'Over by ${CurrencyFormatter.format((-budget.remainingAmount))}'
                        : '${CurrencyFormatter.format(budget.remainingAmount)} left',
                    style: context.textTheme.labelSmall?.copyWith(
                        color: budget.isOverBudget
                            ? colors.expense
                            : context.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(Budget b) {
    if (b.isOverBudget) return 'Over budget';
    if (b.isNearLimit) return 'Approaching limit';
    return 'On track';
  }
}

// ---------------------------------------------------------------------------
// Add / Edit bottom sheet
// ---------------------------------------------------------------------------

class _AddEditBudgetSheet extends ConsumerStatefulWidget {
  const _AddEditBudgetSheet({required this.month, this.existing});
  final DateTime month;
  final Budget? existing;

  @override
  ConsumerState<_AddEditBudgetSheet> createState() =>
      _AddEditBudgetSheetState();
}

class _AddEditBudgetSheetState
    extends ConsumerState<_AddEditBudgetSheet> {
  final _amountController = TextEditingController();
  String? _selectedCategory;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedCategory = widget.existing!.category;
      _amountController.text =
          widget.existing!.budgetAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a category')));
      return;
    }

    setState(() => _saving = true);

    final budget = Budget(
      id: widget.existing?.id,
      year: widget.month.year,
      month: widget.month.month,
      category: _selectedCategory!,
      budgetAmount: double.parse(_amountController.text.trim()),
      alertAtPercentage: 80,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );

    try {
      await ref.read(currentMonthBudgetsProvider.notifier).upsert(budget);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('_AddEditBudgetSheet._save error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save budget. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusFull),
                ),
              ),
            ),
            Text(
              isEdit ? 'Edit Budget' : 'Set Budget',
              style: context.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.base),

            // Category picker
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: buildCategoryList(
                      ref.watch(customCategoriesProvider), 'expense')
                  .where((c) => c != kAddCustomCategorysentinel)
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Icon(CategoryHelper.getIcon(c),
                                size: AppSpacing.iconMd,
                                color: CategoryHelper.getColor(c)),
                            const SizedBox(width: AppSpacing.sm),
                            Text(c),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: isEdit
                  ? null
                  : (v) => setState(() => _selectedCategory = v),
              validator: (v) =>
                  v == null ? 'Please select a category' : null,
            ),
            const SizedBox(height: AppSpacing.base),

            // Amount field
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Budget Amount',
                prefixIcon: Icon(Icons.currency_rupee),
                hintText: '0',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter an amount';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Update' : 'Set Budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
