import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
import '../../data/models/cash_flow_event.dart';
import '../../data/models/credit.dart';
import '../../data/models/invoice.dart';
import '../../data/models/loan.dart';
import '../../data/models/scheduled_payment.dart';
import '../../data/models/transaction.dart';
import 'booking_provider.dart';
import 'credit_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'scheduled_payment_provider.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// cashFlowTimelineProvider — P1.5
// ---------------------------------------------------------------------------
//
// Merges data from all six financial sources into a single, sorted
// List<CashFlowEvent> for the Cash Flow Timeline screen (Pillar B).
//
// Sources:
//   • Transactions  — last 30 days → RecordedEvent
//   • Invoices      — unpaid: overdue → OverdueInvoiceEvent, future → UpcomingInvoiceEvent
//   • Credits       — active with dueDate: overdue → OverdueCreditEvent, future → UpcomingCreditEvent
//   • Loans         — active with nextEmiDate: overdue → OverdueLoanEvent, future → UpcomingLoanEvent
//   • Scheduled     — getOverdue() → OverdueScheduledEvent, getUpcoming() → UpcomingScheduledEvent
//   • Bookings      — getUpcoming() with pending balance → UpcomingBookingEvent
//
// Sort order: ascending date; ties broken by CashFlowEvent.sortPriority
// (overdue → recorded → upcoming → projected).

final cashFlowTimelineProvider = FutureProvider<List<CashFlowEvent>>((ref) async {
  final now = DateTime.now();
  final cutoffPast = now.subtract(const Duration(days: 30));

  // Parallel reads from all repos ──────────────────────────────────────────
  final results = await Future.wait([
    ref.read(transactionRepositoryProvider).getByDateRange(cutoffPast, now),  // 0
    ref.read(invoiceRepositoryProvider).getAll(),                              // 1
    ref.read(creditRepositoryProvider).getActive(),                            // 2
    ref.read(loanRepositoryProvider).getActive(),                              // 3
    ref.read(scheduledPaymentRepositoryProvider).getOverdue(),                 // 4
    ref.read(scheduledPaymentRepositoryProvider).getUpcoming(days: 7),        // 5
    ref.read(bookingRepositoryProvider).getUpcoming(limit: 20),               // 6
  ]);

  final events = <CashFlowEvent>[];

  // Transactions → RecordedEvent ────────────────────────────────────────────
  for (final t in results[0] as List<Transaction>) {
    events.add(RecordedEvent.fromTransaction(t));
  }

  // Invoices → OverdueInvoiceEvent / UpcomingInvoiceEvent ───────────────────
  for (final inv in results[1] as List<Invoice>) {
    if (inv.status == InvoiceStatus.paid) continue;
    final due = inv.dueDate ?? inv.issueDate;
    if (due.isBefore(now)) {
      events.add(OverdueInvoiceEvent.fromInvoice(inv));
    } else {
      events.add(UpcomingInvoiceEvent.fromInvoice(inv));
    }
  }

  // Credits → OverdueCreditEvent / UpcomingCreditEvent ──────────────────────
  for (final c in results[2] as List<Credit>) {
    final dueDate = c.dueDate;
    if (dueDate == null) continue;
    if (dueDate.isBefore(now)) {
      events.add(OverdueCreditEvent.fromCredit(c));
    } else {
      events.add(UpcomingCreditEvent.fromCredit(c));
    }
  }

  // Loans → OverdueLoanEvent / UpcomingLoanEvent ────────────────────────────
  for (final l in results[3] as List<Loan>) {
    final nextEmi = l.nextEmiDate;
    if (nextEmi == null) continue;
    if (nextEmi.isBefore(now)) {
      events.add(OverdueLoanEvent.fromLoan(l));
    } else {
      events.add(UpcomingLoanEvent.fromLoan(l));
    }
  }

  // Scheduled payments ───────────────────────────────────────────────────────
  for (final sp in results[4] as List<ScheduledPayment>) {
    events.add(OverdueScheduledEvent.fromPayment(sp));
  }
  for (final sp in results[5] as List<ScheduledPayment>) {
    events.add(UpcomingScheduledEvent.fromPayment(sp));
  }

  // Bookings → UpcomingBookingEvent ──────────────────────────────────────────
  for (final b in results[6] as List<Booking>) {
    if (b.paidAmount >= b.totalAmount) continue; // fully settled
    events.add(UpcomingBookingEvent.fromBooking(b));
  }

  // Sort: ascending date, ties by sortPriority ───────────────────────────────
  events.sort((a, b) {
    final dateCmp = a.date.compareTo(b.date);
    return dateCmp != 0 ? dateCmp : a.sortPriority.compareTo(b.sortPriority);
  });

  return events;
});

// ---------------------------------------------------------------------------
// Convenience slice providers
// ---------------------------------------------------------------------------

/// Only the overdue items from the timeline (sortPriority == 0).
final overdueEventsProvider = FutureProvider<List<CashFlowEvent>>((ref) async {
  final all = await ref.watch(cashFlowTimelineProvider.future);
  return all.where((e) => e.status == CashFlowStatus.overdue).toList();
});

/// Count of overdue items — used by the home-screen urgency nudge card.
final overdueEventCountProvider = FutureProvider<int>((ref) async {
  final overdue = await ref.watch(overdueEventsProvider.future);
  return overdue.length;
});

/// Total amount outstanding across all overdue events.
final overdueEventTotalProvider = FutureProvider<double>((ref) async {
  final overdue = await ref.watch(overdueEventsProvider.future);
  return overdue.fold<double>(0.0, (sum, e) => sum + e.amount);
});
