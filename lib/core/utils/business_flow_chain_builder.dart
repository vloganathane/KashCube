// ---------------------------------------------------------------------------
// BusinessFlowChainBuilder — P2.8 / E3 (Pillar D)
// ---------------------------------------------------------------------------
// Pure Dart utility — no DB access, no async. Assembles BusinessFlowChain
// objects by matching FK links between Quote/Challan/Booking/Invoice/Transaction.
//
// Usage:
//   final chains = BusinessFlowChainBuilder.build(
//     partyId: partyId, partyName: partyName,
//     quotes: [...], challans: [...], bookings: [...],
//     invoices: [...], transactions: [...],
//   );
// ---------------------------------------------------------------------------

import '../../data/models/booking.dart';
import '../../data/models/business_flow_chain.dart';
import '../../data/models/delivery_challan.dart';
import '../../data/models/invoice.dart';
import '../../data/models/party_reminder.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';

class BusinessFlowChainBuilder {
  BusinessFlowChainBuilder._();

  // Leakage thresholds
  static const int _quoteLockDays =
      3; // accepted quote → no invoice after N days
  static const int _challanLockDays =
      2; // dispatched challan → no invoice after N days
  static const int _bookingLockDays =
      1; // completed/confirmed booking past service date

  /// Assemble chains for a single party given parallel-loaded lists.
  static List<BusinessFlowChain> build({
    required int partyId,
    required String partyName,
    required List<Quote> quotes,
    required List<DeliveryChallan> challans,
    required List<Booking> bookings,
    required List<Invoice> invoices,
    required List<Transaction> transactions,
    List<PartyReminder> reminders = const [],
  }) {
    final now = DateTime.now();
    final chains = <BusinessFlowChain>[];
    final usedInvoiceIds = <int>{};

    // ── TYPE 1: Quote chains ────────────────────────────────────────────────
    for (final q in quotes) {
      if (q.id == null) continue;

      // Find matching invoice(s) via invoice.quoteId
      final linkedInvoices = invoices.where((i) => i.quoteId == q.id).toList();
      final inv = linkedInvoices.isNotEmpty ? linkedInvoices.first : null;
      if (inv?.id != null) usedInvoiceIds.add(inv!.id!);

      // Find transactions linked to that invoice
      final linkedTxns = inv != null
          ? transactions.where((t) => t.linkedInvoiceId == inv.id).toList()
          : <Transaction>[];

      final ChainStatus status;
      if (q.status == QuoteStatus.rejected) {
        status = ChainStatus.cancelled;
      } else if (q.status == QuoteStatus.accepted && inv == null) {
        // Accepted but no invoice raised yet
        status = ChainStatus.awaitingInvoice;
      } else if (inv == null) {
        // Still in draft/sent — not yet leaking
        status = ChainStatus.awaitingPayment;
      } else {
        status = _invoiceChainStatus(inv, linkedTxns);
      }

      final totalValue = inv?.total ?? q.total;
      final received = linkedTxns.fold<double>(0, (s, t) => s + t.amount);
      final outstanding = (totalValue - received).clamp(0.0, double.infinity);
      final age = now.difference(q.createdAt).inDays;

      final chainReminders = _remindersInWindow(
        reminders,
        q.createdAt,
        inv?.dueDate ?? now,
      );

      chains.add(
        BusinessFlowChain(
          origin: ChainOrigin.quote,
          status: status,
          partyId: partyId,
          partyName: partyName,
          quote: q,
          invoice: inv,
          transactions: linkedTxns,
          reminders: chainReminders,
          totalValue: totalValue,
          receivedAmount: received,
          outstandingAmount: outstanding,
          daysSinceOrigin: age,
        ),
      );
    }

    // ── TYPE 2: Delivery Challan chains ─────────────────────────────────────
    for (final dc in challans) {
      if (dc.id == null) continue;

      // Find invoice via challan.convertedInvoiceId OR invoice.challanId
      Invoice? inv = dc.convertedInvoiceId != null
          ? invoices.cast<Invoice?>().firstWhere(
              (i) => i?.id == dc.convertedInvoiceId,
              orElse: () => null,
            )
          : invoices.cast<Invoice?>().firstWhere(
              (i) => i?.challanId == dc.id,
              orElse: () => null,
            );
      if (inv?.id != null) usedInvoiceIds.add(inv!.id!);

      final linkedTxns = inv != null
          ? transactions.where((t) => t.linkedInvoiceId == inv.id).toList()
          : <Transaction>[];

      final ChainStatus status;
      if (dc.status == ChallanStatus.returned) {
        status = ChainStatus.cancelled;
      } else if (dc.status == ChallanStatus.dispatched && inv == null) {
        status = ChainStatus.awaitingInvoice;
      } else if (inv == null) {
        status = ChainStatus.awaitingPayment;
      } else {
        status = _invoiceChainStatus(inv, linkedTxns);
      }

      final totalValue = inv?.total ?? 0.0;
      final received = linkedTxns.fold<double>(0, (s, t) => s + t.amount);
      final outstanding = (totalValue - received).clamp(0.0, double.infinity);
      final age = now.difference(dc.challanDate).inDays;

      chains.add(
        BusinessFlowChain(
          origin: ChainOrigin.challan,
          status: status,
          partyId: partyId,
          partyName: partyName,
          challan: dc,
          invoice: inv,
          transactions: linkedTxns,
          reminders: _remindersInWindow(
            reminders,
            dc.challanDate,
            inv?.dueDate ?? now,
          ),
          totalValue: totalValue,
          receivedAmount: received,
          outstandingAmount: outstanding,
          daysSinceOrigin: age,
        ),
      );
    }

    // ── TYPE 3: Booking chains ───────────────────────────────────────────────
    for (final b in bookings) {
      if (b.id == null) continue;

      // Find invoice via booking.invoiceId OR transaction.linkedBookingId
      Invoice? inv = b.invoiceId != null
          ? invoices.cast<Invoice?>().firstWhere(
              (i) => i?.id == b.invoiceId,
              orElse: () => null,
            )
          : null;
      if (inv?.id != null) usedInvoiceIds.add(inv!.id!);

      // Transactions: either linked to the invoice or directly to the booking
      final linkedTxns = transactions
          .where(
            (t) =>
                (inv != null && t.linkedInvoiceId == inv.id) ||
                t.linkedBookingId == b.id,
          )
          .toList();

      final ChainStatus status;
      if (b.status == BookingStatus.cancelled ||
          b.status == BookingStatus.noShow) {
        status = ChainStatus.cancelled;
      } else if ((b.status == BookingStatus.completed ||
              b.status == BookingStatus.confirmed) &&
          inv == null) {
        status = ChainStatus.awaitingInvoice;
      } else if (inv == null) {
        status = ChainStatus.awaitingPayment;
      } else {
        status = _invoiceChainStatus(inv, linkedTxns);
      }

      final totalValue = inv?.total ?? b.totalAmount;
      final received = linkedTxns.fold<double>(0, (s, t) => s + t.amount);
      final outstanding = (totalValue - received).clamp(0.0, double.infinity);
      final age = now.difference(b.startDatetime).inDays.abs();

      chains.add(
        BusinessFlowChain(
          origin: ChainOrigin.booking,
          status: status,
          partyId: partyId,
          partyName: partyName,
          booking: b,
          invoice: inv,
          transactions: linkedTxns,
          reminders: _remindersInWindow(
            reminders,
            b.startDatetime,
            inv?.dueDate ?? now,
          ),
          totalValue: totalValue,
          receivedAmount: received,
          outstandingAmount: outstanding,
          daysSinceOrigin: age,
        ),
      );
    }

    // ── TYPE 4: Direct Invoice chains ────────────────────────────────────────
    for (final inv in invoices) {
      if (inv.id == null) continue;
      if (usedInvoiceIds.contains(inv.id)) continue; // already in a chain
      if (inv.quoteId != null || inv.challanId != null) continue; // has origin

      final linkedTxns = transactions
          .where((t) => t.linkedInvoiceId == inv.id)
          .toList();

      final status = _invoiceChainStatus(inv, linkedTxns);
      final received = linkedTxns.fold<double>(0, (s, t) => s + t.amount);
      final outstanding = (inv.total - received).clamp(0.0, double.infinity);
      final age = now.difference(inv.issueDate).inDays;

      chains.add(
        BusinessFlowChain(
          origin: ChainOrigin.directInvoice,
          status: status,
          partyId: partyId,
          partyName: partyName,
          invoice: inv,
          transactions: linkedTxns,
          reminders: _remindersInWindow(
            reminders,
            inv.issueDate,
            inv.dueDate ?? now,
          ),
          totalValue: inv.total,
          receivedAmount: received,
          outstandingAmount: outstanding,
          daysSinceOrigin: age,
        ),
      );
    }

    // Sort: leaking first → needs action → complete → cancelled
    chains.sort((a, b) {
      final aScore = _chainSortScore(a);
      final bScore = _chainSortScore(b);
      return bScore.compareTo(aScore);
    });

    return chains;
  }

  // ── Leaking chain detector (global — across all parties) ────────────────────

  /// Returns chains where:
  ///  • Accepted quote with no invoice for >_quoteLockDays
  ///  • Dispatched challan with no invoice for >_challanLockDays
  ///  • Completed/confirmed booking with no invoice and service date past
  static List<BusinessFlowChain> filterLeaking(List<BusinessFlowChain> chains) {
    final now = DateTime.now();
    return chains.where((c) {
      if (!c.isLeaking) return false;
      return switch (c.origin) {
        ChainOrigin.quote => c.daysSinceOrigin >= _quoteLockDays,
        ChainOrigin.challan => c.daysSinceOrigin >= _challanLockDays,
        ChainOrigin.booking =>
          c.booking != null &&
              c.booking!.startDatetime.isBefore(now) &&
              c.daysSinceOrigin >= _bookingLockDays,
        ChainOrigin.directInvoice => false, // can't leak if it IS the invoice
      };
    }).toList();
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  static ChainStatus _invoiceChainStatus(Invoice inv, List<Transaction> txns) {
    if (inv.status == InvoiceStatus.paid && txns.isNotEmpty) {
      return ChainStatus.complete;
    }
    if (inv.status == InvoiceStatus.partiallyPaid) {
      return ChainStatus.invoicedPartially;
    }
    return ChainStatus.awaitingPayment;
  }

  static int _chainSortScore(BusinessFlowChain c) => switch (c.status) {
    ChainStatus.awaitingInvoice => 100,
    ChainStatus.awaitingPayment => 80,
    ChainStatus.invoicedPartially => 60,
    ChainStatus.complete => 10,
    ChainStatus.cancelled => 0,
  };

  /// Returns reminders whose `sentAt` falls within [from, to].
  static List<PartyReminder> _remindersInWindow(
    List<PartyReminder> all,
    DateTime from,
    DateTime to,
  ) {
    final end = to.isAfter(from) ? to : from.add(const Duration(days: 90));
    return all
        .where(
          (r) =>
              r.sentAt.isAfter(from.subtract(const Duration(days: 1))) &&
              r.sentAt.isBefore(end.add(const Duration(days: 1))),
        )
        .toList();
  }
}
