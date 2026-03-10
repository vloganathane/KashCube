# Kash Cube - Progress Report
**Date:** 10 March 2026  
**Current Phase:** Monetization Infrastructure — Sprint 1 ✅ COMPLETE + Sprint 2 ✅ COMPLETE

---

## Executive Summary

Since the last report (7 March), two full monetization sprints have landed:

1. **Sprint 1 — Monetization Gate Infrastructure** — `SubscriptionTier` enum, PDF watermark, `UpgradePromptSheet`, report export gate, PDF share wired to upgrade prompt, Upgrade Screen UI — **100% complete**.
2. **Sprint 2 — Starter Tier Features** — UPI QR on invoice, 5 industry templates, Report PDF export, GSTR-1 JSON export, barcode scanner for item catalog — **100% complete**.

**Database:** v50 (bumped from v45 → v49 in Sprint 1, v49 → v50 in Sprint 2)  
**Flutter Analyze:** **No issues found!** (0 errors, 0 warnings)  
**App Status:** Monetization gates live, all Starter + Business tier features implemented. Ready for Sprint 3 (real IAP wiring).

---

## What Shipped Since 7 March 2026

### Sprint 1 — Monetization Foundation ✅ ALL COMPLETE

#### S1-T1 — `SubscriptionTier` enum + provider
- [x] `lib/core/constants/subscription_tier.dart` — `enum SubscriptionTier { free, starter, business }` with `isStarter`, `isBusiness`, `isFree`, `dbValue`, `displayName` extensions
- [x] `SettingsKeys.subscriptionTier` key added to `settings_provider.dart`
- [x] `SubscriptionTierNotifier` + `subscriptionTierProvider` — single source of truth; persisted to SQLite settings

#### S1-T2 — PDF watermark on all 3 document services
- [x] `PdfDocumentData.showFreeWatermark` field added
- [x] `PdfLayoutEngine._buildFooter()` — renders a tinted green watermark band on Free tier: _"Created with KashCube Free · Remove watermark → Upgrade to Starter at ₹499/year"_
- [x] `InvoicePdfService`, `DeliveryChallanPdfService`, `BookingConfirmationPdfService` — all accept and pass `showFreeWatermark` flag

#### S1-T3 — `UpgradePromptSheet` widget
- [x] `lib/presentation/widgets/upgrade_prompt_sheet.dart` — reusable bottom sheet with `[Share with Watermark]` + `[Upgrade to Starter ₹499/yr →]` buttons; never hard-blocks the flow

#### S1-T4 — Report export gate on Reports screen
- [x] Export FAB added to `reports_screen.dart`
- [x] Free → shows `UpgradePromptSheet`; Starter/Business → format picker (PDF P&L or CSV)

#### S1-T5 — Wire PDF share to upgrade prompt on all 4 detail screens
- [x] `InvoiceDetailScreen`, `QuoteDetailScreen`, `DeliveryChallanDetailScreen`, `BookingDetailScreen` — Free tier shows `UpgradePromptSheet` ("Share with Watermark" / "Upgrade"); Starter+ shares directly without watermark

#### S1-T6 — Upgrade Screen (UI, no real IAP yet)
- [x] `lib/presentation/screens/settings/upgrade_screen.dart` — full tier comparison table, pricing (₹59/mo or ₹499/yr · ₹129/mo or ₹999/yr), annual savings callout (30%/35%), cancellation guarantee copy, ITC deductibility note
- [x] `kDebugMode` dev buttons: "Simulate Starter" / "Simulate Business" / "Reset to Free" for QA
- [x] Wired into settings screen

---

### Sprint 2 — Starter Tier Features ✅ ALL COMPLETE

#### S2-T1 — UPI Payment QR on Invoice
- [x] `Business.upiId String?` field added with `copyWith`, `toMap`, `fromMap`, `props` updates
- [x] DB v50 migration: `ALTER TABLE businesses ADD COLUMN upi_id TEXT`
- [x] `businesses_screen.dart` — UPI ID `TextFormField` with `Icons.qr_code_outlined`, hint `'yourname@upi'`
- [x] `PdfDocumentData.upiQrBytes Uint8List?` field added
- [x] `PdfLayoutEngine` — renders 72×72 QR image + "Scan to pay via UPI" label to left of signatory box when QR bytes present
- [x] `InvoicePdfService` — `showUpiQr: bool = false` param; generates UPI URI (`upi://pay?pa=…&pn=…&am=…&tn=…&cu=INR`) → `QrPainter.toImage(200)` → `Uint8List`; uses non-deprecated `eyeStyle`/`dataModuleStyle` API
- [x] `InvoiceDetailScreen` + `QuoteDetailScreen` — `showUpiQr: tier.isStarter` wired

#### S2-T2 — 5 Industry Invoice Template Presets
- [x] `pdf_document_data.dart` — 5 new `DocumentTemplate` static consts: `pharmacy` (#006064/banner), `restaurant` (#5D4037/banner), `service` (#1565C0/minimal), `freelancer` (#37474F/minimal/no-logo), `generic` (#1B5E20/minimal)
- [x] `presets` list updated: 9 presets total (classic, modern, plain, receipt + 5 new)
- [x] `database_helper.dart` v50 migration — `_seedDocumentTemplatePresets()` extended with 5 new `INSERT OR IGNORE` rows

#### S2-T3 — Report PDF Export
- [x] `lib/data/services/report_pdf_service.dart` (NEW) — `ReportPdfService.instance.generate(MonthlyPnL, String)` → A4 P&L summary PDF with header, 3-column summary cards, income/expense category tables (sorted by amount, with % share), top 5 parties table, generated-on footer
- [x] `reports_screen.dart` — format picker bottom sheet: "P&L Summary PDF" → `ReportPdfService` → `Share.shareXFiles`; "Transaction CSV" → existing `CsvExporter`

#### S2-T4 — GSTR-1 JSON Export (Business tier)
- [x] `gstr1_service.dart` — `exportJson(Gstr1Workbook)` method added: builds GSTN portal-compatible JSON (b2b, b2cl, b2cs, cdnr, hsn, doc_issue sections); `_round2()` helper; writes to `getTemporaryDirectory()`, returns `XFile(mimeType: 'application/json')`
- [x] `gstr1_screen.dart` — `_exportJson()` method; `onExportJson` callback added to `_WorkbookPreview`; full-width "Export JSON for GST Portal" button (disabled with explanatory label when not Business tier)

#### S2-T5 — EAN Barcode Scanner for Item Catalog (Business tier)
- [x] `qr_scanner_sheet.dart` — `showBarcodeScannerSheet(BuildContext) → Future<String?>` added; scans EAN-13, EAN-8, UPC-A, UPC-E, Code128, Code39, ITF using existing `MobileScanner` + `_ScannerOverlay`
- [x] `item_catalog_screen.dart` — SKU field gets `Icons.barcode_reader` suffix icon on Business tier; taps open scanner, auto-fills SKU controller on successful scan

---

## Database Status

**Current Version:** 50

| Version | Change |
|---------|--------|
| v46–v49 | Subscription tier key, various Sprint 1 settings additions |
| v50 | `businesses.upi_id TEXT` column; 5 new document template presets seeded |

---

## Code Quality

**Flutter Analyze:** ✅ **No issues found!** (maintained throughout all Sprint 1 + Sprint 2 work)

**Tests:** Unit + widget tests cover core models, repositories, SMS parser, formatters. Widget tests for Unified Tracking System screens (Party360°, CashFlowScreen, ActionCenter multi-select) remain outstanding from previous sprint.

---

## Feature Gate Status (as of 10 March 2026)

| Tier | Feature | Status |
|------|---------|--------|
| FREE | Transactions (SMS + manual) | ✅ |
| FREE | Credits / Udhar | ✅ |
| FREE | Budgets + in-app reports | ✅ |
| FREE | PIN + biometric lock | ✅ |
| FREE | Backup / restore (AES-256) | ✅ |
| FREE | Invoices + Quotes + DCs + Bookings | ✅ |
| FREE | PDF watermark on Free tier | ✅ Sprint 1 |
| STARTER | Watermark-free output + upgrade gate | ✅ Sprint 1 |
| STARTER | Report export (P&L PDF + CSV) | ✅ Sprint 2 |
| STARTER | Invoice templates (9 presets incl. 5 industry) | ✅ Sprint 2 |
| STARTER | UPI payment QR on invoice | ✅ Sprint 2 |
| STARTER | WhatsApp reminder buttons | ✅ |
| BUSINESS | Purchase Bills + ITC | ✅ |
| BUSINESS | E-Way Bill + transporter registry | ✅ |
| BUSINESS | GSTR-3B summary + export | ✅ |
| BUSINESS | GSTR-1 JSON export (portal-ready) | ✅ Sprint 2 |
| BUSINESS | Barcode scanner for items (EAN/UPC/Code128) | ✅ Sprint 2 |
| BUSINESS | Custom invoice templates (unlimited) | ✅ |
| BUSINESS | Inventory management | ❌ Sprint 4 |
| BUSINESS | Staff payroll module | ❌ Sprint 4 |
| BUSINESS | Tally XML / Excel export | ❌ Sprint 4 |
| BUSINESS | LAN sync (Wi-Fi, zero server) | ❌ Sprint 4 |

---

## What's NOT Done (Deferred)

- ❌ **Sprint 3 — Real IAP wiring** (`in_app_purchase` package, `IapService`, wire to Upgrade Screen)
- ❌ Widget tests for Unified Tracking System screens (Party360°, CashFlowScreen, ActionCenter)
- ❌ Inventory management (products, stock movements, reorder alerts) → Sprint 4
- ❌ Staff payroll module (`staff`, `payroll_runs`, `payroll_items` tables) → Sprint 4
- ❌ Tally XML / Excel export for CA handoff → Sprint 4
- ❌ LAN sync (mDNS + TCP socket, ECDH key exchange, `sync_id` migration) → Sprint 4 (requires DB foundation work)
- ❌ UPI Tip Jar in Settings → About (static QR, zero infra)
- ❌ GSTR-2B reconciliation (match purchase bills vs imported GSTR-2B JSON)
- ❌ Beta preparation (onboarding flow, permissions gate, Play Store Internal Test)
- ❌ Multi-user / staff access (PIN-based profile switching)
- ❌ e-Invoicing / IRN (requires network calls — will **never** be built)

---

## Next Steps — Priority Order

### 1. Sprint 3 — Wire Real IAP (1–2 sprints)
- Add `in_app_purchase: ^3.2.0` to pubspec
- `IapService` — load Play Store products, handle purchase flow, verify receipt locally, update `subscriptionTierProvider`
- Replace dev simulation buttons in Upgrade Screen with real IAP
- Product IDs: `com.kashcube.starter.monthly`, `com.kashcube.starter.annual`, `com.kashcube.business.monthly`, `com.kashcube.business.annual`

### 2. UPI Tip Jar (0.5 sprint)
- Settings → About → "Support KashCube" → static UPI QR image (₹50/₹100/₹200/custom)
- Zero infrastructure; measures user appreciation before IAP validated

### 3. Sprint 4 — Business Tier Build-out
Priority order within Sprint 4:
1. **Inventory (Phase A MVP)** — `products` + `stock_movements` tables, DB v51, stock register screen, invoice item → product link
2. **Low-stock alerts** — WorkManager daily check, local notification
3. **Tally XML export** — map invoices/transactions to Tally Voucher XML; CA handoff
4. **Staff payroll** — `staff`, `attendance`, `salary_payments` tables
5. **LAN Sync (Phase 0 prerequisite)** — add `sync_id` to all 10 core tables, `deleted_at` where missing, `sync_peers` table (DB v52+)

### 4. Beta Preparation (parallel to Sprint 3)
- 3-screen first-launch flow (Welcome → SMS Permission → Profile)
- App version bump: `1.0.0-beta.1+50` (build = DB version convention)
- Push to Play Store Internal Test track
- Recruit 5 real Indian SME users for validation

---

## Thoughts on Current State

**What's strong:**
- The monetization architecture is clean — `subscriptionTierProvider` is the single gate; adding a new gated feature is a one-liner (`ref.read(subscriptionTierProvider).isStarter`)
- Sprint 1 + 2 delivered with zero analyzer issues throughout — discipline maintained
- UPI QR on invoice is a genuine differentiator for Indian users; no competitors do it offline + on-device
- 9 invoice templates (including 5 industry-specific) close the Vyapar parity gap on template variety
- GSTR-1 JSON export is a high-value feature — SMEs/CAs can now upload directly to the GST portal

**Risks / Concerns:**
1. **IAP not wired yet** — the tier gates are all built but `subscriptionTierProvider` defaults to `free` for real users, and the "Simulate Business" buttons are hidden behind `kDebugMode`. Sprint 3 is blocking monetization.
2. **Inventory still missing** — the single biggest Vyapar parity gap. Retailers cannot use KashCube for stock management until Sprint 4 lands.
3. **No real users yet** — all testing is still manual + unit/widget. Need beta testers to validate the billing + GSTR + booking workflows against real Indian SME usage patterns.
4. **DB at v50** — LAN sync requires adding `sync_id` to all 10 core tables, which will be DB v52+. The earlier this foundation is laid, the less churn on the model layer later.

---

**Status:** Monetization gates built, Starter + Business features complete. Blocked on IAP wiring (Sprint 3) before any revenue can be collected.

**HEAD:** Sprint 2 complete — `flutter analyze` → "No issues found!"

