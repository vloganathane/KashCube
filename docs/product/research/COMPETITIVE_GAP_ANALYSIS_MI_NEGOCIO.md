# Competitive Gap Analysis — My Business (Mi Negocio) by Goolaxo

**Reviewed:** 26 March 2026  
**Play Store:** https://play.google.com/store/apps/details?id=com.segb_d3v3l0p.minegocio  
**Rating:** 4.5 ★ / 25.6K reviews / 1M+ downloads  
**Developer:** Goolaxo  
**Last updated:** 19 March 2026  
**Target market:** Latin America (Spanish-first, English supported)  
**Monetisation:** Contains ads + in-app purchases  
**Data privacy:** Shares location, app activity, and 2 other data types with third parties

---

## What Mi Negocio Does

An offline-first, all-in-one SME management app covering inventory, sales, purchases, employees, and basic reporting. Its closest analog in KashCube's competitive landscape is a Latin American Vyapar with a POS twist.

---

## Feature Inventory

### Inventory
- Full stock tracking across products and services
- **Low-stock alerts** + automated restock reports
- **Product expiration date scheduling** (tracks shelf life)
- Shrinkage / write-off tracking (mentioned in reviews)

### Sales / POS
- Barcode scan or manual item entry
- **Thermal (ticket-size) receipt PDF** in addition to A4
- Receipts exportable as PDF and JPG
- **Partial payments** — confirm outstanding receivables
- Customer quotes / estimates

### Purchases
- Purchase order creation and tracking
- Supplier credit tracking

### Customers & Suppliers
- Detailed profiles with transaction history
- Payment reminders and scheduled notifications

### Employees & HR
- **Payroll management** (built, not just schema)
- **Attendance tracking**

### Reports
- Performance reports with charts and statistics
- Real-time insights

### Data Portability
- CSV import/export (spreadsheet-compatible)
- Website integration (mentioned in description)

---

## KashCube Wins (Where We Are Clearly Better)

| Dimension | Mi Negocio | KashCube |
|---|---|---|
| **Privacy** | Shares data with 3rd parties, contains ads | 100% local, zero collection, no ads — ever |
| **Indian tax compliance** | None | GSTR-1, GSTR-3B, E-Way Bill, ITC, HSN/SAC |
| **UPI / SMS auto-capture** | Not present | 56 Indian sender IDs, auto-import |
| **Indian locale** | Western numbers | ₹, `en_IN`, Indian comma grouping (₹1,23,456) |
| **Khata / Udhar credit ledger** | Not present | Core feature |
| **Tally XML / CA export** | CSV only | Tally XML + Excel built-in |
| **LAN / P2P sync** | Not present | W1 LAN sync shipped |
| **Biometric + PIN vault** | Not mentioned | PBKDF2-HMAC-SHA256 + biometric |
| **FEFO lot / batch tracking** | Expiry date on product (not per-lot) | Full FEFO lot movements (v81) |
| **WhatsApp deep-link reminders** | Not present | Built-in (Starter+) |
| **No account required** | Unknown | Never requires an account |

---

## Features Mi Negocio Has That KashCube Is Missing

### 🔴 High Priority

#### 1. Low-Stock Alerts
- **What they do:** When stock falls below a threshold, user gets an alert + auto-report.
- **KashCube status:** `items` table has `min_stock` column. No alert trigger exists.
- **Implementation path:** Add a `WorkManager` periodic job (already used for notifications) that queries `SELECT * FROM items WHERE current_stock <= min_stock AND min_stock > 0`. Fire a local notification per item. Existing `NotificationService` wiring can be reused.
- **Effort:** ~1 day

#### 2. Salary Slip PDF Generation
- **What they do:** Full payroll + staff receive a printable salary slip.
- **KashCube status:** Payroll cycle code exists (DB schema + loop) but no PDF output.
- **Implementation path:** Add a salary-slip template to `PdfService` (reuse existing A4 template infrastructure). Populate from `payroll_entries` table. Add "Generate Slip" button in staff detail / payroll screen.
- **Effort:** ~2 days

#### 3. Attendance Tracking
- **What they do:** Daily punch-in/out per employee.
- **KashCube status:** Not built.
- **Implementation path:** New `attendance` table (`staff_id`, `date`, `check_in`, `check_out`, `status`). Simple calendar-based UI in staff detail screen. Used as input to salary calculation.
- **Effort:** ~3 days

### 🟠 Medium Priority

#### 4. Thermal / Ticket-Size Receipt PDF
- **What they do:** 58mm or 80mm receipt format for POS / thermal printers.
- **KashCube status:** Only A4 PDF templates exist.
- **Implementation path:** Add a `ReceiptSize.thermal58` / `ReceiptSize.thermal80` enum to `PdfService`. Render a compact (no logo, minimal padding) invoice layout at 58mm/80mm width. Let user select receipt format in Settings.
- **User need:** Any kirana, pharmacy, or food stall using a Bluetooth thermal printer wants this.
- **Effort:** ~2 days

#### 5. Stock Write-Off / Adjustment Screen
- **What they do:** Record shrinkage, damaged goods, or manual corrections.
- **KashCube status:** Inventory movements exist for purchases/sales but no manual adjustment flow.
- **Implementation path:** Add an "Adjust Stock" button in inventory item detail. Accept `+/-` quantity, reason (theft/damage/correction/expired), and date. Write directly to `inventory_movements` with type `adjustment`.
- **Effort:** ~1 day

#### 6. Purchase Order (PO) Status Flow
- **What they do:** Create a PO, track it through "sent", "partial delivery", "completed".
- **KashCube status:** Purchase bills exist as point-in-time records. No PO lifecycle.
- **Implementation path:** Add `status` column to purchase bills (`draft → sent → received → partial → closed`) and a status picker in the purchase bill edit screen.
- **Effort:** ~2 days

---

## Features Intentionally Different / Out of Scope

| Feature | Reason |
|---|---|
| Ads | Privacy policy prohibits monetisation via ads |
| Data sharing with 3rd parties | Privacy-first — non-negotiable |
| Cloud sync | Privacy-by-design; LAN/P2P sync is the alternative |
| Website integration requiring server | No network calls by design |

---

## Competitive Summary

Mi Negocio is the strongest offline-first SME app in its region. At 1M+ downloads and 4.5 stars it validates the exact market KashCube is targeting. Its fatal weakness for India is **privacy** (ads + data sharing) combined with **no Indian tax / UPI support**.

KashCube is already ahead on every India-specific dimension. The three actionable gaps to close are:

1. **Low-stock alerts** — quick win, `min_stock` data already exists
2. **Salary slip PDF** — unlock HR module for shops with employees
3. **Thermal receipt** — unlock POS-style use cases (kirana, pharmacy, food stall)

Closing these three turns KashCube into a comprehensive answer for any Indian small business that currently cobbles together Mi Negocio + a thermal receipt app + a CA's spreadsheet.
