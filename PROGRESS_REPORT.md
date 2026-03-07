# Kash Cube - Progress Report
**Date:** 7 March 2026  
**Current Phase:** Unified Tracking System — All 3 Phases ✅ COMPLETE

---

## Executive Summary

The app has grown dramatically since the last report (27 Feb). Since then, two
full implementation plans have landed:

1. **March/April 2026 Plan (Tracks A + B + Phase 2)** — Fiscal Year
   Management and Storage/Disaster Recovery — **100% complete** (commits
   `d0a3eb6` → `5f4d00e`).
2. **Unified Tracking System (Pillars A–D + Shared Lifecycle Layer)** — Party
   360° View, Cash Flow Timeline, Bulk Actions, Business Flow Tracker,
   LifecycleTag — **Phases 1 & 2 complete, Phase 3 complete except widget
   tests** (commit `2182d68`).

**Database:** v45 (stable)  
**Flutter Analyze:** 21 issues — **3 actual errors** in `party_statement_pdf_service.dart` (const-eval type), 2 warnings, 16 info-level hints. Needs a fix pass.  
**App Status:** Feature-rich, approaching beta readiness. Core UX is solid.

---

## What Shipped Since 27 Feb 2026

### March/April 2026 Plan — ALL COMPLETE

#### Track A — Fiscal Year Management
- [x] DB schema: 7 FY settings keys added (`fiscal_year_start_month`, `invoice_no_format`, `auto_reset_invoice_no`, etc.)
- [x] `FiscalYearService` — `currentFiscalYear`, `getFYLabel()`, `isApproachingYearEnd()`, `isResetDue()`, `nextInvoiceNo()`
- [x] `InvoiceNumberService` fully refactored — FY-aware format (`INV-25-26-042`), auto-resets on 1 April
- [x] FY quick filter in Reports screen — `[This FY ●]  [Last FY]  [Custom]` chip row
- [x] Year-end warning notifications (7d, last day, next day triggers)
- [x] Home screen dismissible `MaterialBanner` — shown from 25 March until FY closed

#### Track B — Storage & Disaster Recovery
- [x] WAL mode + daily integrity check + rolling snapshot (`kash_cube_prev.db`)
- [x] `android/app/src/main/res/xml/data_extraction_rules.xml` — exclude-only Android backup strategy
- [x] `PdfCacheManager` — ephemeral PDFs with FY-prefixed filenames, auto-purge >24h
- [x] `StorageHealthScreen` — per-FY usage bar, image bar, "Back Up Now", "Clear cache"
- [x] Image compression on import — 800×600, quality 70, hard cap 150 KB
- [x] DB `VACUUM` on 30-day schedule via background Isolate
- [x] Encrypted `.kashcube` export/import — AES-256-GCM + PBKDF2 (generation + restore, 5-attempt lockout)
- [x] Onboarding backup nudge (after 5 transactions, monthly reminder)

#### Phase 2 — Year-End Closing Wizard
- [x] 3-step wizard UI
- [x] FY archiving to `archive_FY{YYYY}.db`
- [x] Backup prompt in wizard Step 3
- [x] `backup_rules.xml` updated to include archive DBs

---

### Unified Tracking System — COMPLETE (Phase 3 tests pending)

#### Pillar A — Party 360° View
- [x] `PartyFinancialSummary` model with `compute()` factory
- [x] `partyFinancialSummaryProvider(partyId)` — parallel SQLite queries
- [x] `Party360Screen` — net outstanding chip, per-module summary rows  
- [x] `Party360Screen` unified timeline — all invoices, dues, loans, transactions, bookings in one list
- [x] "Deals" tab — `FlowChainTile` per business chain
- [x] Navigation: party name tap in Action Center → `Party360Screen`
- [x] Party search autocomplete shows net outstanding balance

#### Pillar B — Cash Flow Timeline
- [x] `CashFlowEvent` sealed class (`RecordedEvent`, `OverdueEvent`, `UpcomingEvent`)
- [x] `cashFlowTimelineProvider` — merges 9 sources, 90-day window
- [x] `CashFlowScreen` — month navigator, PAST/TODAY/UPCOMING dividers, filter chips, tap-to-detail
- [x] Reports screen prominent card → `CashFlowScreen`

#### Pillar C — Bulk Actions
- [x] Multi-select mode in `ActionCenterScreen` (long-press or AppBar toggle)
- [x] `BulkReminderService` — sequential WhatsApp deep-link per item, SMS fallback
- [x] Consolidated Party Statement PDF — `PartyStatementPdfService`

#### Pillar D — Business Flow Tracker
- [x] `BusinessFlowChain` model (4 chain types: Quote, Challan, Booking, Direct Invoice)
- [x] `BusinessFlowChainBuilder` — pure Dart, FK-based assembly (no DB migration needed)
- [x] `businessFlowChainsProvider(partyId)` + `leakingChainsProvider`
- [x] `FlowChainTile` widget with reminder event nodes woven in
- [x] Revenue Leakage alerts in Action Center — `ActionItemType.leakingChain`, dedicated "Leaking" section

#### Shared Lifecycle Layer
- [x] `LifecycleStage` enum + `LifecycleInfo` value class
- [x] `LifecycleClassifier` — pure Dart, 5 type-specific classifiers
- [x] `LifecycleTag` widget — colour-coded `[ SENT · 14d ]` pill
- [x] Wired into: Action Center tiles, `InvoiceDetailScreen`, `FlowChainTile`, `Party360Screen` timeline, `CashFlowScreen` tiles
- [x] Context-aware action button labels (Send Reminder / Follow Up / Collect Now / Record Balance)
- [x] "Stale Items" filter chip (items with `daysInStage > 7`) + amber left-border in Party360

#### Other work shipped in same period
- [x] Party Document Ledger — Options A, B, C + outstanding balance
- [x] Contact QR deep link + Play Store install referrer
- [x] Delivery Challan e-Way Bill support + upload how-to card
- [x] Multi-item Bookings (3D-1 → 3D-3: data layer, form UI, detail/payment/invoice seam)
- [x] Action Center + WorkManager daily overdue notification (F4)
- [x] Dues/informal credit improvements (G1-G4 gap closure)
- [x] `getByPartyId` on Quote, Challan, Booking, Invoice, Credit, Loan repos

---

## Database Status

**Current Version:** 45

**Notable schema additions since v18:**
- `scheduled_payments.party_id` (v45) — wires bills into Party 360°
- FY settings keys (fiscal_year_start_month, invoice_no_format, etc.)
- `transactions.linked_booking_id`, `transactions.business_id` (earlier versions)
- WAL mode, daily snapshot, 30-day VACUUM

---

## Code Quality

**Flutter Analyze:** 21 issues total
- **3 errors** — `lib/data/services/party_statement_pdf_service.dart` lines 162, 164, 221: `const_eval_type_bool_num_string` — const expression contains non-bool/num/String operand. **Needs fix before next release.**
- **2 warnings** — `country_picker_field.dart`: unnecessary null comparison + dead code
- **1 info** — `indian_state_dropdown.dart`: deprecated `value` → use `initialValue`
- **15 info** — miscellaneous (unused imports, etc.)

**Tests:**
- Unit tests: core models, repositories, SMS parser, formatters — covered
- Widget tests: most screens tested
- Unified Tracking System (P3.13): **widget tests not yet written** — only outstanding task from the full Unified Tracking plan

---

## What's NOT Done (Explicitly Deferred)

- ❌ Widget tests for Unified Tracking System screens (P3.13 partial)
- ❌ Beta preparation / onboarding flow (3-screen setup, permissions gate)
- ❌ POS quick mode / counter billing → Year 2
- ❌ Stock / inventory management → Year 2
- ❌ e-Invoicing / IRN (requires network calls — will never be built)
- ❌ Recurring invoice generation (ScheduledPayment integration deferred)
- ❌ `LifecycleStage` stored in DB — MVP is computed-only; DB-stored variant deferred to Phase 2 (v45+)
- ❌ Lifecycle stage manual override in InvoiceDetailScreen — deferred

---

## Next Steps — Priority Order

### 1. Fix 3 flutter analyze errors (1–2 hours)
`party_statement_pdf_service.dart` lines 162, 164, 221 — remove `const` from expressions containing non-primitive operands. Low risk, quick win.

### 2. Write widget tests for Unified Tracking screens (~3 hours)
Covers `Party360Screen`, `CashFlowScreen`, `ActionCenterScreen` multi-select, `FlowChainTile`. Completes P3.13 and closes the Unified Tracking plan.

### 3. Beta Preparation (Week 11 from roadmap, ~45 hours)
- 3-screen first-launch flow (Welcome → SMS Permission → Profile)
- Permission gates wired properly
- Feedback button (email intent, no network)
- Play Store Internal Test track
- **Why now:** All major features are in. Real users will catch edge cases faster than manual testing.

### 4. Party Management Polish (Week 23-24, ~20 hours remaining)
`Party360Screen` exists and is powerful. Remaining polish:
- Party FK backfill for existing credits/loans entered as free text (P3.1 partially done)
- One-shot OS contact picker for phone/email on party form
- WhatsApp/SMS reminder templates per party

### 5. Bookings polish & calendar view (optional)
Core bookings are complete (multi-item, PDF, payment). A calendar view (month grid or week strip) would appeal to doctors/homestays. Low priority — list view is functional.

---

## Thoughts on the Current State

**Strengths:**
- The data model is extremely deep for an indie app — 45 DB migrations, 25+ models, all properly linked via FK
- The Unified Tracking System is a genuine differentiator: most small-business apps never connect invoices, loans, dues, and bookings into one party view
- Zero network calls maintained throughout — the privacy story is genuinely clean
- The `LifecycleClassifier` + `LifecycleTag` pattern is well-abstracted and avoids duplication across 5 consumers
- Business Flow Tracker (revenue leakage detection) is a feature that even enterprise tools miss

**Risks / Concerns:**
1. **Complexity creep:** The app now has 14 screen folders, 34 providers, 26 models, and 19 repository implementations. For an indie app targeting small shopkeepers, this may be more surface area than any one person can QA thoroughly.
2. **No real users yet:** All testing is manual + unit/widget tests. The billing, bookings, and Unified Tracking features need to be validated against real Indian SME workflows before locking in the UX.
3. **3 analyzer errors:** Small but should be fixed before beta — they indicate a `const` misuse that could cause subtle runtime issues.
4. **Widget test debt for new screens:** Party 360°, CashFlowScreen, and ActionCenter multi-select are non-trivial and untested at the widget level.
5. **App version still at 1.0.0+1:** pubspec.yaml needs bumping before any beta release. Consider `1.0.0-beta.1+45` (build number = DB version convention).

**What to do next (recommended sequence):**
Fix analyzer → write Unified Tracking widget tests → bump version → Push to Internal Test track → recruit 5 real users.

---

**Status:** Feature-complete for MVP + beta scope. Ready for bug-fix pass and first external testers.

**HEAD commit:** `2182d68` feat: complete Unified Tracking System all 3 phases
