import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/staff.dart';
import '../../providers/inventory_provider.dart' show activeBusinessIdProvider;
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';
import '../../widgets/upgrade_prompt_sheet.dart' show showUpgradePromptSheet;

/// Staff & Payroll management screen — gated behind Business tier.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(subscriptionTierProvider);
    if (!tier.isBusiness) {
      return _GatedPlaceholder(tier: tier);
    }

    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Payroll'),
        centerTitle: false,
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (staff) {
          if (staff.isEmpty) {
            return _EmptyState(onAdd: () => _openAddStaff(context, ref));
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(staffProvider.notifier).load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.base),
              itemCount: staff.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _StaffTile(
                staff: staff[i],
                onTap: () => _openDetail(context, ref, staff[i]),
                onEdit: () => _openAddStaff(context, ref, existing: staff[i]),
                onDeactivate: () => _confirmDeactivate(context, ref, staff[i]),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddStaff(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Staff'),
      ),
    );
  }

  void _openAddStaff(BuildContext context, WidgetRef ref, {Staff? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddEditStaffSheet(existing: existing),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, Staff staff) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StaffDetailSheet(staff: staff),
    );
  }

  Future<void> _confirmDeactivate(
      BuildContext context, WidgetRef ref, Staff staff) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate Staff?'),
        content: Text(
            '${staff.name} will be marked inactive. All past records are preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(staffProvider.notifier).deactivate(staff.id!);
    }
  }
}

// ── Tier gate ─────────────────────────────────────────────────────────────────

class _GatedPlaceholder extends ConsumerWidget {
  const _GatedPlaceholder({required this.tier});
  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff & Payroll')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_outlined,
                  size: 64, color: context.colorScheme.outline),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Staff & Payroll is a\nBusiness tier feature',
                textAlign: TextAlign.center,
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Track employees, record salary payments, and\nmanage HR details — all private, on-device.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colorScheme.outline),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () =>
                    showUpgradePromptSheet(context, featureName: 'Staff & Payroll'),
                icon: const Icon(Icons.star_outline),
                label: const Text('Upgrade to Business'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined,
                size: 64, color: context.colorScheme.outline),
            const SizedBox(height: AppSpacing.lg),
            Text('No staff members yet',
                style: context.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add employees or contractors to track\npayroll and HR details.',
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.outline),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add First Staff Member'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Staff tile ────────────────────────────────────────────────────────────────

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.staff,
    required this.onTap,
    required this.onEdit,
    required this.onDeactivate,
  });

  final Staff staff;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final initials = staff.name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: context.colorScheme.primaryContainer,
          child: Text(
            initials,
            style: TextStyle(
              color: context.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(staff.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          [
            if (staff.designation != null) staff.designation!,
            CurrencyFormatter.format(staff.baseSalary),
            if (staff.salaryType == SalaryType.monthly) '/month'
            else if (staff.salaryType == SalaryType.daily) '/day'
            else if (staff.salaryType == SalaryType.hourly) '/hr'
            else '/contract',
          ].join(' '),
          style: context.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 8),
                Text('Edit'),
              ]),
            ),
            const PopupMenuItem(
              value: 'salary',
              child: Row(children: [
                Icon(Icons.payments_outlined, size: 18),
                SizedBox(width: 8),
                Text('Record Salary'),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'deactivate',
              child: Row(children: [
                Icon(Icons.person_off_outlined, size: 18),
                SizedBox(width: 8),
                Text('Deactivate'),
              ]),
            ),
          ],
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'deactivate') onDeactivate();
            if (v == 'salary') {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _RecordSalarySheet(staff: staff),
              );
            }
          },
        ),
      ),
    );
  }
}

// ── Staff detail sheet ────────────────────────────────────────────────────────

class _StaffDetailSheet extends ConsumerWidget {
  const _StaffDetailSheet({required this.staff});
  final Staff staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaryAsync = ref.watch(salaryPaymentsProvider(staff.id!));
    final dateFormat = DateFormat('dd MMM yyyy');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name,
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (staff.designation != null)
                        Text(staff.designation!,
                            style: context.textTheme.bodySmall
                                ?.copyWith(color: context.colorScheme.outline)),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _RecordSalarySheet(staff: staff),
                    );
                  },
                  child: const Text('Record Salary'),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Info chips
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _InfoChip(
                  label: CurrencyFormatter.format(staff.baseSalary),
                  icon: Icons.currency_rupee,
                ),
                if (staff.phone != null)
                  _InfoChip(label: staff.phone!, icon: Icons.phone_outlined),
                if (staff.department != null)
                  _InfoChip(label: staff.department!, icon: Icons.business_outlined),
                if (staff.joinDate != null)
                  _InfoChip(
                    label: 'Joined ${dateFormat.format(staff.joinDate!)}',
                    icon: Icons.calendar_today_outlined,
                  ),
              ],
            ),
          ),
          const Divider(),
          // Section title
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.sm, AppSpacing.base, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Salary History',
                  style: context.textTheme.labelMedium
                      ?.copyWith(color: context.colorScheme.outline)),
            ),
          ),
          Expanded(
            child: salaryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (payments) {
                if (payments.isEmpty) {
                  return const Center(child: Text('No salary payments yet.'));
                }
                return ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: payments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = payments[i];
                    final isPaid =
                        p.status == SalaryPaymentStatus.paid;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.periodLabel),
                      subtitle: Text(
                          p.paidDate != null
                              ? 'Paid ${dateFormat.format(p.paidDate!)}'
                              : p.status.name,
                          style: context.textTheme.bodySmall),
                      trailing: Text(
                        CurrencyFormatter.format(p.netSalary),
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isPaid
                              ? context.kashColors.income
                              : context.colorScheme.onSurface,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add/Edit staff sheet ──────────────────────────────────────────────────────

class _AddEditStaffSheet extends ConsumerStatefulWidget {
  const _AddEditStaffSheet({this.existing});
  final Staff? existing;

  @override
  ConsumerState<_AddEditStaffSheet> createState() => _AddEditStaffSheetState();
}

class _AddEditStaffSheetState extends ConsumerState<_AddEditStaffSheet> {
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _designCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  SalaryType _salaryType = SalaryType.monthly;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = widget.existing!;
      _nameCtrl.text = s.name;
      _designCtrl.text = s.designation ?? '';
      _phoneCtrl.text = s.phone ?? '';
      _deptCtrl.text = s.department ?? '';
      _salaryCtrl.text = s.baseSalary > 0 ? s.baseSalary.toStringAsFixed(0) : '';
      _salaryType = s.salaryType;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _designCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final businessId = ref.read(activeBusinessIdProvider);
    final staff = Staff(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      designation: _designCtrl.text.trim().isNotEmpty
          ? _designCtrl.text.trim()
          : null,
      phone: _phoneCtrl.text.trim().isNotEmpty
          ? _phoneCtrl.text.trim()
          : null,
      department: _deptCtrl.text.trim().isNotEmpty
          ? _deptCtrl.text.trim()
          : null,
      salaryType: _salaryType,
      baseSalary:
          double.tryParse(_salaryCtrl.text.replaceAll(',', '')) ?? 0,
      businessId: businessId,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: _isEdit ? now : null,
    );

    if (_isEdit) {
      await ref.read(staffProvider.notifier).update(staff);
    } else {
      await ref.read(staffProvider.notifier).add(staff);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base,
          AppSpacing.base + bottomPadding),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit Staff' : 'Add Staff Member',
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _designCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Designation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _salaryCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Base Salary (₹)',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<SalaryType>(
                      initialValue: _salaryType,
                      decoration: const InputDecoration(
                        labelText: 'Per',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SalaryType.monthly,
                          child: Text('Month'),
                        ),
                        DropdownMenuItem(
                          value: SalaryType.daily,
                          child: Text('Day'),
                        ),
                        DropdownMenuItem(
                          value: SalaryType.hourly,
                          child: Text('Hour'),
                        ),
                        DropdownMenuItem(
                          value: SalaryType.contractual,
                          child: Text('Contract'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _salaryType = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _deptCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _save,
                child: Text(_isEdit ? 'Save Changes' : 'Add Staff'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Record salary sheet ───────────────────────────────────────────────────────

class _RecordSalarySheet extends ConsumerStatefulWidget {
  const _RecordSalarySheet({required this.staff});
  final Staff staff;

  @override
  ConsumerState<_RecordSalarySheet> createState() => _RecordSalarySheetState();
}

class _RecordSalarySheetState extends ConsumerState<_RecordSalarySheet> {
  final _form = GlobalKey<FormState>();
  final _baseCtrl = TextEditingController();
  final _allowCtrl = TextEditingController(text: '0');
  final _deductCtrl = TextEditingController(text: '0');
  final _bonusCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  SalaryPaymentStatus _status = SalaryPaymentStatus.paid;

  @override
  void initState() {
    super.initState();
    _baseCtrl.text = widget.staff.baseSalary > 0
        ? widget.staff.baseSalary.toStringAsFixed(0)
        : '';
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _allowCtrl.dispose();
    _deductCtrl.dispose();
    _bonusCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _net {
    final base = double.tryParse(_baseCtrl.text) ?? 0;
    final allow = double.tryParse(_allowCtrl.text) ?? 0;
    final deduct = double.tryParse(_deductCtrl.text) ?? 0;
    final bonus = double.tryParse(_bonusCtrl.text) ?? 0;
    return base + allow + bonus - deduct;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final payment = SalaryPayment(
      staffId: widget.staff.id!,
      payPeriodMonth: _month,
      payPeriodYear: _year,
      baseSalary: double.tryParse(_baseCtrl.text) ?? 0,
      allowances: double.tryParse(_allowCtrl.text) ?? 0,
      deductions: double.tryParse(_deductCtrl.text) ?? 0,
      bonus: double.tryParse(_bonusCtrl.text) ?? 0,
      netSalary: _net,
      status: _status,
      paidDate: _status == SalaryPaymentStatus.paid ? DateTime.now() : null,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      createdAt: DateTime.now(),
    );
    await ref.read(salaryPaymentsProvider(widget.staff.id!).notifier).record(payment);
    if (mounted) Navigator.pop(context);
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final currentYear = DateTime.now().year;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base,
          AppSpacing.base + bottomPadding),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Record Salary',
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          widget.staff.name,
                          style: context.textTheme.bodySmall
                              ?.copyWith(color: context.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),
              // Pay period picker
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: const InputDecoration(
                        labelText: 'Month',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(_months[i]),
                        ),
                      ),
                      onChanged: (v) => setState(() => _month = v!),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (int y = currentYear - 2; y <= currentYear + 1; y++)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setState(() => _year = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _baseCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Base Salary (₹) *',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter base salary' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _allowCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Allowances',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _deductCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Deductions',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _bonusCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Bonus',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              // Net preview
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Net Salary',
                        style: context.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      CurrencyFormatter.format(_net),
                      style: context.textTheme.titleSmall?.copyWith(
                        color: context.kashColors.income,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<SalaryPaymentStatus>(
                segments: const [
                  ButtonSegment(
                    value: SalaryPaymentStatus.paid,
                    label: Text('Paid'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  ButtonSegment(
                    value: SalaryPaymentStatus.pending,
                    label: Text('Pending'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                  ButtonSegment(
                    value: SalaryPaymentStatus.partial,
                    label: Text('Partial'),
                    icon: Icon(Icons.timelapse_outlined),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: (s) =>
                    setState(() => _status = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _save,
                child: const Text('Save Salary Record'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: context.textTheme.bodySmall),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
