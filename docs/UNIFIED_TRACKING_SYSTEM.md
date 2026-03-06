# Unified Tracking & Management System

> **Authored:** 7 March 2026  
> **Status:** Planning — not yet started  
> **Scope:** Three complementary features that weave KashCube's siloed modules
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

---

## Three Pillars

```
┌──────────────────────────────────────────────────────────────────┐
│  Pillar A              Pillar B              Pillar C            │
│  Party 360°            Cash Flow Timeline    Bulk Actions        │
│  (who owes what)       (when does it land)   (work at scale)     │
│                                                                  │
│  Effort: Medium        Effort: Small         Effort: Small       │
│  Value:  ★★★★★         Value:  ★★★★          Value:  ★★★★        │
└──────────────────────────────────────────────────────────────────┘
```

These are **independent** — each can ship without the others, but they share the
`PartyFinancialSummary` data model (Pillar A) which Pillar C also uses.

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

  // Counts
  final int openInvoices;
  final int openDues;
  final int activeLoans;
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

> **No DB migration required** — all FK columns already exist.

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
- `ScheduledPayment` → set `partyId` (new column if needed)

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

## Implementation Sequence

### Phase 1 — Foundation (Week 1) `~3 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P1.1 | `PartyFinancialSummary` model + `compute()` factory | — | 2h |
| P1.2 | Repository methods: `getByPartyId` on Invoice/Credit/Loan/Txn | — | 3h |
| P1.3 | `partyFinancialSummaryProvider(int partyId)` | P1.1, P1.2 | 2h |
| P1.4 | `CashFlowEvent` sealed class | — | 1h |
| P1.5 | `cashFlowTimelineProvider` | P1.4 | 3h |

### Phase 2 — Core screens (Week 2) `~4 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P2.1 | `Party360Screen` – header + summary chips | P1.3 | 4h |
| P2.2 | `Party360Screen` – unified timeline list | P1.2, P1.3 | 4h |
| P2.3 | `CashFlowScreen` – full screen with month nav | P1.5 | 5h |
| P2.4 | Action Center multi-select mode | `actionCenterProvider` | 3h |
| P2.5 | `BulkReminderService` | P2.4 | 2h |

### Phase 3 — Polish & wiring (Week 3) `~2 days`

| ID | Task | Depends on | Effort |
|----|------|-----------|--------|
| P3.1 | Party FK backfill in AddCreditScreen + Loan form | P1.2 | 2h |
| P3.2 | Party search shows net outstanding in autocomplete | P1.3 | 2h |
| P3.3 | Consolidated Party Statement PDF | P2.1, P2.2 | 3h |
| P3.4 | Cash Flow → Reports tab integration | P2.3 | 1h |
| P3.5 | `flutter analyze` + widget tests for new screens | all | 3h |

**Total estimated:** ~38 hours across 3 weeks.

---

## File Map

```
lib/
├── data/
│   ├── models/
│   │   ├── party_financial_summary.dart   ← NEW (P1.1)
│   │   └── cash_flow_event.dart           ← NEW (P1.4)
│   ├── repositories/
│   │   └── (extensions to existing repos) ← MODIFY (P1.2)
│   └── services/
│       ├── bulk_reminder_service.dart     ← NEW (C2)
│       └── party_statement_service.dart   ← NEW (C3)
├── presentation/
│   ├── providers/
│   │   ├── party_financial_provider.dart  ← NEW (P1.3)
│   │   └── cash_flow_provider.dart        ← NEW (P1.5)
│   └── screens/
│       ├── parties/
│       │   └── party_360_screen.dart      ← NEW (P2.1, P2.2)
│       ├── reports/
│       │   └── cash_flow_screen.dart      ← NEW (P2.3)
│       └── home/
│           └── action_center_screen.dart  ← MODIFY (P2.4)
```

---

## Privacy Compliance Checklist

All three pillars are **100% on-device**:

- [x] `PartyFinancialSummary` — in-memory aggregation of local SQLite tables
- [x] `CashFlowEvent` — in-memory merge using existing local providers
- [x] `BulkReminderService` — OS WhatsApp deep-link (no READ_CONTACTS, no network)
- [x] Party Statement PDF — generated locally using `pdf` package, shared via OS share sheet
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

---

## Success Metrics (in-app, no analytics)

These can be verified manually during QA:

- Party 360°: opening any party with >0 open invoices shows correct `netOutstanding`
- Cash Flow: today's divider lands correctly; tapping an upcoming event navigates to its source screen
- Bulk Remind: selecting 3 items → "Remind All" opens 3 WhatsApp pre-fills in sequence
- `flutter analyze`: 0 new errors after all phases complete
