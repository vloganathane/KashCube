import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/models/recurring_transaction.dart';
import '../../providers/recurring_provider.dart';
import '../../widgets/party_picker_field.dart';
import '../search/search_screen.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _currencyFormat = NumberFormat.currency(
  locale: AppConstants.locale,
  symbol: AppConstants.currencySymbol,
  decimalDigits: 0,
);

/// Screen listing all recurring transactions with ability to add/edit/delete.
class RecurringTransactionsScreen extends ConsumerWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(recurringTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search recurring',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SearchScreen(initialFilter: SearchFilter.recurring),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_recurring',
        onPressed: () => _openAddScreen(context),
        child: const Icon(Icons.add),
      ),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat,
                    size: 64,
                    color: context.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    'No recurring transactions',
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Add one to auto-create transactions'),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _RecurringCard(item: items[i]),
          );
        },
      ),
    );
  }

  void _openAddScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddRecurringTransactionScreen()),
    );
  }
}

// ---------------------------------------------------------------------------
// Recurring transaction card
// ---------------------------------------------------------------------------

class _RecurringCard extends ConsumerWidget {
  const _RecurringCard({required this.item});

  final RecurringTransaction item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = item.type == 'income';
    final amountColor = isIncome
        ? context.kashColors.income
        : context.kashColors.expense;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: amountColor.withValues(alpha: 0.12),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: amountColor,
          ),
        ),
        title: Text(item.category),
        subtitle: Text(
          '${item.frequency.label} · Next: ${_dateFormat.format(item.nextDate)}'
          '${item.partyName != null ? ' · ${item.partyName}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '-'}${_currencyFormat.format(item.amount)}',
              style: context.textTheme.titleSmall?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch(
              value: item.isActive,
              onChanged: (val) {
                ref
                    .read(recurringTransactionsProvider.notifier)
                    .toggleActive(item.id!, val);
              },
            ),
          ],
        ),
        onTap: () => _showDetail(context, ref),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.category, style: ctx.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _currencyFormat.format(item.amount),
                style: ctx.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              _DetailRow(
                label: 'Type',
                value: item.type == 'income' ? 'Income' : 'Expense',
              ),
              _DetailRow(label: 'Frequency', value: item.frequency.label),
              _DetailRow(
                label: 'Next Date',
                value: _dateFormat.format(item.nextDate),
              ),
              if (item.partyName != null)
                _DetailRow(label: 'Party', value: item.partyName!),
              if (item.paymentMethod != null)
                _DetailRow(label: 'Payment', value: item.paymentMethod!),
              if (item.notes != null && item.notes!.isNotEmpty)
                _DetailRow(label: 'Notes', value: item.notes!),
              if (item.lastGenerated != null)
                _DetailRow(
                  label: 'Last Generated',
                  value: _dateFormat.format(item.lastGenerated!),
                ),
              _DetailRow(
                label: 'Status',
                value: item.isActive ? 'Active' : 'Paused',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final confirmed = await showDialog<bool>(
                          context: context,
                          useRootNavigator: false,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete?'),
                            content: const Text(
                              'This will remove the recurring transaction. '
                              'Past generated transactions are not affected.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: context.colorScheme.error,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          ref
                              .read(recurringTransactionsProvider.notifier)
                              .remove(item.id!);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
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
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add recurring transaction screen
// ---------------------------------------------------------------------------

class AddRecurringTransactionScreen extends ConsumerStatefulWidget {
  const AddRecurringTransactionScreen({super.key});

  @override
  ConsumerState<AddRecurringTransactionScreen> createState() =>
      _AddRecurringTransactionScreenState();
}

class _AddRecurringTransactionScreenState
    extends ConsumerState<AddRecurringTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _partyController = TextEditingController();
  final _notesController = TextEditingController();

  String _type = 'expense';
  String _category = AppConstants.defaultCategories.first;
  String _paymentMethod = AppConstants.paymentMethods.first;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  DateTime _startDate = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _partyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _type == 'income'
        ? AppConstants.incomeCategories
        : AppConstants.defaultCategories;

    // Reset category if current one is not in the list
    if (!categories.contains(_category)) {
      _category = categories.first;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Recurring')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.base,
          ),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Type toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (val) => setState(() => _type = val.first),
            ),
            const SizedBox(height: AppSpacing.base),

            // Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '${AppConstants.currencySymbol} ',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter amount';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Category
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Frequency
            DropdownButtonFormField<RecurringFrequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              items: RecurringFrequency.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _frequency = v);
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Start date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('First occurrence'),
              subtitle: Text(_dateFormat.format(_startDate)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _startDate = picked);
                }
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Payment method
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
              items: AppConstants.paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _paymentMethod = v);
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Party name
            PartyPickerField(
              controller: _partyController,
              labelText: 'Party (optional)',
            ),
            const SizedBox(height: AppSpacing.base),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final recurring = RecurringTransaction(
      amount: double.parse(_amountController.text),
      type: _type,
      category: _category,
      frequency: _frequency,
      nextDate: _startDate,
      paymentMethod: _paymentMethod,
      partyName: _partyController.text.isEmpty ? null : _partyController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    ref.read(recurringTransactionsProvider.notifier).add(recurring);
    Navigator.of(context).pop();
  }
}
