# Tutorial Coach Marks — Spec

**Status:** Design approved, not yet implemented  
**Package:** [`tutorial_coach_mark`](https://pub.dev/packages/tutorial_coach_mark)  
**Last updated:** March 2026

---

## Overview

Kash Cube uses in-app coach marks to onboard users into each feature. The strategy follows a **"guided first action"** pattern — the tutorial walks the user through *creating their first record*, so the tutorial itself produces the data needed to make the screen useful.

This is strictly better than a passive tour of an empty screen.

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

### State Provider
```dart
// FutureProvider.family keyed on the tutorial key string
final tutorialDoneProvider = FutureProvider.family<bool, String>(
  (ref, key) async {
    final settings = ref.read(settingsRepositoryProvider);
    return await settings.getBool(key) ?? false;
  },
);
```

### TutorialMixin
A mixin on `ConsumerState` to avoid repeating boilerplate across screens:

```dart
mixin TutorialMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get tutorialKey;
  List<TargetFocus> buildTargets();

  void maybeShowTutorial() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final done = await ref.read(tutorialDoneProvider(tutorialKey).future);
      if (!done) _show();
    });
  }

  void _show() {
    TutorialCoachMark(
      targets: buildTargets(),
      onFinish: _markDone,
      onSkip: _markDone,
    ).show(context: context);
  }

  void _markDone() {
    ref.read(settingsRepositoryProvider).setBool(tutorialKey, true);
    ref.invalidate(tutorialDoneProvider(tutorialKey));
  }
}
```

### GlobalKey Placement
Keys are declared at `State` level, not inside `build()`:

```dart
class _TransactionsScreenState extends ConsumerState<TransactionsScreen>
    with TutorialMixin {
  final _fabKey = GlobalKey();
  final _firstCardKey = GlobalKey(); // only assigned when list is non-empty

  @override
  String get tutorialKey => 'tutorial_tx_guided_done';

  @override
  List<TargetFocus> buildTargets() => [
    TargetFocus(
      identify: 'fab',
      keyTarget: _fabKey,
      contents: [/* title, body */],
    ),
    if (_firstCardKey.currentContext != null)
      TargetFocus(identify: 'first_card', keyTarget: _firstCardKey, ...),
  ];
}
```

### Deferred Trigger (async data)
When the tutorial must wait for data to load, use `ref.listen` rather than `addPostFrameCallback`:

```dart
ref.listen(transactionsProvider, (prev, next) {
  if (prev?.isLoading == true && next.hasValue && (next.value?.isNotEmpty ?? false)) {
    maybeShowTutorial();
  }
});
```

### Form-Screen Coach Marks
The Add Transaction form runs in a new route. Use a separate `TutorialCoachMark` instance scoped to that screen's `BuildContext` — do not pass the parent screen's context into the form.

---

## Replay — `?` Button

Every screen that has a tutorial gets a `?` icon button in the AppBar (or a long-press affordance on the FAB):

```dart
IconButton(
  icon: const Icon(Icons.help_outline),
  tooltip: 'Show tutorial',
  onPressed: () {
    ref.read(settingsRepositoryProvider).setBool(tutorialKey, false);
    ref.invalidate(tutorialDoneProvider(tutorialKey));
    _show();
  },
)
```

This resets only the flag for that screen — all other tutorials are unaffected.

---

## What NOT to Target

| Widget type | Reason |
|-------------|--------|
| Empty-state illustrations | Not in tree when data exists |
| First list item card | May not exist yet; assign `GlobalKey` conditionally |
| Dynamically revealed form fields | Scroll position unpredictable; spotlight geometry breaks |
| Bottom sheet widgets from a parent screen | Different overlay context — use a separate tutorial instance inside the sheet |
| Business-Mode-only widgets | Check `businessModeEnabled` before showing any business-screen tutorial |

---

## Mid-Tutorial Navigation Handling

If the user navigates away (back gesture, notification tap) while a tutorial is active:
- `onSkip` callback fires — always mark the step as done to avoid re-showing on return.
- Do **not** attempt to pop the overlay manually — the library handles cleanup.
- For multi-phase tutorials, store the completed step index so Phase 2 can still fire independently.

---

## Maintenance Rule

> **When you move or rename a widget that has a tutorial `GlobalKey` target, update `buildTargets()` in the same PR.**

Broken key targets produce no error — just a mis-positioned or invisible spotlight. They are silent bugs.

---

## Implementation Order (Suggested)

1. Add `tutorial_coach_mark` to `pubspec.yaml`
2. Create `TutorialMixin` in `lib/core/utils/tutorial_mixin.dart`
3. Implement Transactions Phase 1 + Phase 2 (highest-value, always available)
4. Implement Ledger Phase 1 + Phase 2
5. Implement Reports tour (no Phase 1 needed — just targets filter + export)
6. Implement Invoices, Bookings, Item Catalog in parallel
7. Add `?` buttons to all participating screens
8. Add "Reset all tutorials" option under **Settings → About**
