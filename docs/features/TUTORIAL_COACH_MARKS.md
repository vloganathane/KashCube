# Tutorial Coach Marks — Spec

**Status:** Partially implemented — orientation tour ✅ · flow-following ✅ (Transactions · Credits)  
**Package:** [`tutorial_coach_mark`](https://pub.dev/packages/tutorial_coach_mark)  
**Last updated:** 24 March 2026

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
| Per-feature flows (Invoices, Bookings, Catalog…) | ⬜ |
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

> **Rule:** The `?` action lives on **entry screens** (where the flow can be started/replayed) and **result screens** (where the post-creation tour runs). Intermediate form screens omit it.

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

### Next — Business flows ⬜
11. `InvoicesScreen` add-invoice flow (business-mode gate)
12. `BookingsScreen` add-booking flow
13. `ItemCatalogScreen` add-item flow

### Later ⬜
14. Orientation tours for Home, Reports, Contacts screens
15. Override `tutorialMenuItems` on each screen as its flows are wired
16. Add "Reset all tutorials" option under **Settings → About**
