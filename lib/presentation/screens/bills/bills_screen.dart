import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/recurring_transaction.dart';
import '../../providers/bill_schedule_provider.dart';

/// Filter tabs for the bills list.
enum _BillFilter { all, upcoming, overdue, paid }

/// Screen for managing scheduled / recurring bill payments.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  _BillFilter _filter = _BillFilter.all;

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(scheduledBillsProvider);
    final totalMonthlyAsync = ref.watch(totalMonthlyBillsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Payments'),
      ),
      body: Column(
        children: [
          // Summary card
          totalMonthlyAsync.when(
            data: (total) => _SummaryCard(totalMonthly: total),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: _BillFilter.values.map((f) {
                final label = switch (f) {
                  _BillFilter.all => 'All',
                  _BillFilter.upcoming => 'Upcoming',
                  _BillFilter.overdue => 'Overdue',
                  _BillFilter.paid => 'Paid',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),

          // Bills list
          Expanded(
            child: billsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (bills) => _buildList(bills),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_bills',
        onPressed: () => _showAddBillSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(List<Bill> bills) {
    final filtered = switch (_filter) {
      _BillFilter.all => bills,
      _BillFilter.upcoming =>
        bills.where((b) => !b.isPaidThisPeriod && !b.isOverdue).toList(),
      _BillFilter.overdue => bills.where((b) => b.isOverdue).toList(),
      _BillFilter.paid =>
        bills.where((b) => b.isPaidThisPeriod).toList(),
    };

    if (filtered.isEmpty) {
      return _buildEmpty();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _BillTile(
        bill: filtered[index],
        onMarkPaid: () => _markPaid(filtered[index]),
        onEdit: () => _showEditBillSheet(context, filtered[index]),
        onDelete: () => _confirmDelete(filtered[index]),
      ),
    );
  }

  Widget _buildEmpty() {
    final msg = switch (_filter) {
      _BillFilter.all => 'No bills added yet.\nTap + to add a bill.',
      _BillFilter.upcoming => 'No upcoming bills.',
      _BillFilter.overdue => 'No overdue bills. 🎉',
      _BillFilter.paid => 'No bills paid this period.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: context.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyLarge?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _markPaid(Bill bill) {
    ref.read(scheduledBillsProvider.notifier).markPaid(bill.id!);
    ref.invalidate(totalMonthlyBillsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${bill.name} marked as paid')),
    );
  }

  void _confirmDelete(Bill bill) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Remove "${bill.name}" from your bills?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(scheduledBillsProvider.notifier).deleteBill(bill.id!);
              ref.invalidate(totalMonthlyBillsProvider);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: context.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddBillSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEditBillSheet(
        onSave: (bill) {
          ref.read(scheduledBillsProvider.notifier).addBill(bill);
          ref.invalidate(totalMonthlyBillsProvider);
        },
      ),
    );
  }

  void _showEditBillSheet(BuildContext context, Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEditBillSheet(
        bill: bill,
        onSave: (updated) {
          ref.read(scheduledBillsProvider.notifier).updateBill(updated);
          ref.invalidate(totalMonthlyBillsProvider);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Summary Card
// ─────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double totalMonthly;

  const _SummaryCard({required this.totalMonthly});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm, AppSpacing.base, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long,
                size: AppSpacing.xl,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Bills',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(totalMonthly),
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bill Tile
// ─────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BillTile({
    required this.bill,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isPaid = bill.isPaidThisPeriod;
    final isOverdue = bill.isOverdue;

    final statusColor = isPaid
        ? colors.income
        : isOverdue
            ? colors.expense
            : context.colorScheme.onSurface;

    final statusLabel = isPaid
        ? 'Paid'
        : isOverdue
            ? 'Overdue'
            : 'Due in ${bill.daysUntilDue}d';

    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForCategory(bill.category),
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Name + due info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.name,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: isPaid
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bill.frequency.label} · Day ${bill.dueDay}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(bill.amount),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'RobotoMono',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // Mark paid / more
              if (!isPaid) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  icon: Icon(
                    Icons.check_circle_outline,
                    color: colors.income,
                  ),
                  tooltip: 'Mark Paid',
                  onPressed: onMarkPaid,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    return switch (category) {
      'Bills & Utilities' => Icons.receipt_long,
      'Rent' => Icons.home_outlined,
      'Insurance' => Icons.shield_outlined,
      'Subscription' => Icons.subscriptions_outlined,
      'EMI' => Icons.account_balance_outlined,
      'Internet' => Icons.wifi,
      'Phone' => Icons.phone_android,
      'Electricity' => Icons.bolt,
      'Water' => Icons.water_drop_outlined,
      'Gas' => Icons.local_fire_department_outlined,
      _ => Icons.payment_outlined,
    };
  }
}

// ─────────────────────────────────────────────
// Add / Edit Bill Bottom Sheet
// ─────────────────────────────────────────────

class _AddEditBillSheet extends StatefulWidget {
  final Bill? bill;
  final ValueChanged<Bill> onSave;

  const _AddEditBillSheet({this.bill, required this.onSave});

  @override
  State<_AddEditBillSheet> createState() => _AddEditBillSheetState();
}

class _AddEditBillSheetState extends State<_AddEditBillSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  late String _category;
  late RecurringFrequency _frequency;
  late int _dueDay;
  late bool _isAutoPay;
  late String? _paymentMethod;

  static const _categories = [
    'Bills & Utilities',
    'Rent',
    'Insurance',
    'Subscription',
    'EMI',
    'Internet',
    'Phone',
    'Electricity',
    'Water',
    'Gas',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final b = widget.bill;
    _nameController = TextEditingController(text: b?.name ?? '');
    _amountController = TextEditingController(
      text: b != null ? b.amount.toStringAsFixed(0) : '',
    );
    _notesController = TextEditingController(text: b?.notes ?? '');
    _category = b?.category ?? _categories.first;
    _frequency = b?.frequency ?? RecurringFrequency.monthly;
    _dueDay = b?.dueDay ?? 1;
    _isAutoPay = b?.isAutoPay ?? false;
    _paymentMethod = b?.paymentMethod;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.bill != null;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Bill' : 'Add Bill',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),

              // Bill name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Bill Name',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                  hintText: 'e.g. Electricity, Netflix, Rent',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter bill name' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              // Amount
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.currency_rupee),
                  hintText: '0',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter amount';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Category
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Frequency
              DropdownButtonFormField<RecurringFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  prefixIcon: Icon(Icons.repeat),
                ),
                items: RecurringFrequency.values
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _frequency = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Due day
              DropdownButtonFormField<int>(
                initialValue: _dueDay,
                decoration: const InputDecoration(
                  labelText: 'Due Day',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                items: List.generate(
                  28,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Day ${i + 1}'),
                  ),
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _dueDay = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Payment method
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  prefixIcon: Icon(Icons.payment_outlined),
                ),
                items: AppConstants.paymentMethods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
              const SizedBox(height: AppSpacing.md),

              // Auto-pay toggle
              SwitchListTile(
                title: const Text('Auto-pay'),
                subtitle: const Text('Auto-deducted from account'),
                value: _isAutoPay,
                onChanged: (v) => setState(() => _isAutoPay = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
                maxLines: 2,
                maxLength: 500,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Save button
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(isEdit ? Icons.check : Icons.add),
                label: Text(isEdit ? 'Update Bill' : 'Add Bill'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final bill = Bill(
      id: widget.bill?.id,
      name: _nameController.text.trim(),
      amount: double.parse(_amountController.text.trim()),
      category: _category,
      frequency: _frequency,
      dueDay: _dueDay,
      isAutoPay: _isAutoPay,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      lastPaidDate: widget.bill?.lastPaidDate,
      createdAt: widget.bill?.createdAt ?? DateTime.now(),
    );

    widget.onSave(bill);
    Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Public helper — call from anywhere (e.g. speed-dial FAB)
// ---------------------------------------------------------------------------

/// Shows the add-bill bottom sheet without navigating to BillsScreen.
void showAddBillSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddEditBillSheet(
      onSave: (bill) {
        ref.read(scheduledBillsProvider.notifier).addBill(bill);
        ref.invalidate(totalMonthlyBillsProvider);
      },
    ),
  );
}
