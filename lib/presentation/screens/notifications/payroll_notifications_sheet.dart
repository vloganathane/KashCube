import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/payroll_notification.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/transaction_repository_impl.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
/// Shows pending payroll notifications in a modal bottom sheet.
///
/// Call [showPayrollNotificationsSheet] to open it.
void showPayrollNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PayrollNotificationsSheet(),
  );
}

class _PayrollNotificationsSheet extends ConsumerWidget {
  const _PayrollNotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync =
        ref.watch(payrollNotificationsNotifierProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.90,
      builder: (_, controller) {
        return Column(
          children: [
            // ── Handle ────────────────────────────────────────────────
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined,
                      color: context.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Salary Notifications',
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            // ── Body ──────────────────────────────────────────────────
            Expanded(
              child: notificationsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error: $e')),
                data: (notifications) {
                  if (notifications.isEmpty) {
                    return const _EmptyState();
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: AppSpacing.base,
                    ),
                    itemBuilder: (context, i) => _NotificationTile(
                      notification: notifications[i],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final PayrollNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier =
        ref.read(payrollNotificationsNotifierProvider.notifier);
    final paidDate = _formatDate(notification.paidOn);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.businessName,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (notification.referenceLabel != null)
                      Text(
                        notification.referenceLabel!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.outline,
                        ),
                      ),
                    Text(
                      paidDate,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '+${CurrencyFormatter.format(notification.amount)}',
                style: context.textTheme.titleMedium?.copyWith(
                  color: context.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    notifier.dismiss(notification.notificationId),
                style: TextButton.styleFrom(
                  foregroundColor: context.colorScheme.outline,
                ),
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: () =>
                    _addIncome(context, ref, notification),
                child: const Text('Add Income'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addIncome(
    BuildContext context,
    WidgetRef ref,
    PayrollNotification n,
  ) async {
    final repo = TransactionRepositoryImpl();
    final now  = DateTime.now();
    final txn  = Transaction(
      type:     TransactionType.income,
      amount:   n.amount,
      category: 'Salary',
      date:     now,
      notes:    n.referenceLabel,
    );
    final id = await repo.insert(txn);

    // Invalidate transaction providers so dashboard refreshes.
    ref.invalidate(transactionsProvider);
    ref.invalidate(recentTransactionsProvider);

    await ref
        .read(payrollNotificationsNotifierProvider.notifier)
        .markAdded(n.notificationId, transactionId: id);
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 48, color: context.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No pending salary notifications',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
