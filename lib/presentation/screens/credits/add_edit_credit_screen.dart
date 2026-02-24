import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/credit_record.dart';
import '../../providers/credit_provider.dart';

/// Screen for giving or receiving credit (udhar).
///
/// Pass [credit] to edit an existing record; omit for a new one.
class AddEditCreditScreen extends ConsumerStatefulWidget {
  const AddEditCreditScreen({
    super.key,
    this.credit,
  });

  final CreditRecord? credit;

  bool get isEditing => credit != null;

  @override
  ConsumerState<AddEditCreditScreen> createState() =>
      _AddEditCreditScreenState();
}

class _AddEditCreditScreenState extends ConsumerState<AddEditCreditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  late CreditDirection _direction;
  late DateTime _creditDate;
  DateTime? _dueDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.credit;
    if (c != null) {
      _amountController.text = c.totalAmount.toStringAsFixed(
        c.totalAmount == c.totalAmount.roundToDouble() ? 0 : 2,
      );
      _nameController.text = c.customerName;
      _phoneController.text = c.phoneNumber ?? '';
      _notesController.text = c.notes ?? '';
      _direction = c.direction;
      _creditDate = c.creditDate;
      _dueDate = c.dueDate;
    } else {
      _direction = CreditDirection.given;
      _creditDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerNamesAsync = ref.watch(creditCustomerNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Credit' : 'New Credit'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Direction toggle
            _buildDirectionToggle(),
            const SizedBox(height: AppSpacing.lg),

            // Amount
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${AppConstants.currencySymbol} ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              validator: Validators.validateAmount,
              autofocus: !widget.isEditing,
            ),
            const SizedBox(height: AppSpacing.base),

            // Customer name with autocomplete
            _buildCustomerNameField(customerNamesAsync),
            const SizedBox(height: AppSpacing.base),

            // Phone number
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\+\- ]')),
              ],
              validator: Validators.validatePhone,
            ),
            const SizedBox(height: AppSpacing.base),

            // Credit date
            _buildDateField(
              label: 'Credit Date',
              date: _creditDate,
              onChanged: (d) => setState(() => _creditDate = d),
            ),
            const SizedBox(height: AppSpacing.base),

            // Due date (optional)
            _buildDateField(
              label: 'Due Date (optional)',
              date: _dueDate,
              onChanged: (d) => setState(() => _dueDate = d),
              allowClear: true,
            ),
            const SizedBox(height: AppSpacing.base),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 200,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Save button
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(widget.isEditing ? 'Update Credit' : 'Save Credit'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionToggle() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Credit Type',
              style: context.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DirectionChip(
                    label: 'Given (Diya)',
                    subtitle: 'You lent money',
                    icon: Icons.arrow_upward,
                    isSelected: _direction == CreditDirection.given,
                    color: context.kashColors.expense,
                    onTap: () =>
                        setState(() => _direction = CreditDirection.given),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DirectionChip(
                    label: 'Received (Liya)',
                    subtitle: 'You borrowed money',
                    icon: Icons.arrow_downward,
                    isSelected: _direction == CreditDirection.received,
                    color: context.kashColors.income,
                    onTap: () =>
                        setState(() => _direction = CreditDirection.received),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerNameField(AsyncValue<List<String>> namesAsync) {
    final knownNames = namesAsync.valueOrNull ?? [];

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _nameController.text),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable.empty();
        final query = textEditingValue.text.toLowerCase();
        return knownNames
            .where((name) => name.toLowerCase().contains(query))
            .take(5);
      },
      onSelected: (name) {
        _nameController.text = name;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Sync controllers
        _nameController.text = controller.text;
        controller.addListener(() {
          if (_nameController.text != controller.text) {
            _nameController.text = controller.text;
          }
        });

        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Customer / Party Name',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: Validators.validateName,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required ValueChanged<DateTime> onChanged,
    bool allowClear = false,
  }) {
    final dateFormat = DateFormat('d MMM yyyy');

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: allowClear && date != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _dueDate = null),
                )
              : null,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          date != null ? dateFormat.format(date) : 'Not set',
          style: date == null
              ? context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                )
              : context.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final amount =
          double.parse(_amountController.text.replaceAll(',', ''));

      final credit = CreditRecord(
        id: widget.credit?.id,
        customerName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        totalAmount: amount,
        paidAmount: widget.credit?.paidAmount ?? 0,
        pendingAmount: widget.isEditing
            ? amount - (widget.credit?.paidAmount ?? 0)
            : amount,
        direction: _direction,
        creditDate: _creditDate,
        dueDate: _dueDate,
        isCleared: widget.credit?.isCleared ?? false,
        isOverdue: _dueDate != null && DateTime.now().isAfter(_dueDate!),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: widget.credit?.createdAt,
      );

      final notifier = ref.read(pendingCreditsProvider.notifier);

      if (widget.isEditing) {
        await notifier.updateCredit(credit);
      } else {
        await notifier.addCredit(credit);
      }

      // Invalidate dependent providers
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
      ref.invalidate(creditCustomerNamesProvider);

      if (mounted) {
        context.showSnackBar(
          widget.isEditing ? 'Credit updated' : 'Credit saved',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Error saving credit: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// A styled chip for selecting credit direction.
class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : null),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isSelected ? color : null,
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                textAlign: TextAlign.center,
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
