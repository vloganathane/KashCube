import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/credit.dart';
import '../../providers/credit_provider.dart';
import '../../widgets/party_picker_field.dart';

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _CreditsFilter { all, pendingGiven, pendingReceived, overdue, cleared }

extension _CreditsFilterLabel on _CreditsFilter {
  String get label => switch (this) {
        _CreditsFilter.all => 'All',
        _CreditsFilter.pendingGiven => 'I Lent',
        _CreditsFilter.pendingReceived => 'I Owe',
        _CreditsFilter.overdue => 'Overdue',
        _CreditsFilter.cleared => 'Cleared',
      };
}

// ---------------------------------------------------------------------------
// Credits Screen
// ---------------------------------------------------------------------------

/// Udhar / Credits screen — informal IOU tracker for personal & business use.
///
/// Distinct from [LoansScreen] (formal EMI schedules).
/// This is quick-entry: "Raju owes me ₹500 from 3 Jan."
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  _CreditsFilter _filter = _CreditsFilter.all;

  @override
  Widget build(BuildContext context) {
    final creditsAsync = ref.watch(activeCreditsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dues')),
      body: Column(
        children: [
          // ── Summary strip ─────────────────────────────────────────────
          _SummaryStrip(),

          // ── Filter chips ──────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: _CreditsFilter.values.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: creditsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final filtered = _applyFilter(all);
                if (filtered.isEmpty) {
                  return _EmptyState(filter: _filter);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) => _CreditTile(
                    credit: filtered[i],
                    onRecordPayment: () => _recordPayment(context, filtered[i]),
                    onEdit: () => _openEdit(context, filtered[i]),
                    onDelete: () => _confirmDelete(context, filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.add),
        label: const Text('New Due'),
      ),
    );
  }

  List<Credit> _applyFilter(List<Credit> all) => switch (_filter) {
        _CreditsFilter.all => all,
        _CreditsFilter.pendingGiven => all
            .where((c) => c.isGiven && !c.isCleared)
            .toList(),
        _CreditsFilter.pendingReceived => all
            .where((c) => c.isReceived && !c.isCleared)
            .toList(),
        _CreditsFilter.overdue => all
            .where((c) =>
                !c.isCleared &&
                c.dueDate != null &&
                c.dueDate!.isBefore(DateTime.now()))
            .toList(),
        _CreditsFilter.cleared => all.where((c) => c.isCleared).toList(),
      };

  Future<void> _openAdd(BuildContext context) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddCreditScreen()),
    );
    if (added == true && mounted) {
      ref.read(activeCreditsProvider.notifier).loadActive();
    }
  }

  Future<void> _openEdit(BuildContext context, Credit credit) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddCreditScreen(credit: credit)),
    );
    if (updated == true && mounted) {
      ref.read(activeCreditsProvider.notifier).loadActive();
    }
  }

  Future<void> _recordPayment(BuildContext context, Credit credit) async {
    final amtCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Record Payment — ${credit.customerName}'),
        content: TextFormField(
          controller: amtCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Amount paid',
            prefixText: '₹ ',
            border: const OutlineInputBorder(),
            helperText:
                'Pending: ${CurrencyFormatter.format(credit.pendingAmount)}',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final amt = double.tryParse(amtCtrl.text) ?? 0;
      if (amt > 0) {
        await ref
            .read(activeCreditsProvider.notifier)
            .recordPayment(credit.id!, amt);
      }
    }
    amtCtrl.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, Credit credit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content:
            Text('Remove dues entry for ${credit.customerName}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: ctx.colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref
          .read(activeCreditsProvider.notifier)
          .deleteCredit(credit.id!);
    }
  }
}

// ---------------------------------------------------------------------------
// Summary strip
// ---------------------------------------------------------------------------

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final givenAsync = ref.watch(totalCreditsPendingGivenProvider);
    final receivedAsync = ref.watch(totalCreditsPendingReceivedProvider);
    final colors = context.kashColors;
    final given = givenAsync.valueOrNull ?? 0.0;
    final received = receivedAsync.valueOrNull ?? 0.0;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'To Collect',
              value: CurrencyFormatter.format(given),
              color: colors.credit,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
          Container(
              width: 1,
              height: 36,
              color: context.colorScheme.outlineVariant),
          Expanded(
            child: _Stat(
              label: 'To Pay',
              value: CurrencyFormatter.format(received),
              color: colors.expense,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          Container(
              width: 1,
              height: 36,
              color: context.colorScheme.outlineVariant),
          Expanded(
            child: _Stat(
              label: 'Net',
              value: CurrencyFormatter.format((given - received).abs()),
              color: given >= received ? colors.income : colors.expense,
              icon: given >= received
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.colorScheme.outline)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Credit tile
// ---------------------------------------------------------------------------

class _CreditTile extends StatelessWidget {
  const _CreditTile({
    required this.credit,
    required this.onRecordPayment,
    required this.onEdit,
    required this.onDelete,
  });

  final Credit credit;
  final VoidCallback onRecordPayment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isGiven = credit.isGiven;
    final dirColor = isGiven ? colors.credit : colors.expense;
    final now = DateTime.now();
    final isOverdue = !credit.isCleared &&
        credit.dueDate != null &&
        credit.dueDate!.isBefore(now);

    final statusLabel = credit.isCleared
        ? 'Cleared'
        : isOverdue
            ? 'Overdue'
            : 'Pending';
    final statusColor = credit.isCleared
        ? colors.income
        : isOverdue
            ? colors.overdue
            : colors.credit;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: dirColor.withValues(alpha: 0.12),
        child: Text(
          credit.customerName.isNotEmpty
              ? credit.customerName[0].toUpperCase()
              : '?',
          style: TextStyle(fontWeight: FontWeight.bold, color: dirColor),
        ),
      ),
      title: Text(credit.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${isGiven ? 'You lent' : 'You owe'} · ${DateFormatter.format(credit.creditDate)}',
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          if (credit.dueDate != null)
            Text(
              'Due ${DateFormatter.format(credit.dueDate!)}',
              style: context.textTheme.labelSmall?.copyWith(
                  color: isOverdue ? colors.overdue : context.colorScheme.outline),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(credit.pendingAmount > 0
                ? credit.pendingAmount
                : credit.totalAmount),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: dirColor),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                  fontSize: 10,
                  color: statusColor,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      onTap: _buildContextMenu(context),
    );
  }

  VoidCallback _buildContextMenu(BuildContext context) => () {
        showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Record Payment'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onRecordPayment();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEdit();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: ctx.colorScheme.error),
                  title: Text('Delete',
                      style: TextStyle(color: ctx.colorScheme.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        );
      };
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _CreditsFilter filter;

  @override
  Widget build(BuildContext context) {
    final msg = switch (filter) {
      _CreditsFilter.all => 'No dues recorded yet.\nTap + to add one.',
      _CreditsFilter.pendingGiven => 'No money lent out.',
      _CreditsFilter.pendingReceived => 'You don\'t owe anyone right now.',
      _CreditsFilter.overdue => 'No overdue entries.',
      _CreditsFilter.cleared => 'No cleared entries yet.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_rupee_outlined,
                size: 48,
                color: context.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.base),
            Text(msg,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit Credit screen
// ---------------------------------------------------------------------------

class AddCreditScreen extends ConsumerStatefulWidget {
  const AddCreditScreen({super.key, this.credit});

  /// If provided, opens in edit mode.
  final Credit? credit;

  @override
  ConsumerState<AddCreditScreen> createState() => _AddCreditScreenState();
}

class _AddCreditScreenState extends ConsumerState<AddCreditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CreditDirection _direction = CreditDirection.given;
  DateTime _creditDate = DateTime.now();
  DateTime? _dueDate;
  bool _saving = false;

  /// Party FK — set when user selects from autocomplete.
  int? _selectedCustomerId;

  bool get _isEditing => widget.credit != null;

  @override
  void initState() {
    super.initState();
    final c = widget.credit;
    if (c != null) {
      _direction = c.direction;
      _nameCtrl.text = c.customerName;
      _amountCtrl.text = c.totalAmount.toStringAsFixed(0);
      _phoneCtrl.text = c.phoneNumber ?? '';
      _creditDate = c.creditDate;
      _dueDate = c.dueDate;
      _notesCtrl.text = c.notes ?? '';
      _selectedCustomerId = c.customerId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Due' : 'New Due'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.base),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEditing ? 'Update Due' : 'Save Due'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // ── Direction selector ───────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Type',
                        style: context.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children:
                          CreditDirection.values.map((d) {
                        final selected = _direction == d;
                        final isGiven = d == CreditDirection.given;
                        final color =
                            isGiven ? colors.credit : colors.expense;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: isGiven ? AppSpacing.sm : 0),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _direction = d),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? color.withValues(alpha: 0.10)
                                      : null,
                                  border: Border.all(
                                    color: selected
                                        ? color
                                        : context
                                            .colorScheme.outlineVariant,
                                    width: selected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      isGiven
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      color: selected
                                          ? color
                                          : context.colorScheme
                                              .onSurfaceVariant,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      isGiven
                                          ? 'I Lent (Diya)'
                                          : 'I Owe (Liya)',
                                      style: context.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: selected
                                            ? color
                                            : context.colorScheme
                                                .onSurfaceVariant,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      isGiven
                                          ? 'They owe you'
                                          : 'You owe them',
                                      style: context.textTheme.bodySmall
                                          ?.copyWith(
                                        color: context.colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Amount ───────────────────────────────────────────────────
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount *',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final a = double.tryParse(v);
                if (a == null || a <= 0) return 'Invalid amount';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Party name ────────────────────────────────────────────────
            PartyPickerField(
              controller: _nameCtrl,
              labelText: _direction == CreditDirection.given
                  ? 'Borrower Name *'
                  : 'Lender Name *',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,              onPartySelected: (party) =>
                  setState(() => _selectedCustomerId = party.id),            ),
            const SizedBox(height: AppSpacing.base),

            // ── Phone ─────────────────────────────────────────────────────
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Credit date ───────────────────────────────────────────────
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _creditDate,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _creditDate = picked);
                },
                child: Text(DateFormatter.format(_creditDate)),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Due date ──────────────────────────────────────────────────
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Due Date (optional)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.event_outlined),
                suffixIcon: _dueDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _dueDate = null),
                      )
                    : null,
              ),
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        _dueDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: Text(
                  _dueDate != null
                      ? DateFormatter.format(_dueDate!)
                      : 'Not set',
                  style: _dueDate == null
                      ? TextStyle(
                          color: context.colorScheme.onSurfaceVariant)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final amount = double.parse(_amountCtrl.text.trim());
    final name = _nameCtrl.text.trim();
    final phone =
        _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    try {
      if (_isEditing) {
        final updated = widget.credit!.copyWith(
          customerName: name,
          phoneNumber: phone,
          totalAmount: amount,
          pendingAmount: amount - widget.credit!.paidAmount,
          direction: _direction,
          creditDate: _creditDate,
          dueDate: _dueDate,
          notes: notes,
          updatedAt: DateTime.now(),
          customerId: _selectedCustomerId ?? widget.credit!.customerId,
        );
        await ref.read(activeCreditsProvider.notifier).updateCredit(updated);
      } else {
        final credit = Credit(
          customerName: name,
          phoneNumber: phone,
          totalAmount: amount,
          pendingAmount: amount,
          direction: _direction,
          creditDate: _creditDate,
          dueDate: _dueDate,
          notes: notes,
          customerId: _selectedCustomerId,
          businessId: null, // personal by default; business context set elsewhere
        );
        await ref.read(activeCreditsProvider.notifier).addCredit(credit);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
