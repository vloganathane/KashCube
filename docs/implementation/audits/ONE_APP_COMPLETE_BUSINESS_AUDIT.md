# One App for Complete Business — KashCube Capability Audit

**Date:** 26 March 2026  
**Question:** Can a small business owner use KashCube as their single app to run their entire business?  
**Short answer:** Yes for ~70% of an Indian SME's needs. Three gaps — GSTR-2B reconciliation, bank statement reconciliation, and salary slips — are what force users to keep a second tool today.

---

## Domain-by-Domain Scorecard

```
Sales & Invoicing          ████████████  90%  ✅
Customer / Khata           ████████████  95%  ✅
GST Compliance             ██████████░░  80%  (GSTR-2B missing)
Purchases & Expenses       █████████░░░  75%  (recon missing)
Inventory                  ████████░░░░  65%  (alerts/adjustments missing)
Banking / Reconciliation   █████░░░░░░░  40%  ❌
HR / Payroll               ██████░░░░░░  50%  (no slips, no attendance)
Personal Finance (owner)   ████████░░░░  65%  (no ITR summary)
Reports & Analytics        █████████░░░  80%  ✅
Communication / Reminders  ██████░░░░░░  50%  (WhatsApp only, manual)

OVERALL                    ███████░░░░░  70%
```

---

## 1. Sales & Invoicing — 90% ✅

| Feature | Status |
|---|---|
| Invoices (create, PDF, WhatsApp share) | ✅ |
| Quotes / Estimates | ✅ |
| Delivery Challans | ✅ |
| Bookings / Advance receipts | ✅ |
| 9 PDF templates (5 industry presets) | ✅ |
| Custom template builder (Business tier) | ✅ |
| UPI payment QR on invoice | ✅ |
| Conflict-free multi-device invoice numbering | ✅ |
| E-Way Bill preview | ✅ |
| Tally XML / Excel export | ✅ |
| WhatsApp reminder buttons (manual, Starter) | ✅ |
| Document terms screen | ✅ |
| Global document ledger view | ✅ |
| Recurring invoices (auto-generate on schedule) | 🔄 schema exists; legacy cleanup pending |
| Automated reminders (no user tap required) | ❌ |
| e-Invoicing / IRN generation | 🚫 requires network — by design |

---

## 2. Purchases & Expenses — 75% ✅

| Feature | Status |
|---|---|
| Manual expense entry | ✅ |
| SMS auto-capture (56 Indian sender IDs) | ✅ |
| Purchase bills with GST | ✅ |
| Input Tax Credit (ITC) tracking | ✅ |
| Scheduled bills & payments screen | ✅ |
| Recurring expense auto-generation | 🔄 new schema in place; UI cleanup pending |
| GSTR-2B reconciliation (purchase vs portal) | ❌ explicitly deferred |
| Vendor invoice 3-way matching | 🚫 not in roadmap |

---

## 3. Inventory / Stock — 65% 🟠

| Feature | Status |
|---|---|
| Item catalog with SKU | ✅ |
| Barcode scanner (EAN/UPC/Code128) | ✅ |
| Purchase lot / batch tracking (FEFO) | ✅ shipped 26 Mar 2026 |
| Unit types management | ✅ |
| Inventory screen | ✅ |
| Low-stock alerts | ❌ |
| Stock adjustments / write-offs | ❌ |
| Multi-location / warehouse support | 🚫 |
| Manufacturing / Bill of Materials | 🚫 |

---

## 4. Customer / Party Management — 95% ✅

| Feature | Status |
|---|---|
| Party list (customers + vendors) | ✅ |
| Party 360° view | ✅ |
| Credits / Udhar / Khata ledger | ✅ |
| Loans tracking | ✅ |
| Journal ledger (grouped balance) | ✅ |
| Auto-link repayments to outstanding credits | ✅ |
| Action center (overdue / upcoming alerts) | ✅ |
| Contacts hub | ✅ |
| Local autocomplete (no contacts permission) | ✅ |
| Party-wise PDF / export | ✅ |
| Bulk WhatsApp credit nudge | ✅ |
| Customer account statement PDF | ❌ |
| CRM-style notes / follow-up log per party | 🚫 |

---

## 5. Staff / HR / Payroll — 50% 🟠

| Feature | Status |
|---|---|
| Staff list & detail screens | ✅ |
| Payroll cycle (DB schema + loop) | ✅ |
| Staff terminal / RBAC access control | ✅ |
| User permission management screen | ✅ |
| Attendance tracking | ❌ |
| Leave management | ❌ |
| Salary slip PDF generation | ❌ |
| PF / ESI / TDS deduction calculations | 🚫 |
| Statutory compliance (Form 16, etc.) | 🚫 |

**Verdict:** Payroll module records wages but cannot produce salary slips or calculate statutory deductions. Adequate for a shop with 1–3 daily-wage staff; unusable above ~5 employees.

---

## 6. Banking / Accounts — 40% ❌

| Feature | Status |
|---|---|
| Manual bank accounts management | ✅ |
| Transaction-to-account linkage | ✅ |
| Cash flow screen | ✅ |
| Multi-account balance tracking | ✅ |
| AES-256 encrypted backup / restore | ✅ |
| Bank statement PDF/CSV import | ❌ |
| Bank reconciliation (book vs statement) | ❌ |
| Account-to-account transfers | ❌ |
| Cheque tracking | 🚫 |

**Verdict:** Accounts are maintained by transaction entry, not by reconciliation. Any business doing monthly book-close will need to reconcile manually outside the app.

---

## 7. Tax & GST Compliance — 80% ✅

| Feature | Status |
|---|---|
| GSTR-1 JSON export (GST portal-ready) | ✅ |
| GSTR-3B summary + tax offset | ✅ |
| HSN / SAC code support (local asset, offline) | ✅ |
| GST calculator (CGST/SGST/IGST, reverse charge) | ✅ |
| Purchase bills with ITC | ✅ |
| E-Way Bill generation | ✅ |
| GST period picker + FY close wizard | ✅ |
| Tally XML export for CA handoff | ✅ |
| GSTR-2B reconciliation | ❌ explicitly deferred |
| GSTR-9 (annual return) | 🚫 |
| TDS / TCS tracking | 🚫 |
| ITR-ready summaries (80C/80D, net worth) | ❌ PRD Phase 2; not built |
| e-Invoicing / IRN | 🚫 requires network — by design |

---

## 8. Reports & Analytics — 80% ✅

| Feature | Status |
|---|---|
| Daily / monthly / yearly P&L | ✅ |
| Reports screen with charts (fl_chart) | ✅ |
| P&L PDF export (Starter+) | ✅ |
| Transaction CSV export | ✅ |
| Budget tracking + alerts | ✅ |
| Cash flow report | ✅ |
| Party-wise ledger export | ✅ |
| Category-wise breakdown | ✅ |
| Yearly trend comparison | ✅ |
| GSTR-1/3B reports (Business tier) | ✅ |
| Tally XML / Excel export | ✅ |
| KashCube Web browser dashboard (read-only) | ✅ |
| Custom arbitrary date-range reports | ❌ |
| ITR-ready summary (80C/80D, net worth snapshot) | ❌ PRD Phase 2 |
| Inventory valuation report | 🚫 |
| Live browser push (auto-reload on desktop) | ❌ W2 backlog |

---

## 9. Personal Finance (for the business owner) — 65% 🟠

| Feature | Status |
|---|---|
| Personal transactions (separated from business) | ✅ |
| Context switching (personal / business / investment) | ✅ |
| Loans / EMI tracking | ✅ |
| Investment tracking (FD, MF, stocks — manual entry) | ✅ |
| Budget tracking | ✅ |
| Personal card / identity screen | ✅ |
| PIN + biometric lock (PBKDF2-HMAC-SHA256) | ✅ |
| SMS auto-capture for personal UPI | ✅ |
| ITR-ready summaries (80C/D, net worth) | ❌ PRD Phase 2 |
| Portfolio tracking (live prices) | 🚫 requires network — by design |
| Credit score monitoring | 🚫 |

---

## 10. Communication / Reminders — 50% 🟠

| Feature | Status |
|---|---|
| WhatsApp payment reminder (deep-link) | ✅ |
| In-app action center (overdue + upcoming) | ✅ |
| Scheduled payment reminders | ✅ |
| Local notifications (`flutter_local_notifications`) | ✅ wired for scheduled payments |
| Notification settings screen | ✅ |
| Automated invoice follow-up scheduler | ❌ |
| Outbound SMS to customers | 🚫 |
| Email reminders | 🚫 |
| Cloud push notifications | 🚫 privacy-by-design |
| Onboarding screen | ❌ folder exists, no files — beta prep backlog |

---

## Who Can Use KashCube as Their Only App Today

### ✅ Yes — comfortable fit
- Kirana / general store with 1–5 staff
- Service shop (salon, clinic, repair center, tailor)
- Freelancer / consultant / designer
- Street food / food stall / cloud kitchen
- Sole proprietor with monthly GST filing (GSTR-1 + 3B)
- Pharmacist / chemist (lot tracking + GST billing)
- Any business that is UPI-heavy and WhatsApp-native

### ❌ Will feel gaps
- Trading business needing GSTR-2B reconciliation against portal downloads
- Business wanting automated bank statement reconciliation for month-close
- Employer with 5+ employees needing salary slips, PF/ESI, attendance
- Product business needing low-stock alerts and stock write-off adjustments
- Business owner needing ITR-ready summaries at tax season

---

## The 3 Gaps That Matter Most

Closing any one of these moves KashCube from "70% complete" to genuinely replacing a second tool for a large user segment:

### Gap 1 — GSTR-2B Reconciliation 🔴
Every GST-registered trader must reconcile their purchase bills against the GSTR-2B download from the GST portal (auto-populated from suppliers' GSTR-1). Today, users export from KashCube and do this in Excel or hand it to their CA. A built-in reconciliation screen (import GSTR-2B JSON → match against purchase bills → flag mismatches) would make KashCube self-sufficient for a CA-assisted filer.

### Gap 2 — Bank Statement Reconciliation 🔴
Month-close bookkeeping requires matching every transaction in the books against the bank statement. Without statement import + reconciliation, users must cross-reference manually. A CSV/PDF bank statement parser + reconciliation view (matched / unmatched / suggested matches) would eliminate the #1 reason users still open a spreadsheet.

### Gap 3 — Salary Slip PDF + Attendance 🔴
The payroll schema and cycle exist. But a business owner cannot hand staff a salary slip, track daily attendance, or calculate PF/ESI. Adding a salary slip PDF template (reusing the existing PDF service infrastructure) + a simple attendance punch screen would make the HR module actually usable for a shop with 3–10 employees.

---

## Reference: All Screens Confirmed Implemented

`home`, `transactions`, `add_edit_transaction`, `transaction_detail`, `credits`, `customer_detail`, `reports`, `settings`, `invoices`, `add_edit_invoice`, `invoice_detail`, `quotes`, `delivery_challan`, `purchase_bills`, `add_purchase_bill`, `inventory`, `item_catalog`, `parties`, `party_360`, `ledger`, `cash_flow`, `budgets`, `recurring`, `search`, `loans`, `accounts`, `staff`, `staff_detail`, `payroll`, `manage_users`, `gst` (GSTR-1, GSTR-3B, E-Way Bill, HSN picker), `documents`, `contacts_hub`, `action_center`, `settings/notifications`, `my_personal_card`, `fiscal_year`, `backups`, `kash_cube_web` (W1 read-only)
