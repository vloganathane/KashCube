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
| C1 | e-Invoice IRN placeholder fields | ⬜ | — |
| C2 | e-Way Bill JSON export | ⬜ | — |
| C3 | Offline GSTIN validation | ⬜ | — |
