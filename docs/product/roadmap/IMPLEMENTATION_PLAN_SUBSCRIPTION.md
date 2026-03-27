# Implementation Plan — Subscription & Monetization Gates
# KashCube Sprint: Free → Starter → Business tier infrastructure

**Version:** 1.0  
**Date:** 10 March 2026  
**Status:** COMPLETE 🏆  
**Prerequisite:** Feature audit complete (March 2026) — 16/27 features built  
**Goal:** Ship the monetization gate infrastructure; all existing fully-built features become properly gated

---

## Guiding Principle

> "You own the data. We own the software."

Every implementation decision flows from this. Data (transactions, credits, reports viewed in-app) is never blocked. Software polish (watermark-free PDFs, export files) is gated.

---

## Sprint 1 — Monetization Foundation (builds the gate infrastructure)

These 6 tasks must land before IAP is wired. They also make the app releasable exactly as-is, with the gate toggled via a local dev flag for testing.

### S1-T1 — `SubscriptionTier` enum + settings key ✅ IN PROGRESS
**Files:**
- `lib/core/constants/subscription_tier.dart` ← **new**
- `lib/presentation/providers/settings_provider.dart` ← add key + provider

**What to build:**
```dart
enum SubscriptionTier { free, starter, business }
```
- `SettingsKeys.subscriptionTier = 'subscription_tier'`
- `SubscriptionTierNotifier` (StateNotifier) — loads from settings, defaults to `free`
- `subscriptionTierProvider` — the single source of truth for the gate

**No DB migration needed** — settings is key-value; just insert a new key.

---

### S1-T2 — Watermark footer on all 3 PDF services
**Files:**
- `lib/data/services/pdf_document_data.dart` ← add `showFreeWatermark` field
- `lib/data/services/pdf_layout_engine.dart` ← render watermark band in `_buildFooter`
- `lib/data/services/invoice_pdf_service.dart` ← pass flag
- `lib/data/services/delivery_challan_pdf_service.dart` ← pass flag
- `lib/data/services/booking_confirmation_pdf_service.dart` ← pass flag

**Watermark design:**
```
┌──────────────────────────────────────────────────────────┐
│  📄 Created with KashCube Free · Remove watermark →      │
│     Upgrade to Starter at ₹499/year · kashcube.app       │
└──────────────────────────────────────────────────────────┘
```
- Rendered as a tinted container (light green background) at the very bottom of every page
- Replaces the existing subtle "Powered by Kash Cube" footer text on free tier only
- On Starter/Business: existing subtle "Powered by" stays (or nothing)

---

### S1-T3 — `UpgradePromptSheet` widget (reusable)
**File:** `lib/presentation/widgets/upgrade_prompt_sheet.dart` ← **new**

Shown when a free user tries to share/export. Two buttons:
```
[Share with Watermark]       [Upgrade to Starter ₹499/yr →]
```
- `onShareAnyway` callback — allows sharing the watermarked PDF without blocking
- `onUpgrade` callback — opens Upgrade Screen (or shows a placeholder for now)
- Never hard-blocks the flow

---

### S1-T4 — Report export button on Reports screen
**File:** `lib/presentation/screens/reports/reports_screen.dart`

- Add "Export" FAB or menu item to the reports screen
- On tap: check `subscriptionTierProvider`
  - Starter/Business → call existing `CsvExportService` → share result
  - Free → show `UpgradePromptSheet`
- `CsvExportService` already exists at `lib/data/services/csv_export_service.dart`
- Also add "Export PDF" for Starter+ (P&L monthly summary as PDF)

---

### S1-T5 — Wire PDF share button to upgrade prompt
**Files:** `invoice_detail_screen.dart`, `quote_detail_screen.dart`, `delivery_challan_detail_screen.dart`, `booking_detail_screen.dart`

Currently all 4 screens call PDF service and share directly. Change to:
- Free: show `UpgradePromptSheet`
  - "Share with Watermark" → generate PDF with `showFreeWatermark: true` → share
  - "Upgrade" → placeholder
- Starter+: generate PDF with `showFreeWatermark: false` → share directly

---

### S1-T6 — Upgrade Screen (UI only, no real IAP yet)
**File:** `lib/presentation/screens/settings/upgrade_screen.dart` ← **new**

Static screen showing tier comparison + pricing. CTA buttons are placeholders for now.
Content:
- Tier comparison table (Free / Starter / Business features)
- Pricing: ₹59/mo or ₹499/yr · ₹129/mo or ₹999/yr
- "Cancel anytime. Your data stays readable forever." guarantee
- Annual savings callout (30% / 35%)
- ITC deductibility note for GST users
- DEV ONLY: "Simulate Starter" / "Simulate Business" / "Reset to Free" buttons (hidden behind `kDebugMode`)

---

## Sprint 2 — Complete Starter Tier Features

### S2-T1 — UPI Payment QR on Invoice
**Files:**
- `lib/data/models/business.dart` — add `upiId` field
- `lib/presentation/screens/settings/business_profile_screen.dart` — UPI ID input
- `lib/data/services/pdf_layout_engine.dart` — render QR in invoice footer
- `lib/data/services/pdf_document_data.dart` — add `upiQrData` nullable field

**Logic:** If business has `upiId` set, generate `upi://pay?pa={upiId}&pn={businessName}&am={total}&tn={invoiceNo}` URI and embed as QR in the PDF. Only for invoices (not quotes/DC/bookings).

---

### S2-T2 — 5 Industry Invoice Template Presets
**File:** `lib/data/services/pdf_document_data.dart` (template presets seeding)

Add/rename presets from current 4 (`classic`, `modern`, `plain`, `receipt`) to:
- **Generic** (same as current `classic`)
- **Service / Freelancer** (same as current `modern`, renamed)
- **Pharmacy** (new — monochrome, compact for medicines list)
- **Restaurant** (new — warm accent, compact line items)
- **Receipt** (same as current thermal `receipt`, keep as-is)

These are template configurations, not new layout engines. Each maps to an existing layout style with different accent colours and header style.

---

### S2-T3 — GSTR-1 JSON Export
**File:** `lib/data/services/gstr1_service.dart`

Currently exports CSV ZIP. Add JSON export method that produces the GSTN portal-compatible JSON format (used by ERP integrations). The CSV ZIP is sufficient for most users; JSON is bonus for larger businesses.

---

### S2-T4 — EAN Barcode Scanner for Item Catalog
**File:** `lib/presentation/screens/invoices/item_catalog_screen.dart`

`mobile_scanner` is already in pubspec. Add a scan button on the Add/Edit item form that reads EAN-13/EAN-8 and populates the item catalog entry. No network lookup — just populate name field with the barcode string; user types the description.

---

## Sprint 3 — IAP Wiring ✅ COMPLETE

### S3-T1 — Add `in_app_purchase` package ✅
**File:** `pubspec.yaml`

```yaml
in_app_purchase: ^3.2.0
```

Product IDs (Google Play):
```
com.kashcube.starter.monthly    ₹59/month
com.kashcube.starter.annual     ₹499/year
com.kashcube.business.monthly   ₹129/month
com.kashcube.business.annual    ₹999/year
```

---

### S3-T2 — IAP Service ✅
**File:** `lib/data/services/iap_service.dart` ← **new**

- Load products from Play Store
- Handle purchase flow: purchase → verify receipt locally (Play validates, no KashCube server)
- On verified purchase: update `subscriptionTierProvider` + persist via `SettingsKeys.subscriptionTier`
- On cancellation / expiry: detected on next app launch via Play subscription status

---

### S3-T3 — Wire Upgrade Screen to real IAP ✅
Replaced placeholder buttons in `UpgradeScreen` with real IAP purchase flow via `IapService`. Annual and monthly buttons for Starter and Business tiers now call `IapService.buySubscription()`. Loading indicators shown while Google Play UI is open. Restore purchases action in AppBar.

---

## Sprint 4 — Business Tier Features (Phase 2)

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| S4-T1 | Inventory management (products + stock movements + reorder alerts) | Large | New tables: `products`, `stock_movements`. DB v50. |
| S4-T2 | Low-stock alerts via WorkManager | Medium | Depends on S4-T1 |
| S4-T3 | Tally XML export | Medium | Map transactions + invoices to Tally Voucher XML format |
| S4-T4 | Staff payroll module | Large | New tables: `staff`, `payroll_runs`, `payroll_items` |
| S4-T5 | LAN sync | Extra large | Requires DB v50 sync_id migration. See `PRIVATE_SYNC_BRAINSTORM.md` |
| S4-T6 | GSTR-2B reconciliation | Medium | Match `purchase_bills` against GSTR-2B JSON import |
| S4-T7 | Multi-user / staff access | Large | Likely PIN-based profile switching (no network needed) |

---

## Implementation Order Summary

```
Sprint 1 (Now): Gate infrastructure
  S1-T1 SubscriptionTier enum + provider      ← START HERE
  S1-T2 PDF watermark in layout engine
  S1-T3 UpgradePromptSheet widget
  S1-T4 Report export button on reports screen
  S1-T5 Wire PDF share to upgrade prompt
  S1-T6 Upgrade Screen (UI, no IAP)

Sprint 2 (Next): Complete Starter features
  S2-T1 UPI payment QR on invoice
  S2-T2 5 industry template presets
  S2-T3 GSTR-1 JSON export
  S2-T4 EAN barcode scanner

Sprint 3 ✅: Real IAP
  S3-T1 in_app_purchase package ✅
  S3-T2 IapService ✅
  S3-T3 Wire to Upgrade Screen ✅

Sprint 4 (Phase 2): Business tier build-out
  Inventory → Tally XML → Payroll → LAN sync
```

---

## Files Created / Modified in Sprint 1

| File | Action |
|------|--------|
| `lib/core/constants/subscription_tier.dart` | CREATE |
| `lib/presentation/providers/settings_provider.dart` | MODIFY (add key + provider) |
| `lib/data/services/pdf_document_data.dart` | MODIFY (add `showFreeWatermark`) |
| `lib/data/services/pdf_layout_engine.dart` | MODIFY (render watermark in `_buildFooter`) |
| `lib/data/services/invoice_pdf_service.dart` | MODIFY (accept + pass flag) |
| `lib/data/services/delivery_challan_pdf_service.dart` | MODIFY (accept + pass flag) |
| `lib/data/services/booking_confirmation_pdf_service.dart` | MODIFY (accept + pass flag) |
| `lib/presentation/widgets/upgrade_prompt_sheet.dart` | CREATE |
| `lib/presentation/screens/reports/reports_screen.dart` | MODIFY (add export gate) |
| `lib/presentation/screens/invoices/invoice_detail_screen.dart` | MODIFY (wire upgrade prompt) |
| `lib/presentation/screens/invoices/quote_detail_screen.dart` | MODIFY (wire upgrade prompt) |
| `lib/presentation/screens/invoices/delivery_challan_detail_screen.dart` | MODIFY (wire upgrade prompt) |
| `lib/presentation/screens/bookings/booking_detail_screen.dart` | MODIFY (wire upgrade prompt) |
| `lib/presentation/screens/settings/upgrade_screen.dart` | CREATE |

---

*Last updated: 10 March 2026*  
*Related docs: `MONETIZATION_STRATEGY.md`, `COMPETITIVE_GAP_ANALYSIS.md`*
