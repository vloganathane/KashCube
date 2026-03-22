# GSTR-1 Workbook Export — Design & Implementation Spec

> **Phase E** — extends `GST_COMPLIANCE_PLAN.md`  
> Status: ⬜ Planned  
> Prerequisite: Phases A–D (GST models, GstCalculator, e-Way Bill)

---

## What Is This?

GSTR-1 is the **monthly/quarterly return for outward supplies** every GST-registered dealer must file. KashCube **cannot** file directly to the GSTN portal (that requires a network call to a GSP/ASP — out of scope for a privacy-first, offline app). What it **can** do is generate a ready-to-import **workbook** (CSV files + PDF summary) that the user hands to their CA or uploads to the GSTN offline tool / ClearTax / TallyPrime without manual data entry.

---

## Scope

| Included | Excluded |
|---|---|
| GSTR-1 outward supply tables (T4, T5, T7, T9, T12, T13) | GSTR-2 (purchase-side — no data) |
| CSV per table (GSTN offline tool format) | GSTR-3B, GSTR-9 |
| PDF summary (one-pager for CA review) | Actual GSTN portal filing |
| Business-wise, period-wise filtering | Amendments (GSTR-1A) |
| Credit/Debit note register (T9) | e-Invoice IRN link (IRN not generated offline) |

---

## Data Availability Check

All fields needed for GSTR-1 are already captured by existing models:

| GSTR-1 Field | Source | Available? |
|---|---|---|
| GSTIN of supplier | `businesses.gstin` | ✅ |
| Financial Year | Derived from `invoice.issue_date` | ✅ |
| Return Period (MM/YYYY) | UI date range picker | ✅ |
| Receiver GSTIN | `invoice.customer_gstin` + `parties.gstin` | ✅ |
| Invoice No | `invoice.invoice_no` | ✅ |
| Invoice Date | `invoice.issue_date` | ✅ |
| Invoice Value | `invoice.total` | ✅ |
| Place of Supply (State Code) | `invoice.place_of_supply` | ✅ |
| Reverse Charge | `invoice.reverse_charge` | ✅ |
| Invoice Type | `invoice.invoice_type` (taxInvoice / creditNote / debitNote) | ✅ |
| Taxable Value | `invoice.subtotal` | ✅ |
| Tax Rate (%) | `invoice_items.tax_pct` | ✅ |
| CGST / SGST / IGST | `GstCalculator.calculate()` | ✅ |
| HSN/SAC code | `invoice_items.hsn_code` | ✅ |
| UQC (Unit Quantity Code) | `invoice_items.unit` → GSTN UQC map | ✅ (map exists in `eway_bill_service.dart`) |
| Quantity | `invoice_items.qty` | ✅ |

**No new DB columns needed for Phase E.**

---

## GSTR-1 Tables Covered

### Table 4 — B2B Invoices (Taxable outward supplies to registered persons)

Invoices where `customer_gstin` is non-null, `invoice_type = taxInvoice`, `status != draft`.

**CSV columns (GSTN offline tool T4):**
```
GSTIN of Receiver, Receiver Name, Invoice No, Invoice Date, Invoice Value,
Place of Supply (State Code), Reverse Charge (Y/N), Invoice Type,
E-Commerce GSTIN, Rate (%), Taxable Value, CGST Amount, SGST Amount, IGST Amount
```

- One row per invoice–rate combination (if invoice has mixed 12% + 18% items, two rows)
- **Invoice Type** mapping: `taxInvoice` → "Regular", `billOfSupply` → excluded from T4

---

### Table 5 — B2C Large (Inter-state invoices > ₹2,50,000 to unregistered persons)

Invoices where `customer_gstin` is null AND `total > 250000` AND `isInterState`.

**CSV columns (GSTN T5):**
```
Place of Supply (State Code), Rate (%), Taxable Value, IGST Amount, E-Commerce GSTIN
```

- Grouped by `place_of_supply` + rate (aggregate per group, not per invoice)

---

### Table 7 — B2C Small Consolidated (All other B2C supplies)

Invoices where `customer_gstin` is null AND (`total ≤ 250000` OR intra-state).

**CSV columns (GSTN T7):**
```
Type (OE = Others), Place of Supply (State Code), Rate (%), Taxable Value, CGST, SGST, IGST
```

- Single consolidated row per state × rate combination

---

### Table 9 — Credit / Debit Notes (Registered receivers)

Invoices where `invoice_type = creditNote` or `debitNote` AND `customer_gstin` is non-null.

**CSV columns (GSTN T9):**
```
GSTIN of Receiver, Note No, Note Date, Note Type (C/D), Place of Supply,
Original Invoice No, Original Invoice Date, Value, Rate (%), Taxable Value, CGST, SGST, IGST
```

- `Original Invoice No` ← `invoice.originalInvoiceNo` (snapshot field — not a live JOIN)
- `Original Invoice Date` ← `invoice.originalInvoiceDate` (snapshot, survives if original is deleted)

> ⚠️ **Blocker**: `originalInvoiceNo` / `originalInvoiceDate` / `originalInvoiceId` do not yet exist on the `Invoice` model or `invoices` table. This is the **only data gap** for full GSTR-1 output. Everything else is already captured. See Gap 1 below.

---

### Table 12 — HSN-wise Summary

Line items grouped by `hsn_code` × `tax_pct`. Sum `qty`, `taxable_amount`, `cgst`, `sgst`, `igst`.

**CSV columns (GSTN T12):**
```
HSN/SAC, Description, UQC (GSTN unit code), Total Quantity, Total Value,
Taxable Value, Integrated Tax Amount, Central Tax Amount, State/UT Tax Amount, Cess Amount
```

- UQC mapping: app unit → GSTN UQC (reuse map from `EwayBillService._uqcMap`)
- Description: auto-populated from `catalog_items.name` for that HSN (first match)
- Cess: always 0 for now

---

### Table 13 — Document Summary

Count of documents (invoices, credit notes, debit notes) issued in the period.

**CSV columns (GSTN T13):**
```
Nature of Document, Series From, Series To, Total Submitted, Cancelled
```

| Nature | Source |
|---|---|
| Invoices for outward supply | `invoice_type IN (taxInvoice, billOfSupply)` |
| Invoices for inward supply (reverse charge) | `reverse_charge = 1` |
| Credit Notes | `invoice_type = creditNote` |
| Debit Notes | `invoice_type = debitNote` |

- "Series From" / "Series To": lowest and highest `invoice_no` in period (string sort)
- "Cancelled": invoices with `status = cancelled` in period

---

## Architecture

### New Files

```
lib/
├── data/
│   └── services/
│       └── gstr1_service.dart          # Aggregation engine
├── domain/
│   └── usecases/
│       └── generate_gstr1_workbook.dart
├── presentation/
│   └── screens/
│       └── gst/
│           ├── gstr1_screen.dart        # Period picker + preview + export
│           ├── gstr1_table_view.dart    # Scrollable table widget for preview
│           └── gstr_period_picker.dart  # Month/quarter + FY widget
└── core/
    └── utils/
        └── csv_exporter.dart            # Generic List<List<String>> → CSV bytes
```

### Modified Files

```
lib/presentation/screens/reports/reports_screen.dart  # Add "GSTR-1" entry
```

---

## `Gstr1Service` Contract

```dart
// lib/data/services/gstr1_service.dart

class Gstr1Workbook {
  final String businessGstin;
  final String businessName;
  final DateRange period;          // start/end dates
  final String returnPeriodLabel;  // e.g. "032026" (MMYYYY)

  final List<Gstr1B2bRow> tableB2b;            // T4
  final List<Gstr1B2cLargeRow> tableB2cLarge;  // T5
  final List<Gstr1B2cSmallRow> tableB2cSmall;  // T7
  final List<Gstr1CdnRow> tableCdn;            // T9
  final List<Gstr1HsnRow> tableHsn;            // T12
  final Gstr1DocSummary docSummary;            // T13

  // Headline numbers for PDF summary
  int get totalInvoices;
  double get totalTaxableValue;
  double get totalCgst;
  double get totalSgst;
  double get totalIgst;
  double get totalTaxLiability;
}

abstract class Gstr1ServiceInterface {
  Future<Gstr1Workbook> generateWorkbook({
    required int businessId,
    required DateTime from,
    required DateTime to,
  });
}
```

### Aggregation Logic

```dart
// Pseudo-code for generateWorkbook()

final invoices = await _invoiceRepo.fetchForPeriod(
  businessId: businessId,
  from: from,
  to: to,
  excludeStatuses: [InvoiceStatus.draft],
);

for (final inv in invoices) {
  final gst = GstCalculator.calculate(inv.items, inv.placeOfSupply, business.state);

  if (inv.invoiceType == InvoiceType.taxInvoice) {
    if (inv.customerGstin != null) {
      // → T4 B2B (grouped by inv + rate)
    } else if (gst.isInterState && inv.total > 250000) {
      // → T5 B2C Large (grouped by state + rate)
    } else {
      // → T7 B2C Small (grouped by state + rate)
    }
  } else if (inv.invoiceType == InvoiceType.billOfSupply) {
    // → T7 B2C Small (no IGST/CGST/SGST, all zero)
  } else if (inv.invoiceType == InvoiceType.creditNote ||
             inv.invoiceType == InvoiceType.debitNote) {
    if (inv.customerGstin != null) {
      // → T9
    }
  }

  // All non-draft invoices → T12 HSN (group by hsn + rate)
}
// → T13 Document Summary (counts + series)
```

---

## CSV Export Format

Each table exported as a separate `.csv` file with UTF-8 BOM (required by GSTN offline tool).

File naming convention:
```
GSTR1_<MMYYYY>_<GSTIN>_T4_B2B.csv
GSTR1_<MMYYYY>_<GSTIN>_T5_B2CLarge.csv
GSTR1_<MMYYYY>_<GSTIN>_T7_B2CSmall.csv
GSTR1_<MMYYYY>_<GSTIN>_T9_CDN.csv
GSTR1_<MMYYYY>_<GSTIN>_T12_HSN.csv
GSTR1_<MMYYYY>_<GSTIN>_T13_DocSummary.csv
```

All 6 files zipped as:
```
GSTR1_<MMYYYY>_<GSTIN>.zip
```
Shared via `share_plus` (`SharePlus.shareXFiles()`).

### `CsvExporter` utility
```dart
// lib/core/utils/csv_exporter.dart

class CsvExporter {
  /// Converts headers + rows into CSV bytes (UTF-8 with BOM).
  static Uint8List encode(List<String> headers, List<List<dynamic>> rows);

  /// Writes to a temp file and returns the File.
  static Future<File> writeToTemp(String fileName, Uint8List bytes);

  /// Zips multiple files, returns XFile ready for share_plus.
  static Future<XFile> zipFiles(String zipName, List<File> files);
}
```

---

## PDF Summary (One-Pager for CA)

Generated by a new `Gstr1PdfService` (extends `PdfLayoutEngine` patterns):

```
┌─────────────────────────────────────────────────────────────────┐
│  GSTR-1 WORKBOOK SUMMARY                                        │
│  Business: Acme Traders   GSTIN: 29ABCDE1234F1Z5               │
│  Return Period: March 2026 (032026)                             │
├─────────────────────────────────────────────────────────────────┤
│  Table 4 — B2B Invoices       12 invoices   ₹4,56,000 taxable  │
│  Table 5 — B2C Large (inter)   3 invoices   ₹94,000 taxable    │
│  Table 7 — B2C Small           8 invoices   ₹32,000 taxable    │
│  Table 9 — Credit/Debit Notes  1 note       ₹5,000             │
│  Table 12 — HSN Summary        4 HSN codes  —                  │
│  Table 13 — Document Summary  24 docs       1 cancelled        │
├─────────────────────────────────────────────────────────────────┤
│  TOTAL TAXABLE VALUE: ₹5,77,000                                 │
│  CGST: ₹28,850    SGST: ₹28,850    IGST: ₹0                    │
│  TOTAL TAX LIABILITY: ₹57,700                                   │
├─────────────────────────────────────────────────────────────────┤
│  Generated on 01 Apr 2026 by KashCube · kashcube.com            │
└─────────────────────────────────────────────────────────────────┘
```

---

## UI Flow — `Gstr1Screen`

```
Reports Screen
  └─ "GST Returns" row
       └─ Gstr1Screen
            ├─ [Business picker]           ← if multi-business
            ├─ GstrPeriodPicker            ← month + FY, or quarter + FY
            ├─ [Generate Preview button]
            │
            ├─ Preview: Summary cards       ← T4 count, T5 count, tax totals
            ├─ Expandable table tabs:
            │    T4 | T5 | T7 | T9 | T12 | T13
            │
            └─ Export row:
                 [Export CSV (ZIP)]   [Export PDF Summary]
```

### `GstrPeriodPicker` widget

```dart
// Monthly (default) or Quarterly toggle
// Fiscal year picker: maps FY "2025-26" to Apr 2025 – Mar 2026
// Month/Quarter dropdown filtered to current FY
// Shows warning if selected period overlaps with future dates

GstrPeriodPicker(
  onChanged: (DateRange range, String returnPeriodLabel) { ... },
)
```

---

## Known Gaps & Phased Resolution

### Gap 1 — Credit/Debit Note original-invoice link (the only blocking gap for Table 9)

**Problem**: `InvoiceType.creditNote` and `InvoiceType.debitNote` exist in the enum and are serialised correctly, but the `invoices` table and `Invoice` model have **no reference back to the original invoice**. GSTR-1 T9 mandates `Original Invoice No` and `Original Invoice Date` on every credit/debit note row. Without these, T9 cannot be populated.

Missing DB columns (need a new migration):
```sql
ALTER TABLE invoices ADD COLUMN original_invoice_id   INTEGER REFERENCES invoices(id) ON DELETE SET NULL;
ALTER TABLE invoices ADD COLUMN original_invoice_no   TEXT;   -- snapshot (survives original deletion)
ALTER TABLE invoices ADD COLUMN original_invoice_date TEXT;   -- ISO-8601 date snapshot
```

Missing `Invoice` model fields:
```dart
/// FK to the original invoice (only set when invoiceType is creditNote / debitNote).
final int? originalInvoiceId;
/// Snapshot of the original invoice number at the time the note was created.
final String? originalInvoiceNo;
/// Snapshot of the original invoice date (ISO-8601).
final String? originalInvoiceDate;
```

**Resolution (Phase F1 + F2 in `GST_COMPLIANCE_PLAN.md`)**:
- DB migration: add the 3 columns above
- `Invoice` model: add fields, update `copyWith`, `toMap`, `fromMap`
- `QuoteBuilderScreen`: support `invoiceType = creditNote / debitNote`; when selected, show a "Link to original invoice" picker that snapshots `originalInvoiceNo` + `originalInvoiceDate`
- `Gstr1Service` T9 population uses `originalInvoiceNo` / `originalInvoiceDate` directly from the model

### Gap 2 — Multi-rate invoices in B2B/B2C tables

**Problem**: GSTN T4 requires one row per invoice × rate combination. Current aggregation needs to expand `invoice_items` grouped by `tax_pct`.

**Resolution**: `Gstr1Service` iterates `invoice.items`, groups by `tax_pct`, sums `taxable_amount` per group, calls `GstCalculator` per rate bucket.

### Gap 3 — `invoice.place_of_supply` stores state name or code?

**Problem**: GSTR-1 needs 2-digit state code (e.g., "29" for Karnataka). If `place_of_supply` stores "Karnataka" (text), need a lookup.

**Resolution**: Add `stateCodeFromName(String stateName)` to `GstinValidator` (the `_stateNames` reverse map already partially exists). Alternatively store state code at invoice creation time.

**Check**: `GstinValidator.stateCodeFrom(gstin)` exists. Need equivalent `stateCodeFromName()`.

### Gap 4 — Cancelled invoice count for T13

**Problem**: `InvoiceStatus` enum — verify `cancelled` value exists and is persisted.

**Resolution**: `grep_search InvoiceStatus` before implementation.

---

## Implementation Phases

### Phase E1 — Data Layer
- [ ] `Gstr1Service` with `generateWorkbook()` — no UI yet
- [ ] Row models: `Gstr1B2bRow`, `Gstr1B2cLargeRow`, `Gstr1B2cSmallRow`, `Gstr1CdnRow`, `Gstr1HsnRow`, `Gstr1DocSummary`
- [ ] `CsvExporter` utility (UTF-8 BOM, zip)
- [ ] `stateCodeFromName()` in `GstinValidator`
- [ ] Unit tests: `test/data/services/gstr1_service_test.dart`
  - B2B row generation
  - B2C split by threshold and inter/intra state
  - HSN aggregation across multiple invoices
  - Mixed-rate invoice expansion

### Phase E2 — PDF Summary
- [ ] `Gstr1PdfService` — one-pager PDF
- [ ] Wire to `PdfLayoutEngine` header/footer conventions

### Phase E3 — UI
- [ ] `GstrPeriodPicker` widget
- [ ] `Gstr1Screen` — period picker + summary cards + table tabs + export buttons
- [ ] Entry in `ReportsScreen` ("GST Returns" row)

### Phase E4 — Credit/Debit Note creation (unlocks Table 9)
- [ ] `QuoteBuilderScreen`: support `invoiceType = creditNote / debitNote`
- [ ] `original_invoice_id` FK on `invoices` (DB migration v3x)
- [ ] Link-to-original-invoice picker in form
- [ ] T9 population in `Gstr1Service`

---

## Testing Checklist

```dart
// Scenario 1: B2B invoice, intra-state, 18% GST
// → T4: 1 row, CGST 9% + SGST 9%, IGST 0

// Scenario 2: B2C invoice, inter-state, ₹3,00,000, 18%
// → T5: 1 aggregate row for that state + rate

// Scenario 3: B2C invoice, inter-state, ₹1,00,000, 18%
// → T7: 1 aggregate row

// Scenario 4: Mixed-rate invoice (some items 5%, some 18%), B2B
// → T4: 2 rows for same invoice (one per rate bucket)

// Scenario 5: Bill of Supply (composition/exempted, 0% GST)
// → T7 with zero tax, taxable value only

// Scenario 6: Credit Note against B2B invoice
// → T9: note row with C type, original invoice reference
```

---

## Out of Scope (Explicitly)

1. **GSTN portal filing** — requires network + GSP/ASP credentials
2. **GSTR-2 / GSTR-2B** — purchase-side; no expenses/purchase tracking in KashCube
3. **GSTR-3B** — aggregate return; requires GSTR-2 data (purchases)
4. **GSTR-9 Annual Return** — requires full year reconciliation
5. **Amendments (GSTR-1A)** — future phase; needs "amend previous return" workflow
6. **e-Invoice IRN in GSTR-1** — IRN field exists in DB but IRN is not generated offline; the T4 export can include QR/IRN if available, else leave blank
7. **Cess** — not implemented (relevant for tobacco, luxury goods, vehicles); always 0

---

## Dependencies

No new packages required. All existing dependencies cover Phase E:

| Need | Package |
|---|---|
| ZIP creation | `dart:io` + `archive` (already in Flutter) |
| CSV encoding | `dart:convert` (pure Dart) |
| File sharing | `share_plus` (already in pubspec) |
| Date formatting | `intl` (already in pubspec) |
| PDF | `pdf` (already in pubspec via printing) |

> Verify `archive` package: run `grep 'archive' pubspec.yaml`. If absent, it's a pure-Dart package with no network calls — safe to add.

---

*Document created: 2026-02*  
*Owner: KashCube engineering*  
*Related: `GST_COMPLIANCE_PLAN.md`, `DATABASE_SCHEMA.md`, `SMS_PARSING_SPEC.md`*
