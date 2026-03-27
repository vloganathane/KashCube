# Unified Tracking & Management System

> **Authored:** 7 March 2026  
> **Updated:** 7 March 2026  
> **Status:** Phase 1 ✅ · Phase 2 ✅ · Phase 3 ⚠️ (2 partial tasks remaining)  
> **Scope:** Four complementary pillars that weave KashCube's siloed modules
> into a single, coherent financial picture per party and across time, backed
> by a shared Lifecycle Layer used across all pillars.

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
| Quote accepted → Invoice never raised; Challan dispatched → Invoice never converted | Revenue leakage — money earned but never billed |

---

## Four Pillars + Shared Lifecycle Layer

```
┌────────────────────┬────────────────────┬────────────────────┬────────────────────┐
│  Pillar A          │  Pillar B          │  Pillar C          │  Pillar D          │
│  Party 360°        │  Cash Flow         │  Bulk Actions      │  Business Flow     │
│  (who owes what)   │  Timeline          │  (work at scale)   │  Tracker           │
│                    │  (when does it     │                    │  (deal chain       │
│                    │   land)            │                    │   Q→I→T)           │
│  Effort: Medium    │  Effort: Small     │  Effort: Small     │  Effort: Small*    │
│  Value:  ★★★★★     │  Value:  ★★★★      │  Value:  ★★★★      │  Value:  ★★★★★     │
└────────────────────┴────────────────────┴────────────────────┴────────────────────┘
* FK links already exist in DB — no migration needed for MVP

         ╔══════════════════════════════════════════════════════════╗
         ║  Shared Lifecycle Layer  (used by ALL four pillars)     ║
         ║  LifecycleClassifier · LifecycleInfo · LifecycleTag     ║
         ║  Covers: Invoice · Due · Loan · Bill · Booking · Chain  ║
         ╚══════════════════════════════════════════════════════════╝
```

The four pillars are **independent** — each can ship without the others. They share
the `PartyFinancialSummary` model (Pillar A used by Pillar C). The **Shared Lifecycle
Layer** is not a pillar but a set of utilities (`LifecycleClassifier`, `LifecycleInfo`,
`LifecycleTag`) consumed by all four pillars:
- **Pillar A** (Party 360°): `LifecycleTag` on each item in the unified timeline
- **Pillar B** (Cash Flow): stage subtitle on each event tile
- **Pillar C** (Bulk Actions): stale-item filter and context-aware button labels
- **Pillar D** (Business Flow): `LifecycleTag` on Invoice nodes inside `FlowChainTile`;
  standalone Dues/Loans/Bills (which have no chain) also use it in Action Center tiles

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

## Shared Lifecycle Layer

> Not a pillar — a set of **shared utilities** consumed by all four pillars.
> Handles the single question: *"How long has this item been in its current stage,
> and what should happen next?"*
>
> For **Invoice nodes inside a chain** (Pillar D): `FlowChainTile` calls
> `LifecycleClassifier.forInvoice()` to annotate each chain step.
> For **standalone items with no chain** — Dues, Loans, Bills — `_ActionItemTile`
> in Action Center calls the same classifier directly.

### Stage machines

```
Invoice:  draft → sent → reminded → partiallyPaid → paid
                                      ↓ if past due date at any stage
                                    overdue

Due/Credit: active → reminded → partial → cleared
                     ↓ if past due date
                   overdue

Loan:     active → paying (paidEmis > 0) → overdue → cleared

Bill:     active → upcoming (≤7 days) → overdue → paid

Booking:  pending → confirmed → [service date] → completed / noShow
```

The **age in current stage** (`daysInStage`) is the key metric for prioritisation.

### Existing fields that drive computed stages

| Source | Fields used |
|--------|-------------|
| `Invoice` | `status`, `reminderSentAt`, `paidAmount`, `dueDate`, `updatedAt` |
| `Credit` | `isCleared`, `isOverdue`, `dueDate`, `pendingAmount`, `createdAt` |
| `Loan` | `isCleared`, `isOverdue`, `paidEmis`, `nextEmiDate`, `dueDate`, `updatedAt` |
| `ScheduledPayment` | `lastPaidDate`, `nextDate`, `isActive` |
| `party_reminders` | `sent_at` per party (closest proxy for "last reminded") |

### Design decision: computed vs stored

| Approach | Pro | Con |
|----------|-----|-----|
| **Computed** (MVP) | Zero DB migration, ship in days | Cannot store custom stage overrides |
| **Stored** — add `lifecycle_stage` + `last_action_at` columns | Persistent, queryable, allows override | Requires DB migration (v45+) |

**Ship computed MVP.** Add stored columns only if users request manual override.

### What needs building

#### LC1 — `LifecycleStage` enum + `LifecycleInfo` value class

```dart
// lib/data/models/lifecycle_info.dart
enum LifecycleStage {
  draft, active, sent, reminded, partiallyPaid, overdue, paying, cleared, paid,
}

class LifecycleInfo {
  final LifecycleStage stage;
  final int daysInStage;         // days since last stage transition
  final DateTime? lastActionAt;  // last reminder or payment event
  final String? lastActionLabel; // "Reminded via WhatsApp", "₹5,000 received"
  final String? nextActionHint;  // "Send a reminder" / "Record payment"
}
```

#### LC2 — `LifecycleClassifier` (pure Dart, no DB access)

```dart
// lib/core/utils/lifecycle_classifier.dart
// Pure functions — no async, no DB — safe to call inside build().
class LifecycleClassifier {
  static LifecycleInfo forInvoice(Invoice inv, {DateTime? lastReminderAt});
  static LifecycleInfo forCredit(Credit c, {DateTime? lastReminderAt});
  static LifecycleInfo forLoan(Loan l);
  static LifecycleInfo forBill(ScheduledPayment p);
  static LifecycleInfo forBooking(Booking b);
}
```

#### LC3 — `LifecycleTag` widget

```dart
// lib/presentation/widgets/lifecycle_tag.dart
// LifecycleTag(info: lifecycleInfo)
// Renders: [ SENT · 14d ]  [ OVERDUE · 7d ]  [ REMINDED · 2d ]
// Colour-coded. Optional expandedMode = true → stage progress dots.
```

#### LC4 — Integration points

| Consumer | Where | Context |
|----------|-------|---------|
| `_ActionItemTile` (Action Center) | Below party name — for standalone Dues/Loans/Bills AND chain-invoice items | `LifecycleClassifier.forX(item)` |
| `FlowChainTile` (Pillar D) | Invoice step node inside deal chain | `LifecycleClassifier.forInvoice(inv)` |
| `InvoiceDetailScreen` | Header section | `LifecycleClassifier.forInvoice(inv, lastReminderAt: ...)` |
| `Party360Screen` (Pillar A) | Each item in unified timeline | `LifecycleClassifier.forX(item)` |
| `CashFlowScreen` (Pillar B) | Event tile subtitle | `LifecycleClassifier.forX(item)` |

#### LC5 — Context-aware action button labels in Action Center

| Stage | Button label |
|-------|--------------|
| `sent` + >7 days | **Send Reminder** (amber) |
| `reminded` + >3 days | **Follow Up** (orange) |
| `overdue` | **Collect Now** (red) |
| `partiallyPaid` | **Record Balance** (primary) |
| `active` + due in 3d | **View** (neutral) |

#### LC6 — "Stale Items" filter chip in Action Center

Applies to **all** `ActionItem` types including chain-linked and standalone:

```dart
// [All]  [To Collect]  [To Pay]  [Stale ●]
// "Stale" = lifecycle.daysInStage > kDefaultStallThreshold (default 7)
const int kDefaultStallThreshold = 7;
```

Stale items also receive an amber left-border in Party 360°'s unified timeline.

---

## Pillar D — Business Flow Tracker

### Goal
Every sale has a **chain**: it starts somewhere (Quote / Challan / Booking /
direct Invoice) and ends with cash received (Transaction). Pillar D makes that
chain visible, surfacing deals that are **stuck mid-chain** — accepted quotes
never invoiced, dispatched challans never converted, services delivered but
never billed.

```
── Chain types ─────────────────────────────────────────────────────

  TYPE 1 — Quote chain
  Quote (draft) → sent → accepted → Invoice (sent) → reminded → Transaction
                                 ↓ if accepted but no Invoice
                               ⚠ REVENUE LEAKAGE (E5 orphan)

  TYPE 2 — Delivery Challan chain
  Challan (draft) → dispatched → converted → Invoice → reminded → Transaction
                              ↓ if dispatched but no Invoice after N days
                            ⚠ REVENUE LEAKAGE

  TYPE 3 — Booking chain
  Booking (pending) → confirmed → [service date] → Invoice → Transaction
                                                 ↓ if service date past, no Invoice
                                               ⚠ REVENUE LEAKAGE

  TYPE 4 — Direct Invoice chain
  Invoice (draft) → sent → reminded → partially paid → Transaction(s)

────────────────────────────────────────────────────────────────────
```

### FK audit — what already exists

| Link | Field | Status |
|------|-------|--------|
| Invoice knows its Quote origin | `Invoice.quoteId` (int?) | ✅ exists |
| Invoice knows its Challan origin | `Invoice.challanId` (int?) | ✅ exists |
| Challan knows if it was invoiced | `DeliveryChallan.convertedInvoiceId` (int?) + `isConverted` getter | ✅ bidirectional |
| Booking knows its Invoice | `Booking.invoiceId` (int?) | ✅ exists |
| Transaction knows its Invoice | `Transaction.linkedInvoiceId` (int?) | ✅ exists |
| Transaction knows its Booking | `Transaction.linkedBookingId` (int?) | ✅ exists |
| Quote knows its Invoice | via query `SELECT * FROM invoices WHERE quote_id = ?` | ✅ queryable |

> **No DB migration needed for MVP.** All FK columns are already in production.

### What a chain looks like in the UI

```
┌─ Deal Chain — Rajesh Traders ─────────────────────────── ⚠ Action needed ─┐
│                                                                              │
│  Quote #Q-042       ✅ Accepted   28 Feb       ₹85,000                       │
│       │                                                                      │
│       ▼                                                                      │
│  Invoice #INV-0051  🔴 Overdue    5 Mar        ₹85,000   [Send Reminder]    │
│       │                                                                      │
│       ▼                                                                      │
│  Payment            ⏳ Awaited    —            ₹85,000                       │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────── │
│  Challan #DC-017    ✅ Dispatched  4 Mar        ₹12,000                       │
│       │                                                                      │
│       ▼                                                                      │
│  Invoice            ⚠️  NOT RAISED yet          ₹12,000   [Convert Now →]   │
└──────────────────────────────────────────────────────────────────────────── ┘
```

### What needs building

> Invoice nodes inside a `FlowChainTile` use `LifecycleClassifier.forInvoice()`
> from the Shared Lifecycle Layer to render their stage pill and `daysInStage`.
> Standalone Dues/Loans/Bills that have **no chain** are handled by the same
> classifier directly in `_ActionItemTile` — no duplication.

#### E1 — `BusinessFlowChain` model

```dart
// lib/data/models/business_flow_chain.dart
enum ChainOrigin { quote, challan, booking, directInvoice }
enum ChainStatus {
  complete,           // Invoice paid + Transaction linked
  awaitingPayment,    // Invoice sent/overdue, no transaction yet
  awaitingInvoice,    // Origin doc exists, no invoice raised — REVENUE LEAKAGE
  invoicedPartially,  // partiallyPaid
  cancelled,          // Quote rejected / Booking cancelled / Challan returned
}

class BusinessFlowChain {
  final ChainOrigin origin;
  final ChainStatus status;
  final int partyId;
  final String partyName;

  // Source document (exactly one is non-null)
  final Quote? quote;
  final DeliveryChallan? challan;
  final Booking? booking;

  // Downstream (may be null if not yet raised)
  final Invoice? invoice;
  final List<Transaction> transactions;

  // Derived
  final double totalValue;
  final double receivedAmount;   // sum of linked transaction amounts
  final double outstandingAmount; // totalValue - receivedAmount
  final int daysSinceOrigin;     // days since source doc was created/accepted
  final bool isLeaking;          // awaitingInvoice — origin done, nothing billed

  // Reminder/notification history (from party_reminders filtered by date range)
  final List<ReminderRecord> reminders;
}
```

#### E2 — `businessFlowChainsProvider(int partyId)`

> Renamed task IDs E1–E6 retained below for traceability to implementation sequence.

```dart
// lib/presentation/providers/business_flow_provider.dart
final businessFlowChainsProvider =
    FutureProvider.family<List<BusinessFlowChain>, int>((ref, partyId) async {
  // All queries are parallel — all local SQLite
  final [quotes, challans, bookings, invoices, transactions] = await Future.wait([
    ref.read(quoteRepositoryProvider).getByPartyId(partyId),
    ref.read(challanRepositoryProvider).getByPartyId(partyId),
    ref.read(bookingRepositoryProvider).getByPartyId(partyId),
    ref.read(invoiceRepositoryProvider).getByPartyId(partyId),   // P1.2 — already planned
    ref.read(transactionRepositoryProvider).getByPartyId(partyId),
  ]);
  return BusinessFlowChainBuilder.build(
    quotes: quotes, challans: challans, bookings: bookings,
    invoices: invoices, transactions: transactions,
  );
});

// Global orphan provider — all parties, all leaking chains
final leakingChainsProvider = FutureProvider<List<BusinessFlowChain>>((ref) async {
  // Queries:
  // 1. Quotes: status = accepted, no matching invoice (quote_id not in invoices)
  // 2. Challans: status = dispatched, convertedInvoiceId IS NULL, dispatched > N days ago
  // 3. Bookings: status = confirmed/completed, invoiceId IS NULL, serviceDate < today
  ...
});
```

#### E3 — `BusinessFlowChainBuilder` (pure Dart, no DB)

```dart
// lib/core/utils/business_flow_chain_builder.dart
// Pure function: given raw lists, assembles chains by matching FK links.
// Quote → find Invoice where invoice.quoteId == quote.id
//       → find Transactions where transaction.linkedInvoiceId == invoice.id
// Challan → find Invoice where challan.convertedInvoiceId == invoice.id (or invoice.challanId)
// Booking → invoice.id == booking.invoiceId
//         → also transaction.linkedBookingId == booking.id
// Unmatched Invoices (quoteId == null && challanId == null &&
//   no booking.invoiceId points to it) → TYPE 4 direct
class BusinessFlowChainBuilder {
  static List<BusinessFlowChain> build({...});
}
```

#### E4 — `FlowChainTile` widget

A collapsible card showing the full chain vertically:
```
[origin icon + doc no + date]  →  [invoice status + LifecycleTag]  →  [payment status]
```
Used in Party 360°'s new "Deals" tab. The Invoice step node renders a `LifecycleTag`
pill (e.g. `[ OVERDUE · 7d ]`) sourced from LC2/LC3 in the Shared Lifecycle Layer.

#### E5 — Revenue Leakage Alert in Action Center

New `ActionItemType.leakingChain` in the existing `ActionItem` enum:
- Accepted quotes with no invoice > 3 days
- Dispatched challans with no invoice > 2 days
- Completed bookings with no invoice > 1 day
- Surfaces in Action Center under a new **"Leaking"** urgency section (distinct
  from Overdue — CTA is "Raise Invoice", not "Remind")
- Leaking items are **also** shown by the LC6 Stale filter if `daysInStage > 7`

```dart
enum ActionItemType {
  invoice,
  dues,
  bill,
  loanEmi,
  leakingChain,   // ← NEW (E5)
}
```

#### E6 — Reminder / notification event nodes in chain

Each reminder from `party_reminders` that falls within the chain's date window
is inserted as an event node between Invoice and Transaction:

```
Invoice #INV-0051  sent 5 Mar
    │
    ├── 📱 Reminder sent via WhatsApp  6 Mar
    ├── 📱 Follow-up sent              8 Mar
    │
    ▼
Payment  ⏳ Awaited
```

No new data — filtered from existing `party_reminders` rows by `sent_at` timestamp.

### Chain completion state machine summary

```
Quote:    draft → sent → accepted ─────────────────────────────────────────────────────────►─┐
                           │                                                                   │
                        [raise invoice]                                                        │
                           │                                                                  ⚠️
                           ▼                                                             ORPHAN if
Challan:  draft → dispatched ──────[convert to invoice]──────────────────────────────►  no invoice
                                        │                                              within N days
                                        ▼
Booking:  pending → confirmed ─────[raise invoice] ──────────────────────────────────►────────┤
                                        │
Direct:                                 │
                                        ▼
                             Invoice: draft → sent → [remind×N] → partiallyPaid → paid
                                                                                      │
                                                                                      ▼
                                                                           Transaction(s) linked
                                                                           ══ CHAIN COMPLETE ══
```

### Decisions required

| # | Question | Recommendation |
|---|----------|----------------|
| D-Q1 | Should `QuoteRepository.getByPartyId()` be added (new method on existing repo)? | Yes — same pattern as P1.2 for Invoice/Credit/Loan |
| D-Q2 | Threshold for "dispatched challan with no invoice" = how many days? | 2 days (configurable later) |
| D-Q3 | Should `leakingChainsProvider` appear as a dedicated "Leaking" section in Action Center, or fold into the existing Overdue section? | Dedicated section — visually distinct, different CTA ("Raise Invoice" not "Remind") |
| D-Q4 | One `FlowChainDetailScreen` or chain shown inline in Party 360°? | Inline in Party 360° Deals tab; `FlowChainDetailScreen` only for Action Center tap-through |

---

## Implementation Sequence

### Phase 1 — Foundation (Week 1) `~3 days` ✅ COMPLETE

| ID | Task | Depends on | Effort | Status |
|----|------|-----------|--------|--------|
| P1.1 | `PartyFinancialSummary` model + `compute()` factory | — | 2h | ✅ |
| P1.2 | Repository methods: `getByPartyId` on Invoice/Credit/Loan/Txn | — | 3h | ✅ |
| P1.3 | `partyFinancialSummaryProvider(int partyId)` | P1.1, P1.2 | 2h | ✅ |
| P1.4 | `CashFlowEvent` sealed class | — | 1h | ✅ |
| P1.5 | `cashFlowTimelineProvider` | P1.4 | 3h | ✅ |
| P1.6 | DB migration v45: add `party_id` column to `scheduled_payments` | — | 1h | ✅ |
| P1.7 | `BookingRepository.getByPartyId(int id)` + wire into `partyFinancialSummaryProvider` | P1.1 | 1h | ✅ |
| P1.8 | `QuoteRepository.getByPartyId(int id)` + `ChallanRepository.getByPartyId(int id)` | — | 1h | ✅ |

### Phase 2 — Core screens (Week 2) `~4 days` ✅ COMPLETE

| ID | Task | Depends on | Effort | Status |
|----|------|-----------|--------|--------|
| P2.1 | `Party360Screen` – header + summary chips | P1.3 | 4h | ✅ |
| P2.2 | `Party360Screen` – unified timeline list | P1.2, P1.3 | 4h | ✅ |
| P2.3 | `CashFlowScreen` – full screen with month nav | P1.5 | 5h | ✅ |
| P2.4 | Action Center multi-select mode | `actionCenterProvider` | 3h | ✅ |
| P2.5 | `BulkReminderService` | P2.4 | 2h | ✅ |
| P2.6 | Navigation hooks: Party detail → Party360Screen; tap party name in `_ActionItemTile` → Party360Screen | P2.1 | 2h | ✅ |
| P2.7 | Add Cash Flow entry to Reports screen (prominent card → `CashFlowScreen`) | P2.3 | 1h | ✅ |
| P2.8 | `BusinessFlowChainBuilder` pure utility (E3) | P1.8 | 2h | ✅ |
| P2.9 | `businessFlowChainsProvider` + `leakingChainsProvider` (E2) | P2.8, P1.2, P1.7 | 3h | ✅ |
| P2.10 | `FlowChainTile` widget + "Deals" tab in Party360Screen (E4) | P2.1, P2.9 | 3h | ✅ |

### Phase 3 — Polish, wiring & Lifecycle Layer (Week 3) `~3 days` ⚠️ 1 task partial

| ID | Task | Depends on | Effort | Status |
|----|------|-----------|--------|--------|
| P3.1 | Party FK backfill in AddCreditScreen + Loan form | P1.2 | 2h | ✅ |
| P3.2 | Party search shows net outstanding in autocomplete | P1.3 | 2h | ✅ |
| P3.3 | Consolidated Party Statement PDF | P2.1, P2.2 | 3h | ✅ |
| P3.4 | Cash Flow → Reports tab integration | P2.3 | 1h | ✅ |
| P3.5 | `LifecycleStage` enum + `LifecycleInfo` value class (LC1) | — | 2h | ✅ |
| P3.6 | `LifecycleClassifier` pure utility (LC2) | P3.5 | 3h | ✅ |
| P3.7 | `LifecycleTag` widget (LC3) | P3.5 | 2h | ✅ |
| P3.8 | Wire `LifecycleTag` into Action Center tiles, InvoiceDetailScreen, FlowChainTile invoice node (LC4) | P3.6, P3.7, P2.10 | 3h | ✅ ActionCenter ✅ InvoiceDetail ✅ FlowChainTile ✅ Party360Screen timeline ✅ CashFlowScreen tiles ✅ |
| P3.9 | Context-aware action button labels in `_ActionItemTile` (LC5) | P3.6 | 1h | ✅ |
| P3.10 | "Stale Items" filter chip in Action Center + amber border in Party360 timeline (LC6) | P3.6 | 2h | ✅ filter chip ✅ amber left-border in Party360 timeline ✅ |
| P3.11 | Revenue Leakage alerts in Action Center — `ActionItemType.leakingChain` (E5) | P2.9 | 3h | ✅ |
| P3.12 | Reminder event nodes woven into chain display (E6) | P2.10 | 2h | ✅ |
| P3.13 | `flutter analyze` + widget tests for all new code | all | 3h | ⚠️ flutter analyze 0 errors ✅ · widget tests ❌ (not written) |

**Total estimated:** ~71 hours across 3 weeks.

> The Shared Lifecycle Layer (LC1–LC6) is built last so it can integrate into
> the Party 360°, Action Center, and Business Flow screens shipped in Phase 2.

---

## File Map

```
lib/
├── core/
│   └── utils/
│       ├── lifecycle_classifier.dart          ← NEW (LC2)  — Shared Lifecycle Layer
│       └── business_flow_chain_builder.dart   ← NEW (E3)   — Pillar D
├── data/
│   ├── models/
│   │   ├── party_financial_summary.dart       ← NEW (P1.1) — Pillar A
│   │   ├── cash_flow_event.dart               ← NEW (P1.4) — Pillar B
│   │   ├── lifecycle_info.dart                ← NEW (LC1)  — Shared Lifecycle Layer
│   │   └── business_flow_chain.dart           ← NEW (E1)   — Pillar D
│   ├── repositories/
│   │   └── (extensions to existing repos)     ← MODIFY (P1.2, P1.7, P1.8)
│   └── services/
│       ├── bulk_reminder_service.dart         ← NEW (C2)   — Pillar C
│       └── party_statement_service.dart       ← NEW (C3)   — Pillar C
├── presentation/
│   ├── providers/
│   │   ├── party_financial_provider.dart      ← NEW (P1.3) — Pillar A
│   │   ├── cash_flow_provider.dart            ← NEW (P1.5) — Pillar B
│   │   └── business_flow_provider.dart        ← NEW (E2)   — Pillar D
│   ├── widgets/
│   │   ├── lifecycle_tag.dart                 ← NEW (LC3)  — Shared Lifecycle Layer
│   │   └── flow_chain_tile.dart               ← NEW (E4)   — Pillar D
│   └── screens/
│       ├── parties/
│       │   ├── party_360_screen.dart           ← NEW (P2.1, P2.2)
│       │   └── flow_chain_detail_screen.dart   ← NEW (E4)
│       ├── reports/
│       │   └── cash_flow_screen.dart           ← NEW (P2.3)
│       └── home/
│           └── action_center_screen.dart       ← MODIFY (P2.4, LC4, LC5, LC6, E5)
```

---

## Privacy Compliance Checklist

All four pillars + the Shared Lifecycle Layer are **100% on-device**:

- [x] `PartyFinancialSummary` — in-memory aggregation of local SQLite tables
- [x] `CashFlowEvent` — in-memory merge using existing local providers
- [x] `BulkReminderService` — OS WhatsApp deep-link (no READ_CONTACTS, no network)
- [x] Party Statement PDF — generated locally using `pdf` package, shared via OS share sheet
- [x] `LifecycleClassifier` / `LifecycleTag` (Shared Lifecycle Layer) — pure in-memory computation; display only; no DB writes in MVP
- [x] `BusinessFlowChainBuilder` — pure in-memory join of local model lists; no network, no new permissions
- [x] `leakingChainsProvider` — SQL queries on existing tables with no new columns required
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

5. **Lifecycle stage override** (Shared Lifecycle Layer): Should users be able
   to manually set a stage (e.g. mark an invoice as "sent" even though
   `status = draft`)?
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
- Shared Lifecycle Layer: an invoice in `sent` status with `updatedAt` 14 days ago shows `LifecycleStage.sent` and `daysInStage = 14`; `_ActionItemTile` button shows "Send Reminder" not "View"
- Shared Lifecycle Layer: `LifecycleTag` renders correctly on a chain Invoice node inside `FlowChainTile` (Pillar D) AND on a standalone Due in `_ActionItemTile` — same widget, same classifier, different call site
- Shared Lifecycle Layer: a fully paid invoice shows `LifecycleStage.paid` — no tag rendered in Action Center (paid items are filtered out)
- Bookings: party with 1 confirmed booking shows `activeBookings = 1` and advance in `bookingsPending`; `netOutstanding` reflects the subtracted advance
- Stale filter: Action Center "Stale" chip shows only items where `daysInStage > 7`; chip badge is hidden when 0 items match
- Business Flow: a Quote with `status = accepted` and no matching invoice shows in Action Center "Leaking" section with CTA "Raise Invoice"
- Business Flow: `BusinessFlowChainBuilder.build()` correctly assembles Quote→Invoice→Transaction chain using FK links without any DB migration
- Business Flow: Party 360° "Deals" tab shows all chain types; `FlowChainTile` renders reminder event nodes between Invoice and Transaction steps
- `flutter analyze`: 0 new errors after all phases complete
