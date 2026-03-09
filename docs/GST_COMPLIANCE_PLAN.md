# GST Compliance Plan — KashCube

> Started: 2 March 2026
> Goal: Produce legally valid GST Tax Invoices, lay groundwork for e-Way Bill and future e-Invoice (IRN).

---

## Current State Audit

| Field / Feature | Status | Location |
|-----------------|--------|----------|
| Seller GSTIN (`gst_no`) | ✅ Exists | `businesses` table, `Business.gstNo` |
| Seller state (place of supply) | ✅ Exists | `businesses.state` |
| Buyer GSTIN | ✅ Column exists | `parties.gstin` |
| Buyer state | ✅ Exists | `parties.state` |
| HSN code on item catalog | ✅ Exists | `item_catalog.hsn_code` |
| GST % on item catalog | ✅ Exists | `item_catalog.tax_pct` |
| GST UOM codes (e-Way Bill) | ✅ Done DB v31 | `unit_types` table |
| Invoice numbering / FY reset | ✅ Done | `fiscal_year_service.dart` |
| PDF generation | ✅ Basic | `invoice_pdf_service.dart` |
| **HSN + unit on invoice line items** | ❌ Missing | `invoice_items` / `quote_items` |
| **Invoice type** (Tax Invoice / Bill of Supply) | ❌ Missing | `invoices` / `quotes` |
| **Place of supply on invoice** | ❌ Missing | `invoices` / `quotes` |
| **Reverse charge flag** | ❌ Missing | `invoices` / `quotes` |
| **CGST / SGST vs IGST split** | ❌ Missing | PDF + model |
| **"TAX INVOICE" header on PDF** | ❌ Missing | PDF |
| **Seller GSTIN on PDF** | ❌ Missing | PDF |
| **Buyer GSTIN on PDF** | ❌ Missing | PDF |
| **SAC codes** (services) | ❌ Missing | `item_catalog` |

---

## Phases

### Phase A — Foundation (DB + Models) ← **Starting now**

**Goal:** All GST-required data fields exist in DB and models.

#### A1 — DB v32: Add GST columns to invoice/quote tables
- `invoice_items`: + `hsn_code TEXT`, `unit TEXT DEFAULT 'PCS'`, `hsn_or_sac TEXT DEFAULT 'HSN'`
- `quote_items`: same three columns
- `invoices`: + `invoice_type TEXT DEFAULT 'tax_invoice'`, `place_of_supply TEXT`, `reverse_charge INTEGER DEFAULT 0`, `customer_gstin TEXT`
- `quotes`: + `invoice_type TEXT DEFAULT 'tax_invoice'`, `place_of_supply TEXT`, `reverse_charge INTEGER DEFAULT 0`, `customer_gstin TEXT`

Migration: `ALTER TABLE … ADD COLUMN …` for existing installs. Backfill `invoice_items.unit` from item_catalog where possible.

#### A2 — Model updates
- `InvoiceItem`: add `hsnCode`, `unit`, `hsnOrSac` fields
- `QuoteItem`: same
- `Invoice`: add `InvoiceType` enum, `invoiceType`, `placeOfSupply`, `reverseCharge`, `customerGstin`
- `Quote`: same additions

#### A3 — Invoice form: auto-populate from item catalog
When user adds a line item from catalog, copy `hsn_code` and `unit` from `item_catalog` into the `invoice_items` row.

#### A4 — SAC code support on item catalog
Add `hsn_or_sac TEXT DEFAULT 'HSN'` toggle to `item_catalog` and item form (Products → HSN, Services → SAC).

---

### Phase B — CGST / SGST vs IGST logic + PDF upgrade

**Goal:** Invoice PDF is a legally valid GST Tax Invoice.

#### B1 — `GstCalculator` service
```dart
class GstCalculator {
  /// Intra-state (same state) → CGST + SGST (each = gst/2)
  /// Inter-state (different state) → IGST (= full gst)
  static GstSplit calculate({
    required String? sellerState,
    required String? buyerState,
    required double taxableAmount,
    required double gstPct,
  });
}

class GstSplit {
  final double cgst;    // 0 for inter-state
  final double sgst;    // 0 for inter-state
  final double igst;    // 0 for intra-state
  final double total;
  final bool isInterState;
}
```

#### B2 — PDF: Tax Invoice header
Replace current generic header with:
- Document title: **"TAX INVOICE"** / "BILL OF SUPPLY" / "ESTIMATE" depending on type
- Seller block: Name, address, **GSTIN: XX…**, state
- Customer block: Name, address, **GSTIN: XX…** (if registered), state
- Invoice metadata: Invoice No, Date, **Place of Supply: [State]**, Due Date
- **"Subject to Reverse Charge: Yes/No"** line (mandatory field)

#### B3 — PDF: GST summary table
Replace current simple totals with compliant GST summary:

```
+------------------+--------+----------+-------+-------+-------+-----+
| HSN/SAC          | Taxable| Rate     | CGST  | SGST  | IGST  | Tot |
+------------------+--------+----------+-------+-------+-------+-----+
| 998314 (service) | 10,000 | 18%      | 900   | 900   | —     |1800 |
| 8541 (product)   |  5,000 | 12%      | 300   | 300   | —     | 600 |
+------------------+--------+----------+-------+-------+-------+-----+
| Total            | 15,000 |          |1,200  |1,200  | —     |2400 |
+------------------+--------+----------+-------+-------+-------+-----+
```

Grouped by HSN/SAC + rate combination (GSTN requirement).

---

### Phase C — Advanced Compliance ✅ Done (DB v34)

**Goal:** Ready for e-Invoice mandate and e-Way Bill integration.

#### C1 — e-Invoice fields (IRN placeholder) ✅
Added `irn TEXT`, `irn_ack_no TEXT`, `irn_ack_date TEXT`, `qr_code_data TEXT` to `invoices` table (DB v34).
`Invoice` model updated: constructor, fields, `copyWith`, `toMap`, `fromMap`, `hasEInvoice` getter.
(Actual IRN generation requires GSTN API call — out of scope for network-free app.)

#### C2 — e-Way Bill JSON export ✅
`lib/data/services/eway_bill_service.dart` — `EwayBillService.instance.exportAndShare(invoice, ...)`.
Builds GSTN `EWB_Import_Template`-compatible JSON:
- `supplyType`, `subSupplyType`, `docType` (INV/BIL/CRN/DBN) from `InvoiceType`
- From/To GSTIN, trade name, address, state code, pincode
- Per-item: `hsnCode`, `qtyUnit` (app unit → GSTN UOM map, 40+ mappings), `taxableAmount`, CGST/SGST/IGST rates
- Totals: `cgstValue`, `sgstValue`, `igstValue`, `totInvValue`
- Transport fields left blank (user fills after export)
- Shared via `share_plus` as `application/json`

#### C3 — GSTIN validation ✅
`lib/core/utils/gstin_validator.dart` — pure offline utility, no I/O.
- `GstinValidator.isValid(gstin)` — regex + state code coverage check
- `GstinValidator.validate(value)` — `TextFormField.validator` callback
- `GstinValidator.validateWithState(value, selectedState: ...)` — cross-checks embedded state code
- `GstinValidator.stateCodeFrom(gstin)`, `stateNameFrom(gstin)`, `stateMatches(gstin, stateName)`
- Wired into `party_form_sheet.dart` (with state cross-check) and `businesses_screen.dart` (replaces inline regex)

---

### Phase E — GSTR-1 Workbook Export ✅ Done

**Goal:** Generate a GSTR-1 ready-to-import workbook (CSV files + PDF summary) for outward supplies. The workbook is handed to a CA or uploaded directly to the GSTN offline tool / ClearTax — no portal filing, no network calls.

> Full spec: [`docs/GSTR1_WORKBOOK_SPEC.md`](GSTR1_WORKBOOK_SPEC.md)

#### E1 — Data layer & aggregation service ✅ Done
- `Gstr1Service.generateWorkbook(businessId, from, to)` → `Gstr1Workbook`
- Row models for all 6 tables (T4 B2B, T5 B2C Large, T7 B2C Small, T9 CDN, T12 HSN, T13 Doc Summary)
- `CsvExporter` utility (UTF-8 BOM, ZIP via `archive`)
- `stateCodeFromName()` reverse lookup in `GstinValidator`
- Mixed-rate invoice expansion (one row per invoice × GST rate bucket)
- Unit tests: `test/data/services/gstr1_service_test.dart`

#### E2 — PDF summary ✅ Done
- `Gstr1PdfService` — one-page summary (period, business GSTIN, table-wise counts/amounts, tax liability strip, HSN quick-view, footer)
- Direct `pdf` package (singleton `instance`, returns `File`)

#### E3 — UI ✅ Done
- `GstrPeriodPicker` widget (month/quarter + fiscal year chips, 12-month grid)
- `Gstr1Screen` — period picker → generate → preview tabs (T4/T5/T7/T9/T12/T13) → CSV ZIP + PDF export
- Entry in `ReportsScreen` under `_GstReturnsCard` (visible in business mode)

#### E4 — Credit/Debit Note original-invoice link + creation UI (unlocks T9) ✅ Done (via Phase F1 + F2)
- **DB migration**: add `original_invoice_id INTEGER`, `original_invoice_no TEXT`, `original_invoice_date TEXT` to `invoices` table — these 3 columns are the sole blocker for GSTR-1 Table 9
- `Invoice` model: `originalInvoiceId`, `originalInvoiceNo`, `originalInvoiceDate` fields + `copyWith`/`toMap`/`fromMap`
- `QuoteBuilderScreen`: support `invoiceType = creditNote / debitNote`; link-to-original-invoice picker snapshots `originalInvoiceNo` + `originalInvoiceDate`

---

### Phase F — Full Credit / Debit Notes ✅ Done

**Goal:** First-class Credit Note and Debit Note documents — issued against existing invoices, printed with correct GST format, tracked in the invoice list, and flowing into GSTR-1 T9 automatically.

#### F1 — DB + Model (DB v47) ✅ Done
- Add to `invoices` table:
  - `original_invoice_id INTEGER REFERENCES invoices(id) ON DELETE SET NULL`
  - `original_invoice_no TEXT` — snapshot (survives if original is deleted)
  - `original_invoice_date TEXT` — ISO-8601 snapshot
- **`InvoiceStatus`** enum: add `cancelled` value (also needed for GSTR-1 T13 cancelled document count)
- **`Invoice`** model: `originalInvoiceId`, `originalInvoiceNo`, `originalInvoiceDate`; update `copyWith`, `toMap`, `fromMap`

#### F2 — Creation flow ✅ Done
- **"Create Credit Note"** action on `InvoiceDetailScreen` (3-dot menu):
  - Pre-fills customer, GSTIN, place of supply from original
  - Pre-fills items from original (user adjusts qty to what was returned/corrected)
  - Auto-snapshots `originalInvoiceNo` + `originalInvoiceDate`
  - Reason field: Goods Returned / Price Correction / Post-sale Discount
- **"Create Debit Note"** action — same flow, reasons: Underbilling / Additional Charges
- Both routed through `QuoteBuilderScreen` with `invoiceType` locked
- Original invoice detail shows a linked badge: *"1 Credit Note raised"*

#### F3 — PDF ✅ Done
- Document title: **"CREDIT NOTE"** / **"DEBIT NOTE"** — automatically from `invoice.invoiceType.label.toUpperCase()`
- Sub-header line: `"Against: INV-2025-001"` via `subTypeLabel` in `PdfDocumentData` (set in `InvoicePdfService`)
- Reason printed in the notes section

#### F4 — Invoice list & status ✅ Done
- `invoiceTypeFilterProvider` added (Riverpod `StateProvider<InvoiceType?>`)
- `filteredInvoicesProvider` respects both status and type filters
- Filter bar extended: status chips + vertical divider + **Credit Notes** / **Debit Notes** type chips
- Selecting a type chip clears the status filter; selecting a status chip clears the type filter
- `_InvoiceTile` shows a small **CN** / **DN** badge (coloured red / orange) beside the invoice number

---

### Phase G — Purchase Bills & GSTR-3B Offset ✅ Done

**Goal:** Record vendor invoices locally so the app can compute **net GST payable = output tax − ITC**, and generate the full GSTR-3B Consolidated Offset Summary (matching the CA-issued format) for every return period. No GSTN portal calls — purely a local purchase + offset register.

#### G1 — DB + Models (DB v48) ✅
- New `purchase_bills` table:
  ```sql
  id, business_id, bill_no, vendor_party_id, vendor_name, vendor_gstin,
  bill_date, due_date, place_of_supply, reverse_charge INTEGER DEFAULT 0,
  subtotal, igst_amount, cgst_amount, sgst_amount, cess_amount, tax_total, total,
  paid_amount,
  itc_eligible INTEGER DEFAULT 1,  -- 0 = blocked u/s 17(5)
  itc_block_reason TEXT,           -- 'motor_vehicle','food','club','personal','construction','works_contract','other'
  itc_availed INTEGER DEFAULT 0,   -- 1 = availed in GSTR-3B
  itc_reversal_reason TEXT,        -- 'rule_42','rule_43','section_17_5','other'
  notes, status, created_at, updated_at
  ```
- New `purchase_bill_items` table — mirrors `invoice_items` with per-line IGST/CGST/SGST amounts
- `PurchaseBill` + `PurchaseBillItem` models (Equatable)
- `PurchaseBillStatus` enum: `unpaid`, `paid`, `partiallyPaid`
- `ItcEligibility` enum: `eligible`, `ineligible`, `blocked` (s.17(5))
- `ItcBlockReason` enum: `motorVehicle`, `food`, `club`, `personal`, `construction`, `worksContract`, `other`

#### G2 — Repository ✅
- `lib/domain/repositories/purchase_bill_repository.dart` — abstract interface
- `lib/data/repositories/purchase_bill_repository_impl.dart` — sqflite implementation
- Methods: `insert`, `update`, `delete`, `fetchById`, `fetchAll`, `fetchForPeriod`, `fetchForBusiness`, `markPaid`
- Riverpod providers in `lib/presentation/providers/purchase_bill_provider.dart`

#### G3 — Add Purchase Bill screen ⬜
- `lib/presentation/screens/purchases/add_purchase_bill_screen.dart`
- Vendor picker (from `parties`)  ·  Line items with HSN + GST %  ·  Auto-calculated CGST/SGST/IGST
- **ITC eligibility toggle** per bill + block-reason dropdown when off
- Reverse Charge toggle (RCM bills — NRC vs RC column in 3B Table 3.1(d))
- Entry: FAB on purchase list screen + "Record Bill" from GST screen

#### G4 — Purchase Bills list screen ⬜
- `lib/presentation/screens/purchases/purchase_bills_screen.dart`
- Filter tabs: All | Unpaid | Paid | Blocked ITC
- Summary strip: ITC available this month / FY (CGST / SGST / IGST)
- Pull monthly totals into `PurchaseSummary` value object

#### G5 — GSTR-3B Offset Screen + Export ✅

**Format matches the CA sample (Consolidated 3B Offset Summary):**

**Table 1 — Outward Supply Summary** (auto-computed from invoices):
| Month | NRC taxable | RC taxable | Non-taxable | Total | IGST | CGST | SGST | CESS |
| + Paid by IGST credit / CGST credit / SGST credit / Cash |

**Table 2 — Inward Supply (RCM)** (auto-computed from purchase_bills where reverse_charge=1):
| Month | RC amounts + Liability | Paid by cash | Interest | Late fees | Due date | Filing date |

**Table 3 — ITC Summary** (auto-computed from purchase_bills):
| Month | ITC Eligible NRC/RC | ITC Reversed | ITC Ineligible | ITC Reclaimed |

**User-entered per-month fields** (Electronic Ledger data not available locally):
- Paid by IGST/CGST/SGST/CESS credit columns (Tables 1 & 2)
- Paid by cash (Tables 1 & 2)
- Interest & late fees (Table 2)
- Filing date (Table 2)
- ITC Reversal amounts (Table 3)

**Offset validation** (enforced in `Gstr3bOffsetService`):
- CGST credit → CGST liability first; remaining can offset IGST
- SGST credit → SGST liability first; remaining can offset IGST
- IGST credit → IGST first, then CGST, then SGST
- Underpayment highlighted in red; overpayment shown as balance

**Export:**
- `Gstr3bPdfService` — 2-page PDF matching sample layout (3 tables + notes)
- `Gstr3bExcelService` (using `excel` package) — `.xlsx` with 3 styled sheets + Grand Total row
- Share via `share_plus`

**Entry:**
- `_Gstr3bCard` in `ReportsScreen` (alongside `_GstReturnsCard`, visible in business mode)

**Data models:**
- `Gstr3bMonthRow` — one row per month: outward liability + ITC + payment columns
- `Gstr3bWorkbook` — FY + 12 rows + grand totals
- `Gstr3bOffsetService.buildWorkbook(businessId, fy, userLedgerInputs)` — mixes auto+manual data

---

## State Codes Reference (for place_of_supply)

| Code | State | Code | State |
|------|-------|------|-------|
| 01 | Jammu & Kashmir | 19 | West Bengal |
| 02 | Himachal Pradesh | 20 | Jharkhand |
| 03 | Punjab | 21 | Odisha |
| 04 | Chandigarh | 22 | Chhattisgarh |
| 05 | Uttarakhand | 23 | Madhya Pradesh |
| 06 | Haryana | 24 | Gujarat |
| 07 | Delhi | 26 | Dadra & NH |
| 08 | Rajasthan | 27 | Maharashtra |
| 09 | Uttar Pradesh | 28 | Andhra Pradesh |
| 10 | Bihar | 29 | Karnataka |
| 11 | Sikkim | 30 | Goa |
| 12 | Arunachal Pradesh | 31 | Lakshadweep |
| 13 | Nagaland | 32 | Kerala |
| 14 | Manipur | 33 | Tamil Nadu |
| 15 | Mizoram | 34 | Puducherry |
| 16 | Tripura | 35 | Andaman & Nicobar |
| 17 | Meghalaya | 36 | Telangana |
| 18 | Assam | 37 | Andhra Pradesh (new) |
| 96 | Foreign | 99 | Other Territory |

---

### Phase D — e-Way Bill Complete (Option A + Option B scaffold)

**Goal:** e-Way Bill generation is fully usable in-app (Option A). Option B (GSP API) is cleanly scaffolded behind an explicit consent gate — no network code runs unless the user opts in.

#### D1 — Transport details + threshold guard + validity (Option A) ⬜
- `_EwayBillSheet` bottom sheet on invoice detail screen collects:
  - Transport mode: Road / Rail / Air / Ship
  - Vehicle number (regex validated: `AA00AA0000`)
  - Transporter name + GSTIN (optional)
  - Distance (km) — drives validity calculation
- Threshold guard: warning banner when `invoice.total < ₹50,000` (EWB not mandatory, but still allowed)
- Validity display: `valid_until = generated_at + floor(distance / 100)` days (min 1 day, GSTN rule)
- EWB fields persisted on `invoices` table (DB v36): `ewb_no`, `ewb_generated_at`, `ewb_valid_until`, `vehicle_no`, `transporter_name`, `transporter_gstin`, `transport_mode`, `distance_km`
- EWB status badge on invoice detail: *"EWB generated · Valid until 5 Mar"*
- Frequent transporters stored in `transporters` table (DB v36) — autocomplete on transporter name field

#### D2 — GSP connector scaffold (Option B) ⬜
- Abstract interface: `lib/domain/repositories/gsp_connector.dart` — `generateEwb()`, `cancelEwb()`, `updateVehicle()`
- Result model: `GspEwbResult` with `ewbNo`, `validUntil`
- Stub implementation: `lib/data/services/gsp/masters_india_connector.dart` (throws `UnimplementedError` — no network code)
- `flutter_secure_storage` added to pubspec (for future API key storage — unused until D3)
- Settings keys pre-seeded in `settings` table: `gsp_enabled=0`, `gsp_provider=masters_india`, `gsp_consent_given_at=`

#### D3 — Consent UI + live GSP integration (future, explicit opt-in) ⬜
- Settings screen: "GSP Connect" tile — disabled by default
- Consent dialog (shown once): explicit warning that invoice data leaves the device
- API key entry via `flutter_secure_storage`
- `MastersIndiaConnector` fully implemented
- Privacy policy updated with GSP section

---

## Progress

| Phase | Task | Status | Commit |
|-------|------|--------|--------|
| A1 | DB v32: GST columns on invoice/quote tables | ✅ Done | `2a781f6` |
| A2 | Model updates (InvoiceItem, Invoice, QuoteItem, Quote) | ✅ Done | `2a781f6` |
| A3 | Invoice form: auto-populate HSN/unit from catalog | ✅ Done | `f9e997f` |
| A4 | SAC code toggle on item catalog | ✅ Done | `f9e997f` |
| B1 | GstCalculator service | ✅ Done | `dde9b3e` |
| B2 | PDF: TAX INVOICE header with GSTINs | ✅ Done | `dde9b3e` |
| B3 | PDF: HSN-grouped GST summary table | ✅ Done | `dde9b3e` |
| C1 | e-Invoice IRN placeholder fields | ✅ Done | `9f8914b` |
| C2 | e-Way Bill JSON export | ✅ Done | `9f8914b` |
| C3 | GSTIN validation utility | ✅ Done | `9f8914b` |
| — | HSN/SAC offline autocomplete (DB v35) | ✅ Done | `fdd3a4f` |
| D1 | Transport dialog, threshold guard, validity, EWB registry | ⬜ In progress | — |
| D2 | GspConnector scaffold (Option B stub) | ⬜ In progress | — |
| D3 | Consent UI + live GSP integration | ⬜ Future | — |
| C3 | Offline GSTIN validation | ✅ Done | `9f8914b` |
| E1 | Gstr1Service, row models, CsvExporter, unit tests | ⬜ Planned | — |
| E2 | Gstr1PdfService — one-page summary | ⬜ Planned | — |
| E3 | Gstr1Screen + GstrPeriodPicker + ReportsScreen entry | ⬜ Planned | — |
| E4 | Credit/Debit Note link columns + creation UI + T9 | ⬜ Planned | — |
| F1 | DB v47: original_invoice columns + cancelled status | ✅ Done | — |
| F2 | Credit/Debit Note creation flow (from invoice detail) | ✅ Done | v47 data; CN/DN builder; linked card |
| F3 | PDF: CREDIT NOTE / DEBIT NOTE title + against-invoice line | ✅ Done | `subTypeLabel` in `InvoicePdfService` |
| F4 | Invoice list filter chips + CN/DN tile badge | ✅ Done | `invoiceTypeFilterProvider` + `_StatusFilterBar` |
| G1 | DB v48: purchase_bills + purchase_bill_items + models + repo | ✅ Done | — |
| G2 | PurchaseBillRepository interface + implementation | ✅ Done | — |
| G3 | Add Purchase Bill screen + ITC eligibility toggle | ✅ Done | `AddPurchaseBillScreen` |
| G4 | Purchase Bills list screen | ✅ Done | `PurchaseBillsScreen` |
| G5 | GSTR-3B Offset Screen + PDF + Excel export | ✅ Done | `Gstr3bService` + `Gstr3bPdfService` + `Gstr3bOffsetScreen` |
