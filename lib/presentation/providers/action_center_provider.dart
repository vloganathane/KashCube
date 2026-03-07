// ---------------------------------------------------------------------------
// Action Center Provider
// ---------------------------------------------------------------------------
// Aggregates overdue/upcoming invoices, dues (credits), bills and loan EMIs
// from every local source into a unified, priority-sorted List<ActionItem>.
//
// Uses Option A: live computation — no stored `isOverdue` flags are used.
// All overdue/urgency judgements are made against DateTime.now() at build time.
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/action_item.dart';
import '../../data/models/credit.dart';
import '../../data/models/invoice.dart';
import '../../data/models/loan.dart';
import '../../data/models/scheduled_payment.dart';
import '../../core/utils/lifecycle_classifier.dart';
import 'business_flow_provider.dart';
import 'credit_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'scheduled_payment_provider.dart';

// ── Helper: urgency bucket ───────────────────────────────────────────────────

ActionUrgency _urgencyFor(DateTime? dueDate) {
  if (dueDate == null) return ActionUrgency.dueThisMonth;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final diff = due.difference(today).inDays; // negative = overdue
  if (diff < 0) return ActionUrgency.overdue;
  if (diff == 0) return ActionUrgency.dueToday;
  if (diff <= 7) return ActionUrgency.dueThisWeek;
  return ActionUrgency.dueThisMonth;
}

int _daysOverdue(DateTime? dueDate) {
  if (dueDate == null) return 0;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return today.difference(due).inDays; // positive = overdue, negative = future
}

// ── Main provider ────────────────────────────────────────────────────────────

/// A sorted list of action items across all financial sources.
///
/// Items are sorted from most urgent (highest sortScore) first.
/// Only items due within the next 30 days (or already overdue) are included.
final actionCenterProvider = Provider<AsyncValue<List<ActionItem>>>((ref) {
  final creditsAsync   = ref.watch(activeCreditsProvider);
  final loansAsync     = ref.watch(activeLoansProvider);
  final overdueLoans   = ref.watch(overdueLoansProvider);
  final billsAsync     = ref.watch(upcomingScheduledProvider);
  final overdueBills   = ref.watch(overdueScheduledProvider);
  final invoicesAsync  = ref.watch(invoicesProvider);
  final leakingAsync   = ref.watch(leakingChainsProvider);

  // Wait for all sources
  if (creditsAsync.isLoading ||
      loansAsync.isLoading ||
      overdueLoans.isLoading ||
      billsAsync.isLoading ||
      overdueBills.isLoading ||
      invoicesAsync.isLoading ||
      leakingAsync.isLoading) {
    return const AsyncLoading();
  }

  if (creditsAsync.hasError) return AsyncError(creditsAsync.error!, creditsAsync.stackTrace!);
  if (loansAsync.hasError)   return AsyncError(loansAsync.error!, loansAsync.stackTrace!);
  if (invoicesAsync.hasError) return AsyncError(invoicesAsync.error!, invoicesAsync.stackTrace!);

  final items = <ActionItem>[];
  final now = DateTime.now();
  final cutoff = now.add(const Duration(days: 30));

  // ── Credits / Dues ─────────────────────────────────────────────────────────
  final credits = creditsAsync.valueOrNull ?? [];
  for (final c in credits) {
    if (c.isCleared) continue;
    final due = c.dueDate;
    if (due != null && due.isAfter(cutoff)) continue; // too far away
    final urgency = _urgencyFor(due);
    final overdueDays = _daysOverdue(due);
    items.add(ActionItem(
      type: ActionItemType.dues,
      direction: c.direction == CreditDirection.given
          ? ActionItemDirection.toCollect
          : ActionItemDirection.toPay,
      urgency: urgency,
      daysOverdue: overdueDays,
      title: c.customerName,
      subtitle: 'Due',
      amount: c.pendingAmount,
      dueDate: c.dueDate,
      sourceId: c.id ?? 0,
      lifecycleInfo: LifecycleClassifier.forCredit(c),
    ));
  }

  // ── Loans / EMIs ────────────────────────────────────────────────────────────
  // Combine active (upcoming EMIs) + explicit overdue loans — deduplicate by id
  final loanMap = <int, Loan>{};
  for (final l in [...loansAsync.valueOrNull ?? [], ...overdueLoans.valueOrNull ?? []]) {
    if (l.id != null) loanMap[l.id!] = l;
  }
  final loans = loanMap.values.toList();

  for (final l in loans) {
    // Use nextEmiDate if available, else dueDate
    final due = l.nextEmiDate ?? l.dueDate;
    if (due != null && due.isAfter(cutoff)) continue;
    final urgency = _urgencyFor(due);
    final overdueDays = _daysOverdue(due);
    items.add(ActionItem(
      type: ActionItemType.loanEmi,
      direction: l.isLent
          ? ActionItemDirection.toCollect
          : ActionItemDirection.toPay,
      urgency: urgency,
      daysOverdue: overdueDays,
      title: l.lenderName,
      subtitle: 'Loan EMI',
      amount: l.pendingAmount,
      dueDate: due,
      sourceId: l.id ?? 0,
      lifecycleInfo: LifecycleClassifier.forLoan(l),
    ));
  }

  // ── Scheduled Bills ─────────────────────────────────────────────────────────
  // Deduplicate by id
  final billMap = <int, ScheduledPayment>{};
  for (final b in [...billsAsync.valueOrNull ?? [], ...overdueBills.valueOrNull ?? []]) {
    if (b.id != null) billMap[b.id!] = b;
  }
  final bills = billMap.values.toList();

  for (final b in bills) {
    final due = b.nextDate;
    if (due.isAfter(cutoff)) continue;
    final urgency = _urgencyFor(due);
    final overdueDays = _daysOverdue(due);
    items.add(ActionItem(
      type: ActionItemType.bill,
      direction: ActionItemDirection.toPay,
      urgency: urgency,
      daysOverdue: overdueDays,
      title: b.name,
      subtitle: b.partyName,
      amount: b.amount,
      dueDate: due,
      sourceId: b.id ?? 0,
      lifecycleInfo: LifecycleClassifier.forBill(b),
    ));
  }

  // ── Invoices ────────────────────────────────────────────────────────────────
  // Only include non-draft, unpaid/partially-paid invoices
  final invoices = invoicesAsync.valueOrNull ?? [];
  for (final inv in invoices) {
    if (inv.status == InvoiceStatus.draft) continue;
    if (inv.status == InvoiceStatus.paid) continue;
    final due = inv.dueDate;
    if (due != null && due.isAfter(cutoff)) continue;
    final urgency = _urgencyFor(due);
    final overdueDays = _daysOverdue(due);
    items.add(ActionItem(
      type: ActionItemType.invoice,
      direction: ActionItemDirection.toCollect,
      urgency: urgency,
      daysOverdue: overdueDays,
      title: inv.customerName,
      subtitle: 'Invoice ${inv.invoiceNo}',
      amount: inv.balanceDue,
      dueDate: inv.dueDate,
      sourceId: inv.id ?? 0,
      lifecycleInfo: LifecycleClassifier.forInvoice(
        inv,
        lastReminderAt: inv.reminderSentAt,
      ),
    ));
  }

  // ── Leaking Chains (E5) ────────────────────────────────────────────────────
  // Accepted quotes / dispatched challans / confirmed bookings with no invoice.
  final leaking = leakingAsync.valueOrNull ?? [];
  for (final chain in leaking) {
    final days = chain.daysSinceOrigin;
    final urgency = days >= 4
        ? ActionUrgency.overdue
        : days == 0
            ? ActionUrgency.dueToday
            : ActionUrgency.dueThisWeek;
    items.add(ActionItem(
      type: ActionItemType.leakingChain,
      direction: ActionItemDirection.toCollect,
      urgency: urgency,
      daysOverdue: days,
      title: chain.partyName,
      subtitle: chain.chainTitle,
      amount: chain.totalValue,
      dueDate: null,
      sourceId: chain.partyId, // used to navigate to Party360Screen
      lifecycleInfo: null,
    ));
  }

  // Sort highest sortScore first
  items.sort((a, b) => b.sortScore.compareTo(a.sortScore));

  return AsyncData(items);
});

// ── Derived providers ─────────────────────────────────────────────────────────

/// Count of overdue items — used for badge on home screen.
final actionCenterOverdueCountProvider = Provider<int>((ref) {
  return ref
      .watch(actionCenterProvider)
      .valueOrNull
      ?.where((i) => i.urgency == ActionUrgency.overdue)
      .length ?? 0;
});

/// Total amount to collect (overdue + this week).
final actionCenterToCollectProvider = Provider<double>((ref) {
  final items = ref.watch(actionCenterProvider).valueOrNull ?? [];
  return items
      .where((i) => i.direction == ActionItemDirection.toCollect)
      .fold(0.0, (sum, i) => sum + i.amount);
});

/// Total amount to pay (overdue + this week).
final actionCenterToPayProvider = Provider<double>((ref) {
  final items = ref.watch(actionCenterProvider).valueOrNull ?? [];
  return items
      .where((i) => i.direction == ActionItemDirection.toPay)
      .fold(0.0, (sum, i) => sum + i.amount);
});
