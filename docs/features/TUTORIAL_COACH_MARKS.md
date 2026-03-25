# Tutorial Coach Marks — Spec

**Status:** Partially implemented — orientation tour ✅ · flow-following ✅ (Transactions · Credits · Invoices)  
**Package:** [`tutorial_coach_mark`](https://pub.dev/packages/tutorial_coach_mark)  
**Last updated:** 25 March 2026

---

## What's Already Shipped

| Deliverable | Status |
|-------------|--------|
| `tutorial_coach_mark` in `pubspec.yaml` | ✅ v1.3.3 |
| `TutorialMixin` in `lib/core/utils/tutorial_mixin.dart` | ✅ |
| Tutorial keys in `SettingsKeys` | ✅ |
| `TransactionsScreen` orientation tour (FAB · Search · Filter) | ✅ |
| `?` adaptive dropdown on TransactionsScreen & CreditsScreen | ✅ |
| `heroTag` collision fix across all FABs | ✅ |
| Flow-following orchestrator | ✅ `TutorialFlowNotifier` + `TutorialFlowStep` |
| Add Transaction guided flow | ✅ FAB → form → result card |
| New Credit guided flow | ✅ FAB → form → result card |
| `CreditsScreen` orientation tour (FAB · Filter chips) | ✅ |
| `InvoicesScreen` orientation tour (FAB · Search · Filter) | ✅ |
| New Invoice guided flow (FAB → `QuoteBuilderScreen` → result) | ✅ |
| `?` help button on `QuoteBuilderScreen` (contextual form guide) | ✅ |
| Per-feature flows (Bookings, Catalog…) | ⬜ |
| Orientation tours for Home, Reports, Contacts | ⬜ |
| "Reset all tutorials" in Settings → About | ⬜ |

---

## Overview

Kash Cube uses **two complementary coach mark strategies**:

1. **Orientation tours** — spotlight persistent chrome (FABs, nav icons, filter buttons) on first screen visit. One screen, one `TutorialCoachMark` instance. Already implemented on TransactionsScreen.
2. **Flow-following tutorials** — walk the user through a multi-screen action flow (e.g. Tap FAB → fill form → save). Each screen in the flow owns its own `TutorialCoachMark` instance, coordinated by a shared `TutorialFlowNotifier` state machine.

Both strategies follow the **"guided first action"** pattern — the tutorial walks the user through *creating their first record*, so the tutorial itself produces the data needed to make the screen useful. This is strictly better than a passive tour of an empty screen.

---

## Core Principles

1. **Do, don't describe.** Guide the user to take an action, not just look at the UI.
2. **Data as a side effect.** The first-action guide creates data, solving the chicken-and-egg problem.
3. **Never trap the user.** "Skip for now" is always visible on every step.
4. **Once auto, always replayable.** Auto-show fires once. A `?` button replays on demand forever.
5. **Only target persistent UI.** Never spotlight a widget that may not be in the tree (empty-state cards, async list items, conditionally rendered sections).
6. **Defer to data, not time.** Don't show a tour of a list screen until the list has at least one item.

---

## Tutorial Structure — Two Phases

### Phase 1 — "Do it" (Guided First Action)
A multi-step coach mark that walks through creating the first record of a feature.  
- Fires on first launch of the feature screen (or first app open for Home).  
- Ends when the user saves a record.  
- Marks `tutorial_<feature>_guided_done = true` in settings on completion OR skip.

### Phase 2 — "Explore it" (Post-Creation Tour)
A shorter 2–3 step tour of the result after the record is created.  
- Immediately follows Phase 1 completion (or fires on subsequent opens if Phase 1 was skipped).  
- Targets the newly created card: "Tap to edit · Swipe to delete · Long-press for quick actions."  
- Marks `tutorial_<feature>_tour_done = true`.

---

## Per-Feature First Action Map

| Feature | Phase 1 — Guided Action | Phase 2 — Post-Creation | Trigger Condition |
|---------|------------------------|-------------------------|-------------------|
| **Transactions** | Spotlight FAB → guide through Add Transaction form (amount → category → save) | Spotlight the created card: tap/swipe/edit | First app open after wizard |
| **Ledger** | Spotlight FAB → guide "Give Credit" to a party (name → amount → due date → save) | Spotlight the person row: tap for Party 360 / add settlement | First open of Ledger tab |
| **Invoices** | Spotlight + → guide creating first invoice (customer → one line item → save) | Spotlight invoice card: Share PDF / Mark Paid / Send Reminder | First open of Invoices screen |
| **Bookings** | Spotlight + → guide creating first booking (customer → service → date/time → save) | Spotlight booking card: Mark Complete / Reschedule | First open of Bookings screen |
| **Reports** | No Phase 1 (no record to create) | Spotlight filter icon + export button | After first transaction exists |
| **GST / GSTR-1** | No Phase 1 | Spotlight "auto-populated from invoices" area + Export JSON button | After first invoice exists |
| **Item Catalog** | Spotlight + → guide adding first item (name → HSN → price → GST rate → save) | Spotlight the item row | First open of Item Catalog |

---

## Settings Keys

All flags stored in the existing `settings` table (key-value). No schema change required.

| Key | Type | Meaning |
|-----|------|---------|
| `tutorial_tx_guided_done` | bool | Phase 1 for Transactions shown/skipped |
| `tutorial_tx_tour_done` | bool | Phase 2 for Transactions shown/skipped |
| `tutorial_ledger_guided_done` | bool | Phase 1 for Ledger |
| `tutorial_ledger_tour_done` | bool | Phase 2 for Ledger |
| `tutorial_invoices_guided_done` | bool | Phase 1 for Invoices |
| `tutorial_invoices_tour_done` | bool | Phase 2 for Invoices |
| `tutorial_bookings_guided_done` | bool | Phase 1 for Bookings |
| `tutorial_bookings_tour_done` | bool | Phase 2 for Bookings |
| `tutorial_reports_tour_done` | bool | Tour for Reports |
| `tutorial_gst_tour_done` | bool | Tour for GST screen |
| `tutorial_catalog_guided_done` | bool | Phase 1 for Item Catalog |
| `tutorial_catalog_tour_done` | bool | Phase 2 for Item Catalog |

---

## Architecture

### Two-layer model

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1 — Orientation Tour (TutorialMixin)             │
│  Single screen · static chrome · fires on first visit   │
│  ✅ Implemented                                          │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  Layer 2 — Flow-Following (TutorialFlowNotifier)        │
│  Cross-screen · user action sequence · state machine    │
│  ⬜ To be implemented                                    │
└─────────────────────────────────────────────────────────┘
```

---

### Layer 1 — Orientation Tour

Already built. See `lib/core/utils/tutorial_mixin.dart`.

**Persistence:** done-flag stored as `'true'` string in SQLite `settings` table via `SettingsRepository.set(key, 'true')` (no `setBool` helper — read back with `get(key) == 'true'`).

**Settings provider read pattern:**
```dart
final done = await ref.read(settingsRepositoryProvider).get(tutorialKey) == 'true';
await ref.read(settingsRepositoryProvider).set(tutorialKey, 'true');
```

**`TutorialMixin` API:**
```dart
mixin TutorialMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get tutorialKey;           // e.g. SettingsKeys.tutorialTransactionsDone
  List<TargetFocus> buildTargets(); // spotlights for this screen

  void maybeShowTutorial(); // call from initState — deferred to first frame
  void replayTutorial();    // call from ? AppBar button
}
```

**`GlobalKey` placement — always at State level:**
```dart
class _TransactionsScreenState extends ConsumerState<TransactionsScreen>
    with TutorialMixin<TransactionsScreen> {
  final _fabKey    = GlobalKey();
  final _searchKey = GlobalKey();
  final _filterKey = GlobalKey();

  @override
  String get tutorialKey => SettingsKeys.tutorialTransactionsDone;

  @override
  List<TargetFocus> buildTargets() => [
    TargetFocus(identify: 'fab',    keyTarget: _fabKey,    ...),
    TargetFocus(identify: 'search', keyTarget: _searchKey, ...),
    TargetFocus(identify: 'filter', keyTarget: _filterKey, ...),
  ];

  @override
  void initState() {
    super.initState();
    maybeShowTutorial();
  }
}
```

**Deferred trigger (async data):**
```dart
ref.listen(transactionsProvider, (prev, next) {
  if (prev?.isLoading == true && next.hasValue && (next.value?.isNotEmpty ?? false)) {
    maybeShowTutorial();
  }
});
```

---

### Layer 2 — Flow-Following Tutorial Orchestrator

A single Riverpod `StateNotifier` acts as a cross-screen state machine. Each screen in the flow `ref.listen`s to it and shows its own `TutorialCoachMark` when the active step is theirs.

**Why a separate instance per screen is required:**  
`TutorialCoachMark` binds its overlay to a specific navigator's `OverlayState`. When a new route is pushed, the previous screen's `GlobalKey` targets are unmounted — spotlights become orphaned. A new `TutorialCoachMark` instance must be created for each route boundary.

#### Orchestrator enum & notifier

```dart
// lib/presentation/providers/tutorial_flow_provider.dart

enum TutorialFlowStep {
  none,

  // ── Add Transaction flow ──────────────────────────────────────────────
  addTxFab,       // TransactionsScreen  → spotlight FAB
  addTxAmount,    // AddEditTransaction  → spotlight Amount field
  addTxCategory,  // AddEditTransaction  → spotlight Category picker
  addTxSave,      // AddEditTransaction  → spotlight Add Transaction button
  addTxResult,    // TransactionsScreen  → spotlight the newly created card

  // ── New Credit flow ───────────────────────────────────────────────────
  newCreditFab,
  newCreditParty,
  newCreditAmount,
  newCreditSave,
  newCreditResult,
}

class TutorialFlowNotifier extends StateNotifier<TutorialFlowStep> {
  TutorialFlowNotifier() : super(TutorialFlowStep.none);

  void advance(TutorialFlowStep next) => state = next;
  void abandon() => state = TutorialFlowStep.none;  // skip/back mid-flow
  void finish()  => state = TutorialFlowStep.none;  // successful completion
}

final tutorialFlowProvider =
    StateNotifierProvider<TutorialFlowNotifier, TutorialFlowStep>(
        (_) => TutorialFlowNotifier());
```

#### How a screen participates

```dart
// TransactionsScreen — starts the flow and shows step addTx_fab
@override
void initState() {
  super.initState();
  // Orientation tour (Layer 1) — fires unconditionally on first visit
  maybeShowTutorial();
}

// Separately, listen for the flow orchestrator asking this screen to act
// (called from build via ref.listen)
ref.listen(tutorialFlowProvider, (_, step) {
  if (step == TutorialFlowStep.addTxFab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showFlowMark_addTxFab(); // single TargetFocus on the FAB
    });
  }
  if (step == TutorialFlowStep.addTxResult) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _newestCardKey.currentContext == null) return;
      _showFlowMark_addTxResult();
    });
  }
});
```

```dart
// AddEditTransactionScreen — shows steps addTxAmount → addTxCategory → addTxSave
@override
void initState() {
  super.initState();
  final step = ref.read(tutorialFlowProvider);
  if (step == TutorialFlowStep.addTxAmount) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showFormFlowMark());
  }
}
```

#### Add Transaction flow — step diagram

```
TransactionsScreen                     AddEditTransactionScreen
       │
  [initState or ?-replay]
  orchestrator.advance(addTxFab)
       │
  ── spotlight FAB ──────────────────────────────────
  user taps FAB → route push
  advance(addTxAmount)  ← set BEFORE Navigator.push
       │                                    │
                                  initState sees addTxAmount
                                  ── spotlight Amount field ──
                                  user taps → advance(addTxCategory)
                                  ── spotlight Category ──────
                                  user taps → advance(addTxSave)
                                  ── spotlight Add button ────
                                  user saves → advance(addTxResult)
                                  Navigator.pop()
       │
  route returns, ref.listen fires addTxResult
  ── spotlight newly created card ──
  finish()   →   mark tutorial_tx_flow_done = 'true'
```

#### Cancellation / back-gesture handling

```dart
// In AddEditTransactionScreen PopScope
PopScope(
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) {
      final step = ref.read(tutorialFlowProvider);
      if (step.name.startsWith('addTx')) {
        ref.read(tutorialFlowProvider.notifier).abandon();
        ref.read(settingsRepositoryProvider)
            .set(SettingsKeys.tutorialTxFlowDone, 'true');
      }
    }
  },
  child: ...,
)
```

#### SpeedDial FAB — spotlight the main button, not the mini-buttons

The flow spotlights the main FAB (prompting tap), then lets the SpeedDial open naturally. The SpeedDial's `_openTransaction` callback calls `advance(addTx_amount)` before pushing the form route — the mini-buttons are never targeted directly because they are not in the tree until the dial is open:

```dart
// In SpeedDialFab._openTransaction
void _openTransaction() {
  _toggle(); // close dial
  if (ref.read(tutorialFlowProvider) == TutorialFlowStep.addTxFab) {
    ref.read(tutorialFlowProvider.notifier).advance(TutorialFlowStep.addTxAmount);
  }
  // ... push AddEditTransactionScreen
}
```

---

### Multi-Flow Screen Participation

A screen can participate in multiple flows simultaneously — both as an **entry point** for several different flows, and as a **mid-point** in one flow while being an entry for another. The key constraints are:

1. **Only one flow active at a time.** `TutorialFlowNotifier` is a single `StateNotifier<TutorialFlowStep>`. Starting a new flow implicitly replaces the current one.
2. **Priority ordering for auto-start.** When `initState` checks whether to start a flow automatically, check flows in descending priority order and start the first uncompleted one:

```dart
// TransactionsScreen initState — priority ordering
@override
void initState() {
  super.initState();         // Layer 1 orientation tour
  maybeShowTutorial();
  _maybeStartFlow();         // Layer 2 flow auto-start
}

Future<void> _maybeStartFlow() async {
  final settings = ref.read(settingsRepositoryProvider);
  // Priority 1: Add Transaction flow (most important first action)
  if (await settings.get(SettingsKeys.tutorialTxFlowDone) != 'true') {
    ref.read(tutorialFlowProvider.notifier).advance(TutorialFlowStep.addTxFab);
    return;
  }
  // Priority 2: Import SMS flow (hypothetical future flow)
  // if (await settings.get(SettingsKeys.tutorialImportSmsDone) != 'true') { ... }
}
```

3. **`?` menu as the selection mechanism.** When a screen has multiple flows the user can *manually* replay, the `?` dropdown (see Replay section below) is the natural UI for letting the user pick which guide to run. Each menu item maps to a specific flow start or orientation replay.

4. **Same form, multiple entry flows.** If a form screen (e.g. `AddEditTransactionScreen`) is reachable from two different flows, it just reads `ref.read(tutorialFlowProvider)` and dispatches on the *active step* — it doesn't care which entry path triggered it:

```dart
// AddEditTransactionScreen initState — flow-agnostic dispatch
final step = ref.read(tutorialFlowProvider);
if (step == TutorialFlowStep.addTxAmount) _showAddTxFormMark();
// future: else if (step == TutorialFlowStep.someOtherFlow_amount) ...
```

5. **Sealed classes for scale.** A flat `enum` works cleanly for ≤ 6 flows. Beyond that, migrate to sealed classes to avoid an ever-growing enum and enable exhaustive matching per screen:

```dart
// Scaled alternative — each flow owns its own step type
sealed class TutorialFlowStep {}
final class TxFlowStep extends TutorialFlowStep { final int index; ... }
final class CreditFlowStep extends TutorialFlowStep { final int index; ... }
final class InvoiceFlowStep extends TutorialFlowStep { final int index; ... }

// Screen check becomes readable and compiler-enforced
ref.listen(tutorialFlowProvider, (_, step) {
  if (step is TxFlowStep && step.index == 0) _showFabMark();
  if (step is TxFlowStep && step.index == 4) _showResultMark();
});
```

---

### Settings keys

**Layer 1 — already in `SettingsKeys`:**
```dart
static const tutorialTransactionsDone = 'tutorial_transactions_done';
static const tutorialCreditsDone      = 'tutorial_credits_done';
static const tutorialHomeDone         = 'tutorial_home_done';
static const tutorialReportsDone      = 'tutorial_reports_done';
```

**Layer 2 — to be added when each flow is wired:**
```dart
static const tutorialTxFlowDone     = 'tutorial_tx_flow_done';
static const tutorialCreditFlowDone = 'tutorial_credit_flow_done';
```

---

## Replay — `?` AppBar Action

Every screen that has at least one tutorial gets a `?` action in the AppBar. The action renders **adaptively** based on how many guide items the screen exposes:

| Items | Rendered as | UX |
|-------|-------------|----|
| 1 | `IconButton` | single tap, no extra step |
| 2+ | `PopupMenuButton` | tap opens dropdown list of guides |

This means a screen with only an orientation tour keeps the same single-tap UX as today. A screen with both an orientation tour *and* one or more flows automatically gets a labeled dropdown — no extra code needed at the screen level.

### `TutorialMenuItem` + `buildTutorialAppBarAction()`

Add to `TutorialMixin`:

```dart
// lib/core/utils/tutorial_mixin.dart

class TutorialMenuItem {
  final String label;
  final VoidCallback onTap;
  const TutorialMenuItem({required this.label, required this.onTap});
}

mixin TutorialMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  // ... existing API ...

  /// Override to expose more items. Default: orientation tour only.
  List<TutorialMenuItem> get tutorialMenuItems => [
    TutorialMenuItem(label: 'Replay orientation tour', onTap: replayTutorial),
  ];

  /// Drop into AppBar.actions — renders as IconButton or PopupMenuButton.
  Widget buildTutorialAppBarAction() {
    final items = tutorialMenuItems;
    if (items.length == 1) {
      return IconButton(
        icon: const Icon(Icons.help_outline_rounded),
        tooltip: items.first.label,
        onPressed: items.first.onTap,
      );
    }
    return PopupMenuButton<TutorialMenuItem>(
      icon: const Icon(Icons.help_outline_rounded),
      tooltip: 'Tutorial guides',
      onSelected: (item) => item.onTap(),
      itemBuilder: (_) => items
          .map((item) => PopupMenuItem(value: item, child: Text(item.label)))
          .toList(),
    );
  }
}
```

### Wiring on a screen with multiple guides

```dart
// TransactionsScreen — once flow is wired
@override
List<TutorialMenuItem> get tutorialMenuItems => [
  TutorialMenuItem(label: 'Orientation tour', onTap: replayTutorial),
  TutorialMenuItem(
    label: 'How to add a transaction',
    onTap: () {
      ref.read(settingsRepositoryProvider)
          .set(SettingsKeys.tutorialTxFlowDone, 'false');
      ref.read(tutorialFlowProvider.notifier)
          .advance(TutorialFlowStep.addTxFab);
    },
  ),
];

// AppBar — replace the current hardcoded IconButton
appBar: AppBar(
  actions: [
    buildTutorialAppBarAction(), // ← adaptive: button or dropdown
    ...
  ],
)
```

### Screens that sit mid-flow only (form screens)

Form screens that are reachable *as part of a flow* but have no standalone guide (e.g. `AddEditTransactionScreen`) do **not** need a `?` appbar action. The entry screen's `?` menu resets and restarts the full flow from step 1.

> **Rule:** The `?` action lives on **entry screens** (where the flow can be started/replayed) and **result screens** (where the post-creation tour runs). Intermediate form screens omit it unless the form is complex enough to warrant in-context help (see below).

---

## `?` Button on Complex Form Screens

For complex forms (many required fields, non-obvious structure), a `?` help button in the AppBar restarts the contextual spotlight guide from the most relevant step — not from scratch.

### When to add

| Condition | Quick `?` | Detail `?` |
|---|:---:|:---:|
| New record, 4+ non-obvious fields, accessed via guided flow | ✅ | ✅ |
| Edit mode | ❌ | ✅ (field ref still useful) |
| Simple 2–3 field sheet/dialog | ❌ | ❌ |
| Delivery Challan / Credit Note / Debit Note | ❌ | ❌ niche/expert |

Currently applies to: `QuoteBuilderScreen` (Quick mode ✅) · `AddEditTransactionScreen` (Quick ✅ · Detail ⬜).

### Contextual restart pattern (`_restartFormTutorial`)

Instead of blindly replaying from step 1, inspect what the user has filled and point to the **next thing they need to do**:

```dart
void _restartFormTutorial() {
  if (_customerCtrl.text.trim().isEmpty) {
    // Not in a flow — kick one off at the customer step
    if (!ref.read(tutorialFlowProvider).isNewInvoiceFlow) {
      ref.read(tutorialFlowProvider.notifier)
          .advance(TutorialFlowStep.newInvoiceCustomer);
    } else {
      _showCustomerFieldMark(); // already in flow, just re-show the mark
    }
  } else if (_items.every((i) => i.itemName.trim().isEmpty && i.unitPrice == 0)) {
    ref.read(tutorialFlowProvider.notifier)
        .advance(TutorialFlowStep.newInvoiceLineItem);
  } else {
    ref.read(tutorialFlowProvider.notifier)
        .advance(TutorialFlowStep.newInvoiceSave);
  }
}
```

**UX result:** Tapping `?` at any point in the form takes the user to the *next* incomplete step, not the beginning.

---

## Two-Mode Form Guides: Quick + Detail

### Concept

Every complex form `?` button offers two complementary guide modes:

| Mode | Purpose | Steps | Flow-connected? | Stateful (done flag)? |
|------|---------|:-----:|:--------------:|:---------------------:|
| **Quick** | Get the user to complete one real action | 3–5 | ✅ `TutorialFlowNotifier` | ✅ Yes — fires once |
| **Detail** | Field-by-field reference / help manual | All fields | ❌ Standalone | ❌ No — always replayable |

**Key distinction:** Quick mode is onboarding. Detail mode is a help manual embedded in the UI — reference material users can reopen any time they're unsure about a specific field.

### `?` dropdown shape (new record, complex form)

```dart
// ? PopupMenuButton on AddEditTransactionScreen (new transaction only)
[
  PopupMenuItem(label: 'Quick guide'),     // 3–5 steps, flow-integrated
  PopupMenuItem(label: 'Field reference'), // all fields, always replayable
]
```

### Implementation pattern — `_showDetailModeMark()`

Detail mode is a **standalone `TutorialCoachMark`** — not wired to `TutorialFlowNotifier`. No `advance()` calls. No settings key to persist. Same ref-capture + `Future(() {...})` rules still apply:

```dart
void _showDetailModeMark() {
  // No flowNotifier needed — detail mode is entirely self-contained
  TutorialCoachMark(
    targets: [
      TargetFocus(keyTarget: _typeChipsKey,     /* explanation */),
      TargetFocus(keyTarget: _amountFieldKey,   /* explanation */),
      TargetFocus(keyTarget: _accountFieldKey,  /* explanation */),
      TargetFocus(keyTarget: _categoryFieldKey, /* explanation */),
      TargetFocus(keyTarget: _partyFieldKey,    /* explanation */),
      TargetFocus(keyTarget: _dateTimeKey,      /* explanation */),
      TargetFocus(keyTarget: _paymentMethodKey, /* explanation */),
      TargetFocus(keyTarget: _modeKey,          /* explanation */),
      TargetFocus(keyTarget: _saveButtonKey,    /* explanation */),
    ],
    colorShadow: Colors.black,
    opacityShadow: 0.85,
    onSkip: () { return true; },  // no provider state to clean up
    onFinish: () {},
  ).show(context: context);
}
```

### Detail field map — `AddEditTransactionScreen` (9 steps)

| Step | Field | Key | Content |
|------|-------|-----|---------|
| 1 | **What happened?** chips | `_typeChipsKey` | Spent/Earned for everyday money · Lent/Borrowed for money between people · Invested/Redeemed for savings & MF |
| 2 | **Amount** | `_amountFieldKey` | Enter in rupees — Indian comma formatting applied automatically (₹1,23,456) |
| 3 | **Account** | `_accountFieldKey` | Which bank/wallet this came from or went to. Leave blank to record without account tracking |
| 4 | **Category** | `_categoryFieldKey` | Affects your Reports breakdown. Tap "+ Add custom category" to create your own |
| 5 | **Party / Merchant** | `_partyFieldKey` | Who you paid or received from. Tap the contacts icon to pick from saved parties |
| 6 | **Date & Time** | `_dateTimeKey` | Defaults to now. Tap either to change for past or future transactions |
| 7 | **Payment Method** | `_paymentMethodKey` | UPI, Cash, Card, Net Banking, or Wallet. Auto-updates when you pick an Account |
| 8 | **Personal / Business** | `_modeKey` | Personal: your personal ledger. Business: records in business P&L and can appear on invoices |
| 9 | **Add Transaction** | `_saveButtonKey` | Saves and returns. Balance, reports, and party ledger update instantly |

> **New GlobalKeys required before implementing:** `_typeChipsKey`, `_accountFieldKey`, `_partyFieldKey`, `_dateTimeKey`, `_paymentMethodKey`, `_modeKey` — add alongside the existing `_amountFieldKey`, `_categoryFieldKey`, `_saveButtonKey`.

---

## Known Pitfalls & Fixes

### 1. SpeedDialFab — `key` targets the Column, not the button

`SpeedDialFab` renders as a `Column` (dial options + main button). Assigning a `GlobalKey` to the widget attaches it to the entire Column's render box — the spotlight covers all the mini-options too.

**Fix:** Use the dedicated `fabButtonKey` parameter, which threads the key directly onto the inner `FloatingActionButton`:

```dart
// ❌ Wrong — key targets the whole Column
SpeedDialFab(key: _fabKey, showAllOptions: false)

// ✅ Correct — key targets the inner FAB button only
SpeedDialFab(fabButtonKey: _fabKey, showAllOptions: false)
```

The `fabButtonKey` parameter is declared on `SpeedDialFab` and forwarded to its internal `FloatingActionButton(key: widget.fabButtonKey, ...)`.

### 2. `ref.read()` in tutorial callbacks causes "ref after dispose" crash

`TutorialCoachMark`'s `onSkip`/`onFinish` callbacks may fire after the widget is disposed (e.g. navigate away then skip). Calling `ref.read()` on a disposed widget throws `StateError: Cannot use "ref" after the widget was disposed`.

**Fix:** Capture provider refs **before** showing the coach mark:

```dart
void _showFabFlowMark() {
  // ✅ Capture BEFORE showing — refs are safe even after disposal
  final flowNotifier = ref.read(tutorialFlowProvider.notifier);
  final settingsRepo = ref.read(settingsRepositoryProvider);

  TutorialCoachMark(
    onSkip: () {
      flowNotifier.abandon();      // safe — no ref.read()
      settingsRepo.set(...);        // safe — no ref.read()
      return true;
    },
  ).show(context: context);
}
```

### 3. "Tried to modify a provider while the widget tree was building"

`TutorialCoachMark` sometimes calls `onSkip` during its own build phase (first frame). Calling `StateNotifier.state =` at that point is forbidden by Riverpod.

**Fix:** Wrap **all** provider state modifications in `Future(() { ... })` inside tutorial callbacks:

```dart
onSkip: () {
  Future(() {              // ← defer until after build completes
    flowNotifier.abandon();
    settingsRepo.set(SettingsKeys.tutorialInvoiceFlowDone, 'true');
  });
  return true;
},
onFinish: () {
  Future(() {
    flowNotifier.finish();
    settingsRepo.set(SettingsKeys.tutorialInvoiceFlowDone, 'true');
  });
},
```

This pattern must be applied consistently to **every** `onSkip`/`onFinish`/`onClickTarget` callback that modifies Riverpod state.

### 4. Auto-start `_maybeStartFlow()` fires on every navigation return

Calling `_maybeStartFlow()` from `initState` re-triggers the flow overlay every time the user navigates back to the screen (e.g. pressing back from the form).

**Fix:** Do **not** auto-start the guided flow from `initState`. The flow should only start on explicit user action via the `?` menu:

```dart
@override
void initState() {
  super.initState();
  _tabController = TabController(length: 2, vsync: this);
  maybeShowTutorial(); // ✅ orientation tour only — fires once via settings flag
  // ❌ _maybeStartFlow(); — removed; use ? menu to replay
}
```

---

## What NOT to Target

| Widget type | Reason |
|-------------|--------|
| Empty-state illustrations | Not in tree when data exists |
| First list item card | May not exist yet; assign `GlobalKey` conditionally |
| Dynamically revealed form fields | Scroll position unpredictable; spotlight geometry breaks |
| Bottom sheet widgets from a parent screen | Different overlay context — use a separate tutorial instance inside the sheet |
| Business-Mode-only widgets | Check `businessModeEnabled` before showing any business-screen tutorial |
| SpeedDial mini-buttons | Not in tree until the dial is expanded — spotlight the main FAB instead |

---

## Anti-Patterns — Never Do These

| Anti-pattern | Why it breaks |
|---|---|
| One `TutorialCoachMark` instance kept alive across route push | Previous screen's `GlobalKey` targets unmount → spotlights orphaned or invisible |
| `rootOverlay: true` across route boundaries | Overlay renders but targets have no geometry → black blind |
| `addPostFrameCallback` chains for cross-screen sequencing | Timing-based; breaks on slow devices or when data is async |
| Passing parent `BuildContext` into a pushed route for overlay | Context is stale after the push; overlay attaches to the wrong navigator |
| Targeting SpeedDial open-state mini-buttons | Widget is not in the tree until the dial is expanded |

---

## Mid-Tutorial Navigation Handling

If the user navigates away (back gesture, notification tap) while a tutorial is active:
- `onSkip` callback fires — always mark the step as done to avoid re-showing on return.
- Do **not** attempt to pop the overlay manually — the library handles cleanup.
- For multi-phase tutorials, store the completed step index so Phase 2 can still fire independently.

---

## Maintenance Rules

> **When you move or rename a widget that has a tutorial `GlobalKey` target, update `buildTargets()` in the same PR.**

> **When you rename or add a route that is part of a flow, update the `TutorialFlowStep` enum and orchestrator wiring in the same PR.**

Broken key targets produce no error — just a mis-positioned or invisible spotlight. They are silent bugs.

---

## Screen Audit

### App navigation structure

```
AppShell (5 tabs, per-tab Navigator)
├── Tab 0: Home           → HomeScreen
├── Tab 1: Transactions   → TransactionsHubScreen → TransactionsScreen ✅
├── Tab 2: Business       → BusinessHubScreen
│                              ├── push → CreditsScreen + AddCreditScreen ✅
│                              ├── push → InvoicesScreen → QuoteBuilderScreen
│                              ├── push → BookingsScreen → CreateBookingScreen
│                              ├── push → LoansScreen
│                              ├── push → ItemCatalogScreen
│                              └── push → StaffListScreen, InventoryScreen, …
├── Tab 3: Contacts       → PartiesScreen
└── Tab 4: Settings       → SettingsScreen
```

### Tier 1 — Core personal-mode screens (highest impact)

| Screen | FAB action | Flow | Priority |
|--------|-----------|------|----------|
| `TransactionsScreen` | Add Transaction → `AddEditTransactionScreen` | `addTxFab → addTxAmount → … → addTxResult` | ✅ Done |
| `CreditsScreen` | New Due → `AddCreditScreen` | `newCreditFab → newCreditAmount → … → newCreditResult` | ✅ Done |

### Tier 2 — Business-mode only (gate with `businessModeEnabled`)

| Screen | FAB action | Flow steps | Notes |
|--------|-----------|------------|-------|
| `InvoicesScreen` | New Invoice (`SpeedDialFab`) | `newInvoiceFab → … → newInvoiceResult` | Spotlight main FAB only (SpeedDial) |
| `BookingsScreen` | New Booking → `CreateBookingScreen` | `newBookingFab → … → newBookingResult` | Personal + Business modes |
| `ItemCatalogScreen` | Add Item | `newItemFab → … → newItemResult` | Guard `!widget.pickMode` |

### Tier 3 — Orientation tour only (no Phase 1 flow)

| Screen | Tour targets | Deferred condition |
|--------|-------------|--------------------|
| `HomeScreen` | Balance card · Search · Tune | First app open |
| `ReportsScreen` | Period picker · Export button | After ≥1 transaction |
| `PartiesScreen` | FAB (Add Contact) · Filter chips | First open |

### Tier 4 — Skip for now (Settings-level / niche)

`LoansScreen`, `BudgetScreen`, `RecurringTransactionsScreen`, `StaffListScreen`, `InventoryScreen`, `PurchaseBillsScreen` — tutorial ROI low; users discover organically.

---

### Full Screen Inventory

All 69 screens across 18 modules. Work through these one at a time top-to-bottom.

**Legend:** ✅ Done · ⬜ Queued (item #) · 🔜 Later · — Skip · `✅ Quick · ⬜ Detail` = Quick guide done, Detail field-reference pending

| # | Module | Screen | Form | Status | Plan / Reason |
|---|--------|--------|:----:|--------|---------------|
| 1 | transactions | `transactions_screen` | — | ✅ Done | Orientation tour + Add Transaction flow |
| 2 | transactions | `add_edit_transaction_screen` | ✓ | ✅ Quick · ⬜ Detail | Quick guide (3 steps) ✅ · 9-step field reference ⬜ Item 18 |
| 3 | ledger | `credits_screen` | ✓ | ✅ Done | Orientation tour + New Credit flow |
| 4 | invoices | `invoices_screen` | — | ✅ Done | Orientation tour + New Invoice flow |
| 5 | invoices | `quote_builder_screen` | ✓ | ✅ Done | Form spotlights + contextual `?` help |
| 6 | bookings | `bookings_screen` | — | ⬜ Item 19 | Orientation + New Booking flow |
| 7 | bookings | `create_booking_screen` | ✓ | ⬜ Item 19 | Form spotlights: customer → service → datetime → save |
| 8 | invoices | `item_catalog_screen` | ✓ | ⬜ Item 20 | Add Item flow; guard `!widget.pickMode` |
| 9 | home | `home_screen` | — | ⬜ Item 21 | Orientation tour: balance card · quick-add · tune |
| 10 | reports | `reports_screen` | — | ⬜ Item 21 | Orientation tour: period picker · export |
| 11 | parties | `parties_screen` | — | ⬜ Item 21 | Orientation tour: FAB · filter chips |
| 12 | ledger | `ledger_screen` | — | 🔜 Later | Unified ledger; orientation once data exists |
| 13 | bookings | `booking_detail_screen` | — | 🔜 Later | Post-creation result spotlight (part of Item 18) |
| 14 | reports | `cash_flow_screen` | — | 🔜 Later | Orientation once ≥1 transaction exists |
| 15 | gst | `gstr1_screen` | — | 🔜 Later | Orientation: "auto-populated from invoices" + Export |
| 16 | loans | `loans_screen` | ✓ | — Skip | Low discovery ROI; power-user feature |
| 17 | reports | `budget_screen` | ✓ | — Skip | Low ROI for new users |
| 18 | recurring | `recurring_transactions_screen` | ✓ | — Skip | Power-user; users self-discover |
| 19 | inventory | `inventory_screen` | ✓ | — Skip | Stock tracking; niche B2B |
| 20 | invoices | `delivery_challans_screen` | — | — Skip | B2B niche |
| 21 | invoices | `delivery_challan_detail_screen` | ✓ | — Skip | B2B niche |
| 22 | invoices | `invoice_detail_screen` | ✓ | — Skip | View-only; action buttons have tooltips |
| 23 | invoices | `quote_detail_screen` | — | — Skip | View-only |
| 24 | invoices | `ewb_preview_screen` | — | — Skip | E-way bill; expert feature |
| 25 | gst | `add_purchase_bill_screen` | ✓ | — Skip | Tax-expert screen |
| 26 | gst | `purchase_bills_screen` | — | — Skip | Tax-expert screen |
| 27 | gst | `purchase_bill_detail_screen` | — | — Skip | Tax-expert screen |
| 28 | gst | `gstr_period_picker` | — | — Skip | Dialog/picker widget |
| 29 | gst | `gstr3b_offset_screen` | — | — Skip | Tax-expert screen |
| 30 | bills | `bills_screen` | ✓ | — Skip | Covered by Transactions flow |
| 31 | bills | `bills_and_payments_screen` | ✓ | — Skip | Covered by Transactions flow |
| 32 | parties | `party_360_screen` | — | — Skip | Summary view; users navigate naturally |
| 33 | staff | `staff_list_screen` | — | — Skip | HR module; role-gated |
| 34 | staff | `staff_screen` | ✓ | — Skip | HR module |
| 35 | staff | `staff_detail_screen` | — | — Skip | HR module |
| 36 | business | `business_hub_screen` | — | — Skip | Navigation hub |
| 37 | business | `global_document_ledger_screen` | — | — Skip | Power feature |
| 38 | business | `tally_export_screen` | — | — Skip | Accountant feature |
| 39 | contacts | `contacts_hub_screen` | — | — Skip | Navigation hub; covered by Parties tour |
| 40 | home | `action_center_screen` | — | — Skip | Overlay panel |
| 41 | home | `customize_home_screen` | — | — Skip | One-time personalisation |
| 42 | search | `search_screen` | — | — Skip | Universal search; self-explanatory |
| 43 | transactions | `transactions_hub_screen` | — | — Skip | Navigation hub |
| 44 | transactions | `transaction_detail_screen` | — | — Skip | View-only |
| 45 | transactions | `bill_viewer_screen` | — | — Skip | Document viewer |
| 46 | transactions | `category_management_screen` | ✓ | — Skip | Admin-level; users reach via settings |
| 47 | settings | `settings_screen` | — | — Skip | Settings hub |
| 48 | settings | `accounts_manage_screen` | — | — Skip | Opening balances; one-time |
| 49 | settings | `businesses_screen` | ✓ | — Skip | Initial setup; wizard covers it |
| 50 | settings | `document_terms_screen` | — | — Skip | Doc template settings |
| 51 | settings | `encrypted_backup_screen` | ✓ | — Skip | Security settings |
| 52 | settings | `fy_close_wizard_screen` | — | — Skip | Annual task |
| 53 | settings | `manage_users_screen` | ✓ | — Skip | Multi-user admin |
| 54 | settings | `my_personal_card_screen` | ✓ | — Skip | Profile card |
| 55 | settings | `notification_settings_screen` | — | — Skip | Settings |
| 56 | settings | `open_on_laptop_screen` | — | — Skip | Web companion setup |
| 57 | settings | `pin_lock_screen` | — | — Skip | Auth flow |
| 58 | settings | `profile_screen` | — | — Skip | Settings |
| 59 | settings | `sms_permission_screen` | — | — Skip | One-time permission prompt |
| 60 | settings | `storage_health_screen` | — | — Skip | Diagnostic screen |
| 61 | settings | `template_builder_screen` | — | — Skip | Power-user |
| 62 | settings | `template_list_screen` | — | — Skip | Power-user |
| 63 | settings | `unit_types_screen` | ✓ | — Skip | Settings; low frequency |
| 64 | settings | `upgrade_screen` | — | — Skip | Subscription screen |
| 65 | settings | `user_permissions_screen` | — | — Skip | Multi-user admin |
| 66 | auth | `setup_wizard_screen` | — | — Skip | One-time onboarding |
| 67 | auth | `staff_pin_screen` | — | — Skip | Auth |
| 68 | auth | `terms_gate_screen` | — | — Skip | One-time consent |
| 69 | auth | `user_selection_screen` | — | — Skip | Auth |

**Summary:** 5 done · 7 queued (Items 18–21) · 4 later · 54 skip

---

## Implementation Order

### Done ✅
1. `tutorial_coach_mark` added to `pubspec.yaml`
2. `TutorialMixin` created at `lib/core/utils/tutorial_mixin.dart` (includes `TutorialMenuItem` + `buildTutorialAppBarAction()`)
3. Tutorial keys added to `SettingsKeys`
4. `TransactionsScreen` orientation tour (FAB · Search · Filter) + `?` replay button
5. `heroTag` collision fix across all FABs (per-tab navigator architecture)
6. `TutorialFlowNotifier` + `TutorialFlowStep` enum at `lib/presentation/providers/tutorial_flow_provider.dart`
7. Add Transaction flow wired: `TransactionsScreen` → `AddEditTransactionScreen` (3-step) → `TransactionsScreen` (result)
8. `TransactionsScreen` `?` upgraded to adaptive `PopupMenuButton` (orientation tour + add-tx flow)
9. New Credit flow wired: `CreditsScreen` → `AddCreditScreen` (3-step: amount · party · save) → `CreditsScreen` (result)
10. `CreditsScreen` orientation tour (FAB · Filter chips) + adaptive `?` dropdown
11. `InvoicesScreen` orientation tour (FAB · Search · Filter) + adaptive `?` dropdown (`Orientation tour` + `How to create an invoice`)
12. New Invoice guided flow: `InvoicesScreen` (FAB spotlight) → `QuoteBuilderScreen` (customer → line items → save) → `InvoicesScreen` (result card)
13. `QuoteBuilderScreen` contextual `?` help button on new invoice/quote (smart `_restartFormTutorial` — points to next incomplete step)
14. Fixed: `fabButtonKey` on `SpeedDialFab` for precise FAB spotlight targeting
15. Fixed: captured refs before `TutorialCoachMark` to prevent "ref after dispose" crash
16. Fixed: all tutorial callbacks use `Future(() {...})` to prevent "modifying provider during build" error
17. Fixed: removed `_maybeStartFlow()` auto-start from `initState` — guided flow only starts via `?` menu

### Next — Quick win ⬜
18. `AddEditTransactionScreen` detail mode — `_showDetailModeMark()` (9 steps, all fields) + upgrade `?` from `IconButton` to `PopupMenuButton` ("Quick guide" / "Field reference")

### Business flows ⬜
19. `BookingsScreen` add-booking flow
20. `ItemCatalogScreen` add-item flow

### Later ⬜
21. Orientation tours for Home, Reports, Contacts screens
22. Override `tutorialMenuItems` on each screen as its flows are wired
23. Add "Reset all tutorials" option under **Settings → About**
