# Implementation Roadmap
# Kash Cube Development Plan

**Version:** 2.8  
**Date:** February 26, 2026  
**Duration:** 6 months (26 weeks)

---

## Design Philosophy — Dead Simple

> **Every feature must pass the 5-second test:** can a new user understand what it does in 5 seconds without reading anything? If not, it's too complex for the core app.

- **Core nav never changes:** Home · Transactions · Ledger · Reports — that's it
- **Business Mode toggle** in Settings (off by default) — enables billing/POS features; invisible to personal finance users
- **Every new feature is additive** — never replaces something simpler
- **No feature for its own sake** — if it doesn't help track or understand money faster, it doesn't ship

---

## Overview

This roadmap follows a **core-first, iterative approach**:
1. Build minimal core (Weeks 1-6)
2. Self-test for 2 weeks
3. Scale with essential features (Weeks 7-10)
4. Beta test (Weeks 11-14)
5. Launch & grow (Weeks 15-26)

---

## Phase 1: Core MVP (Weeks 1-6)

### Week 1-2: Transaction Foundation

#### Week 1: Project Setup & SMS Reading
**Goal:** Get basic SMS parsing working

**Tasks:**
- [x] Set up Flutter project structure
- [x] Configure SQLite database
- [x] Implement SMS permissions (Android)
- [x] Create SMS listener service
- [x] Parse basic UPI SMS (PhonePe, GPay)
- [ ] Test with real SMS from personal phone

**Deliverables:**
- Flutter app that can read and parse UPI SMS
- Extract: amount, merchant, date, type (sent/received)

**Time Estimate:** 40 hours

#### Week 2: Transaction UI
**Goal:** Display and add transactions

**Tasks:**
- [x] Design transaction data model
- [x] Create transaction list UI
- [x] Build add transaction screen (manual entry)
- [x] Implement transaction detail view
- [x] Add edit/delete functionality
- [x] Basic category dropdown
- [x] Bill/receipt attachment support (photo + PDF, per transaction)

**Deliverables:**
- Transaction list displaying parsed SMS
- Manual entry form for cash transactions
- CRUD operations working

**Time Estimate:** 40 hours

---

### Week 3-4: Intelligence & Credit System

#### Week 3: Smart Categorization & Business Mode
**Goal:** Auto-suggest categories and separate business/personal

**Tasks:**
- [x] Implement merchant-based categorization logic
- [x] Add business/personal toggle to transactions
- [x] Create quick confirmation dialog after SMS detection
- [x] Build daily summary dashboard
- [x] Implement smart suggestions based on history
- [x] Add transaction filters (today, week, month)

**Deliverables:**
- Auto-categorization working (80%+ accuracy)
- Quick confirm flow (<10 seconds)
- Dashboard showing daily income/expense/profit

**Time Estimate:** 40 hours

#### Week 4: Credit Management (Udhar)
**Goal:** Track credits given and received

**Tasks:**
- [x] Design credit record data model (with direction, payments)
- [x] Create "Give/Receive Credit" screen
- [x] Build collections dashboard (pending credits with filters)
- [x] Implement customer profile view
- [x] Build payment history per customer
- [x] Record payment screen with quick amount buttons

**Deliverables:**
- Can record credit given to/received from customers
- Collections dashboard with pending/overdue/cleared filters
- Customer profiles with full credit history
- Payment recording with method tracking
- DB migration v3: credit_payments table + direction column

**Time Estimate:** 40 hours

---

### Week 5-6: Essential Polish

#### Week 5: Reports & Search
**Goal:** Make data actionable

**Tasks:**
- [x] Build monthly report with P&L
- [x] Add category breakdown charts (pie charts with fl_chart)
- [x] Implement search functionality (global search screen)
- [x] Add filters (date, category, mode, type, payment method)
- [x] Add monthly trend bar chart (last 6 months)
- [x] Add loan tracking (basic model, repo, screen, payments)

**Deliverables:**
- Monthly reports showing profit/loss with month selector
- Category breakdown pie charts (income & expense)
- Monthly trend bar chart with income/expense comparison
- Top parties list by transaction volume
- Global search across transactions and credits
- Advanced transaction filters (type, category, payment method)
- Full loan tracking (add, pay, delete, detail, overdue/cleared tabs)
- Loans accessible via Home screen quick action

**Time Estimate:** 40 hours

#### Week 6: Data & Security
**Goal:** Backup and security essentials

**Tasks:**
- [x] Implement database backup/restore
- [x] Add CSV export functionality
- [x] Build PIN lock screen
- [x] Add biometric authentication
- [x] Implement recurring transactions
- [x] Fix critical bugs from testing

**Deliverables:**
- Database backup/restore via BackupService (copy/share .db files)
- CSV export with share sheet integration
- PIN lock screen (4-digit, setup/confirm/unlock/remove flows)
- Biometric authentication (fingerprint/face) via local_auth
- App lock gate on launch with auto biometric attempt
- Recurring transactions (model, repo, provider, screen, auto-generation)
- Settings screen fully wired: PIN toggle, biometric toggle, backup, restore, export
- Recurring quick action on Home screen
- MVP ready for daily use

**Time Estimate:** 40 hours

---

## ✅ End of Phase 1 Checkpoint

### Self-Test Period (2 weeks)
**Goal:** Use Kash Cube exclusively for personal finances

**Activities:**
- Use app for all financial tracking
- Note every friction point
- Test with different SMS patterns
- Measure: Do I open it 5+ times per day?
- Validate: Can I close my manual tracking sheet?

**Success Criteria:**
- ✅ 90%+ transactions auto-captured
- ✅ <10 sec to confirm transaction
- ✅ Daily dashboard gives instant insight
- ✅ Zero major bugs
- ✅ I genuinely depend on it

**Decision Point:**
- **If success criteria met:** Proceed to Phase 2
- **If not:** Iterate on core untilmet

---

## ✅ Phase 1.5: Unified Transaction Model + Bills & Payments (Weeks 7–7.5)

### Week 7: Architecture Redesign
**Goal:** Unify all financial events (income, expense, lending, borrowing, investment, settlement) into a single Transaction model with progressive disclosure form

**Tasks:**
- [x] Expand TransactionType enum: `income, expense, lent, borrowed, invested, receivedBack, paidBack, redeemed` (+ `transfer` as 9th type)
- [x] Add nullable lending fields to Transaction model (dueDate, interestRate, interestType, repaymentFrequency, totalInstallments, emiAmount, linkedTransactionId, toAccountId)
- [x] DB migration V6→V7: add columns, migrate loans data, update type enum values
- [x] DB migration V7→V8: add `to_account_id` column, pre-seed 3 default accounts (Bank, UPI/Wallet, Cash)
- [x] Remove separate Loan model, loan_repository, loan_provider
- [x] Update SMS parser with keyword→type detection (EMI→paidBack, SIP→invested, loan disbursed→borrowed)
- [x] Rebuild Add/Edit Transaction screen with progressive disclosure (2-3 fields default, expanding based on type)
- [x] Rebuild Ledger screen as grouped aggregation view (GROUP BY party from transactions table)
- [x] Update Home dashboard, search, and providers to use unified model
- [x] Update all tests for new transaction types

**Additional tasks completed (beyond original scope):**
- [x] Remove `investment` from `TransactionMode` — only `personal` / `business` remain; mode field hidden for non-income/expense types
- [x] Add `transfer` as 9th `TransactionType` with from/to account pickers in the form
- [x] Multi-account infrastructure: `AccountRepository` interface + `AccountRepositoryImpl` + `accountsProvider`
- [x] `AccountsManageScreen` accessible from Settings (add/edit/archive accounts)
- [x] `showAccountPicker()` reusable bottom sheet widget
- [x] `LedgerPartyEntry.partyType` sourced via LEFT JOIN with `parties` table (`'person'` / `'vendor'`)
- [x] Settings gear icon added to Home app bar
- [x] Custom app launcher icon generated from `assets/logo.png` (adaptive icon, API 26+)
- [x] Compact pinned `SliverAppBar` replacing the large variant

**Week 7.5 — Bills & Payments UX Overhaul (26 Feb 2026):**
- [x] Speed-dial FAB: Transaction / Loan·Lend / Bills & Pay
- [x] Home card "Ledger" tile renamed to "Loans" (`handshake_outlined` icon)
- [x] Merged `Bill` + `RecurringTransaction` models → unified `ScheduledPayment` model
  - `ScheduledFrequency` enum with `toMonthly()` / `nextOccurrence()` helpers
  - `isOneTime`, `autoCreate`, `isAutoPay`, `isPaidThisPeriod`, `isOverdue`, `daysUntilDue`
- [x] New `ScheduledPaymentRepository` (domain interface + SQLite impl)
- [x] New `scheduledPaymentsProvider` (StateNotifier: add / update / remove / markPaid / markUnpaid)
- [x] `processScheduledAutoCreations()` replaces `processDueRecurringTransactions()`
- [x] New `BillsAndPaymentsScreen` — filter chips (All / Recurring / One-time / Overdue / Paid), summary card (monthly in/out), swipe-to-pay dismissible list
- [x] New `AddEditScheduledPaymentScreen` — type toggle (Expense/Income), schedule toggle (Recurring/One-time), frequency dropdown, due-day picker, one-time date picker, auto-create & auto-pay switches
- [x] Home screen Overview & Personal cards: "Bills" + "Recurring" tiles → single "Bills & Pay" tile → `BillsAndPaymentsScreen`
- [x] `upcomingItemsProvider`: `BillUpcomingItem` → `ScheduledUpcomingItem(payment)`
- [x] `NotificationService` updated for `ScheduledUpcomingItem`
- [x] DB v9 → v10: `scheduled_payments` table with migration from `bills` + `recurring_transactions`

**Deliverables:**
- Single Transaction model for ALL financial events (9 types)
- Progressive form: select type → relevant fields appear
- Ledger tab shows net positions per party (who owes what)
- Transfer type: from-account / to-account pickers, no party name needed
- Multi-account support: manage accounts from Settings
- No separate Credits/Loans screens — everything is a transaction
- Single "Bills & Payments" entry point replacing two separate screens
- Unified `ScheduledPayment` model covering bills, subscriptions, salary, EMIs, one-time reminders

**Time Estimate:** 50 + 12 hours (delivered)

---

## Phase 2: Scale Features (Weeks 8-11)

### Week 8: Money Management
**Goal:** Add budget tracking and savings goals

**Tasks:**
- [ ] Implement category-wise budgets
- [ ] Add budget vs actual tracking
- [ ] Build budget alerts (80%, 100%, exceeded)
- [ ] Create savings goals feature
- [ ] Add spending insights
- [ ] Build weekly summary notification

**Deliverables:**
- Can set monthly budgets per category
- Alerts when approaching limit
- Visual progress on savings goals

**Time Estimate:** 40 hours

---

### Week 9: Complete Financial View + Party Management
**Goal:** Parse all financial SMS and make parties first-class citizens

#### Part A — SMS Completeness
- [ ] Add credit card SMS parsing (HDFC, ICICI, SBI, Axis)
- [ ] Add debit card SMS parsing
- [ ] Add bank account SMS parsing (NEFT, RTGS, balance updates)
- [ ] Add duplicate transaction detection
- [ ] Build account balance tracking (per-account running balance)

#### Part B — Customer / Vendor Management

**DB migration:** add `phone`, `email`, `notes` columns to existing `parties` table — one migration, zero breaking changes.

**Privacy approach:**
- No `READ_CONTACTS` permission — never
- "Pick from Contacts" uses a one-shot `Intent.ACTION_PICK` OS picker; the system contacts app opens, user selects one person, only that name + number is returned. KashCube never sees the rest of the phonebook.

**Tasks:**
- [ ] DB migration: add `phone TEXT`, `email TEXT`, `notes TEXT` to `parties` table
- [ ] Rebuild Parties screen: add/edit with name, phone, email, type (Customer / Vendor / Individual), GSTIN (optional), notes
- [ ] "Pick from Contacts" one-shot OS picker button on party form (no permission needed)
- [ ] Party detail screen: unified history — transactions + credits/loans + scheduled payments all in one view
- [ ] Autocomplete on party name field across all entry screens (already partially there)
- [ ] Send reminder actions on credits and loans: bottom sheet → WhatsApp / SMS / Email
  - WhatsApp: `wa.me/91XXXXXXXXXX?text=...` deep link
  - SMS: `sms:+91XXXXXXXXXX?body=...` Android intent
  - Email: `mailto:...?subject=...&body=...` intent
  - All three are OS intents — KashCube never touches the network
  - User reviews and edits the pre-filled message before sending
  - Log "reminder sent" timestamp on the credit/loan record after dispatch

**Message templates (locally generated, user-editable before send):**
```
Udhar / Credit reminder:
  "Hi [Name], friendly reminder — ₹[amount] is due
   (since [date]). Let me know. — [Your name]"

Loan overdue:
  "Hi [Name], ₹[amount] (due [date]) is still pending.
   Please pay when convenient. — [Your name]"
```

- [ ] Add `reminderSentAt` field to credits and loans tables

**Deliverables:**
- Parties are full profiles with contact details
- One-shot contact picker: zero permissions, full convenience
- WhatsApp/SMS/Email reminders from any credit or loan — all OS intents, no network
- Party detail shows complete financial relationship at a glance
- SMS parsing covers major Indian banks and cards
- Duplicate transaction detection active

**Time Estimate:** 55 hours

---

### Week 10: Smart Features
**Goal:** Handle edge cases and advanced scenarios

**Tasks:**
- [ ] Add refund tracking and linking
- [ ] Implement failed transaction tracking
- [ ] Add cashback detection and tracking
- [ ] Build merchant intelligence (spending patterns)
- [ ] Add ATM withdrawal tracking
- [ ] Implement wallet balance tracking (Paytm, Amazon Pay)
- [ ] Receipt scanning via on-device ML Kit OCR (Indian receipt layouts)

**Deliverables:**
- Refunds link back to original transactions
- Cashback tracked separately
- Complete picture of all money movement
- Auto-extract amount + store from photographed receipts (cash transactions)

**Time Estimate:** 40 hours

---

### Week 11: UX Polish
**Goal:** Make experience delightful

**Tasks:**
- [ ] Build home screen widget (Android)
- [ ] Add quick actions (long-press app icon)
- [ ] Implement voice input for manual entry
- [ ] Add calculator in amount fields
- [ ] Build net worth dashboard
- [ ] Add spending pattern insights
- [ ] Performance optimization (handle 10k+ transactions)

**Deliverables:**
- Widget shows quick stats
- Voice: "Add 500 rupees food"
- Fast even with large dataset

**Time Estimate:** 40 hours

---

## ✅ End of Phase 2 Checkpoint

### Feature Validation (1 week)
**Goal:** Validate scaled features with 10-20 beta users

**Activities:**
- Recruit friends/family as testers
- Collect usage data (crash-free, feature usage)
- Gather qualitative feedback
- Measure retention (Day 1, 3, 7)

**Success Criteria:**
- ✅ 70%+ Day-7 retention
- ✅ No critical bugs
- ✅ Positive NPS from beta users
- ✅ At least 3 features users "can't live without"

**Decision Point:**
- **If validated:** Prepare for public beta
- **If not:** Iterate based on feedback

---

## Phase 3: Beta Release (Weeks 11-14)

### Week 11: Beta Preparation
**Goal:** Prepare for wider testing — first impression must be instant and trustworthy

**Tasks:**

#### Setup Screen (3 screens, always skippable)

```
Screen 1 — Welcome
  Headline: "Your money. Your phone. Nobody else."
  Subtext:  "KashCube reads your SMS locally and never
             sends anything anywhere."
  CTA: Get Started  (skip link bottom-right)

Screen 2 — Permissions
  [ ] Read SMS      "Auto-captures UPI & bank transactions"
  [ ] Notifications "Reminds you before bills are due"
  Biometric lock    optional toggle (on by default if hardware present)
  → Grant & Continue  (triggers Android system dialogs in sequence)
  Note: if denied, explains how to grant later from Settings

Screen 3 — How do you use money?
  ○ Personal only         (default — Business Mode off)
  ○ Business + Personal   (enables Business Mode in Settings)
  Optional: monthly income range  (pre-seeds budget thresholds)
  → Start Tracking
```

**Rules:**
- Skip button always visible on all 3 screens — never block entry
- No account creation, no email, no sign-in — ever
- No feature walkthroughs or tooltips — users learn by doing
- Skipping everything still gives a fully working app
- `setupCompletedProvider` boolean in Settings — shows setup only on first launch

- [ ] Build 3-screen setup flow (Welcome → Permissions → Profile)
- [ ] Wire SMS + notification permission dialogs to Screen 2
- [ ] Save `businessModeEnabled` + income range from Screen 3 to Settings
- [ ] Gate setup on first-launch flag; never show again after completion
- [ ] Set up local crash logging (write to file, shareable via Settings)
- [ ] Build in-app feedback sheet (text + optional log attachment, shared via `share_plus`)
- [ ] Create beta test plan doc
- [ ] Prepare Play Store Beta track

**Deliverables:**
- Setup completes in <30 seconds including permission dialogs
- SMS permission granted rate >80% (context-first approach)
- Business Mode correctly set at onboarding, changeable in Settings
- Beta track on Play Store

**Time Estimate:** 45 hours

---

### Week 12: Beta Launch
**Goal:** Get to 50-100 beta testers

**Tasks:**
- [ ] Launch TestFlight/Play Store Beta
- [ ] Write launch post for beta community
- [ ] Create demo video
- [ ] Set up feedback channels (Telegram/Discord)
- [ ] Monitor crashes and bugs
- [ ] Daily bug fixes and improvements

**Deliverables:**
- 50+ beta testers onboarded
- Feedback loop established
- Critical bugs identified and fixed

**Time Estimate:** 40 hours

---

### Week 13-14: Beta Iteration
**Goal:** Polish based on real-world usage

**Tasks:**
- [ ] Analyze user feedback and pain points
- [ ] Fix top 10 reported bugs
- [ ] Optimize most-used flows
- [ ] Improve SMS parsing accuracy
- [ ] Add missing bank/UPI patterns
- [ ] Performance optimization
- [ ] Prepare Play Store listing

**Deliverables:**
- Stable build with <1% crash rate
- 90%+ SMS parsing accuracy
- Play Store listing ready (screenshots, description)

**Time Estimate:** 60 hours

---

## Phase 4: Public Launch (Weeks 15-18)

### Week 15: Launch Preparation
**Goal:** Prepare for public release

**Tasks:**
- [ ] Finalize Play Store listing
- [ ] Create marketing materials
- [ ] Write launch blog post
- [ ] Prepare social media content
- [ ] Set up analytics (privacy-friendly)
- [ ] Create demo videos and screenshots
- [ ] Build landing page

**Deliverables:**
- Play Store submission ready
- Marketing collateral complete
- Landing page live

**Time Estimate:** 40 hours

---

### Week 16: Public Launch 🚀
**Goal:** Launch on Play Store

**Tasks:**
- [ ] Submit to Play Store
- [ ] Launch on Product Hunt
- [ ] Post on Reddit (r/india, r/india investments)
- [ ] Tweet launch announcement
- [ ] Email beta users
- [ ] Monitor reviews and respond
- [ ] Track downloads and retention

**Deliverables:**
- Live on Play Store
- Initial reviews and ratings
- 1,000+ downloads (target)

**Time Estimate:** 30 hours (plus monitoring)

---

### Week 17-18: Post-Launch Support
**Goal:** Stabilize and iterate

**Tasks:**
- [ ] Monitor crash reports daily
- [ ] Fix critical bugs within 24 hours
- [ ] Respond to all Play Store reviews
- [ ] Analyze user behavior
- [ ] Identify drop-off points
- [ ] Optimize onboarding if <50% completion
- [ ] Plan next features based on requests

**Deliverables:**
- Stable release (v1.0.1, v1.0.2)
- <1% crash rate
- 60%+ onboarding completion
- Roadmap for next features

**Time Estimate:** 60 hours

---

## Phase 5: Growth & Monetization (Weeks 19-26)

### Week 19-20: Pro Tier
**Goal:** Simple monetisation — one upgrade, clear value

**Guiding rule:** Pro features enhance what's already useful; they don't add complexity to the free tier.

**Tasks:**
- [ ] Implement in-app purchase (Google Play Billing — one-time or annual)
- [ ] Build Pro upgrade flow (single screen, clear value props)
- [ ] Advanced reports: custom date ranges, category drill-down (Pro)
- [ ] PDF export with branded invoice/statement layout (Pro, uses `pdf` package — 100% local)
- [ ] Month-over-month comparison chart (Pro)
- [ ] Budget tracking with category limits + visual progress bars (Pro)
- [ ] Test payment flow end-to-end

**Deliverables:**
- Pro plan purchasable from Settings
- 3–4 Pro features clearly surfaced behind a paywall
- Free tier remains fully functional for core tracking

**Time Estimate:** 45 hours

---

### Week 21-22: Business Mode — Billing & Invoicing
**Goal:** Opt-in business layer; zero impact on personal finance users

**Guiding rule:** Business Mode is a toggle in Settings. When off, none of these screens or nav items appear. The core 4-tab nav never changes.

**Architecture:**
```
item_catalog     (name, unit_price, tax_pct, hsn_code*, is_active)
quotes           (customer_party_id, status, valid_until, total, notes)
quote_items      (quote_id, item_name, qty, unit_price, discount_pct, line_total)
invoices         (quote_id?, invoice_no, status, due_date, total, paid_amount,
                  customer_party_id, notes)
                  -- status: draft | sent | paid | overdue
invoice_items    (invoice_id, item_name, qty, unit_price, line_total)
```
*hsn_code stored but not validated until GST scope opens

**Tasks:**
- [ ] Add `businessModeEnabled` to Settings
- [ ] Item catalog screen: add/edit products & services with price + tax %
- [ ] Quote builder: pick customer (from parties), add items, apply discount, save draft
- [ ] Quote → Invoice conversion (one tap; auto-assign INV-YYYY-NNN)
- [ ] Invoice payment recording → auto-creates `Transaction(type: income)` in main ledger
- [ ] Quote/Invoice list with status filters (Draft / Sent / Paid / Overdue)
- [ ] Share invoice as PDF (offline, `pdf` + `share_plus`)
- [ ] Basic GST line items: CGST + SGST / IGST split shown on invoice (no GSTIN validation yet)
- [ ] Send quote/invoice via WhatsApp / SMS / Email (OS intents, same pattern as Week 9)

**Message templates (locally generated, user-editable):**
```
Quote sent:      "Hi [name], quote #[no] for ₹[amt]. Valid till [date]. — [biz]"
Invoice due:     "Hi [name], invoice #[no] ₹[amt] due [date]. — [biz]"
Invoice overdue: "Hi [name], invoice #[no] ₹[amt] was due [date]. Still pending. — [biz]"
```

**Explicitly out of scope this sprint:**
- POS quick mode / counter billing → Year 2 (see Future Backlog)
- Delivery flow / order tracking → Year 2
- Stock / inventory management → Year 2
- GSTIN validation → regex check, add when needed
- e-Invoicing / IRN → requires network call, deferred indefinitely
- Recurring invoices → hook exists via ScheduledPayment, wire up later

**Deliverables:**
- Business Mode off by default — personal users see nothing new
- Full quote → invoice → payment → ledger pipeline working locally
- PDF invoice shareable via WhatsApp / email
- Transaction bridge: paid invoice = income entry in main dashboard

**Time Estimate:** 60 hours

---

### Week 23-24: Retention & Reach
**Goal:** Make the app stickier without adding complexity

**Guiding rule:** Only ship retention features that work passively — no features that require the user to change their behaviour.

**Tasks:**
- [ ] Smart due-date notifications (loans, bills) — already architected, tune thresholds
- [ ] Monthly summary notification ("Here's your February: spent ₹X, saved ₹Y")
- [ ] Bank statement CSV import (map columns → transactions; handles HDFC, SBI, ICICI formats)
- [ ] Month-over-month comparison in Reports (already deferred from Pro tier if not done)
- [ ] Play Store rating prompt (after 10th transaction, not on launch)
- [ ] Referral / share card ("I track finances with Kash Cube — try it")

**Explicitly not doing:**
- Spending predictions (needs 3+ months data; backlogged)
- Referral rewards / gamification (adds complexity, deferred)
- Import from other finance apps (low priority, backlogged)

**Deliverables:**
- Passive notifications that drive daily opens
- CSV import covering top 3 Indian banks
- Organic growth hook via share card

**Time Estimate:** 40 hours

---

### Week 25-26: Scale & Optimize
**Goal:** Prepare for growth — keep it fast and small

**Tasks:**
- [ ] Performance optimization for 50k+ transactions (pagination, query indexing)
- [ ] Add Hindi language support (intl ARB files)
- [ ] Optimize app size (<20MB)
- [ ] Plan iOS version
- [ ] Review and cut any feature that fails the 5-second test

**Deliverables:**
- App handles scale gracefully
- Hindi support live
- iOS development plan ready

**Time Estimate:** 50 hours

---

## Future Backlog (Post Week 26 — demand-driven)

These features are **intentionally deferred**. Each is additive with no architectural rework needed. Ship only when real user demand justifies the complexity cost.

### Year 2: POS & Counter Business Mode

> **Context:** Designed for takeaway restaurants, medical shops, salons, repair shops — any counter business that needs: create bill fast → collect payment → notify customer → verify delivery. Architecture spec is complete (see git history); deferred until billing (Week 21-22) has real users.

**The flow:**
```
POS Quick Mode → tap items → running total → "Collect & Confirm"
  → payment recorded → order # + 4-digit delivery token generated
  → WhatsApp/SMS confirmation sent (OS intent)
  → "Out for Delivery" tap → dispatch message sent
  → Delivery View → customer shows token → cashier enters token → Delivered ✓
```

**Token verification (offline, no network):**
`(orderId * 7 + secondOfDay) % 9000 + 1000` — 4-digit PIN, locally derived. No QR, no deep link, no internet.

**DB additions needed on top of Week 21-22 schema:**
```
invoices: + order_type ('invoice'|'pos'), + status ('out_for_delivery'|'delivered'), + delivery_token
```

**Applicable business types:**
| Business | Catalog items | "Delivered" maps to |
|---|---|---|
| Takeaway restaurant | Menu items | Food handed to customer |
| Medical shop | Medicines | Prescription picked up |
| Salon / spa | Services | Appointment completed |
| Repair shop | Services + parts | Device handed back |
| Any retail counter | Products | Item handed over |

**Message templates:**
```
Order confirmed:  "Order #[no] ✓ [items] Total: ₹[amt] Token: [pin] — [biz]"
Out for delivery: "Order #[no] is on the way! Show token [pin]. — [biz]"
Delivered:        "Order #[no] delivered ✓ Thank you! — [biz]"
```

**Explicitly NOT in Year 2 scope:**
- Kitchen display / table management
- Thermal printer (Android print API exists, wire up in Year 3)

**Effort:** ~3 weeks on top of working billing (Week 21-22)

---

### Year 2: Multi-Device Sync — Tier 3 (P2P Cross-Network)

> **Prerequisites:** Tier 1 (same-network sync) must be live and battle-tested first. Tier 3 is a philosophical compromise — it requires a minimal rendezvous node to punch through NATs. The node is open-source and self-hostable; the app still works fully without it.

**Why not earlier:** Tier 1 covers 80% of real use cases (family, shop WiFi). Tier 3 only matters when devices are on different networks at the same time.

**Architecture:**
```
Device A ──┐                    ┌── Device B
           └── STUN/relay node ─┘
                (self-hosted or
                 community node)
```
- libp2p or WebRTC with STUN for NAT traversal
- Relay node is stateless — only brokers the initial handshake, never sees data
- All data is encrypted end-to-end (same keys from Tier 1 pairing)
- Sync protocol identical to Tier 1 — just the transport changes
- App works 100% offline if relay is unreachable

**Permission model:** unchanged from Tier 1 — signed grants, scoped keys.

**Honest constraints:**
- "Zero network calls" rule is relaxed to "zero data leaves the device unencrypted"
- User must agree to this explicitly in Settings (opt-in, default off)
- Self-hostable relay means power users can run their own

**Effort:** ~3 months (transport layer swap on top of Tier 1 event log)

---

### Business Mode Extensions

| Feature | Effort | Prerequisites | Notes |
|---------|--------|---------------|-------|
| Stock / Inventory management | M | Business Mode live | Add `stock_qty` + `track_stock` to `item_catalog`; decrement on invoice paid |
| GSTIN validation | S | Business Mode live | Regex only — 100% local, no API |
| HSN code display on invoices | S | Business Mode live | Column already in schema, just surface in UI |
| GSTR-1 CSV export | M | HSN codes | Group invoices by HSN; same pattern as existing CSV export |
| Recurring invoices | S | Business Mode live | Wire `ScheduledPayment(autoCreate=true)` to generate invoices instead of transactions |
| UPI collect deep-link | S | Invoice screen | Pre-fill PhonePe/GPay collect URL; user completes in their UPI app |
| Multi-currency invoicing | L | — | Add `currency` column; manual exchange rates; ledger always stays INR |

### Core App Extensions

| Feature | Effort | Prerequisites | Notes |
|---------|--------|---------------|-------|
| Bank statement CSV/PDF import | M | — | Parse common bank statement formats; map to transactions |
| Voice input for manual entry | M | — | On-device speech-to-text via Android SpeechRecognizer |
| Home screen widget (Android) | M | — | Glance/AppWidget: today's balance + quick add |
| Net worth dashboard | S | Account balances | Sum all account balances minus outstanding loans |
| Spending predictions | L | 3+ months data | Simple linear trend on category spend; fully local |
| Multi-user profiles | L | — | Separate SQLite DBs per profile; PIN-protected switch |

### Multi-Device Sync — Tier 1 (Post Week 26, ~6 weeks)

> **Use cases:** Family members on same home WiFi, shop owner + cashier on same shop WiFi. No internet, no server, fully offline.

**How it works:**
```
Device A (Owner)                Device B (Staff/Family)
   |                                  |
   |── mDNS broadcast ──────────────> |
   |<─ mDNS response ────────────────|
   |── QR code pairing ─────────────>|  (one-time key exchange)
   |── signed permission grant ─────>|  (role: staff/viewer/co-owner)
   |                                  |
   |<═══════ TCP socket sync ════════>|  (exchange event log deltas)
```

**DB additions:**
```sql
sync_devices  (device_id, name, public_key, role, granted_at, last_seen)
sync_events   (id, table_name, row_id, operation, payload_json,
               vector_clock, device_id, created_at)
               -- append-only; never deleted; this IS the source of truth
```

**Permission roles:**
| Role | Can do |
|---|---|
| Owner | Full read/write, manage devices |
| Co-owner | Full read/write, no device management |
| Staff | Add transactions, view dashboard; no credits/loans |
| Viewer | Read-only; no sensitive data |
| Accountant | Export only |

**Conflict resolution:** Last-write-wins per row (vector clock timestamp). Edge cases surfaced as UI prompt — user picks winner.

**Explicitly out of scope:**
- Cross-network sync (different WiFi) → Tier 2/3
- Real-time collaborative editing → not needed for financial data

**Effort:** ~6 weeks. Requires `sync_events` event log architecture decision before Week 21-22 DB work (additive, no rework).

---

### Multi-Device Sync — Tier 2 (6 Months Post-Launch, ~4 weeks)

> **Use cases:** Share data with accountant, sync between home and office, async family sync when not on same WiFi. No automatic sync — user-initiated.

**How it works:**
```
Device A: Export → encrypted .kashcube sync package
   → User sends via WhatsApp / email / USB / AirDrop
Device B: Import → decrypt with own key → merge event log
```

- Encrypted with recipient device's public key (from Tier 1 pairing)
- Permission scope baked into the package — a Viewer key can only decrypt their scope
- Merge is identical to Tier 1 (event log replay) — just async instead of live
- Works across any network, any distance, zero server
- No automatic background sync — fully intentional

**This is the privacy purist's version of cross-network sync:** you choose exactly when data leaves the device and to whom.

**Effort:** ~4 weeks on top of Tier 1 event log (transport is file I/O instead of TCP socket).

---

### Compliance (Deferred Indefinitely)

| Feature | Why Deferred |
|---------|-------------|
| e-Invoicing / IRN generation | Requires network call to NIC IRP portal — breaks privacy architecture; only relevant for >₹5Cr turnover businesses |
| Full GSTR filing | Rabbit hole; dedicated CA software handles this better |
| Payment gateway (Razorpay, PayU) | Requires network + SDK that phones home; use UPI deep-link workaround instead |

> **Rule:** Before picking anything from this backlog, ask — does removing this feature make the app meaningfully worse for the majority of users? If the answer is no, leave it here.

---

## Success Milestones

| Milestone | Target Date | Success Metric |
|-----------|-------------|----------------|
| MVP Complete | Week 6 | Daily use by developer |
| Beta Launch | Week 12 | 50 beta users, 70% retention |
| Public Launch | Week 16 | 1,000 downloads |
| First 10,000 users | Week 22 | 10,000 installs, 60% retention |
| Pro Launch | Week 20 | 100 paying users |
| Profitability | Week 26 | ₹50,000/month revenue |

---

## Resource Allocation

### Development Time (26 weeks)
- **Core Development:** 1,000 hours
- **Testing:** 150 hours
- **Bug Fixes:** 100 hours
- **Marketing/Content:** 50 hours
- **Total:** ~1,300 hours

### Team (Initial)
- **Solo Developer:** Core development
- **Beta Testers:** 50-100 volunteers
- **Advisors:** 2-3 for feedback

### Budget (Bootstrap Friendly)
- **Development:** ₹0 (self-developed)
- **Design Assets:** ₹5,000 (icons, graphics)
- **Play Store Fee:** $25 one-time
- **Domain/Hosting:** ₹2,000/year
- **Total Year 1:** <₹10,000

---

## Risk Mitigation

### Technical Risks
- **Risk:** SMS parsing accuracy <90%
  - **Mitigation:** Extensive testing; user feedback loop; pattern database
- **Risk:** Performance issues with large datasets
  - **Mitigation:** Performance testing from Week 1; pagination; indexing

### Product Risks
- **Risk:** Users don't find it useful
  - **Mitigation:** Self-dogfooding; early beta testing; iterate based on feedback
- **Risk:** Competition copies features
  - **Mitigation:** Focus on privacy and UX; build loyal community; open source advantage

### Business Risks
- **Risk:** Low monetization
  - **Mitigation:** Freemium model; multiple tiers; one-time purchase option
- **Risk:** Play Store rejection
  - **Mitigation:** Follow guidelines strictly; clear SMS permission explanation; privacy policy

---

## Decision Points

### After Phase 1 (Week 6)
**Question:** Is the core MVP useful enough for daily use?
- **Yes:** Proceed to Phase 2
- **No:** Iterate on core features

### After Phase 2 (Week 10)
**Question:** Do beta users find it valuable?
- **Yes:** Proceed to public launch
- **No:** Pivot or improve based on feedback

### After Phase 4 (Week 18)
**Question:** Is there product-market fit?
- **Yes:** Invest in growth and monetization
- **No:** Re-evaluate product direction

---

## Next Steps

### This Week
1. ✅ Complete documentation
2. ✅ Set up development environment
3. ✅ Create Flutter project structure
4. ✅ Week 1 tasks (SMS reading) — complete
5. ✅ Week 2 tasks (Transaction UI) — complete
6. ✅ Week 3 tasks (Smart categorization, filters, confirmation flow) — complete
7. ✅ Week 4 tasks (Credit management / Udhar) — complete
8. ✅ Week 5 tasks (Reports & Search) — complete
9. ✅ Week 6 tasks (Data & Security) — complete
10. ✅ Week 7 tasks (Unified Transaction Model, Transfer type, multi-account) — complete
11. ✅ Week 7.5 tasks (Bills & Payments unification, ScheduledPayment model, DB v10) — complete
12. Begin Phase 2 — Week 8: Budget tracking & savings goals

### This Month (Weeks 1-7)
- ✅ Complete transaction foundation (Week 1-2)
- ✅ Build credit management (Week 3-4)
- ✅ Reports, search, filters, loan tracking (Week 5)
- ✅ Backup, PIN lock, biometric, recurring transactions (Week 6)
- ✅ Phase 1 MVP — Complete
- ✅ Unified Transaction Model v7+v8, Transfer type, multi-account (Week 7)
- ✅ Phase 1.5 — Complete
- ✅ Bills & Payments UX Overhaul (Week 7.5) — Complete
- Begin Phase 2: Week 8 (Budgets & Savings Goals)

### Overall Progress
| Week | Status | Key Deliverables |
|------|--------|-----------------|
| Week 1 | ✅ Complete (5/6) | SMS parser, DB schema, SMS listener |
| Week 2 | ✅ Complete (7/7) | Transaction CRUD, bill attachments |
| Week 3 | ✅ Complete (6/6) | Auto-categorization, SMS confirmation, filters |
| Week 4 | ✅ Complete (6/6) | Credit give/receive, collections dashboard, customer profiles |
| Week 5 | ✅ Complete (6/6) | Reports with charts, global search, advanced filters, loan tracking |
| Week 6 | ✅ Complete (6/6) | Backup/restore, CSV export, PIN lock, biometric auth, recurring transactions |
| Week 7 | ✅ Complete (9/9 + extras) | Unified model v7+v8, 9 types, progressive form, Ledger rebuild, Transfer type, multi-account, custom icon |
| Week 7.5 | ✅ Complete | ScheduledPayment model, BillsAndPaymentsScreen, speed-dial FAB, DB v10 |

**Codebase:** ~85 Dart files in `lib/`, 0 lint issues  
**Database:** SQLite v10 (transactions + accounts + scheduled_payments + 9 other tables)  
**Phase 1 MVP:** COMPLETE  
**Phase 1.5 (Unified Model + Bills & Payments):** COMPLETE  
**Current Phase:** Phase 2 (Scale Features) — starting Week 8

### This Quarter (Weeks 1-12)
- Launch MVP
- Scale features
- Beta release

---

## Appendix

### Development Tools
- **IDE:** VS Code with Flutter extensions
- **Version Control:** Git + GitHub
- **Database:** SQLite (sqflite package)
- **State Management:** Riverpod (vs Provider)
- **Testing:** Flutter test framework
- **CI/CD:** GitHub Actions (for automated testing)

### Key Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0
  path_provider: ^2.1.1
  riverpod: ^2.4.0
  telephony: ^0.2.0  # SMS reading
  fl_chart: ^0.66.0  # Charts
  intl: ^0.19.0  # Date formatting
  local_auth: ^2.1.7  # Biometric
  path: ^1.8.3
```

### Performance Targets
- App launch: <2 seconds
- Transaction list (1000 items): 60 FPS scroll
- Search 10k transactions: <100ms
- SMS parsing: <500ms
- Database query: <50ms average

---

**Next Document:** [Technical Architecture](./TECHNICAL_ARCHITECTURE.md)
