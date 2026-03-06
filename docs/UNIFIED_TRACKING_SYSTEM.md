# Unified Tracking & Management System

> **Authored:** 7 March 2026  
> **Status:** Planning — not yet started  
> **Scope:** Four complementary features that weave KashCube's siloed modules
> into a single, coherent financial picture per party and across time.

---

## Problem Statement

KashCube has six mature financial modules (Invoices, Dues/Credits, Loans, Bills,
Bookings, Transactions) but they are **siloed by design**. As a result:

| Symptom | Impact |
|---------|--------|
| A ₹50k invoice + ₹10k credit + ₹5k loan from "Rajesh Traders" appear on 3 separate screens | User cannot answer "How much does Rajesh owe me in total?" |
| Upcoming EMIs, bill due dates, and invoice dues live on separate screens | Cash flow blind spots — missed payments |
| No multi-select / batch remind | User must open each overdue invoice one by one to send WhatsApp reminder |
| No visibility into *how long* an item has been in a stage | Cannot prioritise "Invoice sent 14 days ago, never reminded" over one sent yesterday |
| Bookings (advance deposits, check-in dates) are invisible in Party summary | Net outstanding for a party is wrong if they have an unpaid advance |

---

## Four Pillars

```
┌──────────────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│  Pillar A            │  Pillar B            │  Pillar C            │  Pillar D            │
│  Party 360°          │  Cash Flow Timeline  │  Bulk Actions        │  Lifecycle Tags      │
│  (who owes what)     │  (when does it land) │  (work at scale)     │  (how long & why)    │
│                      │                      │                      │                      │
│  Effort: Medium      │  Effort: Small       │  Effort: Small       │  Effort: Medium      │
│  Value:  ★★★★★       │  Value:  ★★★★        │  Value:  ★★★★        │  Value:  ★★★         │
└──────────────────────┴──────────────────────┴──────────────────────┴──────────────────────┘
```

These are **independent** — each can ship without the others, but they share the
`PartyFinancialSummary` data model (Pillar A) which Pillar C also uses. Pillar D
augments Pillars A and C with richer stage/age data visible in both.

---

## Pillar A — Party 360° View

### Goal
One screen that answers the question: **"Everything about this person or business."**

```
┌─ Rajesh Traders ──────────────────────────────────────────────────┐
│  📞 98400 12345   📧 rajesh@example.com                           │
│  ──────────────────────────────────────────────────────────────── │
│  NET OUTSTANDING        ₹65,000  (to collect)                     │
│  ──────────────────────────────────────────────────────────────── │
│  Invoices    2 open    ₹50,000   Due 10 Mar, 25 Mar               │
│  Dues        1 active  ₹10,000   Overdue 3 days                   │
│  Loans       1 active   ₹5,000   EMI 15 Mar                       │
│  Transactions  18 total (last: 2 Mar)                             │
│  Reminders     3 sent  (last: 1 Mar via WhatsApp)                 │
│  ──────────────────────────────────────────────────────────────── │
│  [Send Reminder]  [Record Payment]  [New Invoice]                 │
└───────────────────────────────────────────────────────────────────┘
     ↓ scrolls into
  Timeline of all items (sorted newest first)
```

### Existing infrastructure

| Asset | Location | Status |
|-------|----------|--------|
| `Credit.customerId` | `lib/data/models/credit.dart` | ✅ links to parties |
| `Loan.lenderId` | `lib/data/models/loan.dart` | ✅ links to parties |
| `Invoice.customerPartyId` | `lib/data/models/invoice.dart` | ✅ links to parties |
| `Transaction.partyId` | `lib/data/models/transaction.dart` | ✅ links to parties |
| `loansByPartyProvider` | `lib/presentation/providers/loan_provider.dart` | ✅ exists |
| `partiesProvider` | `lib/presentation/providers/party_provider.dart` | ✅ exists |
| `party_reminders` table / `ReminderService` | DB v43 | ✅ exists |
| `Booking.partyId` | `lib/data/models/booking.dart` | ⚠️ verify FK column exists |
| `PartyDetailScreen` (partial) | `lib/presentation/screens/parties/` | ⚠️ no financial summary |

### What needs building

#### A1 — `PartyFinancialSummary` model
```dart
// lib/data/models/party_financial_summary.dart
class PartyFinancialSummary {
  final int partyId;
  final String partyName;

  // Net balance: positive = party owes us, negative = we owe party
  final double netOutstanding;

  // Per-module totals
  final double invoicesPending;    // sum of balanceDue where status != paid
  final double duesPending;        // sum of pendingAmount where !isCleared
  final double loansPending;       // sum of pendingAmount where !isCleared
  final double bookingsPending;    // sum of advanceAmount where !isCompleted && !isCancelled

  // Counts
  final int openInvoices;
  final int openDues;
  final int activeLoans;
  final int activeBookings;
  final int transactionCount;
  final int reminderCount;

  // Urgency
  final DateTime? earliestDueDate; // earliest due date across all modules
  final bool hasOverdueItem;

  // Recent activity
  final DateTime? lastTransactionDate;
  final DateTime? lastReminderDate;
}
```

#### A2 — `partyFinancialSummaryProvider(int partyId)`
```dart
// lib/presentation/providers/party_financial_provider.dart
final partyFinancialSummaryProvider =
    FutureProvider.family<PartyFinancialSummary, int>((ref, partyId) async {
  // Parallel queries — all local SQLite
  final [invoices, credits, loans, txnCount, reminders] = await Future.wait([
    ref.read(invoiceRepositoryProvider).getByPartyId(partyId),
    ref.read(creditRepositoryProvider).getByCustomerId(partyId),
    ref.read(loanRepositoryProvider).getByLenderId(partyId),
    ref.read(transactionRepositoryProvider).countByPartyId(partyId),
    ref.read(partyReminderRepositoryProvider).getByPartyId(partyId),
  ]);
  return PartyFinancialSummary.compute(
    partyId: partyId,
    invoices: invoices, credits: credits, loans: loans,
    transactionCount: txnCount, reminders: reminders,
  );
});
```

#### A3 — Repository method additions (no schema changes)

| Repository | New method | SQL |
|-----------|-----------|-----|
| `InvoiceRepository` | `getByPartyId(int id)` | `WHERE customer_party_id = ? AND deleted_at IS NULL` |
| `CreditRepository` | `getByCustomerId(int id)` | `WHERE customer_id = ? AND deleted_at IS NULL` |
| `LoanRepository` | `getByLenderId(int id)` | `WHERE lender_id = ? AND deleted_at IS NULL` |
| `TransactionRepository` | `countByPartyId(int id)` | `SELECT COUNT(*) WHERE party_id = ?` |
| `BookingRepository` | `getByPartyId(int id)` | `WHERE party_id = ? AND status NOT IN ('completed','cancelled')` |

> **No DB migration required** for Invoice/Credit/Loan/Transaction repos — all FK columns already
> exist. `ScheduledPayment.partyId` does **not** yet have a FK column — see P1.6 (DB v45 migration).

#### A4 — `PartyDetailScreen` enhancement

Extend the existing screen (or create `Party360Screen` if it's too coupled):

- **Header card**: name, phone, GSTIN, net outstanding (coloured: income if positive, expense if negative)
- **Summary row**: 3 stat chips (Invoices / Dues / Loans) — tap each to jump to relevant module filtered to this party
- **Unified timeline**: merged list of `Invoice`, `Credit`, `Loan`, `Transaction` items sorted by date, each with a type icon
- **Bottom action bar**: Send Reminder | Record Payment | ⋮ (New Invoice / New Due)

#### A5 — Party search / autocomplete upgrade

Everywhere a party name is typed (AddCreditScreen, QuoteBuilderScreen, etc.), if the user picks an existing party by ID, silently populate `customerId` / `customerPartyId` / `lenderId`. Currently some forms save the text name without populating the FK — this is the root cause of why Party 360° can't aggregate everything.

**Touch points:**
- `AddCreditScreen` → set `customerId`
- Loan add form → set `lenderId`
- `ScheduledPayment` → set `partyId` — **requires DB v45 migration** (task P1.6)

---

## Pillar B — Cash Flow Timeline

### Goal
A single scrollable view showing **all money movement in chronological order** — past recorded, present overdue, future projected — so the user can answer:
**"What cash comes in / goes out, and when?"**

```
◀ Feb 2026              Mar 2026              Apr 2026 ▶
────────────────────────────────────────────────────────
5 Mar  ✅ ₹12,000  HDFC salary (SMS)
6 Mar  ✅  ₹3,500  Grocery — PhonePe (SMS)
────────── TODAY ──────────────────────── 7 Mar ────────
7 Mar  🔴 ₹50,000  Invoice #0041 — Rajesh Traders  OVERDUE
7 Mar  🟠  ₹5,000  Electricity bill                OVERDUE
────────── UPCOMING ────────────────────────────────────
8 Mar  🟡 ₹12,000  HDFC Home Loan EMI
10 Mar 🟡  ₹8,500  Invoice #0043 — Suresh & Co
15 Mar 🟡  ₹2,200  Mobile bill
25 Mar 🟡 ₹45,000  Invoice #0045 — City Mall
1 Apr  🔵 ₹12,000  HDFC Home Loan EMI (projected)
```

### Existing infrastructure

All data sources already have providers:

| Source | Provider | Item type |
|--------|----------|-----------|
| Past transactions (SMS + manual) | `recentTransactionsProvider` | `Transaction` |
| Overdue bills | `overdueScheduledProvider` | `ScheduledPayment` |
| Upcoming bills | `upcomingScheduledProvider` | `ScheduledPayment` |
| Overdue loan EMIs | `overdueLoansProvider` | `Loan` |
| Upcoming loan EMIs | `activeLoansProvider` (nextEmiDate) | `Loan` |
| Overdue invoices | `invoicesProvider` + filter | `Invoice` |
| Upcoming invoices | `invoicesProvider` + filter | `Invoice` |
| Overdue dues | `activeCreditsProvider` + filter | `Credit` |
| Upcoming bookings (check-in/service date) | `bookingsProvider` + filter | `Booking` |
| Booking advances due (not yet received) | `bookingsProvider` + filter | `Booking` |

### What needs building

#### B1 — `CashFlowEvent` sealed class
```dart
// lib/data/models/cash_flow_event.dart
sealed class CashFlowEvent {
  DateTime get date;
  double get amount;
  CashFlowDirection get direction; // inflow / outflow
  CashFlowStatus get status;       // recorded / overdue / upcoming / projected
}

final class RecordedEvent extends CashFlowEvent { ... } // from Transaction
final class OverdueEvent  extends CashFlowEvent { ... } // from any overdue
final class UpcomingEvent extends CashFlowEvent { ... } // from any future
```

#### B2 — `cashFlowTimelineProvider`
```dart
// lib/presentation/providers/cash_flow_provider.dart
// Merges all sources into a date-sorted List<CashFlowEvent>
// Window: 90 days past → 90 days future (configurable)
final cashFlowTimelineProvider = Provider<AsyncValue<List<CashFlowEvent>>>(...);

// Monthly summary for header strip
final cashFlowMonthlySummaryProvider =
    Provider.family<({double inflow, double outflow}), DateTime>(...);
```

#### B3 — `CashFlowScreen`
- **Route:** accessible from Reports tab or Home
- **Header**: month navigator with inflow/outflow totals
- **Dividers**: "PAST" → "TODAY" → "UPCOMING" → "PROJECTED"
- **Event tile**: type icon, description, amount (coloured by direction), status badge
- **Tap**: navigates to source detail (InvoiceDetailScreen, etc.)
- **Filter chip row**: All | Inflow | Outflow | Overdue

---

## Pillar C — Bulk Actions in Action Center

### Goal
When the user has 8 overdue invoices, let them **select all + send WhatsApp to all** in two taps instead of 8 separate opens.

### What needs building

#### C1 — Multi-select mode in `ActionCenterScreen`

- Long-press or "Select" AppBar button toggles selection mode
- Checkboxes appear on each `_ActionItemTile`
- Bottom action bar slides up: **[Remind All (N)] [Mark Paid (N)]**

```
┌─ Action Center ────────────────────── ✓ 3 selected ─┐
│  ☑  Rajesh Traders    Invoice #0041  ₹50,000  7d ago │
│  ☑  Suresh & Co       Invoice #0043   ₹8,500  2d ago │
│  ☐  Priya Electronics Invoice #0045  ₹45,000  Due 25 │
│  ☑  Ravi Kumar        Due            ₹10,000  5d ago │
└──────────────────────────────────────────────────────┘
  ╔══════════════════════════════════════════════════╗
  ║  📱 Remind All (3)        ✓ Mark as Paid (3)    ║
  ╚══════════════════════════════════════════════════╝
```

#### C2 — `BulkReminderService`

```dart
// lib/data/services/bulk_reminder_service.dart
class BulkReminderService {
  /// Opens WhatsApp for each item sequentially (OS deep-link per item).
  /// Returns count of successfully opened chats.
  Future<int> sendReminders(List<ActionItem> items);

  /// Falls back to SMS if no phone number / WhatsApp not installed.
  Future<void> sendSingleReminder(ActionItem item);
}
```

> **Privacy constraint:** Still uses OS intent deep-links — no new permissions,
> no network calls.

#### C3 — Consolidated Party Statement PDF

When multiple items from the **same party** are selected, offer
"Generate Statement" — produces a single PDF listing all open items for that
party (Invoices + Dues + Loans), formatted for sharing via WhatsApp/email.

```dart
// lib/data/services/party_statement_service.dart
// Uses existing pdf: ^3.11.0 package — no new dependency
Future<File> generatePartyStatement(PartyFinancialSummary summary);
```

---

## Pillar D — Lifecycle Tags

### Goal
Every financial item (Invoice, Due, Loan, Bill) moves through a defined sequence
of stages. Lifecycle Tags make that journey **visible and actionable** — so the
user knows not just *what* is overdue, but *how long it has been stuck* and
*what happened last*.

```
Invoice lifecycle:
  draft → sent → reminded → partially paid → paid
                              ↓ if past due date
                            overdue (any stage)

Credit / Due lifecycle:
  active → reminded → partial → cleared
           ↓ if past due date
         overdue

Loan lifecycle:
  active → paying (paidEmis > 0) → overdue → cleared

Bill lifecycle:
  active → upcoming (≤7 days) → overdue → paid
```

The **age in current stage** is the key metric. An invoice that has been `sent`
for 21 days with no reminder is a higher priority than one sent yesterday,
even if both have the same due date.

### Lifecycle stage display (example in Action Center)

```
┌─ Rajesh Traders   Invoice #0041   ₹50,000 ─────────────────────┐
│  📄  Sent 21 days ago · Reminded once · Overdue 7 days          │
│  Stage: REMINDED ──●───────── → PARTIAL → PAID                  │
└────────────────────────────────────────────────────────────────┘
```

### Design decision: computed vs stored

| Approach | Pro | Con |
|----------|-----|-----|
| **Computed** (MVP) — derive stage at runtime from existing fields | Zero DB migration, ship in days | Cannot store custom stage overrides | 
| **Stored** — add `lifecycle_stage` + `last_action_at` columns | Persistent, queryable, allows override | Requires DB migration (v45+) |

**Recommendation:** Ship computed MVP first; add stored columns in a follow-up
migration only if user feedback requests manual stage override.

### Existing fields that drive computed stages

| Source | Existing fields used |
|--------|---------------------|
| `Invoice` | `status` (draft/sent/paid/overdue/partiallyPaid), `reminderSentAt`, `paidAmount`, `dueDate`, `updatedAt` |
| `Credit` | `isCleared`, `isOverdue`, `dueDate`, `pendingAmount`, `createdAt` |
| `Loan` | `isCleared`, `isOverdue`, `paidEmis`, `nextEmiDate`, `dueDate`, `updatedAt` |
| `ScheduledPayment` | `lastPaidDate`, `nextDate`, `isActive` |
| `party_reminders` | `sent_at` per party (closest proxy for "last reminded") |

### What needs building

#### D1 — `LifecycleStage` enum + `LifecycleInfo` value class

```dart
// lib/data/models/lifecycle_info.dart
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

class LifecycleInfo {
  final LifecycleStage stage;
  final int daysInStage;      // days since last stage transition
  final DateTime? lastActionAt; // last reminder or payment event
  final String? lastActionLabel; // "Reminded via WhatsApp", "₹5,000 received"
  final LifecycleStage? nextStage; // suggested next step
  final String? nextActionHint;   // "Send a reminder" / "Record payment"
}
```

#### D2 — `LifecycleClassifier` (pure Dart, no DB access)

```dart
// lib/core/utils/lifecycle_classifier.dart
class LifecycleClassifier {
  static LifecycleInfo forInvoice(Invoice inv, {DateTime? lastReminderAt});
  static LifecycleInfo forCredit(Credit c, {DateTime? lastReminderAt});
  static LifecycleInfo forLoan(Loan l);
  static LifecycleInfo forBill(ScheduledPayment p);
  static LifecycleInfo forBooking(Booking b); // pending → confirmed → checked_in → completed
}
```

All methods are pure functions — no async, no DB calls — so they work inside
`build()` methods directly. Example:

```dart
static LifecycleInfo forInvoice(Invoice inv, {DateTime? lastReminderAt}) {
  final now = DateTime.now();
  final stage = switch (inv.status) {
    InvoiceStatus.draft         => LifecycleStage.draft,
    InvoiceStatus.paid          => LifecycleStage.paid,
    InvoiceStatus.partiallyPaid => LifecycleStage.partiallyPaid,
    InvoiceStatus.overdue       => LifecycleStage.overdue,
    InvoiceStatus.sent => lastReminderAt != null
        ? LifecycleStage.reminded
        : LifecycleStage.sent,
  };
  final lastAction = lastReminderAt ?? inv.updatedAt;
  final daysInStage = lastAction != null
      ? now.difference(lastAction).inDays
      : now.difference(inv.createdAt).inDays;
  return LifecycleInfo(
    stage: stage,
    daysInStage: daysInStage,
    lastActionAt: lastAction,
    ...
  );
}
```

#### D3 — `LifecycleTag` widget

A small reusable widget used wherever an item appears:

```dart
// lib/presentation/widgets/lifecycle_tag.dart
// Usage: LifecycleTag(info: lifecycleInfo)
//
// Renders a compact pill:  [ SENT · 14d ]  or  [ OVERDUE · 7d ]  or  [ REMINDED · 2d ]
// Colour-coded by stage urgency.
// Optional: expandedMode = true → shows progress bar (stage dots)
```

#### D4 — `LifecycleTag` integration points

| Screen | Where added | Info source |
|--------|-------------|-------------|
| `_ActionItemTile` (Action Center) | Below party name | `LifecycleClassifier.forX(item)` |
| `InvoiceDetailScreen` | Header section | `LifecycleClassifier.forInvoice(inv, lastReminderAt: ...)` |
| `Party360Screen` (Pillar A) | Each item in unified timeline | `LifecycleClassifier.forX(item)` |
| `CashFlowScreen` (Pillar B) | Event tile subtitle | `LifecycleClassifier.forX(item)` |

#### D5 — "Next action hint" in Action Center

Action Center `_ActionItemTile` currently shows a generic "View" button.
With lifecycle info, the button label becomes context-aware:

| Stage | Button label |
|-------|--------------|
| `sent` + >7 days | **Send Reminder** (amber) |
| `reminded` + >3 days | **Follow Up** (orange) |
| `overdue` | **Collect Now** (red) |
| `partiallyPaid` | **Record Balance** (primary) |
| `active` + due in 3d | **View** (neutral) |

No new data needed — `daysInStage` from `LifecycleInfo` drives the label.

#### D6 — "Stale Items" filter chip in Action Center

Items with **no activity for N days** (default N = 7) are stale. A dedicated
filter chip surfaces them so the user can prioritise and act in bulk.

```dart
// Action Center filter chip row:
// [All]  [To Collect]  [To Pay]  [Stale ●]
//
// "Stale" = lifecycle.daysInStage > kDefaultStallThreshold
const int kDefaultStallThreshold = 7; // named constant — no DB write, no settings screen in MVP
```

Stale items also receive a subtle **amber left-border** in Party 360°'s unified
timeline, reinforcing that they need attention without being noisy.

> Future: expose `kDefaultStallThreshold` as a user-configurable setting
> (Settings screen → "Alert me if no activity for X days").

### Schema extension (stored lifecycle — Phase 2 only)

If computed MVP proves insufficient, a single DB migration adds:

```sql
-- DB v45 — Lifecycle Tag columns
ALTER TABLE invoices ADD COLUMN lifecycle_stage TEXT;
ALTER TABLE invoices ADD COLUMN last_action_at  TEXT;

ALTER TABLE credits  ADD COLUMN lifecycle_stage TEXT;
ALTER TABLE credits  ADD COLUMN last_action_at  TEXT;

ALTER TABLE loans    ADD COLUMN lifecycle_stage TEXT;
ALTER TABLE loans    ADD COLUMN last_action_at  TEXT;
```

These are nullable — existing rows default to `NULL`, computed classifier
fills in until user explicitly sets a stage override.

---

## Implementation Sequence

### Phase 1 — Foundation (Week 1) `~3 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P1.1 | `PartyFinancialSummary` model + `compute()` factory | — | 2h |
| P1.2 | Repository methods: `getByPartyId` on Invoice/Credit/Loan/Txn | — | 3h |
| P1.3 | `partyFinancialSummaryProvider(int partyId)` | P1.1, P1.2 | 2h |
| P1.4 | `CashFlowEvent` sealed class | — | 1h |
| P1.5 | `cashFlowTimelineProvider` | P1.4 | 3h |
| P1.6 | DB migration v45: add `party_id` column to `scheduled_payments` | — | 1h |
| P1.7 | `BookingRepository.getByPartyId(int id)` + wire into `partyFinancialSummaryProvider` | P1.1 | 1h |

### Phase 2 — Core screens (Week 2) `~4 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P2.1 | `Party360Screen` – header + summary chips | P1.3 | 4h |
| P2.2 | `Party360Screen` – unified timeline list | P1.2, P1.3 | 4h |
| P2.3 | `CashFlowScreen` – full screen with month nav | P1.5 | 5h |
| P2.4 | Action Center multi-select mode | `actionCenterProvider` | 3h |
| P2.5 | `BulkReminderService` | P2.4 | 2h |
| P2.6 | Navigation hooks: Party detail → Party360Screen; tap party name in `_ActionItemTile` → Party360Screen | P2.1 | 2h |
| P2.7 | Add Cash Flow entry to Reports screen (prominent card → `CashFlowScreen`) | P2.3 | 1h |

### Phase 3 — Polish, wiring & Lifecycle (Week 3) `~3 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P3.1 | Party FK backfill in AddCreditScreen + Loan form | P1.2 | 2h |
| P3.2 | Party search shows net outstanding in autocomplete | P1.3 | 2h |
| P3.3 | Consolidated Party Statement PDF | P2.1, P2.2 | 3h |
| P3.4 | Cash Flow → Reports tab integration | P2.3 | 1h |
| P3.5 | `LifecycleStage` enum + `LifecycleInfo` value class (D1) | — | 2h |
| P3.6 | `LifecycleClassifier` pure utility (D2) | P3.5 | 3h |
| P3.7 | `LifecycleTag` widget (D3) | P3.5 | 2h |
| P3.8 | Wire `LifecycleTag` into Action Center + InvoiceDetailScreen (D4) | P3.6, P3.7 | 2h |
| P3.9 | Context-aware action button labels in `_ActionItemTile` (D5) | P3.6 | 1h |
| P3.10 | "Stale Items" filter chip in Action Center + amber border in Party360 timeline (D6) | P3.6 | 2h |
| P3.11 | `flutter analyze` + widget tests for all new code | all | 3h |

**Total estimated:** ~56 hours across 3 weeks.

> Lifecycle Tags (D1–D6) are the last items in Phase 3 so they can layer on top
> of the Party 360° and Action Center screens that ship in Phase 2.

---

## File Map

```
lib/
├── core/
│   └── utils/
│       └── lifecycle_classifier.dart      ← NEW (D2)
├── data/
│   ├── models/
│   │   ├── party_financial_summary.dart   ← NEW (P1.1)
│   │   ├── cash_flow_event.dart           ← NEW (P1.4)
│   │   └── lifecycle_info.dart            ← NEW (D1)
│   ├── repositories/
│   │   └── (extensions to existing repos) ← MODIFY (P1.2)
│   └── services/
│       ├── bulk_reminder_service.dart     ← NEW (C2)
│       └── party_statement_service.dart   ← NEW (C3)
├── presentation/
│   ├── providers/
│   │   ├── party_financial_provider.dart  ← NEW (P1.3)
│   │   └── cash_flow_provider.dart        ← NEW (P1.5)
│   ├── widgets/
│   │   └── lifecycle_tag.dart             ← NEW (D3)
│   └── screens/
│       ├── parties/
│       │   └── party_360_screen.dart      ← NEW (P2.1, P2.2)
│       ├── reports/
│       │   └── cash_flow_screen.dart      ← NEW (P2.3)
│       └── home/
│           └── action_center_screen.dart  ← MODIFY (P2.4, D4)
```

---

## Privacy Compliance Checklist

All four pillars are **100% on-device**:

- [x] `PartyFinancialSummary` — in-memory aggregation of local SQLite tables
- [x] `CashFlowEvent` — in-memory merge using existing local providers
- [x] `BulkReminderService` — OS WhatsApp deep-link (no READ_CONTACTS, no network)
- [x] Party Statement PDF — generated locally using `pdf` package, shared via OS share sheet
- [x] `LifecycleClassifier` — pure in-memory computation from local model fields; no DB writes in MVP
- [x] `LifecycleTag` widget — display only; reads no new data sources
- [ ] No new permissions required beyond what is already granted

---

## Open Design Questions

1. **Party 360° entry point:** Accessible from Party detail AND from each
   `_ActionItemTile` (tap party name)? → Recommended: yes, both.

2. **Cash Flow window:** Default 30 days past + 60 days future, or always the
   current calendar month? → Recommendation: rolling window (30/60), with a
   month-jump nav control.

3. **Bulk "Mark Paid" for invoices:** Should recording payment require an
   amount entry (partial), or default to full balance? → Recommendation:
   full balance with an "Edit amount" option in the confirmation dialog.

4. **Party FK backfill:** When `AddCreditScreen` has a free-text name that
   matches an existing party, auto-link silently, or confirm with the user?
   → Recommendation: auto-link silently (matching by normalised name), show
   a one-time toast "Linked to existing party Rajesh Traders".

5. **Lifecycle stage override:** Should users be able to manually set a stage
   (e.g. mark an invoice as "sent" even though `status = draft`)?
   → MVP: no override — computed only. Phase 2: add stored columns (DB v45)
   and an "Update stage" option in `InvoiceDetailScreen` overflow menu.

6. **`daysInStage` reference point:** For invoices in `sent` stage, count days
   from `updatedAt` or from `lastReminderAt`?
   → Recommendation: use `max(updatedAt, lastReminderAt)` as the reference —
   whichever was more recent.

7. **Cash Flow Screen entry point:** Should `CashFlowScreen` get its own bottom
   nav tab or live under Reports?
   → Recommendation: add as a prominent card in the existing Reports screen
   (preserves bottom nav space). Tap the card → full `CashFlowScreen`. Task P2.7.

8. **Bookings advance direction in net outstanding:** Should a received advance
   reduce `netOutstanding` (party owes us less) or be tracked separately?
   → Recommendation: subtract received advance from `netOutstanding` to reflect
   true remaining receivable. Show `bookingsPending` as a separate line in
   Party 360° for transparency.

9. **Stale threshold (N days):** What value triggers the "Stale" filter?
   → Recommendation: N = 7 days (`kDefaultStallThreshold`). Expose as a
   user setting in a future Settings release.

---

## Success Metrics (in-app, no analytics)

These can be verified manually during QA:

- Party 360°: opening any party with >0 open invoices shows correct `netOutstanding`
- Cash Flow: today's divider lands correctly; tapping an upcoming event navigates to its source screen
- Bulk Remind: selecting 3 items → "Remind All" opens 3 WhatsApp pre-fills in sequence
- Lifecycle Tags: an invoice in `sent` status with `updatedAt` 14 days ago shows `LifecycleStage.sent` and `daysInStage = 14`; `_ActionItemTile` button shows "Send Reminder" not "View"
- Lifecycle Tags: a fully paid invoice shows `LifecycleStage.paid` — no tag rendered in Action Center (paid items are filtered out)
- Bookings: party with 1 confirmed booking shows `activeBookings = 1` and advance in `bookingsPending`; `netOutstanding` reflects the subtracted advance
- Stale filter: Action Center "Stale" chip shows only items where `daysInStage > 7`; chip badge is hidden when 0 items match
- `flutter analyze`: 0 new errors after all phases complete
