// ---------------------------------------------------------------------------
// Lifecycle Layer — LC1
// ---------------------------------------------------------------------------
// LifecycleStage enum and LifecycleInfo value class.
// Consumed by LifecycleClassifier (LC2) and LifecycleTag widget (LC3).
//
// Pure Dart — no Flutter, no DB access. Safe to import anywhere.
// ---------------------------------------------------------------------------

/// The computed stage of a financial item in its lifecycle.
///
/// Stage machines:
/// * Invoice:  draft → sent → reminded → partiallyPaid → paid
///                         overdue (any stage past dueDate)
/// * Credit:   active → reminded → partial → cleared
///                         overdue (past dueDate)
/// * Loan:     active → paying (paidEmis > 0) → overdue → cleared
/// * Bill:     active → upcoming (within 7d) → overdue → paid
/// * Booking:  pending → confirmed → completed / noShow
enum LifecycleStage {
  draft,
  active,
  sent,
  reminded,
  partiallyPaid,
  overdue,
  paying,
  cleared,
  paid,
}

extension LifecycleStageExt on LifecycleStage {
  /// Short display label shown inside [LifecycleTag].
  String get label => switch (this) {
    LifecycleStage.draft => 'DRAFT',
    LifecycleStage.active => 'ACTIVE',
    LifecycleStage.sent => 'SENT',
    LifecycleStage.reminded => 'REMINDED',
    LifecycleStage.partiallyPaid => 'PARTIAL',
    LifecycleStage.overdue => 'OVERDUE',
    LifecycleStage.paying => 'PAYING',
    LifecycleStage.cleared => 'CLEARED',
    LifecycleStage.paid => 'PAID',
  };

  /// Terminal stages — item no longer needs attention.
  bool get isTerminal =>
      this == LifecycleStage.paid || this == LifecycleStage.cleared;

  /// Whether this stage indicates the item needs immediate action.
  bool get isUrgent => this == LifecycleStage.overdue;

  /// Whether this stage indicates a reminder has already been sent.
  bool get wasReminded => this == LifecycleStage.reminded;
}

// ---------------------------------------------------------------------------
// LifecycleInfo
// ---------------------------------------------------------------------------

/// Computed lifecycle metadata for a single financial item.
///
/// Created by [LifecycleClassifier] — never store in DB (computed on the fly).
class LifecycleInfo {
  const LifecycleInfo({
    required this.stage,
    required this.daysInStage,
    this.lastActionAt,
    this.lastActionLabel,
    this.nextActionHint,
  });

  /// Current stage of the item.
  final LifecycleStage stage;

  /// Days since the last stage transition (>= 0).
  /// Reference: `max(updatedAt, lastReminderAt)` where available.
  final int daysInStage;

  /// When the last notable action occurred (reminder sent, payment received).
  final DateTime? lastActionAt;

  /// Human-readable label for the last action, e.g. "Reminded via WhatsApp".
  final String? lastActionLabel;

  /// Suggested next action, e.g. "Send a reminder" / "Record payment".
  final String? nextActionHint;

  /// Whether this item is considered "stale" (no action in N days).
  bool isStale({int threshold = 7}) => daysInStage > threshold;

  @override
  String toString() =>
      'LifecycleInfo(stage: ${stage.name}, daysInStage: $daysInStage)';
}
