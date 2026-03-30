import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/party.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/party_repository_impl.dart';
import '../../../data/services/app_logger.dart';
import '../../providers/party_provider.dart';
import '../../widgets/party_form_sheet.dart';
import '../transactions/add_edit_transaction_screen.dart';

/// Detail screen for a single staff member.
///
/// Shows two tabs:
///  • Profile  — contact, role, salary, join date, notes
///  • Payroll  — month picker, payroll summary, transaction list + "Pay Salary" action
class StaffDetailScreen extends ConsumerStatefulWidget {
  const StaffDetailScreen({super.key, required this.staffPartyId});

  final int staffPartyId;

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// Currently selected pay period.
  late DateTime _payPeriod;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _payPeriod = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Future<Party?> _loadParty() async {
    final repo = PartyRepositoryImpl();
    return repo.getById(widget.staffPartyId);
  }

  void _prevMonth() =>
      setState(() => _payPeriod = DateTime(_payPeriod.year, _payPeriod.month - 1));

  void _nextMonth() {
    final next = DateTime(_payPeriod.year, _payPeriod.month + 1);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _payPeriod = next);
  }

  Future<void> _editStaff(Party staff) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
        existing: staff,
        onSave: (_) {
          ref.invalidate(staffMembersProvider);
          setState(() {}); // triggers FutureBuilder re-read
        },
      ),
    );
  }

  Future<void> _paySalary(Party staff) async {
    final monthLabel = DateFormat('MMMM yyyy').format(_payPeriod);
    if (!mounted) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditTransactionScreen(
          initialType: TransactionType.expense,
          initialCategory: 'Payroll',
          initialPartyName: staff.name,
          initialAmount: staff.staffSalary,
          initialDescription: 'Salary – $monthLabel',
        ),
      ),
    );

    // Invalidate payroll provider so the tab refreshes.
    setState(() {});
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Party?>(
      future: _loadParty(),
      builder: (context, snap) {
        final staff = snap.data;
        if (staff == null && snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (staff == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Staff')),
            body: const Center(child: Text('Staff member not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(staff.name),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => _editStaff(staff),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Payroll'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _ProfileTab(staff: staff),
              _PayrollTab(
                staff: staff,
                payPeriod: _payPeriod,
                onPrevMonth: _prevMonth,
                onNextMonth: _nextMonth,
                onPaySalary: () => _paySalary(staff),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Profile Tab
// ---------------------------------------------------------------------------

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.staff});

  final Party staff;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        // --------------- Staff summary card --------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.colorScheme.primaryContainer,
                  child: Text(
                    staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: context.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.name,
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (staff.staffRole?.isNotEmpty == true)
                        Text(
                          staff.staffRole!,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                      if (staff.staffSalary != null)
                        Text(
                          '${CurrencyFormatter.format(staff.staffSalary!)} / ${_typeLabel(staff.staffSalaryType)}',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: colors.income,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --------------- Details section --------------------
        _SectionHeader('Contact'),
        _DetailRow(Icons.phone_outlined, 'Phone', staff.phoneNumber),
        _DetailRow(Icons.email_outlined, 'Email', staff.email),
        const SizedBox(height: AppSpacing.md),

        _SectionHeader('Employment'),
        _DetailRow(Icons.work_outline, 'Role', staff.staffRole),
        _DetailRow(
          Icons.calendar_today_outlined,
          'Join Date',
          staff.staffJoinDate != null
              ? _fmtDate(staff.staffJoinDate!)
              : null,
        ),
        if (staff.staffSalary != null)
          _DetailRow(
            Icons.currency_rupee,
            'Base Salary',
            '${CurrencyFormatter.format(staff.staffSalary!)} per ${_typeLabel(staff.staffSalaryType)}',
          ),
        if (staff.notes?.isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionHeader('Notes & Bank Details'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              staff.notes!,
              style: context.textTheme.bodyMedium,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  static String _typeLabel(String? type) {
    switch (type) {
      case 'daily':
        return 'day';
      case 'hourly':
        return 'hour';
      default:
        return 'month';
    }
  }

  static String _fmtDate(String iso) {
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(iso));
    } catch (e, st) {
      AppLogger.instance.debug(
        'Failed to format staff date',
        category: 'staff_detail',
        error: e,
      );
      return iso;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colorScheme.primary,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colorScheme.outline),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label: ',
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colorScheme.outline),
          ),
          Expanded(
            child: Text(
              value!,
              style: context.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payroll Tab
// ---------------------------------------------------------------------------

class _PayrollTab extends ConsumerWidget {
  const _PayrollTab({
    required this.staff,
    required this.payPeriod,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onPaySalary,
  });

  final Party staff;
  final DateTime payPeriod;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPaySalary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrollArgs = (
      partyId: staff.id!,
      month: payPeriod.month,
      year: payPeriod.year,
    );
    final payrollAsync = ref.watch(staffPayrollProvider(payrollArgs));
    final colors = context.kashColors;
    final isCurrentMonth = _isCurrentMonth(payPeriod);

    return Column(
      children: [
        // Month selector
        Container(
          color: context.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: onPrevMonth,
              ),
              Text(
                DateFormat('MMMM yyyy').format(payPeriod),
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: isCurrentMonth ? null : onNextMonth,
              ),
            ],
          ),
        ),
        Expanded(
          child: payrollAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (txns) {
              final paid = txns
                  .where((t) => t.category == 'Payroll')
                  .fold(0.0, (sum, t) => sum + t.amount);
              final deductions = txns
                  .where((t) => t.category == 'Payroll Deduction')
                  .fold(0.0, (sum, t) => sum + t.amount);
              final baseSalary = staff.staffSalary ?? 0;
              final alreadyPaid = paid > 0;

              return ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  // Summary card
                  _PayrollSummaryCard(
                    baseSalary: baseSalary,
                    paid: paid,
                    deductions: deductions,
                    alreadyPaid: alreadyPaid,
                    colors: colors,
                  ),
                  const SizedBox(height: AppSpacing.base),

                  // Pay Salary button
                  if (!alreadyPaid && baseSalary > 0)
                    FilledButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        'Pay Salary — ${CurrencyFormatter.format(baseSalary - deductions)}',
                      ),
                      onPressed: onPaySalary,
                    )
                  else if (alreadyPaid)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Payment / Deduction'),
                      onPressed: onPaySalary,
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record Payment'),
                      onPressed: onPaySalary,
                    ),
                  const SizedBox(height: AppSpacing.base),

                  // Transactions list
                  if (txns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'No payroll transactions for this month',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Transactions',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.primary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...txns.map((t) => _PayrollTxnTile(txn: t)),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static bool _isCurrentMonth(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month;
  }
}

class _PayrollSummaryCard extends StatelessWidget {
  const _PayrollSummaryCard({
    required this.baseSalary,
    required this.paid,
    required this.deductions,
    required this.alreadyPaid,
    required this.colors,
  });

  final double baseSalary;
  final double paid;
  final double deductions;
  final bool alreadyPaid;
  final dynamic colors;

  @override
  Widget build(BuildContext context) {
    final net = paid - deductions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _SummaryRow(
              'Base salary',
              CurrencyFormatter.format(baseSalary),
              style: context.textTheme.bodyMedium,
            ),
            if (paid > 0) ...[
              const Divider(height: AppSpacing.base),
              _SummaryRow(
                'Paid',
                CurrencyFormatter.format(paid),
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.kashColors.expense),
              ),
            ],
            if (deductions > 0)
              _SummaryRow(
                'Deductions',
                '−${CurrencyFormatter.format(deductions)}',
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.kashColors.expense),
              ),
            const Divider(height: AppSpacing.base),
            _SummaryRow(
              alreadyPaid ? 'Net paid' : 'Net payable',
              CurrencyFormatter.format(
                  alreadyPaid ? net : baseSalary - deductions),
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: alreadyPaid
                    ? context.kashColors.expense
                    : context.colorScheme.primary,
              ),
            ),
            if (alreadyPaid)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: context.kashColors.income),
                    const SizedBox(width: 4),
                    Text(
                      'Paid',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.kashColors.income,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style ?? context.textTheme.bodyMedium),
          Text(value, style: style ?? context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PayrollTxnTile extends StatelessWidget {
  const _PayrollTxnTile({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final isDeduction = txn.category == 'Payroll Deduction';
    final color = isDeduction
        ? context.kashColors.expense
        : context.colorScheme.primary;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          isDeduction
              ? Icons.remove_circle_outline
              : Icons.payments_outlined,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        txn.notes?.isNotEmpty == true ? txn.notes! : txn.category,
        style: context.textTheme.bodyMedium,
      ),
      subtitle: Text(
        DateFormat('d MMM yyyy').format(txn.date),
        style: context.textTheme.bodySmall
            ?.copyWith(color: context.colorScheme.outline),
      ),
      trailing: Text(
        '${isDeduction ? '−' : ''}${CurrencyFormatter.format(txn.amount)}',
        style: context.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
