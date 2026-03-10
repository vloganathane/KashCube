import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/kash_cube_colors.dart';
import '../../data/models/transaction.dart';

/// Quick payment method picker bottom sheet.
///
/// Shows payment method buttons with smart defaults (last used method starred).
/// Optionally allows date selection for backdated payments.
class PaymentMethodPickerBottomSheet extends StatefulWidget {
  const PaymentMethodPickerBottomSheet({
    super.key,
    required this.amount,
    this.title,
    this.customerName,
    this.partyPrefix = 'from',
    this.lastUsedMethod,
    this.defaultDate,
  });

  final double amount;
  final String? title;
  final String? customerName;
  final String partyPrefix;
  final PaymentMethod? lastUsedMethod;
  final DateTime? defaultDate;

  @override
  State<PaymentMethodPickerBottomSheet> createState() =>
      _PaymentMethodPickerBottomSheetState();
}

class _PaymentMethodPickerBottomSheetState
    extends State<PaymentMethodPickerBottomSheet> {
  late DateTime _selectedDate;
  bool _showDatePicker = false;
  late TextEditingController _amountController;
  late double _amount;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.defaultDate ?? DateTime.now();
    _amount = widget.amount;
    _amountController = TextEditingController(
      text: widget.amount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectMethod(PaymentMethod method) {
    // Parse amount from text field
    final amount = double.tryParse(_amountController.text) ?? _amount;
    Navigator.pop(context, {
      'method': method,
      'date': _selectedDate,
      'amount': amount,
    });
  }

  void _showDateSelector() {
    setState(() {
      _showDatePicker = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Payment Date',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KashCubeColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

          // Title
          Text(
            widget.title ?? 'Payment Received',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.base),

          // Amount (editable for partial payments)
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colors.income,
              fontWeight: FontWeight.bold,
              fontFamily: 'RobotoMono',
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
              prefixStyle: theme.textTheme.headlineMedium?.copyWith(
                color: colors.income,
                fontWeight: FontWeight.bold,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.income, width: 2),
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            onChanged: (value) {
              setState(() {
                _amount = double.tryParse(value) ?? widget.amount;
              });
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap to edit for partial payment',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),

          if (widget.customerName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.partyPrefix} ${widget.customerName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // Date selector (if not today)
          if (_selectedDate.day != DateTime.now().day ||
              _selectedDate.month != DateTime.now().month ||
              _selectedDate.year != DateTime.now().year ||
              _showDatePicker) ...[
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                'Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
          ],

          // Payment method buttons
          Text(
            'Payment Method',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Grid of payment method buttons
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _PaymentMethodButton(
                method: PaymentMethod.cash,
                isRecommended: widget.lastUsedMethod == PaymentMethod.cash,
                onTap: () => _selectMethod(PaymentMethod.cash),
              ),
              _PaymentMethodButton(
                method: PaymentMethod.upi,
                isRecommended: widget.lastUsedMethod == PaymentMethod.upi,
                onTap: () => _selectMethod(PaymentMethod.upi),
              ),
              _PaymentMethodButton(
                method: PaymentMethod.creditCard,
                label: 'Card',
                isRecommended: widget.lastUsedMethod == PaymentMethod.creditCard ||
                    widget.lastUsedMethod == PaymentMethod.debitCard,
                onTap: () => _selectMethod(PaymentMethod.creditCard),
              ),
              _PaymentMethodButton(
                method: PaymentMethod.netBanking,
                label: 'Bank',
                isRecommended: widget.lastUsedMethod == PaymentMethod.netBanking,
                onTap: () => _selectMethod(PaymentMethod.netBanking),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Other date option
          if (!_showDatePicker)
            TextButton.icon(
              onPressed: _showDateSelector,
              icon: const Icon(Icons.access_time, size: 16),
              label: const Text('Other Date...'),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),

          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
        ),
      ),
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  const _PaymentMethodButton({
    required this.method,
    required this.onTap,
    this.label,
    this.isRecommended = false,
  });

  final PaymentMethod method;
  final VoidCallback onTap;
  final String? label;
  final bool isRecommended;

  IconData _getIcon() {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.money;
      case PaymentMethod.upi:
        return Icons.phone_android;
      case PaymentMethod.creditCard:
      case PaymentMethod.debitCard:
        return Icons.credit_card;
      case PaymentMethod.netBanking:
        return Icons.account_balance;
      case PaymentMethod.wallet:
        return Icons.account_balance_wallet;
      case PaymentMethod.cheque:
        return Icons.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SizedBox(
      width: (MediaQuery.of(context).size.width - AppSpacing.lg * 2 - AppSpacing.md) / 2,
      height: 80,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isRecommended
                ? BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getIcon(), size: 28),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label ?? method.label,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 2),
                  Text(
                    '★',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Show payment method picker bottom sheet.
///
/// Returns a map with 'method' (PaymentMethod) and 'date' (DateTime),
/// or null if cancelled.
Future<Map<String, dynamic>?> showPaymentMethodPicker({
  required BuildContext context,
  required double amount,
  String? title,
  String? customerName,
  String partyPrefix = 'from',
  PaymentMethod? lastUsedMethod,
  DateTime? defaultDate,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (context) => PaymentMethodPickerBottomSheet(
      amount: amount,
      title: title,
      customerName: customerName,
      partyPrefix: partyPrefix,
      lastUsedMethod: lastUsedMethod,
      defaultDate: defaultDate,
    ),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
  );
}
