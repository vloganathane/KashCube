import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/loan_payment.dart';
import '../../providers/loan_payment_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/transaction_provider.dart';

// ---------------------------------------------------------------------------
// Loans Screen
// ---------------------------------------------------------------------------

enum _LoansFilter { all, lent, borrowed, overdue, cleared }

/// Dedicated screen for Loan contracts (lent/borrowed with optional EMI schedule).
/// Accessed from Home outstanding tile.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  _LoansFilter _filter = _LoansFilter.all;

  @override
  Widget build(BuildContext context) {
    final loansAsync = ref.watch(activeLoansProvider);
    final clearedAsync = ref.watch(clearedLoansProvider);
    final overdueAsync = ref.watch(overdueLoansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loans & Credits')),
      body: Column(
        children: [
          // Summary row
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.base, AppSpacing.base, 0),
            child: _SummaryCard(),
          ),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: _LoansFilter.values.map((f) {
                final label = switch (f) {
                  _LoansFilter.all => 'All',
                  _LoansFilter.lent => 'Lent (Diya)',
                  _LoansFilter.borrowed => 'Borrowed (Liya)',
                  _LoansFilter.overdue => 'Overdue',
                  _LoansFilter.cleared => 'Cleared',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),

          // Loan list
          Expanded(
            child: switch (_filter) {
              _LoansFilter.cleared => clearedAsync.when(
                  data: (loans) => _LoanList(loans: loans, filter: _filter),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              _LoansFilter.overdue => overdueAsync.when(
                  data: (loans) => _LoanList(loans: loans, filter: _filter),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              _ => loansAsync.when(
                  data: (loans) {
                    final filtered = switch (_filter) {
                      _LoansFilter.lent =>
                        loans.where((l) => l.isLent).toList(),
                      _LoansFilter.borrowed =>
                        loans.where((l) => l.isBorrowed).toList(),
                      _ => loans,
                    };
                    return _LoanList(loans: filtered, filter: _filter);
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddForm(context),
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
    );
  }

  void _openAddForm(BuildContext context) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddLedgerEntryScreen()),
    );
    if (added == true && mounted) {
      _invalidateAll(ref);
    }
  }
}

class _LoanList extends StatelessWidget {
  const _LoanList({required this.loans, required this.filter});
  final List<Loan> loans;
  final _LoansFilter filter;

  @override
  Widget build(BuildContext context) {
    if (loans.isEmpty) {
      final msg = switch (filter) {
        _LoansFilter.overdue => 'No overdue loans',
        _LoansFilter.cleared => 'No cleared loans',
        _LoansFilter.lent => 'Nothing lent out',
        _LoansFilter.borrowed => 'Nothing borrowed',
        _LoansFilter.all => 'No loans yet',
      };
      return Center(
        child: Text(msg, style: context.textTheme.bodyMedium?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        )),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm, AppSpacing.base, 100),
      itemCount: loans.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _LoanTile(loan: loans[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lentAsync = ref.watch(totalPendingLentProvider);
    final borrowedAsync = ref.watch(totalPendingBorrowedProvider);
    final colors = context.kashColors;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'To Receive',
                value: lentAsync.valueOrNull ?? 0,
                color: colors.income,
                icon: Icons.arrow_downward,
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: _MiniStat(
                label: 'To Pay',
                value: borrowedAsync.valueOrNull ?? 0,
                color: colors.expense,
                icon: Icons.arrow_upward,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: context.colorScheme.onSurfaceVariant)),
            Text(
              CurrencyFormatter.format(value),
              style: context.textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loan tile
// ---------------------------------------------------------------------------

class _LoanTile extends ConsumerWidget {
  const _LoanTile({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final isLent = loan.isLent;
    final color = isLent ? colors.income : colors.expense;
    final now = DateTime.now();
    final isOverdue =
        loan.dueDate != null && loan.dueDate!.isBefore(now) && !loan.isCleared;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _DetailSheet(loan: loan),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Text(
                      loan.lenderName.isNotEmpty
                          ? loan.lenderName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loan.lenderName,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                        Text(
                          isLent ? 'Lent (Diya)' : 'Borrowed (Liya)',
                          style: context.textTheme.bodySmall?.copyWith(
                              color: context.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(loan.pendingAmount),
                        style: context.textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (loan.isCleared)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.income.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Cleared',
                              style: context.textTheme.labelSmall
                                  ?.copyWith(color: colors.income)),
                        ),
                      if (isOverdue)
                        Text(
                          'Overdue!',
                          style: context.textTheme.labelSmall
                              ?.copyWith(color: colors.expense),
                        ),
                    ],
                  ),
                ],
              ),
              // Progress bar
              if (!loan.isCleared) ...[
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: loan.progress,
                    backgroundColor:
                        color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${CurrencyFormatter.format(loan.paidAmount)} paid',
                        style: context.textTheme.labelSmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant)),
                    if (loan.dueDate != null)
                      Text(
                        'Due ${DateFormatter.format(loan.dueDate!)}',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: isOverdue
                              ? colors.expense
                              : context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail bottom sheet
// ---------------------------------------------------------------------------

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({required this.loan});
  final Loan loan;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  final _paymentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final colors = context.kashColors;
    final isLent = loan.isLent;
    final amountColor = isLent ? colors.income : colors.expense;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.lenderName,
                          style: context.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold)),
                      Text(
                        isLent ? 'You lent money' : 'You borrowed money',
                        style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    Navigator.pop(context);
                    final edited = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) =>
                              AddLedgerEntryScreen(loan: loan)),
                    );
                    if (edited == true) _invalidateAll(ref);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Key values
            _LabelValue(
                label: 'Principal',
                value:
                    CurrencyFormatter.format(loan.principalAmount)),
            _LabelValue(
                label: 'Paid',
                value: CurrencyFormatter.format(loan.paidAmount)),
            _LabelValue(
              label: 'Outstanding',
              value: CurrencyFormatter.format(loan.pendingAmount),
              valueColor: amountColor,
            ),
            _LabelValue(
                label: 'Date',
                value: DateFormatter.format(loan.loanDate)),
            if (loan.dueDate != null)
              _LabelValue(
                  label: 'Due',
                  value: DateFormatter.format(loan.dueDate!)),
            if (loan.interestRate != null)
              _LabelValue(
                label: 'Interest',
                value:
                    '${loan.interestRate!.toStringAsFixed(1)}% (${loan.interestType.label})',
              ),
            if (loan.repaymentFrequency != null)
              _LabelValue(
                label: 'EMI',
                value:
                    '${CurrencyFormatter.format(loan.emiAmount ?? 0)} / ${loan.repaymentFrequency!.label}',
              ),
            if (loan.repaymentFrequency != null)
              Padding(
                padding:
                    const EdgeInsets.only(bottom: AppSpacing.xs),
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_view_month),
                  label: Text(
                      '${loan.paidEmis}/${loan.totalEmis ?? "?"} installments · View schedule'),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _ScheduleScreen(loan: loan)));
                  },
                ),
              ),

            if (!loan.isCleared) ...[
              const Divider(height: AppSpacing.xl),
              Text('Record Payment',
                  style: context.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _paymentController,
                  decoration: InputDecoration(
                    labelText: isLent
                        ? 'Amount received back'
                        : 'Amount paid back',
                    border: const OutlineInputBorder(),
                    prefixText: '₹ ',
                    suffixText: 'max ${CurrencyFormatter.format(loan.pendingAmount)}',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final a = double.tryParse(v);
                    if (a == null || a <= 0) return 'Invalid amount';
                    if (a > loan.pendingAmount + 0.01) {
                      return 'Exceeds pending ₹${loan.pendingAmount.toStringAsFixed(0)}';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _recordPayment,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                      isLent ? 'Mark Received' : 'Mark Paid'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
  }

  Future<void> _recordPayment() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_paymentController.text);
    await ref
        .read(activeLoansProvider.notifier)
        .recordPayment(widget.loan.id!, amount);
    _invalidateAll(ref);
    if (mounted) {
      Navigator.pop(context);
      context.showSnackBar(
          '${CurrencyFormatter.format(amount)} payment recorded');
    }
  }

  void _confirmDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text(
            'Delete loan with ${widget.loan.lenderName}? This will also remove associated transactions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ctx.colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx); // dialog
              Navigator.pop(ctx); // sheet
              await ref
                  .read(activeLoansProvider.notifier)
                  .deleteLoan(widget.loan.id!);
              _invalidateAll(ref);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schedule screen
// ---------------------------------------------------------------------------

class _ScheduleScreen extends ConsumerWidget {
  const _ScheduleScreen({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(loanPaymentsProvider(loan.id!));

    return Scaffold(
      appBar: AppBar(
        title: Text('${loan.lenderName} — Schedule'),
      ),
      body: paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (payments) {
          if (payments.isEmpty) {
            return const Center(
                child: Text('No repayment schedule generated.'));
          }
          final paid = payments.where((p) => p.isPaid).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(children: [
                      Expanded(
                        child: _LabelValue(
                          label: 'Principal',
                          value: CurrencyFormatter.format(
                              loan.principalAmount),
                        ),
                      ),
                      Expanded(
                        child: _LabelValue(
                          label: 'Installments',
                          value: '$paid / ${payments.length} paid',
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base),
                  itemCount: payments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) =>
                      _InstallmentTile(payment: payments[i], loan: loan),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InstallmentTile extends ConsumerWidget {
  const _InstallmentTile({required this.payment, required this.loan});
  final LoanPayment payment;
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final now = DateTime.now();
    final isOverdue =
        !payment.isPaid && payment.dueDate.isBefore(now);
    final statusColor = payment.isPaid
        ? colors.income
        : isOverdue
            ? colors.expense
            : context.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Text(
            '#${payment.installmentNumber}',
            style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(CurrencyFormatter.format(payment.amount)),
        subtitle: Text(
          payment.isPaid
              ? 'Paid ${payment.paidDate != null ? DateFormatter.format(payment.paidDate!) : ""}'
              : 'Due ${DateFormatter.format(payment.dueDate)}',
          style: TextStyle(color: statusColor),
        ),
        trailing: payment.isPaid
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : TextButton(
                onPressed: () => _markPaid(context, ref),
                child: const Text('Mark Paid'),
              ),
      ),
    );
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    await ref.read(loanPaymentRepositoryProvider).markPaid(
          payment.id!,
          payment.amount,
        );
    await ref
        .read(activeLoansProvider.notifier)
        .addPaymentAmount(loan.id!, payment.amount);
    _invalidateAll(ref);
    ref.invalidate(loanPaymentsProvider(loan.id!));
    if (context.mounted) {
      context.showSnackBar(
          '${CurrencyFormatter.format(payment.amount)} marked paid');
    }
  }
}

// ---------------------------------------------------------------------------
// Add / Edit loan entry screen
// ---------------------------------------------------------------------------

/// Full loan-contract form. Backed by the [Loan] model.
/// On save, auto-creates a linked Transaction (lent/borrowed).
class AddLedgerEntryScreen extends ConsumerStatefulWidget {
  const AddLedgerEntryScreen({super.key, this.loan});

  /// If provided, opens in edit mode.
  final Loan? loan;

  @override
  ConsumerState<AddLedgerEntryScreen> createState() =>
      _AddLedgerEntryScreenState();
}

class _AddLedgerEntryScreenState
    extends ConsumerState<AddLedgerEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _phoneController = TextEditingController();
  final _interestController = TextEditingController();
  final _emiAmountController = TextEditingController();
  final _totalEmisController = TextEditingController();
  final _notesController = TextEditingController();

  LoanDirection _direction = LoanDirection.lent;
  DateTime _loanDate = DateTime.now();
  DateTime? _dueDate;
  InterestType _interestType = InterestType.none;
  RepaymentFrequency? _repaymentFrequency;

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    if (loan != null) {
      _direction = loan.direction;
      _nameController.text = loan.lenderName;
      _amountController.text = loan.principalAmount.toStringAsFixed(0);
      _phoneController.text = loan.phoneNumber ?? '';
      _loanDate = loan.loanDate;
      _dueDate = loan.dueDate;
      _interestType = loan.interestType;
      if (loan.interestRate != null) {
        _interestController.text =
            loan.interestRate!.toStringAsFixed(1);
      }
      _repaymentFrequency = loan.repaymentFrequency;
      if (loan.emiAmount != null) {
        _emiAmountController.text = loan.emiAmount!.toStringAsFixed(0);
      }
      if (loan.totalEmis != null) {
        _totalEmisController.text = loan.totalEmis.toString();
      }
      if (loan.notes != null) {
        _notesController.text = loan.notes!;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    _interestController.dispose();
    _emiAmountController.dispose();
    _totalEmisController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final partyNamesAsync = ref.watch(loanPartyNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Entry' : 'New Loan Entry'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Direction selector
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
                      children: LoanDirection.values.map((d) {
                        final selected = _direction == d;
                        final isLent = d == LoanDirection.lent;
                        final color =
                            isLent ? colors.income : colors.expense;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: isLent ? AppSpacing.sm : 0),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _direction = d),
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? color.withValues(alpha: 0.1)
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
                                      isLent
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      color: selected
                                          ? color
                                          : context.colorScheme
                                              .onSurfaceVariant,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      isLent
                                          ? 'Lent (Diya)'
                                          : 'Borrowed (Liya)',
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
                                      isLent
                                          ? 'You gave money'
                                          : 'You received money',
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

            // Amount
            TextFormField(
              controller: _amountController,
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

            // Party name with autocomplete
            Autocomplete<String>(
              initialValue:
                  TextEditingValue(text: _nameController.text),
              optionsBuilder: (textEditingValue) {
                final names = partyNamesAsync.valueOrNull ?? [];
                if (textEditingValue.text.isEmpty) {
                  return names.take(5);
                }
                return names.where((n) => n
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                _nameController.text = selection;
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _nameController.text = controller.text;
                controller.addListener(() {
                  _nameController.text = controller.text;
                });
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: _direction == LoanDirection.lent
                        ? 'Borrower Name *'
                        : 'Lender Name *',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        const Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Required'
                      : null,
                );
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Phone
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.base),

            // Loan date
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _loanDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _loanDate = picked);
                  }
                },
                child: Text(DateFormatter.format(_loanDate)),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // Due date
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Due Date (optional)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.event),
                suffixIcon: _dueDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _dueDate = null),
                      )
                    : null,
              ),
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ??
                        DateTime.now()
                            .add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now()
                        .add(const Duration(days: 3650)),
                  );
                  if (picked != null) {
                    setState(() => _dueDate = picked);
                  }
                },
                child: Text(
                  _dueDate != null
                      ? DateFormatter.format(_dueDate!)
                      : 'Not set',
                ),
              ),
            ),

            const Divider(height: AppSpacing.xxl),

            // Interest
            Text('Interest', style: context.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<InterestType>(
              segments: InterestType.values
                  .map((t) => ButtonSegment(
                        value: t,
                        label: Text(t.label),
                      ))
                  .toList(),
              selected: {_interestType},
              onSelectionChanged: (v) =>
                  setState(() => _interestType = v.first),
            ),
            if (_interestType != InterestType.none) ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _interestController,
                decoration: const InputDecoration(
                  labelText: 'Annual Interest Rate (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                keyboardType: TextInputType.number,
              ),
            ],

            const Divider(height: AppSpacing.xl),

            // Repayment schedule
            Text('Repayment Schedule',
                style: context.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Set up instalment payments (daily, weekly, or monthly)',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilterChip(
                  label: const Text('None'),
                  selected: _repaymentFrequency == null,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => _repaymentFrequency = null),
                ),
                ...RepaymentFrequency.values.map(
                  (f) => FilterChip(
                    label: Text(f.label),
                    selected: _repaymentFrequency == f,
                    showCheckmark: false,
                    onSelected: (_) =>
                        setState(() => _repaymentFrequency = f),
                  ),
                ),
              ],
            ),
            if (_repaymentFrequency != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emiAmountController,
                decoration: InputDecoration(
                  labelText:
                      '${_repaymentFrequency!.label} Instalment Amount *',
                  border: const OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (_repaymentFrequency == null) return null;
                  if (v == null || v.isEmpty) return 'Required';
                  final a = double.tryParse(v);
                  if (a == null || a <= 0) return 'Invalid';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _totalEmisController,
                decoration: const InputDecoration(
                  labelText: 'Total Instalments *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.format_list_numbered),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (_repaymentFrequency == null) return null;
                  if (v == null || v.isEmpty) return 'Required';
                  final n = int.tryParse(v);
                  if (n == null || n <= 0) return 'Invalid';
                  return null;
                },
              ),
            ],
            const SizedBox(height: AppSpacing.base),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              maxLines: 2,
              maxLength: 200,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Submit
            FilledButton.icon(
              onPressed: _submit,
              icon: Icon(_isEditing ? Icons.check : Icons.add),
              label: Text(_isEditing ? 'Save Changes' : 'Add Entry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);
    final interestRate = _interestType != InterestType.none
        ? double.tryParse(_interestController.text)
        : null;
    final emiAmount = _repaymentFrequency != null
        ? double.tryParse(_emiAmountController.text)
        : null;
    final totalEmis = _repaymentFrequency != null
        ? int.tryParse(_totalEmisController.text)
        : null;
    final phone = _phoneController.text.trim().isEmpty
        ? null
        : _phoneController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    if (_isEditing) {
      final existing = widget.loan!;
      final newPending =
          (amount - existing.paidAmount).clamp(0.0, double.infinity);
      final updated = existing.copyWith(
        direction: _direction,
        lenderName: _nameController.text.trim(),
        phoneNumber: phone,
        principalAmount: amount,
        pendingAmount: newPending,
        loanDate: _loanDate,
        dueDate: _dueDate,
        interestRate: interestRate,
        interestType: _interestType,
        repaymentFrequency: _repaymentFrequency,
        emiAmount: emiAmount,
        totalEmis: totalEmis,
        notes: notes,
      );
      await ref.read(activeLoansProvider.notifier).updateLoan(updated);
    } else {
      final loan = Loan(
        direction: _direction,
        lenderName: _nameController.text.trim(),
        phoneNumber: phone,
        principalAmount: amount,
        pendingAmount: amount,
        loanDate: _loanDate,
        dueDate: _dueDate,
        interestRate: interestRate,
        interestType: _interestType,
        repaymentFrequency: _repaymentFrequency,
        emiAmount: emiAmount,
        totalEmis: totalEmis,
        notes: notes,
      );
      await ref.read(activeLoansProvider.notifier).addLoan(loan);
    }

    _invalidateAll(ref);
    if (mounted) {
      Navigator.pop(context, true);
      context.showSnackBar(
        _isEditing
            ? 'Entry updated'
            : '${CurrencyFormatter.format(amount)} '
                '${_direction == LoanDirection.lent ? "lent" : "borrowed"} added',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _LabelValue extends StatelessWidget {
  const _LabelValue({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant)),
          Text(value,
              style: context.textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(activeLoansProvider);
  ref.invalidate(totalPendingLoanProvider);
  ref.invalidate(totalPendingLentProvider);
  ref.invalidate(totalPendingBorrowedProvider);
  ref.invalidate(clearedLoansProvider);
  ref.invalidate(overdueLoansProvider);
  ref.invalidate(partySummariesProvider);
  ref.invalidate(loanPartyNamesProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(recentTransactionsProvider);
  ref.invalidate(ledgerSummariesProvider);
  ref.invalidate(totalOutstandingLentProvider);
  ref.invalidate(totalOutstandingBorrowedProvider);
  for (final d in LoanDirection.values) {
    ref.invalidate(loansByDirectionProvider(d));
  }
}
