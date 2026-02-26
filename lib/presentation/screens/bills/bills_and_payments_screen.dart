import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/scheduled_payment.dart';
import '../../providers/scheduled_payment_provider.dart';
import '../../widgets/party_picker_field.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _currFmt = NumberFormat.currency(
  locale: AppConstants.locale,
  symbol: AppConstants.currencySymbol,
  decimalDigits: 0,
);

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

enum _SpFilter { all, recurring, oneTime, overdue, paid }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Unified Bills & Payments screen.
///
/// Replaces the legacy `BillsScreen` and `RecurringTransactionsScreen`.
class BillsAndPaymentsScreen extends ConsumerStatefulWidget {
  const BillsAndPaymentsScreen({super.key});

  @override
  ConsumerState<BillsAndPaymentsScreen> createState() =>
      _BillsAndPaymentsScreenState();
}

class _BillsAndPaymentsScreenState
    extends ConsumerState<BillsAndPaymentsScreen> {
  _SpFilter _filter = _SpFilter.all;

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(scheduledPaymentsProvider);
    final summary = ref.watch(scheduledMonthlySummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(scheduledPaymentsProvider.notifier).load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_bills_payments',
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          // ── Summary ──────────────────────────────────────────────────────
          _SummaryCard(
            monthlyExpense: summary.expense,
            monthlyIncome: summary.income,
          ),

          // ── Filter chips ─────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: _SpFilter.values.map((f) {
                final label = switch (f) {
                  _SpFilter.all => 'All',
                  _SpFilter.recurring => 'Recurring',
                  _SpFilter.oneTime => 'One-time',
                  _SpFilter.overdue => 'Overdue',
                  _SpFilter.paid => 'Paid',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: asyncItems.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error: $e')),
              data: (items) {
                final filtered = _applyFilter(items);
                if (filtered.isEmpty) return _emptyState(context);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.sm,
                    AppSpacing.base,
                    AppSpacing.xxxl,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) =>
                      _PaymentCard(item: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ScheduledPayment> _applyFilter(List<ScheduledPayment> items) =>
      switch (_filter) {
        _SpFilter.all => items,
        _SpFilter.recurring => items.where((p) => !p.isOneTime).toList(),
        _SpFilter.oneTime => items.where((p) => p.isOneTime).toList(),
        _SpFilter.overdue => items.where((p) => p.isOverdue).toList(),
        _SpFilter.paid => items.where((p) => p.isPaidThisPeriod).toList(),
      };

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_repeat,
              size: 64,
              color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              _filter == _SpFilter.all
                  ? 'No bills or payments yet'
                  : 'Nothing here',
              style: context.textTheme.titleMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_filter == _SpFilter.all) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text('Tap + to add a bill, subscription, or salary'),
            ],
          ],
        ),
      );

  void _openAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddEditScheduledPaymentScreen()),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.monthlyExpense,
    required this.monthlyIncome,
  });

  final double monthlyExpense;
  final double monthlyIncome;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Monthly out',
                amount: monthlyExpense,
                color: colors.expense,
                icon: Icons.arrow_upward,
              ),
            ),
            const VerticalDivider(width: AppSpacing.xl),
            Expanded(
              child: _SummaryTile(
                label: 'Monthly in',
                amount: monthlyIncome,
                color: colors.income,
                icon: Icons.arrow_downward,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(amount),
            style: context.textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Payment card
// ---------------------------------------------------------------------------

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.item});

  final ScheduledPayment item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = item.isIncome;
    final amountColor =
        isIncome ? context.kashColors.income : context.kashColors.expense;
    final isPaid = item.isPaidThisPeriod;
    final isOverdue = item.isOverdue;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: amountColor.withValues(alpha: 0.12),
          child: Icon(
            _iconFor(item),
            color: amountColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isOverdue)
              _Badge(label: 'Overdue', color: context.kashColors.overdue),
            if (isPaid && !isOverdue)
              _Badge(label: 'Paid', color: context.kashColors.income),
          ],
        ),
        subtitle: Text(
          _subtitle(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          '${isIncome ? '+' : '-'}${_currFmt.format(item.amount)}',
          style: context.textTheme.titleSmall?.copyWith(
            color: amountColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: () => _showDetail(context, ref),
      ),
    );
  }

  IconData _iconFor(ScheduledPayment p) {
    if (p.isOneTime) return Icons.event;
    if (p.autoCreate) return Icons.repeat;
    return Icons.receipt_long;
  }

  String _subtitle(ScheduledPayment p) {
    final parts = <String>[p.category];
    if (p.isOneTime) {
      parts.add('One-time · ${_dateFmt.format(p.nextDate)}');
    } else {
      parts.add(p.frequency?.label ?? '');
      parts.add('Next: ${_dateFmt.format(p.nextDate)}');
    }
    if (p.partyName != null) parts.add(p.partyName!);
    return parts.where((s) => s.isNotEmpty).join(' · ');
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DetailSheet(item: item, ref: ref),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: AppSpacing.xs),
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Detail sheet
// ---------------------------------------------------------------------------

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.item, required this.ref});

  final ScheduledPayment item;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isPaid = item.isPaidThisPeriod;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: context.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _currFmt.format(item.amount),
              style: context.textTheme.headlineSmall,
            ),
            const Divider(height: AppSpacing.xl),
            _Row('Type', item.isIncome ? 'Income' : 'Expense'),
            _Row('Category', item.category),
            _Row(
              'Schedule',
              item.isOneTime
                  ? 'One-time'
                  : item.frequency?.label ?? 'Recurring',
            ),
            _Row('Due', _dateFmt.format(item.nextDate)),
            if (item.partyName != null) _Row('Party', item.partyName!),
            if (item.paymentMethod != null)
              _Row('Payment', item.paymentMethod!),
            _Row('Auto-create txn', item.autoCreate ? 'Yes' : 'No'),
            if (item.isAutoPay) _Row('Auto-pay', 'Set up'),
            if (item.lastPaidDate != null)
              _Row('Last paid', _dateFmt.format(item.lastPaidDate!)),
            if (item.notes != null && item.notes!.isNotEmpty)
              _Row('Notes', item.notes!),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                // Mark paid / unpaid
                if (!item.isOneTime) ...[
                  Expanded(
                    child: isPaid
                        ? OutlinedButton.icon(
                            onPressed: () {
                              ref
                                  .read(scheduledPaymentsProvider.notifier)
                                  .markUnpaid(item);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.undo),
                            label: const Text('Mark Unpaid'),
                          )
                        : FilledButton.icon(
                            onPressed: () {
                              ref
                                  .read(scheduledPaymentsProvider.notifier)
                                  .markPaid(item);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Mark Paid'),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                // Edit
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            AddEditScheduledPaymentScreen(payment: item),
                      ));
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Delete
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colorScheme.error,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete?'),
                        content:
                            const Text('This will remove the scheduled item.'),
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
                    if (ok == true && item.id != null) {
                      ref.read(scheduledPaymentsProvider.notifier).remove(item.id!);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 130,
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

// ---------------------------------------------------------------------------
// Add / Edit screen
// ---------------------------------------------------------------------------

class AddEditScheduledPaymentScreen extends ConsumerStatefulWidget {
  const AddEditScheduledPaymentScreen({super.key, this.payment});

  /// Pass an existing payment to enter edit mode.
  final ScheduledPayment? payment;

  @override
  ConsumerState<AddEditScheduledPaymentScreen> createState() =>
      _AddEditScheduledPaymentScreenState();
}

class _AddEditScheduledPaymentScreenState
    extends ConsumerState<AddEditScheduledPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _partyCtrl;
  late final TextEditingController _notesCtrl;

  late String _type;
  late bool _isOneTime;
  late ScheduledFrequency _frequency;
  late int _dueDay;
  late DateTime _dueDate;
  late bool _autoCreate;
  late bool _isAutoPay;
  late String _category;
  late String? _paymentMethod;

  static const _billCategories = [
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
    'Education',
    'Healthcare',
    'Other',
  ];

  bool get _isEdit => widget.payment != null;

  @override
  void initState() {
    super.initState();
    final p = widget.payment;
    _nameCtrl =
        TextEditingController(text: p?.name ?? '');
    _amountCtrl =
        TextEditingController(text: p != null ? p.amount.toStringAsFixed(0) : '');
    _partyCtrl =
        TextEditingController(text: p?.partyName ?? '');
    _notesCtrl =
        TextEditingController(text: p?.notes ?? '');

    _type = p?.type ?? 'expense';
    _isOneTime = p?.isOneTime ?? false;
    _frequency = p?.frequency ?? ScheduledFrequency.monthly;
    _dueDay = p?.dueDay ?? 1;
    _dueDate = p?.nextDate ?? DateTime.now().add(const Duration(days: 7));
    _autoCreate = p?.autoCreate ?? false;
    _isAutoPay = p?.isAutoPay ?? false;
    _category = p?.category ?? _billCategories.first;
    _paymentMethod = p?.paymentMethod ?? AppConstants.paymentMethods.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _partyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<String> get _categories => _type == 'income'
      ? AppConstants.incomeCategories
      : _billCategories;

  @override
  Widget build(BuildContext context) {
    // Keep _category valid when type changes
    if (!_categories.contains(_category)) {
      _category = _categories.first;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Payment' : 'Add Bill / Payment'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // ── Type toggle ────────────────────────────────────────────────
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
              onSelectionChanged: (v) =>
                  setState(() => _type = v.first),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Schedule toggle ────────────────────────────────────────────
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Recurring'),
                  icon: Icon(Icons.repeat),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('One-time'),
                  icon: Icon(Icons.event),
                ),
              ],
              selected: {_isOneTime},
              onSelectionChanged: (v) =>
                  setState(() => _isOneTime = v.first),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Name ───────────────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Netflix, Electricity Bill, Salary',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Amount ─────────────────────────────────────────────────────
            TextFormField(
              controller: _amountCtrl,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${AppConstants.currencySymbol} ',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter amount';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Category ───────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _categories.contains(_category)
                  ? _category
                  : _categories.first,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Recurring fields ───────────────────────────────────────────
            if (!_isOneTime) ...[
              DropdownButtonFormField<ScheduledFrequency>(
                value: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  prefixIcon: Icon(Icons.repeat),
                  border: OutlineInputBorder(),
                ),
                items: ScheduledFrequency.values
                    .map((f) =>
                        DropdownMenuItem(value: f, child: Text(f.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _frequency = v);
                },
              ),
              const SizedBox(height: AppSpacing.base),

              if (_frequency == ScheduledFrequency.monthly)
                DropdownButtonFormField<int>(
                  value: _dueDay,
                  decoration: const InputDecoration(
                    labelText: 'Due Day (day of month)',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(28, (i) => i + 1)
                      .map((d) => DropdownMenuItem(
                          value: d, child: Text('Day $d')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _dueDay = v);
                  },
                ),
              if (_frequency == ScheduledFrequency.monthly)
                const SizedBox(height: AppSpacing.base),
            ],

            // ── One-time date picker ───────────────────────────────────────
            if (_isOneTime) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Due Date'),
                subtitle: Text(_dateFmt.format(_dueDate)),
                shape: const RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate,
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
              ),
              const SizedBox(height: AppSpacing.base),
            ],

            // ── Toggles ────────────────────────────────────────────────────
            SwitchListTile.adaptive(
              value: _autoCreate,
              onChanged: (v) => setState(() => _autoCreate = v),
              title: const Text('Auto-create transaction'),
              subtitle: const Text(
                  'Automatically add to ledger on the due date'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile.adaptive(
              value: _isAutoPay,
              onChanged: (v) => setState(() => _isAutoPay = v),
              title: const Text('Auto-pay / standing instruction'),
              subtitle: const Text('Payment is set up with bank/UPI'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── Payment method ─────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                prefixIcon: Icon(Icons.credit_card),
                border: OutlineInputBorder(),
              ),
              items: AppConstants.paymentMethods
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _paymentMethod = v),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Party ──────────────────────────────────────────────────────
            PartyPickerField(
              controller: _partyCtrl,
              labelText: 'Party / Payee (optional)',
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Notes ──────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Save ───────────────────────────────────────────────────────
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isEdit ? 'Update' : 'Save'),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final amount = double.parse(_amountCtrl.text);

    // Compute the stored next_date
    DateTime nextDate;
    if (_isOneTime) {
      nextDate = _dueDate;
    } else if (_frequency == ScheduledFrequency.monthly) {
      final today = now;
      nextDate = DateTime(today.year, today.month, _dueDay);
      if (nextDate.isBefore(today)) {
        nextDate = DateTime(today.year, today.month + 1, _dueDay);
      }
    } else {
      nextDate = _frequency.nextOccurrence(now);
    }

    final payment = ScheduledPayment(
      id: widget.payment?.id,
      name: _nameCtrl.text.trim(),
      amount: amount,
      type: _type,
      category: _category,
      isOneTime: _isOneTime,
      frequency: _isOneTime ? null : _frequency,
      dueDay: (!_isOneTime && _frequency == ScheduledFrequency.monthly)
          ? _dueDay
          : null,
      autoCreate: _autoCreate,
      isAutoPay: _isAutoPay,
      isActive: widget.payment?.isActive ?? true,
      nextDate: nextDate,
      lastPaidDate: widget.payment?.lastPaidDate,
      lastGenerated: widget.payment?.lastGenerated,
      partyName:
          _partyCtrl.text.trim().isEmpty ? null : _partyCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: widget.payment?.createdAt ?? now,
      updatedAt: _isEdit ? now : null,
    );

    final notifier = ref.read(scheduledPaymentsProvider.notifier);
    if (_isEdit) {
      notifier.update(payment);
    } else {
      notifier.add(payment);
    }
    Navigator.of(context).pop();
  }
}
