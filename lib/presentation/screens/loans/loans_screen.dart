import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/loan.dart';
import '../../providers/loan_provider.dart';

/// Filter tabs for loans list.
enum _LoanFilter { active, overdue, cleared }

/// Screen listing all loans with summary.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  _LoanFilter _filter = _LoanFilter.active;

  @override
  Widget build(BuildContext context) {
    final loansAsync = ref.watch(activeLoansProvider);
    final totalPendingAsync = ref.watch(totalPendingLoanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
      ),
      body: Column(
        children: [
          // Summary card
          totalPendingAsync.when(
            data: (total) => _SummaryCard(totalPending: total),
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
              children: _LoanFilter.values.map((f) {
                final label = switch (f) {
                  _LoanFilter.active => 'Active',
                  _LoanFilter.overdue => 'Overdue',
                  _LoanFilter.cleared => 'Cleared',
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

          // Loans list
          Expanded(
            child: _buildList(loansAsync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddLoanSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(AsyncValue<List<Loan>> loansAsync) {
    return loansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (activeLoans) {
        // For overdue and cleared, we use separate providers
        if (_filter == _LoanFilter.overdue) {
          return _buildOverdueList();
        }
        if (_filter == _LoanFilter.cleared) {
          return _buildClearedList();
        }

        if (activeLoans.isEmpty) {
          return _buildEmpty();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: activeLoans.length,
          itemBuilder: (context, index) =>
              _LoanTile(loan: activeLoans[index]),
        );
      },
    );
  }

  Widget _buildOverdueList() {
    final overdueAsync = ref.watch(overdueLoansProvider);
    return overdueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        if (loans.isEmpty) return _buildEmpty(message: 'No overdue loans');
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: loans.length,
          itemBuilder: (context, index) => _LoanTile(loan: loans[index]),
        );
      },
    );
  }

  Widget _buildClearedList() {
    final clearedAsync = ref.watch(clearedLoansProvider);
    return clearedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        if (loans.isEmpty) {
          return _buildEmpty(message: 'No cleared loans');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: loans.length,
          itemBuilder: (context, index) => _LoanTile(loan: loans[index]),
        );
      },
    );
  }

  Widget _buildEmpty({String message = 'No loans yet'}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_outlined,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            message,
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap + to add a loan',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddLoanSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddLoanScreen()),
    );
  }
}

/// Summary card showing total pending loans.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totalPending});

  final double totalPending;

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
                Icons.account_balance,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Pending',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(totalPending),
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                      color: context.kashColors.expense,
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

/// Individual loan tile.
class _LoanTile extends ConsumerWidget {
  const _LoanTile({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final daysLeft = loan.daysUntilDue;
    final isOverdue = daysLeft != null && daysLeft < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => _showLoanDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: context.colorScheme.primaryContainer,
                    child: Text(
                      loan.lenderName.isNotEmpty
                          ? loan.lenderName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: context.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loan.lenderName,
                          style: context.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormatter.format(loan.loanDate),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
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
                          fontWeight: FontWeight.w600,
                          fontFamily: 'RobotoMono',
                          color: loan.isCleared ? colors.income : colors.expense,
                        ),
                      ),
                      if (loan.isCleared)
                        Text(
                          'Cleared',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colors.income,
                          ),
                        )
                      else if (isOverdue)
                        Text(
                          'Overdue ${-daysLeft}d',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colors.overdue,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (daysLeft != null)
                        Text(
                          '${daysLeft}d left',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Progress bar
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: loan.progress,
                      backgroundColor:
                          context.colorScheme.surfaceContainerHighest,
                      color: loan.isCleared
                          ? colors.income
                          : context.colorScheme.primary,
                      minHeight: 6,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${(loan.progress * 100).toStringAsFixed(0)}%',
                    style: context.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Amount summary
              Text(
                'Paid ${CurrencyFormatter.formatCompact(loan.paidAmount)} '
                'of ${CurrencyFormatter.formatCompact(loan.principalAmount)}',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoanDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LoanDetailSheet(loan: loan),
    );
  }
}

/// Detail sheet for a loan with pay & delete actions.
class _LoanDetailSheet extends ConsumerStatefulWidget {
  const _LoanDetailSheet({required this.loan});

  final Loan loan;

  @override
  ConsumerState<_LoanDetailSheet> createState() => _LoanDetailSheetState();
}

class _LoanDetailSheetState extends ConsumerState<_LoanDetailSheet> {
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              loan.lenderName,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Amounts
            Row(
              children: [
                Expanded(
                  child: _DetailItem(
                    label: 'Principal',
                    value: CurrencyFormatter.format(loan.principalAmount),
                  ),
                ),
                Expanded(
                  child: _DetailItem(
                    label: 'Paid',
                    value: CurrencyFormatter.format(loan.paidAmount),
                    color: colors.income,
                  ),
                ),
                Expanded(
                  child: _DetailItem(
                    label: 'Pending',
                    value: CurrencyFormatter.format(loan.pendingAmount),
                    color: colors.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Dates
            if (loan.dueDate != null)
              _DetailItem(
                label: 'Due Date',
                value: DateFormatter.format(loan.dueDate!),
              ),
            if (loan.interestRate != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _DetailItem(
                  label: 'Interest',
                  value:
                      '${loan.interestRate!.toStringAsFixed(1)}% (${loan.interestType.label})',
                ),
              ),
            if (loan.notes != null && loan.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _DetailItem(label: 'Notes', value: loan.notes!),
              ),

            if (!loan.isCleared) ...[
              const Divider(height: AppSpacing.xl),

              // Record payment
              Text(
                'Record Payment',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Form(
                key: _formKey,
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _paymentController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '₹',
                          hintText: 'Amount',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: TextButton(
                            onPressed: () {
                              _paymentController.text =
                                  loan.pendingAmount.toStringAsFixed(0);
                            },
                            child: const Text('Full'),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final amount = double.tryParse(v);
                          if (amount == null || amount <= 0) {
                            return 'Invalid';
                          }
                          if (amount > loan.pendingAmount) {
                            return 'Exceeds pending';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _submitPayment,
                      child: const Text('Pay'),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Delete button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _deleteLoan(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Loan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.expense,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_paymentController.text);
    await ref
        .read(activeLoansProvider.notifier)
        .recordPayment(widget.loan.id!, amount);
    ref.invalidate(totalPendingLoanProvider);
    ref.invalidate(overdueLoansProvider);
    ref.invalidate(clearedLoansProvider);
    if (mounted) {
      Navigator.pop(context);
      context.showSnackBar(
        'Payment of ${CurrencyFormatter.format(amount)} recorded',
      );
    }
  }

  Future<void> _deleteLoan(BuildContext context) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Loan?'),
        content: Text(
          'Delete loan of ${CurrencyFormatter.format(widget.loan.principalAmount)} '
          'from ${widget.loan.lenderName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(activeLoansProvider.notifier)
          .deleteLoan(widget.loan.id!);
      ref.invalidate(totalPendingLoanProvider);
      if (mounted) {
        navigator.pop();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Loan deleted')),
        );
      }
    }
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Screen to add a new loan.
class AddLoanScreen extends ConsumerStatefulWidget {
  const AddLoanScreen({super.key});

  @override
  ConsumerState<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends ConsumerState<AddLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lenderController = TextEditingController();
  final _amountController = TextEditingController();
  final _interestController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _loanDate = DateTime.now();
  DateTime? _dueDate;
  InterestType _interestType = InterestType.none;

  @override
  void dispose() {
    _lenderController.dispose();
    _amountController.dispose();
    _interestController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Loan'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Lender name
            TextFormField(
              controller: _lenderController,
              decoration: const InputDecoration(
                labelText: 'Lender Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.base),

            // Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Loan Amount *',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final amount = double.tryParse(v);
                if (amount == null || amount <= 0) return 'Invalid amount';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Loan date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Loan Date'),
              subtitle: Text(DateFormatter.format(_loanDate)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _loanDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _loanDate = picked);
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // Due date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Due Date (Optional)'),
              subtitle: Text(
                _dueDate != null ? DateFormatter.format(_dueDate!) : 'Not set',
              ),
              trailing: _dueDate != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    )
                  : null,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now().add(
                      const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
            ),
            const Divider(height: AppSpacing.xl),

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
                  labelText: 'Interest Rate (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: AppSpacing.base),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Submit
            FilledButton(
              onPressed: _submit,
              child: const Text('Add Loan'),
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

    final loan = Loan(
      lenderName: _lenderController.text.trim(),
      principalAmount: amount,
      pendingAmount: amount,
      loanDate: _loanDate,
      dueDate: _dueDate,
      interestRate: interestRate,
      interestType: _interestType,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    await ref.read(activeLoansProvider.notifier).addLoan(loan);
    ref.invalidate(totalPendingLoanProvider);

    if (mounted) {
      Navigator.pop(context);
      context.showSnackBar('Loan of ${CurrencyFormatter.format(amount)} added');
    }
  }
}
