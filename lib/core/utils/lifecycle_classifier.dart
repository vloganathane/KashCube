// ---------------------------------------------------------------------------
// Lifecycle Layer — LC2
// ---------------------------------------------------------------------------
// Pure Dart utility: classifies a financial item into its current
// LifecycleStage and computes daysInStage.
//
// All methods are static — no async, no DB access — safe to call inside
// build() or in a synchronous provider map.
//
// Reference for daysInStage (per spec Q6 answer):
//   max(updatedAt, lastReminderAt) — whichever event was most recent.
// ---------------------------------------------------------------------------

import '../../data/models/booking.dart';
import '../../data/models/credit.dart';
import '../../data/models/invoice.dart';
import '../../data/models/lifecycle_info.dart';
import '../../data/models/loan.dart';
import '../../data/models/scheduled_payment.dart';

class LifecycleClassifier {
  // Private constructor — static-only class.
  const LifecycleClassifier._();

  // ── Invoice ───────────────────────────────────────────────────────────────
  //
  // Stage machine:
  //   draft → sent → reminded → partiallyPaid → paid
  //                    ↓ if past dueDate at any active stage
  //                  overdue

  static LifecycleInfo forInvoice(
    Invoice inv, {
    DateTime? lastReminderAt,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (inv.status) {
      case InvoiceStatus.paid:
        final ref = inv.paidAt ?? inv.updatedAt;
        return LifecycleInfo(
          stage: LifecycleStage.paid,
          daysInStage: today.difference(_date(ref)).inDays,
          lastActionAt: ref,
          lastActionLabel: 'Paid in full',
          nextActionHint: null,
        );

      case InvoiceStatus.partiallyPaid:
        final ref = _laterOf(inv.updatedAt, lastReminderAt);
        return LifecycleInfo(
          stage: LifecycleStage.partiallyPaid,
          daysInStage: today.difference(_date(ref)).inDays.abs(),
          lastActionAt: ref,
          lastActionLabel: 'Partial payment received',
          nextActionHint: 'Record remaining balance',
        );

      case InvoiceStatus.overdue:
        final dueDay = inv.dueDate != null ? _date(inv.dueDate!) : today;
        final overdueDays = today.difference(dueDay).inDays;
        final ref = _laterOf(inv.updatedAt, lastReminderAt);
        return LifecycleInfo(
          stage: LifecycleStage.overdue,
          daysInStage: overdueDays.clamp(0, 9999),
          lastActionAt: ref,
          lastActionLabel: lastReminderAt != null ? 'Reminder sent' : null,
          nextActionHint: 'Collect payment now',
        );

      case InvoiceStatus.sent:
        // If past due date, treat as overdue even when DB status is still 'sent'
        if (inv.dueDate != null && inv.dueDate!.isBefore(today)) {
          final overdueDays = today.difference(_date(inv.dueDate!)).inDays;
          return LifecycleInfo(
            stage: LifecycleStage.overdue,
            daysInStage: overdueDays.clamp(0, 9999),
            lastActionAt: lastReminderAt ?? inv.updatedAt,
            lastActionLabel:
                lastReminderAt != null ? 'Reminder sent' : 'Invoice sent',
            nextActionHint: 'Collect payment now',
          );
        }
        // Reminder was sent → reminded stage
        if (lastReminderAt != null) {
          final ref = _laterOf(inv.updatedAt, lastReminderAt);
          return LifecycleInfo(
            stage: LifecycleStage.reminded,
            daysInStage: today.difference(_date(ref)).inDays.abs(),
            lastActionAt: ref,
            lastActionLabel: 'Reminder sent',
            nextActionHint: 'Follow up if no reply in 3 days',
          );
        }
        // Plain sent — no reminder yet
        final sentRef = _laterOf(inv.updatedAt, inv.reminderSentAt);
        if (inv.reminderSentAt != null) {
          return LifecycleInfo(
            stage: LifecycleStage.reminded,
            daysInStage: today.difference(_date(sentRef)).inDays.abs(),
            lastActionAt: sentRef,
            lastActionLabel: 'Reminder sent',
            nextActionHint: 'Follow up if no reply',
          );
        }
        return LifecycleInfo(
          stage: LifecycleStage.sent,
          daysInStage: today.difference(_date(sentRef)).inDays.abs(),
          lastActionAt: sentRef,
          lastActionLabel: 'Invoice sent',
          nextActionHint:
              today.difference(_date(sentRef)).inDays > 7
                  ? 'Send a reminder'
                  : null,
        );

      case InvoiceStatus.draft:
        return LifecycleInfo(
          stage: LifecycleStage.draft,
          daysInStage: today.difference(_date(inv.updatedAt)).inDays.abs(),
          lastActionAt: inv.updatedAt,
          lastActionLabel: 'Draft created',
          nextActionHint: 'Send invoice to customer',
        );

      case InvoiceStatus.cancelled:
        return LifecycleInfo(
          stage: LifecycleStage.draft,
          daysInStage: today.difference(_date(inv.updatedAt)).inDays.abs(),
          lastActionAt: inv.updatedAt,
          lastActionLabel: 'Cancelled',
          nextActionHint: null,
        );

      case InvoiceStatus.pendingNumber:
        return LifecycleInfo(
          stage: LifecycleStage.draft,
          daysInStage: today.difference(_date(inv.updatedAt)).inDays.abs(),
          lastActionAt: inv.updatedAt,
          lastActionLabel: 'Awaiting number',
          nextActionHint: 'Sync with primary device to assign a number',
        );
    }
  }

  // ── Credit / Due ──────────────────────────────────────────────────────────
  //
  // Stage machine:
  //   active → reminded → partial → cleared
  //              ↓ if past dueDate
  //            overdue

  static LifecycleInfo forCredit(
    Credit c, {
    DateTime? lastReminderAt,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (c.isCleared) {
      final ref = c.clearedDate ?? c.updatedAt ?? c.createdAt;
      return LifecycleInfo(
        stage: LifecycleStage.cleared,
        daysInStage: today.difference(_date(ref)).inDays.abs(),
        lastActionAt: ref,
        lastActionLabel: 'Cleared',
        nextActionHint: null,
      );
    }

    if (c.isOverdue ||
        (c.dueDate != null && c.dueDate!.isBefore(today))) {
      final dueDay = c.dueDate != null ? _date(c.dueDate!) : today;
      final overdueDays = today.difference(dueDay).inDays;
      return LifecycleInfo(
        stage: LifecycleStage.overdue,
        daysInStage: overdueDays.clamp(0, 9999),
        lastActionAt: lastReminderAt ?? c.updatedAt,
        lastActionLabel: lastReminderAt != null ? 'Reminder sent' : null,
        nextActionHint: c.isGiven ? 'Collect outstanding amount' : 'Pay outstanding amount',
      );
    }

    if (c.paidAmount > 0) {
      final ref = _laterOf(c.updatedAt, lastReminderAt) ?? c.createdAt;
      return LifecycleInfo(
        stage: LifecycleStage.partiallyPaid,
        daysInStage: today.difference(_date(ref)).inDays.abs(),
        lastActionAt: ref,
        lastActionLabel: 'Partial payment received',
        nextActionHint: 'Record remaining amount',
      );
    }

    final reminderRef = lastReminderAt;
    if (reminderRef != null) {
      return LifecycleInfo(
        stage: LifecycleStage.reminded,
        daysInStage: today.difference(_date(reminderRef)).inDays.abs(),
        lastActionAt: reminderRef,
        lastActionLabel: 'Reminder sent',
        nextActionHint: 'Follow up',
      );
    }

    final ref = c.updatedAt ?? c.createdAt;
    return LifecycleInfo(
      stage: LifecycleStage.active,
      daysInStage: today.difference(_date(ref)).inDays.abs(),
      lastActionAt: ref,
      lastActionLabel: null,
      nextActionHint: c.dueDate != null ? 'Due ${_formatDate(c.dueDate!)}' : null,
    );
  }

  // ── Loan ──────────────────────────────────────────────────────────────────
  //
  // Stage machine:
  //   active → paying (paidEmis > 0) → overdue → cleared

  static LifecycleInfo forLoan(Loan l) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (l.isCleared) {
      final ref = l.clearedDate ?? l.updatedAt ?? l.loanDate;
      return LifecycleInfo(
        stage: LifecycleStage.cleared,
        daysInStage: today.difference(_date(ref)).inDays.abs(),
        lastActionAt: ref,
        lastActionLabel: 'Loan cleared',
        nextActionHint: null,
      );
    }

    if (l.isOverdue ||
        (l.nextEmiDate != null && l.nextEmiDate!.isBefore(today))) {
      final dueDay = l.nextEmiDate ?? l.dueDate;
      final overdueDays = dueDay != null
          ? today.difference(_date(dueDay)).inDays.clamp(0, 9999)
          : 0;
      return LifecycleInfo(
        stage: LifecycleStage.overdue,
        daysInStage: overdueDays,
        lastActionAt: l.updatedAt,
        lastActionLabel: null,
        nextActionHint: l.isLent ? 'Collect EMI' : 'Pay EMI',
      );
    }

    if (l.paidEmis > 0) {
      final ref = l.updatedAt ?? l.loanDate;
      return LifecycleInfo(
        stage: LifecycleStage.paying,
        daysInStage: today.difference(_date(ref)).inDays.abs(),
        lastActionAt: ref,
        lastActionLabel: '${l.paidEmis} EMI${l.paidEmis > 1 ? 's' : ''} paid',
        nextActionHint: l.nextEmiDate != null
            ? 'Next EMI ${_formatDate(l.nextEmiDate!)}'
            : null,
      );
    }

    final ref = l.updatedAt ?? l.loanDate;
    return LifecycleInfo(
      stage: LifecycleStage.active,
      daysInStage: today.difference(_date(ref)).inDays.abs(),
      lastActionAt: ref,
      lastActionLabel: null,
      nextActionHint: l.nextEmiDate != null
          ? 'First EMI ${_formatDate(l.nextEmiDate!)}'
          : null,
    );
  }

  // ── ScheduledPayment / Bill ───────────────────────────────────────────────
  //
  // Stage machine:
  //   active → upcoming (≤7 days) → overdue → paid

  static LifecycleInfo forBill(ScheduledPayment p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = _date(p.nextDate);
    final diff = next.difference(today).inDays; // negative = overdue

    if (!p.isActive) {
      return LifecycleInfo(
        stage: LifecycleStage.cleared,
        daysInStage: 0,
        lastActionAt: p.lastPaidDate,
        lastActionLabel: 'Inactive',
        nextActionHint: null,
      );
    }

    if (diff < 0) {
      return LifecycleInfo(
        stage: LifecycleStage.overdue,
        daysInStage: (-diff).clamp(0, 9999),
        lastActionAt: p.lastPaidDate,
        lastActionLabel:
            p.lastPaidDate != null ? 'Last paid ${_formatDate(p.lastPaidDate!)}' : null,
        nextActionHint: 'Pay now',
      );
    }

    if (diff <= 7) {
      return LifecycleInfo(
        stage: LifecycleStage.active,
        daysInStage: diff,
        lastActionAt: p.lastPaidDate,
        lastActionLabel:
            p.lastPaidDate != null ? 'Last paid ${_formatDate(p.lastPaidDate!)}' : null,
        nextActionHint: diff == 0 ? 'Due today' : 'Due in $diff day${diff == 1 ? '' : 's'}',
      );
    }

    return LifecycleInfo(
      stage: LifecycleStage.active,
      daysInStage: diff,
      lastActionAt: p.lastPaidDate,
      lastActionLabel: null,
      nextActionHint: 'Due ${_formatDate(p.nextDate)}',
    );
  }

  // ── Booking ───────────────────────────────────────────────────────────────
  //
  // Stage machine:
  //   pending → confirmed → [service date] → completed / noShow

  static LifecycleInfo forBooking(Booking b) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ref = b.updatedAt ?? b.createdAt ?? b.startDatetime;

    switch (b.status) {
      case BookingStatus.completed:
        return LifecycleInfo(
          stage: LifecycleStage.paid,
          daysInStage: today.difference(_date(ref)).inDays.abs(),
          lastActionAt: ref,
          lastActionLabel: 'Service completed',
          nextActionHint: null,
        );

      case BookingStatus.cancelled:
      case BookingStatus.noShow:
        return LifecycleInfo(
          stage: LifecycleStage.cleared,
          daysInStage: today.difference(_date(ref)).inDays.abs(),
          lastActionAt: ref,
          lastActionLabel: b.status == BookingStatus.cancelled
              ? 'Cancelled'
              : 'No-show',
          nextActionHint: null,
        );

      case BookingStatus.confirmed:
        final confirmRef = b.confirmedAt ?? ref;
        return LifecycleInfo(
          stage: LifecycleStage.sent,
          daysInStage: today.difference(_date(confirmRef)).inDays.abs(),
          lastActionAt: confirmRef,
          lastActionLabel: 'Confirmed',
          nextActionHint: 'Service on ${_formatDate(b.startDatetime)}',
        );

      case BookingStatus.pending:
        return LifecycleInfo(
          stage: LifecycleStage.active,
          daysInStage: today.difference(_date(ref)).inDays.abs(),
          lastActionAt: b.reminderSentAt ?? ref,
          lastActionLabel: b.reminderSentAt != null ? 'Reminder sent' : null,
          nextActionHint: 'Confirm booking',
        );
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Strips time component from [dt]. Returns today if [dt] is null.
  static DateTime _date(DateTime? dt) {
    if (dt == null) return DateTime.now();
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Returns whichever date is later (non-null wins over null).
  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }
}
