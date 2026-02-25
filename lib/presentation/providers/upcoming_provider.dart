import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bill.dart';
import '../../data/models/loan.dart';
import 'bill_schedule_provider.dart';
import 'loan_payment_provider.dart';
import 'loan_provider.dart';

// ---------------------------------------------------------------------------
// UpcomingItem — sealed union of upcoming loan payments + bills
// ---------------------------------------------------------------------------

sealed class UpcomingItem {
  const UpcomingItem();

  /// The deadline date for this item.
  DateTime get dueDate;

  /// Days until due. Negative = overdue.
  int get daysUntilDue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.difference(today).inDays;
  }

  bool get isOverdue => daysUntilDue < 0;
}

/// An upcoming loan EMI repayment or lump-sum due date.
final class LoanUpcomingItem extends UpcomingItem {
  const LoanUpcomingItem(this.loan, {this.resolvedDueDate});

  final Loan loan;
  /// Overrides loan.nextEmiDate when that field is null (e.g. legacy data).
  final DateTime? resolvedDueDate;

  @override
  DateTime get dueDate =>
      resolvedDueDate ?? loan.nextEmiDate ?? loan.dueDate ?? DateTime.now();

  /// Amount expected this installment (EMI or full pending).
  double get paymentAmount => loan.emiAmount ?? loan.pendingAmount;
}

/// An upcoming bill payment.
final class BillUpcomingItem extends UpcomingItem {
  const BillUpcomingItem(this.bill);

  final Bill bill;

  @override
  DateTime get dueDate => bill.nextDueDate;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Merged upcoming items from active loans and unpaid bills.
///
/// Window: overdue items + next 14 days.
/// Sorted ascending by due date (overdue-first, nearest upcoming next).
final upcomingItemsProvider = Provider<AsyncValue<List<UpcomingItem>>>((ref) {
  final loansAsync = ref.watch(activeLoansProvider);
  final billsAsync = ref.watch(scheduledBillsProvider);
  // Fallback: actual next unpaid installment date from loan_payments table,
  // for loans whose next_emi_date column is null (e.g. created before this fix).
  final nextDatesAsync = ref.watch(nextPaymentDatesForAllProvider);

  return loansAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (loans) => billsAsync.when(
      loading: () => const AsyncValue.loading(),
      error: AsyncValue.error,
      data: (bills) {
        // nextDates may still be loading — use empty map as fallback so we
        // don't block the whole section.
        final nextDates = nextDatesAsync.valueOrNull ?? {};

        const windowDays = 14;
        final items = <UpcomingItem>[];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        // Loans: include if active and has a due date within window or overdue.
        // Priority: nextEmiDate > scheduled installment from loan_payments > dueDate
        for (final loan in loans) {
          if (loan.isCleared) continue;

          // Resolve effective due date
          final due = loan.nextEmiDate
              ?? nextDates[loan.id]  // fallback: first unpaid installment
              ?? loan.dueDate;

          if (due == null) continue;
          final dueOnly = DateTime(due.year, due.month, due.day);
          if (dueOnly.difference(today).inDays <= windowDays) {
            items.add(LoanUpcomingItem(
              loan,
              resolvedDueDate:
                  loan.nextEmiDate == null ? nextDates[loan.id] : null,
            ));
          }
        }

        // Bills: include if unpaid and within window or overdue.
        for (final bill in bills) {
          if (bill.isPaidThisPeriod) continue;
          if (bill.daysUntilDue <= windowDays) {
            items.add(BillUpcomingItem(bill));
          }
        }

        // Sort ascending by due date
        items.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        return AsyncValue.data(items);
      },
    ),
  );
});
