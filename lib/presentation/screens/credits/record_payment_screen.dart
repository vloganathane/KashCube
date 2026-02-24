import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/credit_record.dart';
import '../../providers/credit_provider.dart';

/// Screen for recording a payment against a credit record.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.credit});

  final CreditRecord credit;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _paymentMethod = 'UPI';
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final credit = widget.credit;
    final colors = context.kashColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Payment'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Credit summary
            Card(
              color: colors.creditBackground,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.credit.withValues(alpha: 0.15),
                      child: Text(
                        credit.customerName[0].toUpperCase(),
                        style: TextStyle(
                          color: colors.credit,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            credit.customerName,
                            style: context.textTheme.titleSmall,
                          ),
                          Text(
                            'Pending: ${CurrencyFormatter.format(credit.pendingAmount)}',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colors.credit,
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
            const SizedBox(height: AppSpacing.lg),

            // Amount field
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Payment Amount',
                prefixText: '${AppConstants.currencySymbol} ',
                helperText:
                    'Max: ${CurrencyFormatter.format(credit.pendingAmount)}',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              autofocus: true,
              validator: (value) {
                final baseError = Validators.validateAmount(value);
                if (baseError != null) return baseError;
                final amount =
                    double.parse(value!.replaceAll(',', ''));
                if (amount > credit.pendingAmount) {
                  return 'Amount cannot exceed pending ${CurrencyFormatter.format(credit.pendingAmount)}';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // Quick amount buttons
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                _QuickAmountChip(
                  label: 'Full',
                  amount: credit.pendingAmount,
                  onTap: () => _amountController.text =
                      credit.pendingAmount.toStringAsFixed(0),
                ),
                if (credit.pendingAmount >= 200)
                  _QuickAmountChip(
                    label: 'Half',
                    amount: credit.pendingAmount / 2,
                    onTap: () => _amountController.text =
                        (credit.pendingAmount / 2).toStringAsFixed(0),
                  ),
                if (credit.pendingAmount >= 1000)
                  _QuickAmountChip(
                    label: '₹1,000',
                    amount: 1000,
                    onTap: () => _amountController.text = '1000',
                  ),
                if (credit.pendingAmount >= 5000)
                  _QuickAmountChip(
                    label: '₹5,000',
                    amount: 5000,
                    onTap: () => _amountController.text = '5000',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),

            // Payment method
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                prefixIcon: Icon(Icons.payment_outlined),
                border: OutlineInputBorder(),
              ),
              items: AppConstants.paymentMethods.map((method) {
                return DropdownMenuItem(value: method, child: Text(method));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _paymentMethod = v);
              },
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
              maxLines: 2,
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
              label: const Text('Record Payment'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
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

      await ref.read(pendingCreditsProvider.notifier).recordPayment(
            widget.credit.id!,
            amount,
            paymentMethod: _paymentMethod,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      // Invalidate dependent providers
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
      ref.invalidate(creditByIdProvider(widget.credit.id!));
      ref.invalidate(creditPaymentsProvider(widget.credit.id!));

      if (mounted) {
        final isCleared = amount >= widget.credit.pendingAmount;
        context.showSnackBar(
          isCleared
              ? 'Credit cleared! ${CurrencyFormatter.format(amount)} received'
              : 'Payment of ${CurrencyFormatter.format(amount)} recorded',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Error recording payment: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Chip for quick amount selection.
class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.label,
    required this.amount,
    required this.onTap,
  });

  final String label;
  final double amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.flash_on, size: 16),
    );
  }
}
