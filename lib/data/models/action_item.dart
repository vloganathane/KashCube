// ---------------------------------------------------------------------------
// ActionItem — unified "things that need attention" model
// ---------------------------------------------------------------------------
// Aggregates overdue/upcoming invoices, dues (credits), bills, and loan EMIs
// into a single sortable list for the Action Center screen.
// 100% computed in-memory from local DB data — no network calls.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

/// Source type of the action item.
enum ActionItemType {
  invoice,
  dues,   // credit (udhar)
  bill,   // scheduled payment
  loanEmi,
}

/// Whether this is money the user should collect or pay.
enum ActionItemDirection {
  toCollect,
  toPay,
}

/// Urgency bucket used for grouping.
enum ActionUrgency {
  overdue,
  dueToday,
  dueThisWeek,
  dueThisMonth,
}

// ── ActionItem ────────────────────────────────────────────────────────────────

/// A single entry in the Action Center, derived from one of the 4 source types.
class ActionItem {
  const ActionItem({
    required this.type,
    required this.direction,
    required this.urgency,
    required this.daysOverdue,
    required this.title,
    this.subtitle,
    required this.amount,
    this.dueDate,
    required this.sourceId,
  });

  final ActionItemType type;
  final ActionItemDirection direction;
  final ActionUrgency urgency;

  /// Positive = days past due. Negative = days until due.
  final int daysOverdue;

  /// Primary label — party name or bill name.
  final String title;

  /// Secondary label — e.g. "Invoice #0042" or "Loan EMI".
  final String? subtitle;

  final double amount;
  final DateTime? dueDate;

  /// Row id in source table.
  final int sourceId;

  // ── Sort score — higher = shown first ──────────────────────────────────────
  //
  //  overdue > 7 d  → 100 + daysOverdue
  //  overdue 1-7 d  →  50 + daysOverdue
  //  due today      →  40
  //  due in 1-3 d   →  30
  //  due in 4-7 d   →  20
  //  due this month →  10
  //  + log₁₀(amount) × 3  (breaks ties within bucket)

  int get sortScore {
    double base;
    if (urgency == ActionUrgency.overdue) {
      base = daysOverdue > 7 ? 100 + daysOverdue.toDouble()
                             :  50 + daysOverdue.toDouble();
    } else if (urgency == ActionUrgency.dueToday) {
      base = 40;
    } else if (urgency == ActionUrgency.dueThisWeek) {
      final daysLeft = -daysOverdue;
      base = daysLeft <= 3 ? 30 : 20;
    } else {
      base = 10;
    }
    final amountBonus = amount > 0
        ? math.log(amount) / math.ln10 * 3.0
        : 0.0;
    return (base + amountBonus).round();
  }

  @override
  String toString() =>
      'ActionItem($type, $direction, $urgency, days=$daysOverdue, '
      'title=$title, amount=$amount, id=$sourceId)';
}
