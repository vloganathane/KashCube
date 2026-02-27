import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kash_cube_colors.dart';
import '../../core/theme/kash_cube_spacing.dart';
import '../../data/models/transaction.dart';

/// Quick payment method picker bottom sheet.
///
/// Shows payment method buttons with smart defaults (last used method starred).
/// Optionally allows date selection for backdated payments.
class PaymentMethodPickerBottomSheet extends StatefulWidget {
  const PaymentMethodPickerBottomSheet({
    super.key,
    required this.amount,
    this.customerName,
    this.lastUsedMethod,
    this.defaultDate,
  });

  final double amount;
  final String? customerName;
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

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.defaultDate ?? DateTime.now();
  }

  void _selectMethod(PaymentMethod method) {
    Navigator.pop(context, {
      'method': method,
      'date': _selectedDate,
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
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(KashCubeSpacing.lg),
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
          const SizedBox(height: KashCubeSpacing.lg),

          // Title
          Text(
            'Payment Received',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: KashCubeSpacing.xs),

          // Amount
          Text(
            currencyFormat.format(widget.amount),
            style: theme.textTheme.displaySmall?.copyWith(
              color: colors.income,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (widget.customerName != null) ...[
            const SizedBox(height: KashCubeSpacing.xs),
            Text(
              'from ${widget.customerName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],

          const SizedBox(height: KashCubeSpacing.xl),

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
            const SizedBox(height: KashCubeSpacing.base),
          ],

          // Payment method buttons
          Text(
            'Payment Method',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: KashCubeSpacing.md),

          // Grid of payment method buttons
          Wrap(
            spacing: KashCubeSpacing.md,
            runSpacing: KashCubeSpacing.md,
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

          const SizedBox(height: KashCubeSpacing.lg),

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
      width: (MediaQuery.of(context).size.width - KashCubeSpacing.lg * 2 - KashCubeSpacing.md) / 2,
      height: 72,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: KashCubeSpacing.md,
            vertical: KashCubeSpacing.md,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getIcon(), size: 24),
            const SizedBox(height: KashCubeSpacing.xs),
            Text(
              label ?? method.label,
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (isRecommended)
              Text(
                '★',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 10,
                ),
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
  String? customerName,
  PaymentMethod? lastUsedMethod,
  DateTime? defaultDate,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (context) => PaymentMethodPickerBottomSheet(
      amount: amount,
      customerName: customerName,
      lastUsedMethod: lastUsedMethod,
      defaultDate: defaultDate,
    ),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
  );
}
