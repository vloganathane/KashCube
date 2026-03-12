# Feature Extension Principles

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** Design Reference

---

## Core Idea

New features in KashCube should be **extensions of the existing base**, not isolated islands.  
Every feature added from scratch re-invents search, reporting, PDF export, party linking, and
backup. Every feature built on the base gets all of that for free.

---

## The KashCube Base Layer

These primitives are already fully built and should be the first port of call for any new feature:

| Primitive | What it gives you |
|---|---|
| **Parties** | Any person/entity in the system — customer, vendor, lender, staff. Linked to transactions, credits, invoices, reminders. |
| **Transactions** | The financial record of anything money-in/money-out. Category + party + business scoped. Powers all reports. |
| **Credits / Ledger** | Tracks money owed between parties over time. Works for customer udhar, supplier advance, staff loans. |
| **Item Catalog** | Products and services with pricing, HSN/SAC, stock. Reusable across invoices, quotes, bookings, purchase orders. |
| **Invoices / Quotes** | Full document model with line items, tax, PDF render, share. A "payslip" or "PO" is an invoice with a different `invoice_type`. |
| **Businesses** | Every piece of data is `business_id`-scoped. Multi-business is already handled everywhere. |
| **Categories** | Transactions are categorised. A new module just needs a new category value — not a new table. |

---

## Design Rules for New Features

### 1. Data First — Can an Existing Table Be Extended?

Before creating a new table, ask:

- Can a **new `type` / `category` value** on an existing table represent this data?
- Can **1–2 new nullable columns** on a party, transaction, or item row carry the new semantics?
- Will a new table genuinely be queried independently, or does it only make sense alongside an existing entity?

**Good:** `parties.salary_amount`, `parties.role` — Staff is a Party sub-type.  
**Bad:** A separate `staff` table that duplicates name, phone, business_id, and party linkage.

### 2. Transactions Are the Financial Record

Any money movement the new feature produces (salary payout, supplier payment, advance, refund,
commission) **must** be a `Transaction`. This is non-negotiable — it ensures:

- It appears in expense/income reports automatically.
- Budget tracking works.
- The home screen summary is always correct.
- Export / backup covers it.

### 3. Party Linking

Every feature that involves a person/company should link to a `Party`. Avoid storing names as
free text in new tables. If the party type doesn't exist yet, add a `PartyType` enum value.

### 4. UI Providers Are Filters, Not New State

New screens should consume existing Riverpod providers with additional filter parameters
(e.g. `transactionsProvider(filter: TransactionFilter(category: 'Payroll', partyId: staffId))`)
rather than standing up entirely new state trees.

### 5. Documents Are Invoice Variants

If the new feature needs to produce a printable/shareable document (payslip, purchase order,
delivery note, expense report), model it as a new `invoice_type` value. The existing PDF
rendering, preview, and share infrastructure works immediately.

---

## Staff & Payroll — Redesign Example

The original implementation created a separate `staff` + `salary_payments` table.  
Here is how it should be rebuilt using the base:

### Data model

| Concept | KashCube base | New columns only |
|---|---|---|
| Staff member | `Party(type: staff)` | `salary_amount REAL`, `role TEXT`, `join_date TEXT` on `parties` |
| Monthly salary paid | `Transaction(type: expense, category: 'Payroll', party_id: staff.id)` | — |
| Salary advance | `Credit(direction: given, party_id: staff.id)` | — |
| Payslip document | Invoice with `invoice_type = 'payslip'`, `customer_party_id = staff.id` | — |

### What this unlocks for free

- Staff appear in party search and autocomplete.
- Salary transactions appear in monthly expense reports and budget tracking.
- Payslip PDF uses the existing invoice PDF renderer.
- Advances use the existing credit/ledger screen — overdue alerts, clearing, history.
- All data is business-scoped and backed up automatically.

### Screen structure

```
Business Hub → Staff
  └── StaffListScreen
        (query: partiesProvider filtered by PartyType.staff)
        └── StaffDetailScreen(partyId)
              ├── Profile tab  (name, role, salary, join date)
              ├── Payments tab (transactionsProvider filtered category=Payroll + partyId)
              └── Advances tab (creditsProvider filtered partyId)
        └── "Pay Salary" → pre-filled AddTransactionScreen
        └── "Payslip"    → InvoiceScreen(type: payslip, party: staff)
```

---

## Anti-Patterns to Avoid

| Anti-pattern | Why it hurts |
|---|---|
| New table that duplicates `name` + `phone` + `business_id` | Data drift, no party linking, won't appear in party search |
| Custom payment model instead of Transaction | Invisible to reports, budgets, and home summary |
| Feature-specific Riverpod state that mirrors existing state | Two sources of truth, cache invalidation bugs |
| Free-text party names stored in new tables | Can't link history, no autocomplete, no deduplication |
| New PDF/export logic | Maintenance burden; invoice renderer already handles this |

---

## Checklist Before Building Any New Feature

- [ ] Have I checked whether an existing table can be extended with 1–2 columns?
- [ ] Does every money movement produce a `Transaction`?
- [ ] Does every person/company link to a `Party`?
- [ ] Do new screens consume existing providers (with filters) rather than new state trees?
- [ ] If a document is needed, is it an `invoice_type` variant?
- [ ] Is all new data `business_id`-scoped?
