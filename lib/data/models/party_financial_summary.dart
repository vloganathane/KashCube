import 'booking.dart';
import 'credit.dart';
import 'invoice.dart';
import 'loan.dart';
import 'party_reminder.dart';

// ---------------------------------------------------------------------------
// PartyFinancialSummary — P1.1
// ---------------------------------------------------------------------------
//
// Aggregated financial snapshot for a single party.
// All fields are computed in-memory from local SQLite data — no network calls.
//
// Usage:
//   final summary = await ref.watch(partyFinancialSummaryProvider(partyId).future);

class PartyFinancialSummary {
  const PartyFinancialSummary({
    required this.partyId,
    required this.partyName,
    required this.netOutstanding,
    required this.invoicesPending,
    required this.duesPending,
    required this.loansPending,
    required this.bookingsPending,
    required this.openInvoices,
    required this.openDues,
    required this.activeLoans,
    required this.activeBookings,
    required this.transactionCount,
    required this.reminderCount,
    this.earliestDueDate,
    required this.hasOverdueItem,
    this.lastTransactionDate,
    this.lastReminderDate,
  });

  final int partyId;
  final String partyName;

  // ── Net balance ──────────────────────────────────────────────────────────
  /// Positive  → party owes US (to collect).
  /// Negative  → we owe party.
  final double netOutstanding;

  // ── Per-module pending amounts ───────────────────────────────────────────
  /// Sum of (total − paidAmount) for non-paid invoices linked to this party.
  final double invoicesPending;

  /// Sum of pendingAmount for active credit-given entries (udhar — they owe us).
  final double duesPending;

  /// Sum of pendingAmount for active lent-out loans (we lent them money).
  final double loansPending;

  /// Sum of (totalAmount − paidAmount) for active bookings (pending/confirmed).
  final double bookingsPending;

  // ── Counts ───────────────────────────────────────────────────────────────
  final int openInvoices;
  final int openDues;
  final int activeLoans;
  final int activeBookings;
  final int transactionCount;
  final int reminderCount;

  // ── Urgency ──────────────────────────────────────────────────────────────
  /// Earliest upcoming or past due date across all modules.
  final DateTime? earliestDueDate;

  /// True when any module has an item past due.
  final bool hasOverdueItem;

  // ── Recent activity ──────────────────────────────────────────────────────
  final DateTime? lastTransactionDate;
  final DateTime? lastReminderDate;

  // ── Factory: compute from raw lists ──────────────────────────────────────

  factory PartyFinancialSummary.compute({
    required int partyId,
    required String partyName,
    required List<Invoice> invoices,
    required List<Credit> credits,
    required List<Loan> loans,
    required List<Booking> bookings,
    required int transactionCount,
    required List<PartyReminder> reminders,
    DateTime? lastTransactionDate,
  }) {
    final now = DateTime.now();

    // ── Invoices ─────────────────────────────────────────────────────────
    final activeInvoices = invoices
        .where((i) =>
            i.status != InvoiceStatus.paid)
        .toList();

    final invoicesPending = activeInvoices.fold<double>(
      0,
      (sum, inv) => sum + (inv.total - inv.paidAmount).clamp(0, double.infinity),
    );

    final openInvoices = activeInvoices.length;
    final hasOverdueInvoice =
        activeInvoices.any((i) => i.status == InvoiceStatus.overdue ||
            (i.dueDate != null && i.dueDate!.isBefore(now)));

    final invoiceDueDates = activeInvoices
        .where((i) => i.dueDate != null)
        .map((i) => i.dueDate!);

    // ── Credits / Dues (given → they owe us) ─────────────────────────────
    final activeDues = credits
        .where((c) => !c.isCleared && c.direction == CreditDirection.given)
        .toList();
    final duesPending = activeDues.fold<double>(
      0,
      (sum, c) => sum + c.pendingAmount,
    );
    final openDues = activeDues.length;
    final hasOverdueDue = activeDues.any((c) => c.isOverdue ||
        (c.dueDate != null && c.dueDate!.isBefore(now)));
    final dueDueDates = activeDues
        .where((c) => c.dueDate != null)
        .map((c) => c.dueDate!);

    // ── Loans (lent → they owe us) ────────────────────────────────────────
    final activeLentLoans = loans
        .where((l) => !l.isCleared && l.direction == LoanDirection.lent)
        .toList();
    final loansPending = activeLentLoans.fold<double>(
      0,
      (sum, l) => sum + l.pendingAmount,
    );
    final activeLoans = activeLentLoans.length;
    final hasOverdueLoan = activeLentLoans.any((l) => l.isOverdue ||
        (l.nextEmiDate != null && l.nextEmiDate!.isBefore(now)));
    final loanDueDates = activeLentLoans
        .where((l) => l.nextEmiDate != null)
        .map((l) => l.nextEmiDate!);

    // ── Bookings ─────────────────────────────────────────────────────────
    final activeBookingsList = bookings
        .where((b) =>
            b.status == BookingStatus.pending ||
            b.status == BookingStatus.confirmed)
        .toList();
    final bookingsPending = activeBookingsList.fold<double>(
      0,
      (sum, b) => sum + (b.totalAmount - b.paidAmount).clamp(0, double.infinity),
    );
    final activeBookings = activeBookingsList.length;
    final bookingDueDates = activeBookingsList.map((b) => b.startDatetime);

    // ── Net outstanding ───────────────────────────────────────────────────
    final netOutstanding =
        invoicesPending + duesPending + loansPending + bookingsPending;

    // ── Urgency ──────────────────────────────────────────────────────────
    final allDueDates = [
      ...invoiceDueDates,
      ...dueDueDates,
      ...loanDueDates,
      ...bookingDueDates,
    ];
    // Prefer overdue dates first, then upcoming
    allDueDates.sort();
    final earliestDueDate = allDueDates.isNotEmpty ? allDueDates.first : null;

    final hasOverdueItem = hasOverdueInvoice || hasOverdueDue || hasOverdueLoan;

    // ── Reminders ─────────────────────────────────────────────────────────
    DateTime? lastReminderDate;
    if (reminders.isNotEmpty) {
      final sorted = [...reminders]..sort((a, b) => b.sentAt.compareTo(a.sentAt));
      lastReminderDate = sorted.first.sentAt;
    }

    return PartyFinancialSummary(
      partyId: partyId,
      partyName: partyName,
      netOutstanding: netOutstanding,
      invoicesPending: invoicesPending,
      duesPending: duesPending,
      loansPending: loansPending,
      bookingsPending: bookingsPending,
      openInvoices: openInvoices,
      openDues: openDues,
      activeLoans: activeLoans,
      activeBookings: activeBookings,
      transactionCount: transactionCount,
      reminderCount: reminders.length,
      earliestDueDate: earliestDueDate,
      hasOverdueItem: hasOverdueItem,
      lastTransactionDate: lastTransactionDate,
      lastReminderDate: lastReminderDate,
    );
  }
}
