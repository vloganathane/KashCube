// ---------------------------------------------------------------------------
// BusinessFlowChain — E1 (Pillar D)
// ---------------------------------------------------------------------------
// A "deal chain" links a source document (Quote / Challan / Booking /
// direct Invoice) through to payment, surfacing revenue leakage and stuck
// deals.
//
// All data is assembled in-memory from local SQLite — no new DB columns.
// ---------------------------------------------------------------------------

import 'booking.dart';
import 'delivery_challan.dart';
import 'invoice.dart';
import 'party_reminder.dart';
import 'quote.dart';
import 'transaction.dart';

// ── Chain origin ─────────────────────────────────────────────────────────────

enum ChainOrigin {
  quote,
  challan,
  booking,
  directInvoice;

  String get label => switch (this) {
    ChainOrigin.quote => 'Quote',
    ChainOrigin.challan => 'Delivery Challan',
    ChainOrigin.booking => 'Booking',
    ChainOrigin.directInvoice => 'Invoice',
  };

  String get icon => switch (this) {
    ChainOrigin.quote => 'quote',
    ChainOrigin.challan => 'truck',
    ChainOrigin.booking => 'calendar',
    ChainOrigin.directInvoice => 'receipt',
  };
}

// ── Chain status ─────────────────────────────────────────────────────────────

enum ChainStatus {
  /// Invoice paid + at least one linked Transaction present.
  complete,

  /// Invoice raised but awaiting full payment.
  awaitingPayment,

  /// Source document is done but no Invoice has been raised — REVENUE LEAKAGE.
  awaitingInvoice,

  /// Invoice exists with partiallyPaid status.
  invoicedPartially,

  /// Quote rejected / Booking cancelled / Challan returned.
  cancelled;

  String get label => switch (this) {
    ChainStatus.complete => 'Complete',
    ChainStatus.awaitingPayment => 'Awaiting Payment',
    ChainStatus.awaitingInvoice => '⚠ Invoice Not Raised',
    ChainStatus.invoicedPartially => 'Partially Paid',
    ChainStatus.cancelled => 'Cancelled',
  };

  bool get isLeaking => this == ChainStatus.awaitingInvoice;

  bool get needsAction =>
      this == ChainStatus.awaitingInvoice ||
      this == ChainStatus.awaitingPayment ||
      this == ChainStatus.invoicedPartially;
}

// ── BusinessFlowChain ─────────────────────────────────────────────────────────

class BusinessFlowChain {
  const BusinessFlowChain({
    required this.origin,
    required this.status,
    required this.partyId,
    required this.partyName,
    this.quote,
    this.challan,
    this.booking,
    this.invoice,
    this.transactions = const [],
    this.reminders = const [],
    required this.totalValue,
    required this.receivedAmount,
    required this.outstandingAmount,
    required this.daysSinceOrigin,
  });

  final ChainOrigin origin;
  final ChainStatus status;

  final int partyId;
  final String partyName;

  // ── Source document (exactly one should be non-null for non-direct chains)
  final Quote? quote;
  final DeliveryChallan? challan;
  final Booking? booking;

  // ── Downstream
  final Invoice? invoice;
  final List<Transaction> transactions;

  // ── Reminder history (party_reminders filtered by chain date window)
  final List<PartyReminder> reminders;

  // ── Derived amounts
  final double totalValue;
  final double receivedAmount;
  final double outstandingAmount;

  /// Days since the source document was created / accepted.
  final int daysSinceOrigin;

  bool get isLeaking => status.isLeaking;
  bool get isComplete => status == ChainStatus.complete;
  bool get needsAction => status.needsAction;

  /// Human-readable title for the chain (used in FlowChainTile header).
  String get chainTitle {
    return switch (origin) {
      ChainOrigin.quote => 'Quote ${quote?.quoteNo ?? ""}',
      ChainOrigin.challan => 'Challan ${challan?.challanNo ?? ""}',
      ChainOrigin.booking => booking?.serviceName ?? 'Booking',
      ChainOrigin.directInvoice => 'Invoice ${invoice?.invoiceNo ?? ""}',
    };
  }

  /// The primary source doc date.
  DateTime get originDate {
    return switch (origin) {
      ChainOrigin.quote => quote?.createdAt ?? DateTime.now(),
      ChainOrigin.challan => challan?.challanDate ?? DateTime.now(),
      ChainOrigin.booking => booking?.startDatetime ?? DateTime.now(),
      ChainOrigin.directInvoice => invoice?.issueDate ?? DateTime.now(),
    };
  }

  /// Urgent call-to-action label based on status.
  String get ctaLabel => switch (status) {
    ChainStatus.awaitingInvoice => 'Raise Invoice',
    ChainStatus.awaitingPayment => 'Send Reminder',
    ChainStatus.invoicedPartially => 'Record Balance',
    _ => 'View',
  };
}
