import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/parsed_sms.dart';
import '../../data/models/transaction.dart';
import '../screens/transactions/add_edit_transaction_screen.dart';
import '../../data/services/auto_categorizer.dart';
import '../../data/services/app_logger.dart';
import '../providers/dashboard_provider.dart';
import '../providers/sms_provider.dart';
import '../providers/transaction_provider.dart';

/// Bottom sheet listing all pending SMS transactions for batch review.
///
/// Each row shows the parsed amount + party with Quick-Save and Skip actions.
/// Bulk "Save All" / "Skip All" actions are shown at the top.
class SmsBatchReviewSheet extends StatefulWidget {
  const SmsBatchReviewSheet({super.key, required this.widgetRef});

  /// The [WidgetRef] from the calling screen — required because this sheet
  /// is shown from a non-ConsumerWidget context.
  final WidgetRef widgetRef;

  @override
  State<SmsBatchReviewSheet> createState() => _SmsBatchReviewSheetState();
}

class _SmsBatchReviewSheetState extends State<SmsBatchReviewSheet> {
  /// Tracks which items are currently being saved.
  final Set<String> _saving = {};

  WidgetRef get ref => widget.widgetRef;

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingSmsConfirmationsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.40,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Header row with title and bulk actions
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 20,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      pending.length == 1
                          ? '1 SMS transaction to review'
                          : '${pending.length} SMS transactions to review',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (pending.isNotEmpty) ...[
                    TextButton(
                      onPressed: () => _skipAll(pending),
                      child: const Text('Skip All'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.tonal(
                      onPressed: () => _saveAll(context, pending),
                      child: const Text('Save All'),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            if (pending.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: context.colorScheme.primary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'All caught up!',
                        style: context.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = pending[index];
                    return _SmsReviewTile(
                      parsed: item,
                      isSaving: _saving.contains(item.smsBody),
                      onSave: () => _saveOne(context, item),
                      onSkip: () => _skipOne(item),
                      onEdit: () => _editOne(context, item),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _saveOne(BuildContext context, ParsedSms parsed) async {
    final key = parsed.smsBody;
    setState(() => _saving.add(key));

    final tx = _buildTransaction(parsed);
    try {
      await ref.read(transactionsProvider.notifier).addTransaction(tx);
      ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
      ref.read(dashboardSummaryProvider.notifier).loadSummary();
      ref.read(recentTransactionsProvider.notifier).loadRecent();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  void _skipOne(ParsedSms parsed) {
    ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
  }

  Future<void> _saveAll(BuildContext context, List<ParsedSms> items) async {
    final copy = List<ParsedSms>.from(items);
    setState(() {
      for (final p in copy) {
        _saving.add(p.smsBody);
      }
    });

    int savedCount = 0;
    int errorCount = 0;
    for (final parsed in copy) {
      try {
        final tx = _buildTransaction(parsed);
        await ref.read(transactionsProvider.notifier).addTransaction(tx);
        ref
            .read(pendingSmsConfirmationsProvider.notifier)
            .removePending(parsed);
        savedCount++;
      } catch (e, st) {
        // Log and skip item on error — others continue
        AppLogger.instance.warning(
          'Failed to save SMS transaction from batch review',
          category: 'sms_batch_review',
          error: e,
          stackTrace: st,
        );
        errorCount++;
      } finally {
        if (mounted) setState(() => _saving.remove(parsed.smsBody));
      }
    }

    ref.read(dashboardSummaryProvider.notifier).loadSummary();
    ref.read(recentTransactionsProvider.notifier).loadRecent();

    if (context.mounted && errorCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorCount == 1
                ? '1 item could not be saved.'
                : '$errorCount items could not be saved.',
          ),
        ),
      );
    }

    if (context.mounted && savedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedCount == 1
                ? '1 transaction saved.'
                : '$savedCount transactions saved.',
          ),
        ),
      );
    }
  }

  void _skipAll(List<ParsedSms> items) {
    ref.read(pendingSmsConfirmationsProvider.notifier).clear();
  }

  Future<void> _editOne(BuildContext context, ParsedSms parsed) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddEditTransactionScreen(
          initialType: parsed.isCredit
              ? TransactionType.income
              : TransactionType.expense,
          initialAmount: parsed.amount,
          initialPartyName: parsed.partyName,
        ),
      ),
    );
    // Remove from pending regardless — user has taken explicit manual action.
    ref.read(pendingSmsConfirmationsProvider.notifier).removePending(parsed);
  }

  Transaction _buildTransaction(ParsedSms parsed) {
    final category = AutoCategorizer.categorize(parsed);
    final paymentMethod = _paymentMethodFromSource(parsed.sourceType);
    return Transaction(
      amount: parsed.amount,
      date: parsed.date ?? DateTime.now(),
      type: parsed.isCredit ? TransactionType.income : TransactionType.expense,
      category: category,
      partyName: parsed.partyName,
      paymentMethod: paymentMethod,
      smsBody: parsed.smsBody,
      smsSender: parsed.smsSender,
      upiApp: parsed.upiApp,
      upiRefNo: parsed.upiRefNo,
      referenceId: parsed.referenceId,
      autoDetected: true,
      verified: true,
    );
  }

  PaymentMethod _paymentMethodFromSource(SmsSourceType type) {
    switch (type) {
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

// ---------------------------------------------------------------------------
// Individual SMS review tile
// ---------------------------------------------------------------------------

class _SmsReviewTile extends StatelessWidget {
  const _SmsReviewTile({
    required this.parsed,
    required this.isSaving,
    required this.onSave,
    required this.onSkip,
    required this.onEdit,
  });

  final ParsedSms parsed;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onSkip;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isIncome = parsed.isCredit;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '−';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // Direction icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              size: 18,
              color: amountColor,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Amount + party
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$prefix${CurrencyFormatter.format(parsed.amount)}',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'RobotoMono',
                  ),
                ),
                if (parsed.partyName != null)
                  Text(
                    parsed.partyName!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    parsed.smsSender,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Action buttons
          if (isSaving)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Skip',
              color: context.colorScheme.onSurfaceVariant,
              onPressed: onSkip,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit manually',
              color: context.colorScheme.onSurfaceVariant,
              onPressed: onEdit,
            ),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
