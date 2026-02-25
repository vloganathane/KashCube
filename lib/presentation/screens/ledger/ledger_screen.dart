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

/// Filter tabs for the ledger list.
enum _LedgerFilter { all, lent, borrowed, overdue, cleared }

/// Unified Ledger screen — merges Credits + Loans.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  _LedgerFilter _filter = _LedgerFilter.all;

  @override
  Widget build(BuildContext context) {
    final loansAsync = ref.watch(activeLoansProvider);
    final totalPendingAsync = ref.watch(totalPendingLoanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ledger')),
      body: Column(
        children: [
          // Summary card
          totalPendingAsync.when(
            data: (total) => _SummaryCard(
              totalPending: total,
              totalLentAsync: ref.watch(totalPendingLentProvider),
              totalBorrowedAsync: ref.watch(totalPendingBorrowedProvider),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Filter tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: _LedgerFilter.values.map((f) {
                final label = switch (f) {
                  _LedgerFilter.all => 'All',
                  _LedgerFilter.lent => 'Lent (Diya)',
                  _LedgerFilter.borrowed => 'Borrowed (Liya)',
                  _LedgerFilter.overdue => 'Overdue',
                  _LedgerFilter.cleared => 'Cleared',
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

          // List
          Expanded(child: _buildList(loansAsync)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_ledger',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddLedgerEntryScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(AsyncValue<List<Loan>> loansAsync) {
    return switch (_filter) {
      _LedgerFilter.overdue => _buildOverdueList(),
      _LedgerFilter.cleared => _buildClearedList(),
      _LedgerFilter.lent => _buildDirectionList(LoanDirection.lent),
      _LedgerFilter.borrowed => _buildDirectionList(LoanDirection.borrowed),
      _LedgerFilter.all => loansAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (loans) => loans.isEmpty
              ? _buildEmpty()
              : _buildLoanList(loans),
        ),
    };
  }

  Widget _buildDirectionList(LoanDirection direction) {
    final async = ref.watch(loansByDirectionProvider(direction));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        final label = direction == LoanDirection.lent ? 'lent' : 'borrowed';
        if (loans.isEmpty) return _buildEmpty(message: 'No $label entries');
        return _buildLoanList(loans);
      },
    );
  }

  Widget _buildOverdueList() {
    final overdueAsync = ref.watch(overdueLoansProvider);
    return overdueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        if (loans.isEmpty) return _buildEmpty(message: 'No overdue entries');
        return _buildLoanList(loans);
      },
    );
  }

  Widget _buildClearedList() {
    final clearedAsync = ref.watch(clearedLoansProvider);
    return clearedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (loans) {
        if (loans.isEmpty) return _buildEmpty(message: 'No cleared entries');
        return _buildLoanList(loans);
      },
    );
  }

  Widget _buildLoanList(List<Loan> loans) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      itemCount: loans.length,
      itemBuilder: (context, index) => _LedgerTile(loan: loans[index]),
    );
  }

  Widget _buildEmpty({String message = 'No ledger entries yet'}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
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
            'Tap + to add a credit or loan',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary Card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalPending,
    required this.totalLentAsync,
    required this.totalBorrowedAsync,
  });

  final double totalPending;
  final AsyncValue<double> totalLentAsync;
  final AsyncValue<double> totalBorrowedAsync;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm, AppSpacing.base, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: context.colorScheme.primary),
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
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Lent (Diya)',
                      value: totalLentAsync.valueOrNull ?? 0,
                      color: colors.credit,
                      icon: Icons.arrow_upward,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MiniStat(
                      label: 'Borrowed (Liya)',
                      value: totalBorrowedAsync.valueOrNull ?? 0,
                      color: colors.expense,
                      icon: Icons.arrow_downward,
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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.textTheme.labelSmall),
            Text(
              CurrencyFormatter.formatCompact(value),
              style: context.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontFamily: 'RobotoMono',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ledger Tile (individual entry)
// ---------------------------------------------------------------------------

class _LedgerTile extends ConsumerWidget {
  const _LedgerTile({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final daysLeft = loan.daysUntilDue;
    final isOverdue = daysLeft != null && daysLeft < 0;
    final directionColor = loan.isLent ? colors.credit : colors.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Direction indicator avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: directionColor.withValues(alpha: 0.12),
                    child: Icon(
                      loan.isLent ? Icons.arrow_upward : Icons.arrow_downward,
                      color: directionColor,
                      size: 20,
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: directionColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                loan.isLent ? 'Lent' : 'Borrowed',
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: directionColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              DateFormatter.format(loan.loanDate),
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
                          color: loan.isCleared
                              ? colors.income
                              : directionColor,
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
              // Amount summary + schedule info
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paid ${CurrencyFormatter.formatCompact(loan.paidAmount)} '
                      'of ${CurrencyFormatter.formatCompact(loan.principalAmount)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (loan.interestType != InterestType.none &&
                      loan.interestRate != null)
                    Text(
                      '${loan.interestRate!.toStringAsFixed(1)}% ${loan.interestType.label}',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.tertiary,
                      ),
                    ),
                ],
              ),
              if (loan.repaymentFrequency != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14,
                        color: context.colorScheme.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${loan.repaymentFrequency!.label} · '
                      '${loan.paidEmis}/${loan.totalEmis ?? "?"} paid',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.primary,
                        fontWeight: FontWeight.w500,
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

  void _showDetail(BuildContext context, WidgetRef ref) {
    if (loan.repaymentFrequency != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ScheduleScreen(loan: loan)),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _DetailSheet(loan: loan),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Detail Sheet (for entries without repayment schedule)
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
    final directionColor = loan.isLent ? colors.credit : colors.expense;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.base,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title + direction badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    loan.lenderName,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: directionColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    loan.isLent ? 'Lent (Diya)' : 'Borrowed (Liya)',
                    style: context.textTheme.labelMedium?.copyWith(
                      color: directionColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Amounts
            Row(
              children: [
                Expanded(
                  child: _LabelValue(
                    label: 'Principal',
                    value: CurrencyFormatter.format(loan.principalAmount),
                  ),
                ),
                Expanded(
                  child: _LabelValue(
                    label: 'Paid',
                    value: CurrencyFormatter.format(loan.paidAmount),
                    color: colors.income,
                  ),
                ),
                Expanded(
                  child: _LabelValue(
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
              _LabelValue(
                label: 'Due Date',
                value: DateFormatter.format(loan.dueDate!),
              ),
            if (loan.interestRate != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _LabelValue(
                  label: 'Interest',
                  value:
                      '${loan.interestRate!.toStringAsFixed(1)}% (${loan.interestType.label})',
                ),
              ),
            if (loan.phoneNumber != null && loan.phoneNumber!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _LabelValue(
                    label: 'Phone', value: loan.phoneNumber!),
              ),
            if (loan.notes != null && loan.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _LabelValue(label: 'Notes', value: loan.notes!),
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
                          if (amount == null || amount <= 0) return 'Invalid';
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

            // Edit & Delete
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editLoan(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteLoan(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: colors.expense),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  void _editLoan(BuildContext context) {
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddLedgerEntryScreen(loan: widget.loan),
      ),
    );
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_paymentController.text);
    await ref
        .read(activeLoansProvider.notifier)
        .recordPayment(widget.loan.id!, amount);
    _invalidateAll(ref);
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
        title: const Text('Delete Entry?'),
        content: Text(
          'Delete ${CurrencyFormatter.format(widget.loan.principalAmount)} '
          '${widget.loan.isLent ? "lent to" : "borrowed from"} '
          '${widget.loan.lenderName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(activeLoansProvider.notifier)
          .deleteLoan(widget.loan.id!);
      _invalidateAll(ref);
      if (mounted) {
        navigator.pop();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Entry deleted')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Schedule Screen (for entries with repayment schedule)
// ---------------------------------------------------------------------------

class _ScheduleScreen extends ConsumerWidget {
  const _ScheduleScreen({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(loanPaymentsProvider(loan.id!));
    final colors = context.kashColors;
    final directionColor = loan.isLent ? colors.credit : colors.expense;

    return Scaffold(
      appBar: AppBar(
        title: Text(loan.lenderName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddLedgerEntryScreen(loan: loan),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteLoan(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary header
          Card(
            margin: const EdgeInsets.all(AppSpacing.base),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  // Direction badge
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: directionColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        loan.isLent ? 'Lent (Diya)' : 'Borrowed (Liya)',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: directionColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _LabelValue(
                          label: 'Principal',
                          value: CurrencyFormatter.format(
                              loan.principalAmount),
                        ),
                      ),
                      Expanded(
                        child: _LabelValue(
                          label: 'Paid',
                          value: CurrencyFormatter.format(loan.paidAmount),
                          color: colors.income,
                        ),
                      ),
                      Expanded(
                        child: _LabelValue(
                          label: 'Pending',
                          value: CurrencyFormatter.format(
                              loan.pendingAmount),
                          color: colors.expense,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                        '${loan.paidEmis}/${loan.totalEmis ?? "?"} installments',
                        style: context.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 14, color: context.colorScheme.primary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${loan.repaymentFrequency?.label ?? ""}  ·  '
                        '${CurrencyFormatter.format(loan.emiAmount ?? 0)} per installment',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Schedule title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Row(
              children: [
                Text(
                  'Repayment Schedule',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                paymentsAsync.whenOrNull(
                      data: (payments) {
                        final overdue =
                            payments.where((p) => p.isOverdue).length;
                        if (overdue == 0) return null;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: colors.expense.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Text(
                            '$overdue overdue',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: colors.expense,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ) ??
                    const SizedBox.shrink(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Schedule list
          Expanded(
            child: paymentsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (payments) {
                if (payments.isEmpty) {
                  return Center(
                    child: Text(
                      'No installments scheduled',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base),
                  itemCount: payments.length,
                  itemBuilder: (context, index) =>
                      _InstallmentTile(payment: payments[index], loan: loan),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLoan(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: Text(
          'Delete ${CurrencyFormatter.format(loan.principalAmount)} '
          '${loan.isLent ? "lent to" : "borrowed from"} '
          '${loan.lenderName}? This will also delete the repayment schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(activeLoansProvider.notifier).deleteLoan(loan.id!);
      _invalidateAll(ref);
      if (context.mounted) {
        navigator.pop();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Entry deleted')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Installment Tile
// ---------------------------------------------------------------------------

class _InstallmentTile extends ConsumerWidget {
  const _InstallmentTile({required this.payment, required this.loan});

  final LoanPayment payment;
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    final isOverdue = payment.isOverdue;
    final isPaid = payment.isPaid;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: isPaid
          ? colors.income.withValues(alpha: 0.05)
          : isOverdue
              ? colors.expense.withValues(alpha: 0.05)
              : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isPaid
              ? colors.income.withValues(alpha: 0.15)
              : isOverdue
                  ? colors.expense.withValues(alpha: 0.15)
                  : context.colorScheme.surfaceContainerHighest,
          child: isPaid
              ? Icon(Icons.check, size: 18, color: colors.income)
              : Text(
                  '#${payment.installmentNumber}',
                  style: context.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isOverdue
                        ? colors.expense
                        : context.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        title: Row(
          children: [
            Text(
              CurrencyFormatter.format(payment.amount),
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'RobotoMono',
                decoration: isPaid ? TextDecoration.lineThrough : null,
              ),
            ),
            const Spacer(),
            if (isOverdue)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'Overdue',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: colors.expense,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (isPaid)
              Text(
                'Paid',
                style: context.textTheme.labelSmall?.copyWith(
                  color: colors.income,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        subtitle: Text(
          isPaid && payment.paidDate != null
              ? 'Paid on ${DateFormatter.format(payment.paidDate!)}'
              : 'Due ${DateFormatter.format(payment.dueDate)}',
          style: context.textTheme.bodySmall?.copyWith(
            color: isOverdue
                ? colors.expense
                : context.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: isPaid
            ? null
            : IconButton(
                icon: Icon(Icons.payment,
                    color: context.colorScheme.primary),
                tooltip: 'Pay installment',
                onPressed: () => _payInstallment(context, ref),
              ),
      ),
    );
  }

  Future<void> _payInstallment(BuildContext context, WidgetRef ref) async {
    final paymentRepo = ref.read(loanPaymentRepositoryProvider);
    final payAmount = payment.remainingAmount;

    await paymentRepo.markPaid(payment.id!, payAmount);
    await ref
        .read(activeLoansProvider.notifier)
        .addPaymentAmount(loan.id!, payAmount);

    ref.invalidate(loanPaymentsProvider(loan.id!));
    _invalidateAll(ref);

    if (context.mounted) {
      context.showSnackBar(
        'Installment #${payment.installmentNumber} paid '
        '(${CurrencyFormatter.format(payAmount)})',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Label-Value helper
// ---------------------------------------------------------------------------

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value, this.color});

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

// ---------------------------------------------------------------------------
// Add / Edit Ledger Entry Screen
// ---------------------------------------------------------------------------

class AddLedgerEntryScreen extends ConsumerStatefulWidget {
  const AddLedgerEntryScreen({super.key, this.loan});

  /// If provided, the screen is in edit mode.
  final Loan? loan;

  @override
  ConsumerState<AddLedgerEntryScreen> createState() =>
      _AddLedgerEntryScreenState();
}

class _AddLedgerEntryScreenState extends ConsumerState<AddLedgerEntryScreen> {
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
        _interestController.text = loan.interestRate!.toStringAsFixed(1);
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
        title: Text(_isEditing ? 'Edit Entry' : 'New Ledger Entry'),
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
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: LoanDirection.values.map((d) {
                        final selected = _direction == d;
                        final isLent = d == LoanDirection.lent;
                        final color = isLent ? colors.credit : colors.expense;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: isLent ? AppSpacing.sm : 0),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _direction = d),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
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
                                        : context.colorScheme.outlineVariant,
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
                                          : context
                                              .colorScheme.onSurfaceVariant,
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
                                            : context
                                                .colorScheme.onSurfaceVariant,
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
                                        color: context
                                            .colorScheme.onSurfaceVariant,
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
                final amount = double.tryParse(v);
                if (amount == null || amount <= 0) return 'Invalid amount';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Party name with autocomplete
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _nameController.text),
              optionsBuilder: (textEditingValue) {
                final names = partyNamesAsync.valueOrNull ?? [];
                if (textEditingValue.text.isEmpty) return names.take(5);
                return names.where((n) => n
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                _nameController.text = selection;
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                // Sync the autocomplete controller with our _nameController
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
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                );
              },
            ),
            const SizedBox(height: AppSpacing.base),

            // Phone number
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

            // Date
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
                  if (picked != null) setState(() => _loanDate = picked);
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
                    initialDate:
                        _dueDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
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
                  labelText: 'Interest Rate (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: AppSpacing.base),

            const Divider(height: AppSpacing.xl),

            // Repayment Schedule
            Text('Repayment Schedule',
                style: context.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Set up installment payments (daily, weekly, or monthly)',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
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
                      '${_repaymentFrequency!.label} Installment Amount *',
                  border: const OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (_repaymentFrequency == null) return null;
                  if (v == null || v.isEmpty) return 'Required';
                  final amount = double.tryParse(v);
                  if (amount == null || amount <= 0) return 'Invalid';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _totalEmisController,
                decoration: const InputDecoration(
                  labelText: 'Total Installments *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.format_list_numbered),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (_repaymentFrequency == null) return null;
                  if (v == null || v.isEmpty) return 'Required';
                  final count = int.tryParse(v);
                  if (count == null || count <= 0) return 'Invalid';
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
            : '${CurrencyFormatter.format(amount)} ${_direction == LoanDirection.lent ? "lent" : "borrowed"} added',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Helper to invalidate all ledger-related providers
// ---------------------------------------------------------------------------

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(totalPendingLoanProvider);
  ref.invalidate(totalPendingLentProvider);
  ref.invalidate(totalPendingBorrowedProvider);
  ref.invalidate(overdueLoansProvider);
  ref.invalidate(clearedLoansProvider);
  ref.invalidate(partySummariesProvider);
  ref.invalidate(loanPartyNamesProvider);
  // Invalidate direction providers
  for (final d in LoanDirection.values) {
    ref.invalidate(loansByDirectionProvider(d));
  }
}
