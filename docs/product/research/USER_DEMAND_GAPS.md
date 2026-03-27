# What Users Want — KashCube Feature Gaps

**Date:** 26 March 2026  
**Signal sources:** Expense Manager (60K reviews), Wave (23K reviews), KashCube codebase audit  
**Purpose:** Prioritised backlog of missing features ranked by real user demand

---

## 🔴 Users Want This Daily — Highest Friction

### 1. Receipt / Bill Photo Capture with Auto-fill
**User pain:** "I photograph every receipt but still have to type everything in manually."  
**Behaviour:** User takes a photo of a shop bill/receipt → app extracts vendor name, date, and amount via OCR → pre-fills the Add Transaction form → user confirms in one tap.  
**Why it matters:** Eliminates the single biggest friction in daily expense tracking. Cited in competitor reviews more than any other missing feature.  
**Implementation path:** `google_mlkit_text_recognition` (on-device, no network); camera via `image_picker`; regex extraction for ₹ amounts, dates, and merchant name; attach photo to transaction via `receipt_image_path` column.  
**Privacy note:** MLKit runs fully on-device. No image ever leaves the phone.  
**Effort:** Medium

---

### 2. Automated Payment Reminders
**User pain:** "I send an invoice then have to manually remember to follow up every few days."  
**Behaviour:** When creating/editing an invoice, user sets a reminder schedule (e.g. 3 days before due, on due date, 7 days overdue). WorkManager fires a WhatsApp or SMS reminder automatically without any user action.  
**Why it matters:** KashCube already has manual WhatsApp reminder buttons — nobody wants to tap them daily for every overdue invoice. Wave's automated reminders are praised in reviews; their absence is a top complaint.  
**Implementation path:**
- `reminder_schedules` table: `invoice_id`, `trigger_type` (before_due / on_due / after_due), `days_offset`, `channel` (whatsapp / sms), `sent_at`
- WorkManager daily job queries upcoming/overdue invoices, fires via `url_launcher` (WhatsApp deep link) or `telephony` (SMS)
- Toggle per invoice in invoice detail screen
- Global default schedule in Settings  
**Effort:** Medium

---

### 3. Split a Single Transaction Across Categories
**User pain:** "I paid ₹2,300 at a general store — part groceries, part household, part personal. I have to create 3 separate entries."  
**Behaviour:** On the Add Transaction screen, a "Split" button opens a sheet where the user breaks the total into sub-amounts, each with its own category. The parent transaction shows the total; reports aggregate by category across splits.  
**Why it matters:** The #1 friction point in daily personal expense logging. Expense Manager built their entire "split transaction" feature around this exact complaint.  
**Implementation path:**
- `parent_transaction_id` FK on `transactions` table
- `SplitTransactionSheet` — bottom sheet with dynamic line items (category + amount + optional note)
- Parent stores total amount and `is_split = true`; children store sub-amounts
- Reports sum children by category; home screen shows parent total  
**Effort:** Medium

---

## 🟠 Users Want This Weekly — Medium Friction

### 4. Tags on Transactions
**User pain:** "I work across 3 clients. Category 'Travel' is useless — I need to know which client it was for."  
**Behaviour:** Free-form tags on any transaction (e.g. `#infosys`, `#mumbai-trip`, `#q1`). Searchable, filterable, and reportable. Autocomplete from existing tags.  
**Why it matters:** Freelancers and consultants need a second dimension beyond category for project-based reporting. In KashCube's PRD since v1 — never shipped.  
**Implementation path:**
- `tags` table + `transaction_tags` join table (many-to-many)
- Chip input field on Add/Edit Transaction screen
- Tag filter in Transactions list and Reports screen  
**Effort:** Low–Medium

---

### 5. Bulk Payment Against Multiple Invoices (Party-Level Payment)
**User pain:** "My customer owes ₹25,000 across 5 invoices and pays ₹21,000 on account. I have to open each invoice one by one."  
**Behaviour:** From a party's ledger / credit screen, user taps "Record Payment", enters total amount received, and the app distributes it across outstanding invoices oldest-first (or user selects which invoices to apply it to).  
**Why it matters:** Verbatim complaint in Wave reviews. For KashCube's retail/kirana user base with regular credit customers, this is a weekly — sometimes daily — workflow.  
**Implementation path:**
- Party detail screen → "Record Payment" CTA
- Payment allocation sheet: shows all outstanding invoices, pre-selects oldest-first, allows manual reallocation
- Creates payment records against each selected invoice; reduces outstanding balance  
**Effort:** Medium

---

### 6. Invoice Viewed / Opened Notification
**User pain:** "I sent the invoice 3 days ago. Did they even see it? Do I follow up or wait?"  
**Behaviour:** When the invoice PDF is opened (via WhatsApp / share link), the app records a `viewed_at` timestamp. The invoice list shows a "Viewed" chip. An optional notification fires on first open.  
**Why it matters:** Removes invoice follow-up anxiety. Wave highlights this as a core feature. Simple to implement for a huge psychological payoff.  
**Implementation path:**
- `viewed_at TEXT` column on `invoices` table
- Append a unique token to the WhatsApp share message / PDF filename
- When PDF is opened via deep link, local broadcast updates `viewed_at`
- "Viewed" status chip on invoice list and detail screen  
**Effort:** Low

---

### 7. Customer Account Statement (Party Ledger PDF)
**User pain:** "My customer asks 'what do I owe you?' and I have to scroll through 20 invoices and add it up in my head."  
**Behaviour:** From a party's screen, one tap generates a PDF statement showing all invoices, payments received, credit notes, and current outstanding balance. Shareable via WhatsApp.  
**Why it matters:** A retailer's most-used document when collecting monthly dues. The data already exists in KashCube — it just needs a PDF rendering path.  
**Implementation path:**
- `party_statement_pdf_service.dart` — reuse existing `invoice_pdf_service` infrastructure
- Filter `invoices` + `transactions` by `party_id`; render running balance table
- "Share Statement" button on party / credit detail screen  
**Effort:** Low (data exists, PDF infrastructure exists)

---

## 🟡 Users Want This Occasionally — Lower Friction, High Retention

### 8. Calendar View of Expenses / Income
**User pain:** "I can't tell at a glance which weeks I overspend. I want to see my money on a calendar."  
**Behaviour:** Monthly calendar where each day shows a coloured dot / mini-amount for expenses (red) and income (green). Tap any day to see that day's transactions.  
**Why it matters:** High visual impact, frequently cited in Expense Manager reviews as a deciding factor. No calculation complexity — purely a display layer over existing data.  
**Implementation path:**
- `table_calendar` Flutter package
- Day cell decorated with aggregate amounts from `transactions` grouped by date
- Tap → filtered TransactionList for that date  
**Effort:** Low

---

### 9. Notes / Memo Field on Transactions
**User pain:** "I want to write 'paid for Rahul's birthday dinner' but there's nowhere to put it."  
**Behaviour:** A free-text notes/memo input on the Add/Edit Transaction screen. Shown on transaction detail. Searchable.  
**Why it matters:** The DB column `notes` / `description` already exists on the `transactions` table. The UI simply doesn't expose it. This is a trivial fix with meaningful daily value for power users.  
**Implementation path:** Single `TextFormField` on Add/Edit Transaction screen wired to the existing `notes` field.  
**Effort:** Trivial (< 1 hour)

---

### 10. Subcategories
**User pain:** "Food is too broad. I want Groceries, Dining Out, and Snacks separately but grouped under Food in reports."  
**Behaviour:** Two-level category hierarchy. Parent: Food. Children: Groceries, Dining Out, Snacks. Reports can show parent-level rollup or expand to subcategory detail.  
**Why it matters:** Users with 3+ months of data outgrow flat categories. Expense Manager and FreshBooks both have this. Required to eventually support industry-specific category sets.  
**Implementation path:**
- `parent_id INTEGER` self-reference FK on `categories` table
- Category picker shows grouped list (parent header + indented children)
- Reports: toggle between rolled-up and expanded view  
**Effort:** Medium

---

## Prioritised Delivery Order

| # | Feature | Effort | Impact | Ship when |
|---|---|---|---|---|
| 9 | Notes / memo field | Trivial | Daily | This sprint |
| 6 | Invoice viewed tracking | Low | Weekly | This sprint |
| 7 | Customer statement PDF | Low | Weekly | This sprint |
| 8 | Calendar view | Low | Occasional | Next sprint |
| 4 | Tags on transactions | Low–Medium | Weekly | Next sprint |
| 2 | Automated reminders | Medium | Daily | Next sprint |
| 3 | Split transactions | Medium | Daily | Sprint +2 |
| 5 | Bulk party payment | Medium | Weekly | Sprint +2 |
| 10 | Subcategories | Medium | Occasional | Sprint +3 |
| 1 | Receipt OCR scan | Medium | Daily | Sprint +3 |

---

## Quick-Win Sprint (Ship This Week)

These three require no new DB schema and use infrastructure already in place:

1. **Notes field (#9)** — wire existing `notes` column to the transaction form UI
2. **Invoice viewed tracking (#6)** — add `viewed_at` column, record on PDF share open
3. **Customer statement PDF (#7)** — new PDF template using existing party + invoice data

Combined effort: ~1–2 days. Combined user perception impact: significant — these address complaints users write reviews about.
