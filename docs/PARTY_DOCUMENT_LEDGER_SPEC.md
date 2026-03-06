# Party Document Ledger — Specification

## Overview

The Party Document Ledger extends the **Party Detail screen** into a full commercial-relationship view.  
When you open any party (customer / vendor / lender), you see not only cash transactions but also every Invoice, Quote, Delivery Challan (DC), and Booking tied to that party — grouped, filterable, and summarised.

Three complementary views are provided:

| Option | Location | Scope |
|--------|----------|-------|
| **A** | Activity tab → filter chips | Filter the unified timeline by document type |
| **B** | Documents tab in Party Detail | Dedicated tab: Outstanding Balance card + commercial docs |
| **C** | Business Hub → Party Document Ledger | Global cross-party view of all documents |

---

## Option A — Activity Tab Filter Chips

**Where:** Existing "Activity" tab (formerly the single unified list).

**Filter bar** (horizontal scroll row of `FilterChip`s):

```
[ All | Transactions | Invoices | Quotes | DC | Bookings ]
```

- Default selection: **All**
- Tapping a chip hides all other item types
- The `_DocFilter` enum drives this via local `StatefulWidget` state (no provider needed — page-level ephemeral)
- Empty state shown per filter: e.g. "No invoices for {party} yet."

**Enum values:**

```dart
enum _DocFilter { all, transactions, invoices, quotes, dc, bookings }
```

---

## Option B — Documents Tab

**Where:** Second tab in `PartyDetailScreen` (alongside existing Activity tab).

### Outstanding Balance Card

Shown at the top of the Documents tab:

```
┌─────────────────────────────────────────────────┐
│  Outstanding Balance                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────┐ │
│  │ Invoiced │ │  Paid    │ │  Balance │ │Over│ │
│  │ ₹1,50,000│ │ ₹75,000 │ │ ₹75,000 │ │due │ │
│  └──────────┘ └──────────┘ └──────────┘ └────┘ │
└─────────────────────────────────────────────────┘
```

**Calculations (from invoices only):**

| Metric | Formula |
|--------|---------|
| Total Invoiced | `sum(invoice.total)` for all invoices |
| Total Paid | `sum(invoice.paidAmount)` for all invoices |
| Outstanding | `sum(invoice.balanceDue)` where `status != paid` |
| Overdue | `sum(invoice.balanceDue)` where `dueDate < today AND status != paid` |

Note: Quotes and DCs are explicitly excluded from monetary totals since they are not yet tax invoices. Bookings contribute separately via `booking.paidAmount` vs `booking.totalAmount`.

### Documents Section

Below the Outstanding Balance card:

**Filter chips:**
```
[ All | Invoices | Quotes | DC | Bookings ]
```

Each document type renders its own tile:

| Type | Tile content |
|------|-------------|
| Invoice | Invoice no · date · status chip · `₹total` / `₹balance due` |
| Quote | Quote no · date · status chip · `₹total` |
| DC | Challan no · date · status chip · item count |
| Booking | Service · date/time · status chip · `₹total` |

Tap → navigate to respective detail screen.

---

## Option C — Global Party Document Ledger

**Where:** Business Hub → "Party Document Ledger" tile under Documents section.

### Screen: `GlobalDocumentLedgerScreen`

Groups all commercial documents by party with an expandable/collapsible list.

**Header summary row:**
```
X parties · Y open invoices · ₹Z outstanding
```

**Per-party section:**
```
▼  Raj Trading Co                    ₹45,000 due
     3 Invoices  · 2 Quotes  · 1 DC  · 0 Bookings
     [Open]
```

**Tapping "Open"** navigates to `PartyDetailScreen(party: party)` which opens directly on the Documents tab.

**Filter bar** at screen level:
```
[ All parties | Customers | Vendors | Has Balance ]
```

**Sort options:** Most Recent · Highest Balance · Alphabetical

---

## Data Layer Changes

### New repository methods added

#### `QuoteRepository`
```dart
Future<List<Quote>> getByCustomer(String customerName);
```
SQL: `SELECT * FROM quotes WHERE customer_name = ? ORDER BY created_at DESC`

#### `DeliveryChallanRepository`
```dart
Future<List<DeliveryChallan>> getByCustomer(String customerName);
```
SQL: `SELECT * FROM delivery_challans WHERE customer_name = ? ORDER BY created_at DESC`

### New Riverpod providers

| Provider | Type | Purpose |
|----------|------|---------|
| `quotesByCustomerProvider` | `FutureProvider.family<List<Quote>, String>` | Quotes for one party |
| `challansByCustomerProvider` | `FutureProvider.family<List<DeliveryChallan>, String>` | DCs for one party |

### Extended `_partyHistoryFutureProvider`

Added `DeliveryChallan` to the parallel fetch so the unified history includes DCs.

### Sealed class addition — `DeliveryChallanHistoryItem`

```dart
class DeliveryChallanHistoryItem extends PartyHistoryItem {
  DeliveryChallanHistoryItem(this.challan);
  final DeliveryChallan challan;
  
  @override
  DateTime get date => challan.createdAt ?? DateTime.now();
}
```

---

## Navigation

```
PartyDetailScreen
  ├── Tab 0: Activity   (unified timeline + filter chips — Option A)
  └── Tab 1: Documents  (outstanding balance + doc list — Option B)

BusinessHubScreen → Documents section
  ├── Invoices & Quotes  →  InvoicesScreen
  ├── Delivery Challans  →  DeliveryChallansScreen
  ├── Bookings           →  BookingsScreen
  └── Party Doc Ledger   →  GlobalDocumentLedgerScreen  ← NEW (Option C)
```

---

## UI / UX Notes

- **Colour coding in filter chips:** Use per-type accent colours (invoice=blue, quote=teal, DC=orange, booking=purple) to visually distinguish document types.
- **Empty states:** Each filter shows a meaningful empty-state message with a CTA:
  - "No invoices for {party} yet — Create Invoice"
- **Outstanding badge:** When a party has overdue invoices, a red badge shows on the Documents tab.
- **Touch targets:** All list tiles ≥ 48dp. Status chips are non-interactive (display only).
- **Indian locale:** All currency values use `CurrencyFormatter.formatCompact()` or `formatIndianCurrency()`.

---

## Privacy

All data is fetched from local SQLite only. No network calls, no analytics. The Outstanding Balance card is computed client-side from existing invoice rows.

---

## Testing Checklist

- [ ] Filter chips correctly hide/show document types
- [ ] Outstanding = 0 when all invoices are paid (status=paid)
- [ ] Overdue count = 0 when no invoices are past due date
- [ ] `getByCustomer` for Quote returns empty list for party with no quotes
- [ ] `getByCustomer` for DC returns empty list for party with no challans
- [ ] Global ledger "Has Balance" filter shows only parties with outstanding > 0
- [ ] Tapping "Open" on Global Ledger opens PartyDetailScreen on Documents tab
- [ ] Dark mode colours correct (use semantic tokens)
- [ ] Indian number formatting across all monetary values

---

## Future Enhancements (Post-MVP)

- Export per-party statement as PDF (invoices + payments)
- Filter by date range in Documents tab
- Multi-select for batch reminders
- Booking ↔ Invoice auto-link display
