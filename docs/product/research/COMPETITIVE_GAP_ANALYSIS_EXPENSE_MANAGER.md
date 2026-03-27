# Competitive Gap Analysis — Expense Manager (Bishinews)

**Reference app:** Expense Manager by Bishinews  
**Play Store:** https://play.google.com/store/apps/details?id=com.expensemanager  
**Rating:** 4.4 ★ · 60.9K reviews · 5M+ downloads  
**Reviewed on:** 26 March 2026  

---

## Missing Entirely from KashCube

| Feature | Expense Manager behaviour | Priority |
|---|---|---|
| **Split transaction** | Single entry split across multiple categories/amounts with per-split description | 🔴 High |
| **Tags** | User-defined tags on any transaction; fully searchable and reportable | 🔴 High |
| **Calendar view** | Per-day drill-down calendar heatmap + budget forecast overlay | 🔴 High |
| **Subcategories** | Two-level category hierarchy (Category → Subcategory) | 🟠 Medium |
| **Receipt photo capture** | Camera capture attached to each expense/income transaction | 🟠 Medium |
| **Notes / memo on transaction** | Free-text note field wired in the transaction form UI | 🟠 Medium |
| **Import transactions** | CSV / OFX import from other apps or bank exports | 🟠 Medium |
| **Native Android home-screen widget** | Quick-add, budget summary, overview widgets on Android home screen | 🟡 Low |
| **Mileage tracking** | Dedicated mileage log with km/miles → expense conversion | 🟡 Low |
| **Loan / interest / tip calculators** | 6 built-in financial calculators (loan, credit card payoff, interest, tip) | 🟡 Low |
| **Shopping list** | In-app shopping list that can be converted into expenses | 🟡 Low |
| **Budget calendar forecasting** | Projects scheduled & recurring spend forward onto the calendar | 🟡 Low |
| **Credit card payoff tracking** | Card-level balance tracking + statement date / payment due alerts | 🟡 Low |

---

## Partially Done in KashCube

| Feature | Expense Manager | KashCube current state | Gap |
|---|---|---|---|
| **Budget periods** | Daily / weekly / monthly / yearly with progress bar | `budgets` table exists; monthly focus | Daily & weekly granularity not exposed in UI |
| **Payment / bill alerts** | Push notification for each scheduled payment | Scheduled payments (`scheduled_payments` table) exist; catchup loop works | Push notification delivery not confirmed wired to FCM/local notifications |
| **Search depth** | Filter by subcategory, tag, payee, payment method, status, description | Unified search screen exists | Tag and subcategory filter dimensions not available (features don't exist yet) |
| **Budget progress bar** | Visual % spent vs budget per category with color coding | Budget screen listed in PRD | Implementation depth / visual state unknown |
| **Export formats** | HTML, CSV, Excel, PDF | PDF (P&L), CSV (transactions), GSTR-1 JSON, Tally XML | No HTML export; Excel export only for Tally, not general transactions |

---

## Intentionally Different (Not Gaps)

| Aspect | Expense Manager | KashCube rationale |
|---|---|---|
| **Cloud backup** | Dropbox, Google Drive, SD Card auto-sync | Privacy-first; local AES-256 backup + LAN P2P sync by design |
| **Multiple currencies** | Full multi-currency support | ₹-only is correct for Indian market focus |
| **PC browser access** | WiFi LAN web UI for data entry | KashCube has LAN P2P sync; no web UI needed |
| **GST compliance** | No GST awareness | KashCube has full GSTR-1/3B, e-invoicing, HSN/SAC — far ahead |
| **Invoicing / purchase bills** | Not present | KashCube's primary B2B differentiator |
| **Lot / batch tracking** | Not present | Unique to KashCube for inventory-heavy SMEs |
| **UPI/SMS auto-capture depth** | Basic SMS parsing | KashCube covers 56 Indian sender IDs with confidence scoring |

---

## Top 3 Priorities to Close the Gap

### 1. Split Transaction 🔴
Users regularly split a single payment (e.g., grocery bill) across Food, Household, Personal. Without this, power users work around it by creating multiple transactions — a friction point that drives churn. This is the #1 differentiator Expense Manager reviewers positively mention.

**Implementation sketch:**
- Add `parent_transaction_id` to `transactions` table
- `SplitTransactionSheet` — bottom sheet with dynamic line items (category + amount)
- Parent transaction stores total; splits store sub-amounts
- Reports aggregate correctly by summing splits

### 2. Tags + Subcategories 🔴
Tags give users a second dimension for filtering without restructuring their category tree. Subcategories complete the category model. Together they unlock significantly richer report slicing.

**Implementation sketch:**
- `tags` table + `transaction_tags` join table (many-to-many)
- `subcategories` column on `categories` table (parent_id self-reference)
- Tag chips on transaction form (autocomplete from existing tags)
- Filter panel in Transactions and Reports screens

### 3. Calendar View 🔴
High visual impact, low data complexity. Users cited calendar view as a key reason to choose Expense Manager. Shows income/expense density per day, taps into a drill-down list.

**Implementation sketch:**
- Use `table_calendar` Flutter package (already common in Indian fintech apps)
- Day cell decorated with ₹ amount (expense=red dot, income=green dot)
- Tap day → filtered transaction list for that date
- Month total summary row below calendar

---

## Notes from User Reviews (Expense Manager)

- Users want per-split descriptions (not just amounts) — noted as missing even in Expense Manager
- Multi-currency between transactions in the same entry is a pain point there — KashCube should avoid that if/when implementing splits
- Stability and offline-first are praised — KashCube is already strong here
- "No forced pro version / no hidden charges" is a major trust signal — KashCube's freemium model should follow the same transparent messaging
