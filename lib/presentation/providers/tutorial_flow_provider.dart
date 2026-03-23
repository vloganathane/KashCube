import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every discrete step in a cross-screen tutorial flow.
///
/// Naming convention: `<flowName>_<stepName>`.
/// The `none` value means no flow is currently active.
enum TutorialFlowStep {
  none,

  // ── Add Transaction flow ──────────────────────────────────────────────
  /// TransactionsScreen — spotlight the FAB to prompt the first tap.
  addTxFab,

  /// AddEditTransactionScreen — spotlight the Amount field.
  addTxAmount,

  /// AddEditTransactionScreen — spotlight the Category picker.
  addTxCategory,

  /// AddEditTransactionScreen — spotlight the Save / Add Transaction button.
  addTxSave,

  /// TransactionsScreen — spotlight the newly created transaction card.
  addTxResult,

  // ── New Credit flow ───────────────────────────────────────────────────
  newCreditFab,
  newCreditParty,
  newCreditAmount,
  newCreditSave,
  newCreditResult,
}

extension TutorialFlowStepX on TutorialFlowStep {
  /// True while any Add Transaction flow step is active.
  bool get isAddTxFlow => name.startsWith('addTx');

  /// True while any New Credit flow step is active.
  bool get isNewCreditFlow => name.startsWith('newCredit');

  /// True while any flow is active (i.e. not [TutorialFlowStep.none]).
  bool get isActive => this != TutorialFlowStep.none;
}

/// Cross-screen state machine that coordinates multi-step tutorial flows.
///
/// Only one flow can be active at a time. Starting a new flow implicitly
/// replaces any in-progress one.
class TutorialFlowNotifier extends StateNotifier<TutorialFlowStep> {
  TutorialFlowNotifier() : super(TutorialFlowStep.none);

  /// Move to the next step.
  void advance(TutorialFlowStep next) => state = next;

  /// User cancelled mid-flow (back gesture, skip, or navigation away).
  void abandon() => state = TutorialFlowStep.none;

  /// Flow completed successfully.
  void finish() => state = TutorialFlowStep.none;
}

final tutorialFlowProvider =
    StateNotifierProvider<TutorialFlowNotifier, TutorialFlowStep>(
  (_) => TutorialFlowNotifier(),
);
