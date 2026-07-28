import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/parsed_sms.dart';
import '../../data/models/transaction.dart';
import '../../data/services/auto_categorizer.dart';
import '../providers/dashboard_provider.dart';
import '../providers/sms_provider.dart';
import '../providers/transaction_provider.dart';

/// Result of the SMS confirmation bottom sheet.
enum SmsConfirmAction { saved, dismissed, editManually }

/// Shows a quick confirmation bottom sheet when an SMS transaction is detected.
///
/// Designed for <10 second confirmation: user sees parsed data, can tweak
/// category, then confirm or dismiss.
Future<SmsConfirmAction?> showSmsConfirmationSheet(
  BuildContext context,
  WidgetRef ref,
  ParsedSms parsed,
) async {
  return showModalBottomSheet<SmsConfirmAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (context) => _SmsConfirmationContent(parsed: parsed, ref: ref),
  );
}

class _SmsConfirmationContent extends StatefulWidget {
  const _SmsConfirmationContent({required this.parsed, required this.ref});

  final ParsedSms parsed;
  final WidgetRef ref;

  @override
  State<_SmsConfirmationContent> createState() =>
      _SmsConfirmationContentState();
}

class _SmsConfirmationContentState extends State<_SmsConfirmationContent> {
  late String _category;
  late TransactionMode _mode;
  bool _isSaving = false;

  ParsedSms get parsed => widget.parsed;

  @override
  void initState() {
    super.initState();
    _category = AutoCategorizer.categorize(parsed);
    _mode = TransactionMode.personal;
  }

  List<String> get _categories {
    if (parsed.isCredit) return AppConstants.incomeCategories;
    return AppConstants.defaultCategories;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isIncome = parsed.isCredit;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '-';
    final confidenceColor = switch (parsed.confidenceLevel) {
      ConfidenceLevel.high => colors.income,
      ConfidenceLevel.medium => context.colorScheme.tertiary,
      ConfidenceLevel.low => colors.credit,
      ConfidenceLevel.veryLow => colors.expense,
    };

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: context.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Header
          Row(
            children: [
              Icon(
                Icons.sms_outlined,
                color: context.colorScheme.primary,
                size: AppSpacing.iconMd,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Transaction Detected',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Confidence badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  parsed.confidenceLevel.name.toUpperCase(),
                  style: context.textTheme.labelSmall?.copyWith(
                    color: confidenceColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Amount (large, prominent)
          Center(
            child: Text(
              '$prefix${CurrencyFormatter.format(parsed.amount)}',
              style: context.textTheme.headlineMedium?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.bold,
                fontFamily: 'RobotoMono',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Transaction details row
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  if (parsed.partyName != null)
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Party',
                      value: parsed.partyName!,
                    ),
                  if (parsed.sourceType != SmsSourceType.unknown)
                    _DetailRow(
                      icon: Icons.payment_outlined,
                      label: 'Via',
                      value: _paymentMethodLabel,
                    ),
                  if (parsed.upiApp != null)
                    _DetailRow(
                      icon: Icons.phone_android,
                      label: 'App',
                      value: parsed.upiApp!,
                    ),
                  if (parsed.upiRefNo != null)
                    _DetailRow(
                      icon: Icons.tag,
                      label: 'Ref',
                      value: parsed.upiRefNo!,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Category selector (quick chips)
          Text(
            'Category',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final selected = cat == _category;
                return ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat),
                  visualDensity: VisualDensity.compact,
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Mode toggle
          Row(
            children: [
              Text(
                'Mode',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              for (final mode in [
                TransactionMode.personal,
                TransactionMode.business,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(mode.label),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Action buttons
          Row(
            children: [
              // Dismiss
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, SmsConfirmAction.dismissed),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Edit manually
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, SmsConfirmAction.editManually),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Confirm & Save
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _confirmAndSave,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Confirm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  String get _paymentMethodLabel {
    return AutoCategorizer.suggestPaymentMethod(parsed);
  }

  Future<void> _confirmAndSave() async {
    setState(() => _isSaving = true);

    final transaction = Transaction(
      amount: parsed.amount,
      date: parsed.date ?? DateTime.now(),
      type: parsed.isCredit ? TransactionType.income : TransactionType.expense,
      mode: _mode,
      category: _category,
      partyName: parsed.partyName,
      paymentMethod: _paymentMethodFromSource,
      smsBody: parsed.smsBody,
      smsSender: parsed.smsSender,
      upiApp: parsed.upiApp,
      upiRefNo: parsed.upiRefNo,
      referenceId: parsed.referenceId,
      autoDetected: true,
      verified: true,
    );

    try {
      await widget.ref
          .read(transactionsProvider.notifier)
          .addTransaction(transaction);

      // Remove from pending
      widget.ref
          .read(pendingSmsConfirmationsProvider.notifier)
          .removePending(parsed);

      // Refresh dashboard
      widget.ref.read(dashboardSummaryProvider.notifier).loadSummary();
      widget.ref.read(recentTransactionsProvider.notifier).loadRecent();

      if (mounted) {
        Navigator.pop(context, SmsConfirmAction.saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showSnackBar('Error saving: $e', isError: true);
      }
    }
  }

  PaymentMethod get _paymentMethodFromSource {
    switch (parsed.sourceType) {
      case SmsSourceType.upi:
        return PaymentMethod.upi;
      case SmsSourceType.creditCard:
        return PaymentMethod.creditCard;
      case SmsSourceType.debitCard:
        return PaymentMethod.debitCard;
      case SmsSourceType.wallet:
        return PaymentMethod.wallet;
      case SmsSourceType.neft:
      case SmsSourceType.rtgs:
      case SmsSourceType.imps:
      case SmsSourceType.bankAccount:
        return PaymentMethod.netBanking;
      case SmsSourceType.atm:
        return PaymentMethod.cash;
      case SmsSourceType.unknown:
        return PaymentMethod.upi;
    }
  }
}

/// A simple key-value row inside the detail card.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: context.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
