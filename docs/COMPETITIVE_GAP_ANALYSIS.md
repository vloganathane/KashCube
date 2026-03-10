# Competitive Gap Analysis & Brainstorm
# KashCube vs. Indian Market (Vyapar, OkCredit, Khatabook, BizBuzz)

**Version:** 1.1  
**Date:** 10 March 2026  
**Status:** Updated with feature audit results (March 2026)

---

## 1. Competitive Landscape at a Glance

| App | Primary Audience | Revenue Model | Key Moat |
|-----|-----------------|---------------|----------|
| **Vyapar** | SME / Retailers | Freemium (₹849–₹2,999/yr desktop) | GST billing + inventory offline |
| **OkCredit** | Kirana / street shops | Freemium + OkStaff | Simplest udhar ledger in India |
| **Khatabook** | SME / services | Freemium + KhataPay | Payment link collection |
| **Zoho Books** | SME+ / Accountants | Subscription (₹2,499+/yr) | Full accounting + CA integrations |
| **Tally** | SME+ / Accountants | One-time (₹18,000+) | Legacy ERP, offline |
| **KashCube** | Individual + micro-SME | Free, local-only | SMS auto-capture + privacy-first |

### KashCube's Unique Advantages (Defensible Moat)
1. **SMS auto-capture** — no other app does automatic UPI/bank SMS parsing offline. This alone keeps users coming back daily.
2. **100% on-device privacy** — no cloud, no login, no data harvesting. Resonates strongly post-DPDPA (India's data-privacy law).
3. **Personal + Business in one** — most competitors serve only one persona. KashCube has both (Business Mode toggle).
4. **AES-256 encrypted local backup** — rare even in paid apps.
5. **Fully free** — no subscription wall, no "upgrade to unlock reports".

### Codebase Status (March 2026 audit)

Out of 27 monetization-tier features, **16 are fully implemented**, 5 are partial, and 6 are not yet built:

| Tier | Feature | Status |
|------|---------|--------|
| FREE | Transactions (SMS + manual) | ✅ |
| FREE | Credits / Udhar | ✅ |
| FREE | Budgets + in-app reports | ✅ |
| FREE | PIN + biometric lock | ✅ |
| FREE | Backup / restore (AES-256) | ✅ |
| FREE | Invoices + Quotes + DCs + Bookings | ✅ |
| FREE | **PDF watermark** | **❌ Not built** |
| STARTER | WhatsApp reminder buttons | ✅ |
| STARTER | **Watermark gate / isPro flag / IAP** | **❌ Not built** |
| STARTER | Report export (P&L PDF / CSV) | ⚠️ CSV exists in settings; no button on reports screen |
| STARTER | Invoice templates (5 presets) | ⚠️ 4 presets built (classic/modern/plain/receipt); no industry presets |
| STARTER | **UPI payment QR on invoice** | **❌ Not built** |
| BUSINESS | Purchase Bills + ITC | ✅ |
| BUSINESS | E-Way Bill + transporter registry | ✅ |
| BUSINESS | GSTR-3B summary + export | ✅ |
| BUSINESS | GSTR-1 export | ⚠️ CSV ZIP (GSTN-format); not JSON |
| BUSINESS | Custom invoice templates | ✅ |
| BUSINESS | **Inventory management** | **❌ Not built** |
| BUSINESS | Barcode scanner for items | ⚠️ mobile_scanner in pubspec; QR-only for party vCard |
| BUSINESS | **Staff payroll** | **❌ Not built** |
| BUSINESS | **Tally XML export** | **❌ Not built** |
| BUSINESS | **LAN sync** | **❌ Not built (Phase 3)** |

---

## 2. Feature Gap Matrix

### 2.1 Tier-1 Gaps (Highest user demand; closes Vyapar parity)

| # | Feature Gap | Vyapar | OkCredit | KashCube Today | User Impact |
|---|-------------|--------|----------|----------------|-------------|
| G1 | **Inventory Management** | ✅ Full (batch, expiry, FIFO, multi-location) | ❌ | ❌ Not built | Retailers can't use KashCube for stock |
| G2 | **GSTR-1 / GSTR-3B Export** | ✅ One-click JSON/CSV | ❌ | ⚠️ CSV ZIP built; no JSON | SMEs file GST manually — huge pain |
| G3 | **Multi-User / Staff Access** | ✅ Up to 3 users (paid) | ✅ OkStaff | ❌ Not built | Business owners can't give access to accountant/staff |
| G4 | **WhatsApp Payment Reminder** | ✅ (sent via app link) | ✅ | ✅ Built (url_launcher) | Primary collection channel in India |
| G5 | **Customer Payment Collection Link** | ✅ + UPI deep link | ✅ KhataPay | ❌ Not built | Digital storefronts expect payment links |

### 2.2 Tier-2 Gaps (Medium demand; differentiators)

| # | Feature Gap | Vyapar | KashCube Today | Notes |
|---|-------------|--------|----------------|-------|
| G6 | **Low-Stock Alerts** | ✅ | ❌ Not built | Depends on G1 (inventory) being built first |
| G7 | **GSTR-2B Reconciliation** | ✅ | ❌ Not built | Match purchase bills vs GSTR-2B auto-download |
| G8 | **Industry-specific invoice templates** | 10+ (pharmacy, restaurant, textile) | ⚠️ 4 generic presets | Need 5 industry presets: Pharmacy, Restaurant, Service, Freelancer, Generic |
| G9 | **Desktop / Web companion** | ✅ Windows | ❌ Not built | Flutter Web or Windows build possible |
| G10 | **Salary / Payroll tracking** | Basic | ❌ Not built | OkStaff does this; growing demand with gig workers |
| G11 | **Barcode / QR scanner for items** | ✅ | ⚠️ QR only (party vCard) | `mobile_scanner` in pubspec; need EAN scan for item catalog |
| G12 | **Bank statement PDF import** | ❌ | ❌ Not built | Could complement SMS parsing |

### 2.3 Tier-3 Gaps (Nice-to-have; long tail)

| # | Feature Gap | Notes |
|---|-------------|-------|
| G13 | CA / tax professional integration | Needs shared-access or export to Tally XML |
| G14 | Multi-currency / forex | Freelancers billing USD/EUR clients |
| G15 | Subscription / recurring billing automation | Auto-generate invoice monthly |
| G16 | E-commerce connector (Shopify, WooCommerce) | Out of scope for local-first architecture |
| G17 | In-app chat / support | Vyapar has live chat |
| G18 | Audit trail / change log | Who changed what — needed for multi-user |

---

## 3. Deep-Dive Brainstorm per Gap

---

### G1 — Inventory Management

**Problem Statement:**  
A retailer (e.g., a mobile accessories shop owner) adds sales invoices in KashCube but has no way to track stock. Every sale should decrement inventory. Low-stock should alert before a stockout. Batch tracking is needed for pharma/FMCG (expiry dates, batch numbers).

**Proposed Approach — Phased:**

#### Phase A: Basic Stock (MVP Inventory)
- New table: `products` (name, unit, opening_stock, reorder_level, hsn_code, purchase_price, sale_price)
- New table: `stock_movements` (product_id, movement_type: in/out/adjustment, qty, reference_type: invoice/purchase_bill/manual, reference_id, date, notes)
- Current stock = sum of movements (event-sourced — never store redundant `current_stock`)
- Link `invoice_items` → `product_id` (nullable, backward-compatible)
- Link `purchase_bill_items` → `product_id`
- Show stock on Party 360°: "Sold 12 units this month"
- New screen: **Stock Register** (list of products with current stock, reorder badge)

#### Phase B: Low-Stock Alerts
- WorkManager daily check: any product where `current_stock ≤ reorder_level` → local notification
- Action Center integration (existing framework reused)

#### Phase C: Batch + Expiry (Pharma / FMCG)
- New table: `stock_batches` (product_id, batch_no, expiry_date, qty_in, qty_remaining, purchase_bill_id)
- FEFO (first-expiry-first-out) on invoice item selection
- Expiry alerts: 30/15/7 days before

**DB migration:** v50+  
**Screens needed:** Stock Register, Add Product, Stock Adjustment, Stock Ledger per Product  
**Effort estimate:** Phase A = 2 sprints, Phase B = 0.5 sprint, Phase C = 1.5 sprints

---

### G2 — GSTR-1 / GSTR-3B Export

**Problem Statement:**  
KashCube already stores all data needed for GST filing: invoices with GSTIN, HSN, tax breakdown, B2B vs B2C. But there's no export. Users currently copy-type data into Clear Tax / GST portal — extremely painful.

**Current Data Available:**
- `invoices` table: party GSTIN, invoice_date, total_amount, igst/cgst/sgst amounts
- `invoice_items`: hsn_code, quantity, rate, tax_rate
- `purchase_bills` + `purchase_bill_items`: ITC-eligible flag, GSTIN
- `parties`: GSTIN

**Proposed Approach:**

#### GSTR-1 (Outward supplies — B2B + B2C)
- Query invoices for the selected month/quarter
- Split B2B (party has GSTIN) vs B2C (no GSTIN)
- Export as **JSON** matching GST portal schema (so user can upload directly)
- Export as **Excel-compatible CSV** for CA hand-off
- Grouped by: B2B → party GSTIN, B2CS (B2C small) → rate-wise, CDNR (credit notes)
- Already partially specified in `docs/GSTR1_WORKBOOK_SPEC.md`

#### GSTR-3B (Summary self-assessment)
- Aggregate: Total outward taxable, Total ITC claimed, Net tax payable
- One-screen summary with copy-to-clipboard per cell
- No JSON export needed (it's a self-filled form, not uploaded)

#### ITC Reconciliation (GSTR-2B matching)
- Allow user to import GSTR-2B JSON (downloaded from portal)
- Match against `purchase_bills` by invoice number + GSTIN
- Flag mismatches
- This is Tier-2 (G7) but natural follow-on to G2

**New screen:** GST Filing Hub (monthly/quarterly view → GSTR-1 export, ITC summary, GSTR-3B preview)  
**Effort estimate:** GSTR-1 JSON = 1 sprint, GSTR-3B summary = 0.5 sprint

---

### G4 — WhatsApp Payment Reminder

**Problem Statement:**  
The #1 payment collection channel in India is WhatsApp. OkCredit and Vyapar both allow sending "You owe ₹X" reminders. KashCube sends local notifications but can't nudge the customer directly.

**Privacy-First Approach (no server, no API keys):**
- Use `url_launcher` to open `https://wa.me/<mobile>?text=<encoded_message>`
- WhatsApp opens with pre-filled message; user taps Send
- Message template: "Hi [Name], a gentle reminder that ₹[amount] is due since [date] for [invoice/bill]. Thank you! — sent via KashCube"
- Party must have a phone number stored (already in `parties.phone`)
- Add "Remind via WhatsApp" button on:
  - Credit detail screen (udhar)
  - Invoice detail screen (unpaid invoices)
  - Scheduled payment overdue items
- User can edit the message before sending (standard `url_launcher` flow)
- Log the reminder send date in `credits` / `invoices` as `last_reminder_sent`

**No new permissions needed.** `url_launcher` is already in pubspec.  
**Effort estimate:** 0.5 sprint

---

### G5 — Customer Payment Collection Link (UPI Deep Link)

**Problem Statement:**  
Small businesses need to collect payments digitally. Vyapar generates a UPI payment link or QR code for a specific invoice. KashCube has no equivalent.

**Approach — Zero-Backend:**
- Generate a `upi://pay?pa=<vpa>&pn=<name>&am=<amount>&tn=<note>&cu=INR` deep link
- Requires user to configure their UPI VPA in Settings (once)
- On Invoice detail: "Share Payment Link" → generates UPI link → share via `share_plus` (WhatsApp, SMS, etc.)
- Also show as QR code (use `qr_flutter` package — offline, no network)
- QR is displayed in-app or shared as image
- When payment received via SMS, KashCube auto-matches it to the invoice via UPI Ref No. (SMS parsing already extracts UTR/UPI ref)

**New dependency:** `qr_flutter` (pure Dart, offline, ~80KB)  
**New settings field:** "Your UPI VPA" (e.g., name@upi)  
**Effort estimate:** 1 sprint

---

### G8 — Industry-Specific Invoice Templates

**Problem Statement:**  
A medical shop owner, a restaurant owner, and a textile trader all use invoices differently. KashCube has one generic template.

**Brainstorm Options:**

| Option | Effort | Flexibility |
|--------|--------|-------------|
| A: Hardcode 5 templates (generic, medical, restaurant, textile, service) | Low | Low |
| B: Template "presets" that pre-fill default columns/fields + header style | Medium | Medium |
| C: Fully user-customizable template builder (drag columns, choose logo placement) | High | High |

**Recommendation: Option B (presets)**
- Define `InvoiceTemplate` enum: generic, pharmacy, restaurant, textile, service, freelancer
- Each preset controls: visible fields (expiry, batch, HSN, GSTIN), default unit (nos/kg/pcs/hrs), column order, notes template
- Stored in Settings; applies to new invoices
- No per-invoice template switching needed (matches how small businesses work)
- UI: single-screen "Invoice Style" in Settings with preview thumbnail

**Effort estimate:** 1 sprint

---

### G9 — Desktop Companion (Flutter Windows / Web)

**Problem Statement:**  
Accountants and business owners want to do data entry on a large screen. Vyapar has a Windows app. KashCube is mobile-only.

**Privacy-Safe Options:**
1. **Flutter Windows build** — same codebase, SQLite on Windows via `sqflite_common_ffi`. Completely offline. Sync via manual `.kashcube` encrypted backup file copy (same EncryptedBackupService). Effort: 2–3 sprints (responsive layout work).
2. **Flutter Web (localhost only)** — Run as local web server on Android via `shelf`. Access from PC browser on same Wi-Fi. No internet exposure. Effort: 3–4 sprints (complex).
3. **Export to Tally XML / Excel** — Not a desktop app but solves the accountant workflow. Tally XML import is well-documented. Effort: 1 sprint.

**Recommendation:** Option 3 first (low effort, high value for accountants), then Option 1 if demand validated.

---

### G10 — Staff Salary / Payroll Tracking

**Problem Statement:**  
Gig economy workers and small shop owners need to track daily wages, deductions, and monthly salary. OkStaff has 5M+ users for this exact use case.

**Minimal Viable Approach:**
- New table: `staff` (name, role, salary_type: monthly/daily/hourly, rate, join_date, phone)
- New table: `attendance` (staff_id, date, status: present/absent/half_day, overtime_hours)
- New table: `salary_payments` (staff_id, period_from, period_to, gross, deductions, net, paid_date, notes)
- Auto-calculate: net = (days_present / working_days) × monthly_rate + overtime − deductions
- Integration: salary payments show as "Expense" in transactions automatically
- New screen: **Staff & Payroll** (under Business Mode only)

**Effort estimate:** 2 sprints

---

### G11 — Barcode / QR Scanner for Items

**Problem Statement:**  
Adding products by barcode is 5× faster than typing for retail use cases. `mobile_scanner` is already in pubspec.yaml.

**Approach:**
- On "Add Invoice Item" / "Add Purchase Bill Item": show barcode scan FAB
- Scan → look up product by barcode in `products` table → auto-fill name, rate, HSN, tax
- On "Add Product": scan barcode to pre-fill barcode field
- Barcode stored as `products.barcode TEXT`
- Fallback: type barcode manually

**Effort estimate:** 0.5 sprint (dependency already added)

---

## 4. Prioritized Feature Backlog

Based on user impact, effort, and KashCube's architecture readiness:

| Priority | Gap | Sprint Estimate | DB Migration | Dependency |
|----------|-----|-----------------|--------------|------------|
| **P0** | G2: GSTR-1 Export | 1.5 | None (data exists) | — |
| **P0** | G4: WhatsApp Reminder | 0.5 | +`last_reminder_sent` col | None |
| **P1** | G1-A: Basic Inventory | 2.0 | v50: products + movements | — |
| **P1** | G5: UPI Payment Link | 1.0 | +`upi_vpa` in settings | `qr_flutter` |
| **P1** | G8: Invoice Templates | 1.0 | None | — |
| **P2** | G11: Barcode Scanner | 0.5 | +`barcode` col on products | Depends on G1 |
| **P2** | G6: Low-Stock Alerts | 0.5 | None | Depends on G1 |
| **P2** | G10: Staff Payroll | 2.0 | v51: staff + attendance + salary_payments | — |
| **P3** | G1-B: Batch/Expiry | 1.5 | v52: stock_batches | Depends on G1-A |
| **P3** | G9: Tally/Excel export | 1.0 | None | — |
| **P3** | G7: GSTR-2B Reconcile | 1.5 | None | Depends on G2 |
| **P4** | G3: Multi-user | 3.0+ | Major re-arch needed | Security overhaul |
| **P4** | G9: Flutter Windows | 3.0 | None | Responsive layouts |

**Recommended next 3 sprints:**
1. Sprint 1: G2 (GSTR-1 Export) + G4 (WhatsApp Reminder)
2. Sprint 2: G1-A (Basic Inventory) + G11 (Barcode Scanner)
3. Sprint 3: G5 (UPI Payment Link) + G8 (Invoice Templates)

---

## 5. KashCube's Winning Strategy

### Play to the moat — don't fight Vyapar head-on

Vyapar has a 10-year head-start on inventory and GST. Fighting them on features is a losing battle.

**KashCube's winning strategy:**

1. **Privacy as a product** — Make the privacy promise tangible. Show "0 bytes sent to any server" in Settings. Publish a public audit. Indian users are increasingly aware of data exploitation.

2. **SMS auto-capture is irreplaceable** — Double down here. Improve parser accuracy, add more banks (Yes Bank, IndusInd, Federal), auto-reconcile UPI ref numbers with outstanding invoices. Vyapar can't replicate this without accessing SMS (Android permission they'd get pushback on given their cloud model).

3. **Personal finance + business in one** — No competitor does this well. A shop owner is also a person with household expenses. KashCube's unified view (personal transactions + business P&L) is uniquely valuable.

4. **Speed of entry** — Every transaction/invoice should be addable in under 10 seconds. If any flow takes more taps than Vyapar, fix it.

5. **Intelligent action center** — The background daily task already runs. Expand it: "You have 3 unpaid invoices totaling ₹24,000 overdue" → one tap to send WhatsApp reminders to all.

6. **GST as a differentiator, not parity** — Don't just match Vyapar's GSTR-1. Add GSTR-2B auto-matching (they don't do it offline). Add an "ITC health score" showing how much ITC the user is eligible vs. missing due to unverified vendors.

### Segments to own before expanding to inventory:

| Segment | Size | Why KashCube wins |
|---------|------|------------------|
| **Freelancers / consultants** | 82L+ in India | Service invoices, no inventory needed, privacy-conscious, want expense tracking |
| **Medical professionals** | 12L+ doctors | SMS reminders, no stock needed, clinic expenses + patient billing |
| **Gig workers** | 1.5Cr+ | Daily income tracking via SMS, no GST complexity |
| **Home tutors / coaches** | 80L+ | Session-based billing, student credit tracker |
| **Kirana + tea shops (Phase 2)** | 1.2Cr+ | Need inventory — serve after G1 ships |

---

## 6. Open Questions & Decisions Needed

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| Q1 | Should inventory use event-sourcing (stock movements) or snapshot (current_stock column)? | Event-sourcing (more accurate, auditable) vs Snapshot (simpler queries) | **Event-sourcing** (matches our transaction model; enables stock ledger) |
| Q2 | GSTR-1 export format: JSON (GST portal upload) or Excel (CA handoff)? | Both, or pick one first | **JSON first** — higher value; Excel is cosmetic |
| Q3 | UPI VPA storage: plain text in SQLite or encrypted via `flutter_secure_storage`? | SQLite (simple) vs Encrypted (security) | **flutter_secure_storage** — UPI VPA is a financial identifier |
| Q4 | Multi-user: PIN-per-user or Android multi-account approach? | Local PINs with role-based access | **Not in 2026 roadmap** — architecture impact too large |
| Q5 | Should WhatsApp reminders log the sent message (for audit)? | Yes (store in new `reminder_logs` table) vs No | **Yes** — useful for dispute resolution |
| Q6 | Invoice template preset: ship 5 on launch or let users request via GitHub? | Ship 5 | **Ship 5** (generic, pharmacy, restaurant, service, freelancer) |

---

## 7. Anti-patterns to Avoid

1. **Do not add network calls** to support any of these features. G3 (multi-user) is blocked precisely because it requires a trust model that KashCube's architecture doesn't support without a server. Accept this constraint.

2. **Do not add a "sync to cloud" option** even as opt-in. This erodes the privacy promise that users chose KashCube for. If users want cloud sync they have Vyapar. KashCube owns the "no-cloud" positioning.

3. **Do not build inventory before GSTR-1 export.** Inventory is a heavy lift and the data for GST export already exists. Ship the quick win first.

4. **Do not copy Vyapar's UI.** Its UI is dense and form-heavy. KashCube should stay conversational, fast, and mobile-native.

5. **Do not add subscription features** — the free model is a strategic differentiator, not a temporary stance.

---

*Last updated: 10 March 2026*  
*Next review: After Sprint 1 completion*
