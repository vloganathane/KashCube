import 'booking.dart';
import 'credit.dart';
import 'invoice.dart';
import 'loan.dart';
import 'scheduled_payment.dart';
import 'transaction.dart';

// ---------------------------------------------------------------------------
// CashFlowEvent — P1.4
// ---------------------------------------------------------------------------
//
// Sealed class that represents any money movement event on the Cash Flow
// Timeline (Pillar B). Covers:
//   • Past: real recorded Transactions
//   • Overdue: any item whose due date has passed and is unpaid
//   • Upcoming: any future due item (invoice / bill / loan EMI / booking)
//   • Projected: recurring items beyond the near-term window

enum CashFlowDirection { inflow, outflow }

enum CashFlowStatus { recorded, overdue, upcoming, projected }

// ── Source labels ────────────────────────────────────────────────────────────
enum CashFlowSource {
  transaction,
  invoice,
  credit,
  loan,
  scheduledPayment,
  booking,
}

// ── Base ─────────────────────────────────────────────────────────────────────

sealed class CashFlowEvent {
  const CashFlowEvent({
    required this.date,
    required this.amount,
    required this.direction,
    required this.status,
    required this.source,
    required this.description,
    required this.partyName,
    this.sourceId,
    this.categoryLabel,
  });

  final DateTime date;
  final double amount;
  final CashFlowDirection direction;
  final CashFlowStatus status;
  final CashFlowSource source;

  /// Primary display line (e.g. "Invoice #INV-0041 — Rajesh Traders").
  final String description;

  /// Party name for secondary display / tap-through to Party 360°.
  final String? partyName;

  /// ID of the source document — used for navigation to its detail screen.
  final int? sourceId;

  /// Human-readable category or type label for the subtitle.
  final String? categoryLabel;

  /// Sort key: overdue items sort before any future items of the same date.
  int get sortPriority => switch (status) {
    CashFlowStatus.overdue => 0,
    CashFlowStatus.recorded => 1,
    CashFlowStatus.upcoming => 2,
    CashFlowStatus.projected => 3,
  };
}

// ── Concrete subtypes ─────────────────────────────────────────────────────────

/// A real transaction already recorded in the ledger.
final class RecordedEvent extends CashFlowEvent {
  const RecordedEvent({
    required super.date,
    required super.amount,
    required super.direction,
    required super.description,
    super.partyName,
    super.sourceId,
    super.categoryLabel,
    required this.transaction,
  }) : super(
         status: CashFlowStatus.recorded,
         source: CashFlowSource.transaction,
       );

  final Transaction transaction;

  factory RecordedEvent.fromTransaction(Transaction txn) => RecordedEvent(
    date: txn.date,
    amount: txn.amount,
    direction: txn.isIncome
        ? CashFlowDirection.inflow
        : CashFlowDirection.outflow,
    description: txn.category,
    partyName: txn.partyName,
    sourceId: txn.id,
    categoryLabel: txn.category,
    transaction: txn,
  );
}

/// An invoice whose due date has passed and hasn't been paid.
final class OverdueInvoiceEvent extends CashFlowEvent {
  const OverdueInvoiceEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
  }) : super(
         direction: CashFlowDirection.inflow,
         status: CashFlowStatus.overdue,
         source: CashFlowSource.invoice,
         categoryLabel: 'Overdue Invoice',
       );

  factory OverdueInvoiceEvent.fromInvoice(Invoice inv) => OverdueInvoiceEvent(
    date: inv.dueDate ?? inv.issueDate,
    amount: (inv.total - inv.paidAmount).clamp(0, double.infinity),
    description: 'Invoice ${inv.invoiceNo}',
    partyName: inv.customerName,
    sourceId: inv.id,
  );
}

/// An upcoming invoice due date (not yet overdue).
final class UpcomingInvoiceEvent extends CashFlowEvent {
  const UpcomingInvoiceEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
  }) : super(
         direction: CashFlowDirection.inflow,
         status: CashFlowStatus.upcoming,
         source: CashFlowSource.invoice,
         categoryLabel: 'Invoice Due',
       );

  factory UpcomingInvoiceEvent.fromInvoice(Invoice inv) => UpcomingInvoiceEvent(
    date: inv.dueDate!,
    amount: (inv.total - inv.paidAmount).clamp(0, double.infinity),
    description: 'Invoice ${inv.invoiceNo}',
    partyName: inv.customerName,
    sourceId: inv.id,
  );
}

/// An overdue credit/udhar due date.
final class OverdueCreditEvent extends CashFlowEvent {
  const OverdueCreditEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    required this.isInflow,
  }) : super(
         direction: isInflow
             ? CashFlowDirection.inflow
             : CashFlowDirection.outflow,
         status: CashFlowStatus.overdue,
         source: CashFlowSource.credit,
         categoryLabel: 'Overdue Due',
       );

  final bool isInflow;

  factory OverdueCreditEvent.fromCredit(Credit c) => OverdueCreditEvent(
    date: c.dueDate ?? c.creditDate,
    amount: c.pendingAmount,
    description: 'Due — ${c.customerName}',
    partyName: c.customerName,
    sourceId: c.id,
    isInflow: c.isGiven, // given = they owe us = inflow when returned
  );
}

/// Upcoming credit/udhar due date.
final class UpcomingCreditEvent extends CashFlowEvent {
  const UpcomingCreditEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    required this.isInflow,
  }) : super(
         direction: isInflow
             ? CashFlowDirection.inflow
             : CashFlowDirection.outflow,
         status: CashFlowStatus.upcoming,
         source: CashFlowSource.credit,
         categoryLabel: 'Due Date',
       );

  final bool isInflow;

  factory UpcomingCreditEvent.fromCredit(Credit c) => UpcomingCreditEvent(
    date: c.dueDate!,
    amount: c.pendingAmount,
    description: 'Due — ${c.customerName}',
    partyName: c.customerName,
    sourceId: c.id,
    isInflow: c.isGiven,
  );
}

/// An overdue loan EMI.
final class OverdueLoanEvent extends CashFlowEvent {
  const OverdueLoanEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    required this.isInflow,
  }) : super(
         direction: isInflow
             ? CashFlowDirection.inflow
             : CashFlowDirection.outflow,
         status: CashFlowStatus.overdue,
         source: CashFlowSource.loan,
         categoryLabel: 'Overdue EMI',
       );

  final bool isInflow;

  factory OverdueLoanEvent.fromLoan(Loan l) => OverdueLoanEvent(
    date: l.nextEmiDate ?? l.dueDate ?? l.loanDate,
    amount: l.emiAmount ?? l.pendingAmount,
    description: 'Loan EMI — ${l.lenderName}',
    partyName: l.lenderName,
    sourceId: l.id,
    isInflow: l.direction == LoanDirection.lent,
  );
}

/// An upcoming loan EMI.
final class UpcomingLoanEvent extends CashFlowEvent {
  const UpcomingLoanEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    required this.isInflow,
  }) : super(
         direction: isInflow
             ? CashFlowDirection.inflow
             : CashFlowDirection.outflow,
         status: CashFlowStatus.upcoming,
         source: CashFlowSource.loan,
         categoryLabel: 'EMI Due',
       );

  final bool isInflow;

  factory UpcomingLoanEvent.fromLoan(Loan l) => UpcomingLoanEvent(
    date: l.nextEmiDate!,
    amount: l.emiAmount ?? l.pendingAmount,
    description: 'Loan EMI — ${l.lenderName}',
    partyName: l.lenderName,
    sourceId: l.id,
    isInflow: l.direction == LoanDirection.lent,
  );
}

/// An overdue scheduled payment (bill / recurring reminder).
final class OverdueScheduledEvent extends CashFlowEvent {
  const OverdueScheduledEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    super.categoryLabel,
  }) : super(
         direction: CashFlowDirection.outflow,
         status: CashFlowStatus.overdue,
         source: CashFlowSource.scheduledPayment,
       );

  factory OverdueScheduledEvent.fromPayment(ScheduledPayment p) =>
      OverdueScheduledEvent(
        date: p.nextDate,
        amount: p.amount,
        description: p.name,
        partyName: p.partyName,
        sourceId: p.id,
        categoryLabel: p.category,
      );
}

/// An upcoming scheduled payment.
final class UpcomingScheduledEvent extends CashFlowEvent {
  const UpcomingScheduledEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    super.categoryLabel,
  }) : super(
         direction: CashFlowDirection.outflow,
         status: CashFlowStatus.upcoming,
         source: CashFlowSource.scheduledPayment,
       );

  factory UpcomingScheduledEvent.fromPayment(ScheduledPayment p) =>
      UpcomingScheduledEvent(
        date: p.nextDate,
        amount: p.amount,
        description: p.name,
        partyName: p.partyName,
        sourceId: p.id,
        categoryLabel: p.category,
      );
}

/// A projected recurrence of a scheduled payment beyond the near-term window.
final class ProjectedScheduledEvent extends CashFlowEvent {
  const ProjectedScheduledEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
    super.categoryLabel,
  }) : super(
         direction: CashFlowDirection.outflow,
         status: CashFlowStatus.projected,
         source: CashFlowSource.scheduledPayment,
       );
}

/// A booking service date with an outstanding balance.
final class UpcomingBookingEvent extends CashFlowEvent {
  const UpcomingBookingEvent({
    required super.date,
    required super.amount,
    required super.description,
    super.partyName,
    super.sourceId,
  }) : super(
         direction: CashFlowDirection.inflow,
         status: CashFlowStatus.upcoming,
         source: CashFlowSource.booking,
         categoryLabel: 'Booking',
       );

  factory UpcomingBookingEvent.fromBooking(Booking b) => UpcomingBookingEvent(
    date: b.startDatetime,
    amount: (b.totalAmount - b.paidAmount).clamp(0, double.infinity),
    description: '${b.serviceName} — ${b.customerName}',
    partyName: b.customerName,
    sourceId: b.id,
  );
}
