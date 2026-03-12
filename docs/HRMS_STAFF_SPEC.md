# HRMS — Staff & Payroll Spec

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** Planned — Rebuilt on KashCube Base  
**Principle:** [FEATURE_EXTENSION_PRINCIPLES.md](./FEATURE_EXTENSION_PRINCIPLES.md)

---

## 1. Overview

Staff & Payroll (HRMS) lets a business owner manage employees and contractors — profile,
salary, advances, attendance, and payslips — entirely on-device with no cloud dependency.

The original implementation (`staff` + `salary_payments` tables, v52) is a standalone island.
This spec replaces it with a base-extension approach: staff are Parties, salary payouts are
Transactions, advances are Credits, and payslips are Invoice variants.

---

## 2. What Stays vs What Changes

| Original (v52) | Revised approach | Why |
|---|---|---|
| Separate `staff` table (name, phone, email duplicated) | `Party(type: staff)` + 4 new columns | Parties already have contact, search, linking |
| Separate `salary_payments` table | `Transaction(type: expense, category: 'Payroll')` | Appears in reports, budgets, home summary for free |
| No advance tracking | `Credit(direction: given, partyId: staff.id)` | Existing ledger screen handles overdue, clearing, history |
| No payslip document | `Invoice(invoiceType: payslip, customerPartyId: staff.id)` | Existing PDF renderer, preview, share work immediately |
| Staff hidden behind Business tier gate only | Same gate, built properly | No change |

The old `staff` and `salary_payments` tables are **preserved** (no data loss for early testers)
but are no longer the primary data store. A DB v57 migration adds the new columns to `parties`
and back-fills from the old `staff` table.

---

## 3. Data Layer

### 3.1 DB Migration v57 — Extend `parties` Table

Add four nullable columns to `parties`:

```sql
ALTER TABLE parties ADD COLUMN staff_role        TEXT;
ALTER TABLE parties ADD COLUMN staff_salary       REAL;
ALTER TABLE parties ADD COLUMN staff_salary_type  TEXT DEFAULT 'monthly';
ALTER TABLE parties ADD COLUMN staff_join_date    TEXT;
```

No other new tables. The following existing data carries everything else:

| Data | Table | Filter |
|---|---|---|
| Bank / PF / ESI / PAN details | `parties.notes` (structured JSON) or existing `address` fields | — |
| Salary payout | `transactions` | `category = 'Payroll'`, `party_id = staff.id` |
| Salary advance | `credits` | `party_id = staff.id`, `direction = given` |
| Deductions (TDS, PF) | `transactions` | `category = 'Payroll Deduction'`, `party_id = staff.id` |
| Payslip document | `invoices` | `invoice_type = 'payslip'`, `customer_party_id = staff.id` |

### 3.2 `InvoiceType` — Add `payslip`

```dart
enum InvoiceType { taxInvoice, billOfSupply, creditNote, debitNote, payslip }
```

DB value: `'payslip'`. Payslips are excluded from GST filing queries by this type guard.

### 3.3 Transaction Categories — Add Two

Add to seeded categories (no schema change — categories are text values):

- `'Payroll'` — net salary / wages paid to a staff party
- `'Payroll Deduction'` — TDS, PF employer contribution, ESI (separate transactions for audit trail)

### 3.4 Back-fill Migration Logic (v57)

For each row in the old `staff` table where `party_id IS NOT NULL`:

```sql
UPDATE parties SET
  staff_role       = (SELECT designation FROM staff WHERE party_id = parties.id),
  staff_salary     = (SELECT base_salary  FROM staff WHERE party_id = parties.id),
  staff_salary_type= (SELECT salary_type  FROM staff WHERE party_id = parties.id),
  staff_join_date  = (SELECT join_date    FROM staff WHERE party_id = parties.id)
WHERE id IN (SELECT party_id FROM staff WHERE party_id IS NOT NULL);
```

For `staff` rows with no `party_id`, create a new `Party(type: staff)` and link them.

---

## 4. Domain / Repository Layer

No new repositories. Extend existing ones:

### 4.1 `PartyRepository`

```dart
// Already exists — add one filter:
Future<List<Party>> getStaffMembers({required int businessId});
// Implementation: getParties(type: PartyType.staff, businessId: businessId)
```

### 4.2 `TransactionRepository`

```dart
// Already exists — filter:
Future<List<Transaction>> getPayrollHistory({
  required int staffPartyId,
  int? month,
  int? year,
});
// category IN ('Payroll', 'Payroll Deduction') AND party_id = staffPartyId
```

### 4.3 `CreditRepository`

No changes. Advances are queried with existing `getCreditsForParty(partyId)`.

### 4.4 `InvoiceRepository`

```dart
// Already exists — add:
Future<List<Invoice>> getPayslips({required int businessId, int? staffPartyId});
// invoice_type = 'payslip' AND business_id = ?
```

---

## 5. Provider Layer

All providers are **filters on existing providers**, not new state trees.

```dart
// Staff list
final staffProvider = FutureProvider.family<List<Party>, int>(
  (ref, businessId) => ref.read(partyRepositoryProvider)
      .getParties(type: PartyType.staff, businessId: businessId),
);

// Payroll history for one staff member
final staffPayrollProvider = FutureProvider.family<List<Transaction>, ({int partyId, int month, int year})>(
  (ref, args) => ref.read(transactionRepositoryProvider)
      .getPayrollHistory(staffPartyId: args.partyId, month: args.month, year: args.year),
);

// Net salary payable this month (base - advances already paid)
final staffNetPayableProvider = Provider.family<double, ({Party staff, int month, int year})>(
  (ref, args) { /* compute from staffPayrollProvider + creditsProvider */ },
);
```

---

## 6. UI Layer

### 6.1 Screen Map

```
Business Hub → Staff & Payroll
  └── StaffListScreen
        ├── Active / Inactive tabs
        ├── Search bar (reuses party search)
        └── [+ Add Staff] → StaffFormSheet (PartyFormSheet pre-typed as staff)
              └── StaffDetailScreen(partyId)
                    ├── [Profile tab]
                    │     name, role, salary, join date, contact, bank details (notes)
                    ├── [Payroll tab]
                    │     Month/year picker
                    │     Payroll summary card: Base | Allowances | Deductions | Net
                    │     Transaction list (filtered Payroll + Payroll Deduction + partyId)
                    │     [Pay Salary] → pre-filled AddTransactionSheet
                    │     [View Payslip] → InvoiceDetailScreen(type: payslip)
                    └── [Advances tab]
                          Credits list (filtered by partyId, direction: given)
                          [Give Advance] → pre-filled AddCreditScreen
```

### 6.2 StaffListScreen

| Element | Source |
|---|---|
| Staff cards | `staffProvider(businessId)` |
| Search | Existing `PartySearchDelegate` |
| Filter active/inactive | `Party.deletedAt == null` |
| "No staff yet" empty state | Standard pattern |

### 6.3 StaffDetailScreen — Profile Tab

Displays and edits:

| Field | Maps to |
|---|---|
| Name | `party.name` |
| Role / Designation | `party.staffRole` |
| Phone / Email | `party.phoneNumber`, `party.email` |
| Salary | `party.staffSalary` + `party.staffSalaryType` (monthly / daily / hourly) |
| Join Date | `party.staffJoinDate` |
| Bank / PAN / PF / ESI | `party.notes` (structured plain text or key-value) |

Edit via existing `PartyFormSheet` extended with staff-specific fields (shown only when `partyType == staff`).

### 6.4 StaffDetailScreen — Payroll Tab

**Month selector** — prev / current / next month.

**Payroll summary card** — computed from transactions for the selected month:

```
Base salary:     ₹25,000
Allowances:      + ₹2,000
Deductions:      − ₹3,400   (TDS ₹2,000 + PF ₹1,400)
──────────────────────────
Net paid:        ₹23,600    [Paid ✓] or [Pay Now →]
```

**[Pay Salary] action:**  
Opens `AddTransactionScreen` pre-filled:
- `type: expense`
- `category: 'Payroll'`
- `partyId: staff.id`
- `amount: party.staffSalary`
- `description: 'Salary – {Month} {Year}'`
- `paymentMethod: bank_transfer`

**[Add Deduction] action:**  
Same screen, `category: 'Payroll Deduction'`, negative `amount`.

**[Generate Payslip] action:**  
Creates / opens `Invoice(invoiceType: payslip, ...)` — see §6.5.

### 6.5 Payslip Generation

A payslip is an `Invoice` with `invoice_type = 'payslip'`:

```
customer_party_id  = staff.party_id
invoice_no         = 'PAY-{YYYYMM}-{staffId}'   (auto-generated)
issue_date         = last day of pay period
invoice_type       = 'payslip'
business_id        = active business
```

Line items (from that month's Payroll transactions):

| Description | Amount |
|---|---|
| Base Salary | ₹25,000 |
| HRA Allowance | ₹2,000 |
| TDS Deduction | −₹2,000 |
| PF (Employer) | −₹1,400 |
| **Net Salary** | **₹23,600** |

PDF rendering, preview, WhatsApp share → existing invoice infrastructure, zero new code.

### 6.6 Advances Tab

Reuses existing `CreditListWidget` filtered by `partyId`. "Give advance" opens existing
`AddCreditScreen` pre-filled with the staff party.

---

## 7. What We Get for Free by Building on Base

| Feature | Free because of... |
|---|---|
| Staff search + autocomplete | Party search already works for all types |
| Salary in monthly expense report | Transaction category = 'Payroll' |
| Salary in home screen total spend | All expense transactions count |
| Budget alert on payroll | Budget category = 'Payroll' |
| Advance overdue alert | Credit overdue logic already in place |
| Payslip PDF | Invoice PDF renderer |
| Payslip WhatsApp share | `share_plus` already wired on invoices |
| Backup / restore | All data is in SQLite, covered by existing backup |
| Multi-business isolation | `business_id` on Party + Transaction + Credit |

---

## 8. Scope & Phasing

### Phase S1 — Foundation (MVP)

- DB v57 migration (4 columns on `parties`, back-fill)
- `InvoiceType.payslip` added
- `'Payroll'` + `'Payroll Deduction'` categories seeded
- `StaffListScreen` (list, add, search)
- `StaffDetailScreen` — Profile + Payroll tabs
- "Pay Salary" pre-filled transaction shortcut

### Phase S2 — Payslip

- Payslip generation + PDF via existing invoice renderer
- `getPayslips` query + UI in Payroll tab
- Payslip share via WhatsApp / PDF

### Phase S3 — Advances

- Advances tab (reuses credit screen with party filter)
- Salary net payable = base − outstanding advances display

### Phase S4 — Attendance (Optional, future)

Attendance is the one area that has no existing base analogue. If needed:

- New `attendance` table: `(staff_party_id, date, status, business_id)`
- `status`: present / absent / half_day / leave
- Daily count drives `days_worked` → `net_salary = (base / working_days) × days_worked`
- This is Phase S4 only — do not block S1–S3 on it.

---

## 9. Not In Scope

- Shift scheduling / rosters
- Leave application workflow (manager approval)
- Biometric / geo-fenced attendance
- Statutory filing (PF/ESI/TDS returns) — out of scope for privacy-first local app
- Multi-level org chart

---

## 10. DB Version Summary

| Version | Change |
|---|---|
| v52 | `staff` + `salary_payments` tables (original — preserved, not primary) |
| v57 | `parties` gains `staff_role`, `staff_salary`, `staff_salary_type`, `staff_join_date`; back-fill from old `staff` table; `InvoiceType.payslip` support |
