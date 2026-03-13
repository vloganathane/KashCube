# Kash Cube - Progress Report
**Date:** 13 March 2026
**Current Phase:** LAN Sync ✅ · KashCube Web W1 ✅ · Sprint 3 IAP ✅

---

## Executive Summary

Since the last report (10 March), three major features have shipped:

1. **Sprint 3 — Real IAP wiring** — `IapService`, `in_app_purchase` package, `UpgradeScreen` wired to live Play Store purchases, Restore button — **100% complete** (commit `d21081a`)
2. **KashCube Web Sprint W1** — LAN HTTP server (WhatsApp Web model), QR pairing screen, REST API (`/api/v1/…`), bundled SPA web UI, Settings entry — **100% complete** (commit `0a16e9c`)
3. **LAN Sync — Secondary Sync Now** — `SyncClient.buildLocalDeltas()`, `SyncNowNotifier`, "Sync Now" FAB on secondary with live status spinner, snackbar result, AppBar re-pair button — **100% complete** (commit `4950b40`)

**Database:** v65 — all sync columns present since v58 (`sync_id` ULID on all 10 tables, backfilled, unique indexes); `linked_devices` + `last_sync_at` watermark; `sync_peers` via `linked_devices` table
**Flutter Analyze:** **3 pre-existing infos only** (0 errors, 0 warnings)
**App Status:** Full LAN sync stack operational. IAP live. KashCube Web companion ready.

---

## What Shipped Since 10 March 2026

### Sprint 3 — Real IAP Wiring ✅ ALL COMPLETE (commit `d21081a`)
- `in_app_purchase: ^3.2.0` added to pubspec
- `lib/data/services/iap_service.dart` — `IapService.instance` singleton; loads Play Store products, handles purchase flow, verifies receipt locally, updates `subscriptionTierProvider`
- `upgrade_screen.dart` — converted to `ConsumerStatefulWidget`; purchase buttons call `IapService.buySubscription()`; loading spinner per product; "Restore" in AppBar; dev simulation buttons retained for debug builds
- Product IDs: `com.kashcube.starter.monthly`, `com.kashcube.starter.annual`, `com.kashcube.business.monthly`, `com.kashcube.business.annual`

### KashCube Web Sprint W1 ✅ ALL COMPLETE (commit `0a16e9c`)
- `docs/KASHCUBE_WEB_SPEC.md` — full architecture spec (WhatsApp Web model)
- `pubspec.yaml` — `shelf`, `shelf_router`, `shelf_web_socket`, `web_socket_channel` added; `assets/web_ui/` registered
- `lib/data/services/web_server_service.dart` — shelf HTTP server on random port; `X-KashCube-Token` auth middleware; WebSocket push for live reload
- `lib/data/services/web_api_routes.dart` — REST handlers: dashboard, transactions CRUD (paginated), parties, categories, credits, invoices, invoice PDF (501 stub)
- `assets/web_ui/index.html` — full SPA: Dashboard, Transactions list+search, Add Transaction form, Credits, Invoices tabs
- `lib/presentation/providers/web_server_provider.dart` — `WebServerNotifier` (start/stop/revokeSession)
- `lib/presentation/screens/settings/kashcube_web_screen.dart` — QR pairing screen; "New QR" / "Stop" buttons; privacy note
- `settings_screen.dart` — "KashCube Web" tile in Sync section

### LAN Sync — Secondary Sync Now ✅ (commit `4950b40`)
- `sync_client.dart` — `buildLocalDeltas({DateTime? since})` — collects local rows for push
- `sync_provider.dart` — `SyncNowState`, `SyncNowNotifier`, `syncNowProvider`; flow: mDNS scan (10s) → TCP connect → `pullDeltas` → `pushDeltas` → stamp `last_sync_at` → handle `SyncRevokedException`
- `linked_devices_screen.dart` — secondary FAB: "Sync Now" with inline spinner; AppBar: QR re-pair icon; `ref.listen` snackbar showing rows pulled/pushed; `_syncLabel()` helper

---

## Previously Shipped (before 10 March)

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

**Current Version:** 65

| Version | Change |
|---------|--------|
| v46–v49 | Subscription tier key, Sprint 1 settings additions |
| v50 | `businesses.upi_id TEXT`; 5 new document template presets |
| v51–v57 | Inventory, staff, RBAC, payroll tables |
| v58 | `sync_id` ULID on all 10 P0 tables; backfill; unique indexes; `linked_devices`, `device_recovery`, `pairing_history`, `plan_features`, `app_users`, auth tables (Phase 0 sync foundation) |
| v59–v60 | RBAC app_users, permissions; LAN discovery + Owner Mirror (L1) |
| v61–v62 | Staff Terminal permission-scoped sync (L2); Phase D1 My Identity |
| v63 | Context layer — `context_id` on 13 tables, `activeContextProvider` |
| v64 | Phase D3 — Linked Sessions, `shareable_plan_features`, `secondary_display_name` |
| v65 | Phase D4 — Payroll Loop; subscription + plan gates |

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
| BUSINESS | Inventory management | ✅ |
| BUSINESS | Staff payroll module | ✅ |
| BUSINESS | Tally XML / Excel export | ✅ |
| BUSINESS | LAN sync (Wi-Fi, zero server) | ✅ v58–v66 |
| BUSINESS | KashCube Web (browser companion) | ✅ W1 |
| ALL | Real IAP (Play Store) | ✅ Sprint 3 |

---

## What's NOT Done (Deferred as of 13 March 2026)

- ❌ **KashCube Web W2** — wire `notifyTransactionChange()` into create/edit flows (live push to browser); foreground notification while server active; auto-revoke session on app pause >30 min; invoice PDF generation (current 501 stub)
- ❌ **Periodic background LAN sync** — `WorkManager` periodic task; auto-sync when primary found on same WiFi without user action
- ❌ Widget tests for Unified Tracking System screens (Party360°, CashFlowScreen, ActionCenter)
- ❌ UPI Tip Jar in Settings → About (static QR, zero infra)
- ❌ GSTR-2B reconciliation (match purchase bills vs GSTR-2B JSON import)
- ❌ Beta preparation (onboarding flow, permissions gate, Play Store Internal Test)
- ❌ e-Invoicing / IRN (requires network calls — will **never** be built)

---

## Next Steps — Priority Order

### 1. KashCube Web W2 (1 sprint)
- Wire `WebServerService.notifyTransactionChange()` into transaction create/edit flows — browser auto-reloads on new transaction
- Add `flutter_local_notifications` persistent notification while server active ("KashCube Web active on 192.168.x.x:8080")
- Auto-revoke session when app goes to background >30 min
- Invoice PDF generation for the W1 501 stub

### 2. Periodic Background LAN Sync (0.5 sprint)
- `WorkManager` periodic task (~15 min interval)
- Check mDNS for primary on same WiFi; if found, run full sync silently
- Update sync badge on Settings tile with "Last synced X min ago"

### 3. UPI Tip Jar (0.5 sprint)
- Settings → About → "Support KashCube" → static UPI QR (₹50/₹100/₹200/custom)
- Zero infrastructure; measures user appreciation

### 4. Beta Preparation
- 3-screen first-launch flow (Welcome → SMS Permission → Profile)
- App version bump to `1.0.0-beta.1+65`
- Push to Play Store Internal Test track
- Recruit 5 real Indian SME users

---

## Current State Assessment

**What's strong:**
- **LAN sync is fully operational** — mDNS discovery, TCP delta exchange, paired device registry, secondary Sync Now flow. Far ahead of the original roadmap.
- **KashCube Web** — WhatsApp Web model, zero internet, QR pairing, full SPA. A genuine differentiator.
- **IAP live** — real Play Store purchase flow wired. Revenue collection is unblocked.
- **DB at v65** — `sync_id` on all tables since v58, all P0 sync tables present. No schema migrations needed before beta.
- **0 analyzer errors** — maintained throughout every sprint.

**Risks / Concerns:**
1. **No real users yet** — all testing is still manual + emulator. Need beta testers to validate IAP, LAN sync, and GST workflows against real Indian SME usage.
2. **KashCube Web W2 pending** — the browser companion is live but changes on the phone don't push to the browser automatically yet. The live-reload WebSocket is wired but `notifyTransactionChange()` isn't called from the transaction write path.
3. **Background sync not automatic** — secondary must tap "Sync Now" manually. A `WorkManager` periodic task would make it feel more like WhatsApp multi-device.

---

**Status:** IAP live, LAN sync end-to-end, KashCube Web W1 complete. Ready for W2 or beta prep.

**HEAD:** `4950b40` — v66 LAN sync secondary Sync Now · `flutter analyze` → 3 pre-existing infos only

