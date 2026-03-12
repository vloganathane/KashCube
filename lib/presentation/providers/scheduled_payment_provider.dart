import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/scheduled_payment.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/scheduled_payment_repository_impl.dart';
import '../../domain/repositories/scheduled_payment_repository.dart';
import 'context_provider.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final scheduledPaymentRepositoryProvider =
    Provider<ScheduledPaymentRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return ScheduledPaymentRepositoryImpl(null, contextId);
  },
);

// ---------------------------------------------------------------------------
// Main list — CRUD
// ---------------------------------------------------------------------------

final scheduledPaymentsProvider = StateNotifierProvider<
    ScheduledPaymentsNotifier,
    AsyncValue<List<ScheduledPayment>>>(
  (ref) => ScheduledPaymentsNotifier(
    ref.read(scheduledPaymentRepositoryProvider),
  ),
);

class ScheduledPaymentsNotifier
    extends StateNotifier<AsyncValue<List<ScheduledPayment>>> {
  ScheduledPaymentsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final ScheduledPaymentRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _repo.getAll();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(ScheduledPayment payment) async {
    try {
      await _repo.insert(payment);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(ScheduledPayment payment) async {
    try {
      await _repo.update(payment);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> remove(int id) async {
    try {
      await _repo.delete(id);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark a payment paid:
  /// * Advances [nextDate] to the next occurrence for recurring items.
  /// * Sets [isActive]=false for one-time items.
  Future<void> markPaid(ScheduledPayment payment) async {
    final now = DateTime.now();
    ScheduledPayment updated;

    if (payment.isOneTime) {
      updated = payment.copyWith(
        lastPaidDate: now,
        isActive: false,
        updatedAt: now,
      );
    } else {
      final nextDate = payment.frequency?.nextOccurrence(payment.nextDate) ??
          payment.nextDate;
      updated = payment.copyWith(
        lastPaidDate: now,
        nextDate: nextDate,
        updatedAt: now,
      );
    }
    await update(updated);
  }

  Future<void> markUnpaid(ScheduledPayment payment) async {
    await update(payment.copyWith(lastPaidDate: null, updatedAt: DateTime.now()));
  }
}

// ---------------------------------------------------------------------------
// Derived — monthly totals
// ---------------------------------------------------------------------------

/// Total monthly expense outflow from active recurring scheduled payments.
final totalMonthlyScheduledExpenseProvider = FutureProvider<double>((ref) {
  ref.watch(scheduledPaymentsProvider); // refresh when list changes
  return ref.read(scheduledPaymentRepositoryProvider).getTotalMonthlyExpense();
});

/// Monthly income + expense summary from recurring scheduled payments.
final scheduledMonthlySummaryProvider =
    Provider<({double income, double expense})>((ref) {
  final asyncList = ref.watch(scheduledPaymentsProvider);
  return asyncList.when(
    data: (items) {
      double income = 0;
      double expense = 0;
      for (final p in items) {
        if (p.isOneTime || p.frequency == null) continue;
        final monthly = p.frequency!.toMonthly(p.amount);
        if (p.type == 'income') {
          income += monthly;
        } else {
          expense += monthly;
        }
      }
      return (income: income, expense: expense);
    },
    loading: () => (income: 0.0, expense: 0.0),
    error: (_, _) => (income: 0.0, expense: 0.0),
  );
});

// ---------------------------------------------------------------------------
// Context-filtered lists (personal vs business)
// ---------------------------------------------------------------------------

/// Personal Bills Payable — utilities, subscriptions, rent, etc.
final personalBillsProvider =
    Provider<AsyncValue<List<ScheduledPayment>>>((ref) {
  return ref.watch(scheduledPaymentsProvider).whenData(
        (items) =>
            items.where((p) => p.billContext == 'personal').toList(),
      );
});

/// Business Payables — supplier / vendor dues, office expenses, etc.
final businessPayablesProvider =
    Provider<AsyncValue<List<ScheduledPayment>>>((ref) {
  return ref.watch(scheduledPaymentsProvider).whenData(
        (items) =>
            items.where((p) => p.billContext == 'business').toList(),
      );
});

/// Monthly summary for personal bills only.
final personalMonthlySummaryProvider =
    Provider<({double income, double expense})>((ref) {
  final asyncList = ref.watch(personalBillsProvider);
  return asyncList.when(
    data: (items) {
      double income = 0;
      double expense = 0;
      for (final p in items) {
        if (p.isOneTime || p.frequency == null) continue;
        final monthly = p.frequency!.toMonthly(p.amount);
        if (p.type == 'income') {
          income += monthly;
        } else {
          expense += monthly;
        }
      }
      return (income: income, expense: expense);
    },
    loading: () => (income: 0.0, expense: 0.0),
    error: (_, _) => (income: 0.0, expense: 0.0),
  );
});

/// Monthly summary for business payables only.
final businessMonthlySummaryProvider =
    Provider<({double income, double expense})>((ref) {
  final asyncList = ref.watch(businessPayablesProvider);
  return asyncList.when(
    data: (items) {
      double income = 0;
      double expense = 0;
      for (final p in items) {
        if (p.isOneTime || p.frequency == null) continue;
        final monthly = p.frequency!.toMonthly(p.amount);
        if (p.type == 'income') {
          income += monthly;
        } else {
          expense += monthly;
        }
      }
      return (income: income, expense: expense);
    },
    loading: () => (income: 0.0, expense: 0.0),
    error: (_, _) => (income: 0.0, expense: 0.0),
  );
});

/// Overdue scheduled payments (unpaid + past due date).
final overdueScheduledProvider =
    FutureProvider<List<ScheduledPayment>>((ref) {
  return ref.read(scheduledPaymentRepositoryProvider).getOverdue();
});

/// Upcoming scheduled payments (next 7 days).
final upcomingScheduledProvider =
    FutureProvider<List<ScheduledPayment>>((ref) {
  return ref
      .read(scheduledPaymentRepositoryProvider)
      .getUpcoming(days: 7);
});

// ---------------------------------------------------------------------------
// Auto-creation service
// ---------------------------------------------------------------------------

/// Processes [ScheduledPayment]s with `autoCreate=true` whose `nextDate` is
/// in the past and creates real transactions for them.
///
/// Call on app startup from AppShell.initState.
Future<int> processScheduledAutoCreations(WidgetRef ref) async {
  final repo = ref.read(scheduledPaymentRepositoryProvider);
  final txnRepo = ref.read(transactionRepositoryProvider);

  final due = await repo.getDueForAutoCreate();
  var generated = 0;

  for (final item in due) {
    try {
      final txn = Transaction(
        amount: item.amount,
        date: item.nextDate,
        type: item.type == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        category: item.category,
        partyName: item.partyName,
        paymentMethod: item.paymentMethod != null
            ? PaymentMethod.fromDb(item.paymentMethod!)
            : PaymentMethod.cash,
        notes: '${item.notes ?? ''} [Auto: ${item.isOneTime ? 'one-time' : item.frequency?.label ?? ''}]'
            .trim(),
        autoDetected: false,
      );
      await txnRepo.insert(txn);

      // Advance or deactivate
      final now = DateTime.now();
      if (item.isOneTime) {
        await repo.update(item.copyWith(
          isActive: false,
          lastGenerated: now,
          updatedAt: now,
        ));
      } else {
        final next = item.frequency?.nextOccurrence(item.nextDate) ??
            item.nextDate;
        await repo.update(item.copyWith(
          nextDate: next,
          lastGenerated: now,
          updatedAt: now,
        ));
      }
      generated++;
    } catch (e) {
      debugPrint('Failed to auto-create txn for scheduled payment ${item.id}: $e');
    }
  }

  if (generated > 0) {
    debugPrint('Auto-created $generated scheduled payment transactions');
    ref.invalidate(transactionsProvider);
    ref.invalidate(scheduledPaymentsProvider);
  }

  return generated;
}
