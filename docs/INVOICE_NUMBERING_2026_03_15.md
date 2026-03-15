# Conflict-Free GST Invoice Numbering — Multi-Device

**Created:** 2026-03-15  
**Status:** Implemented

---

## 1. Problem Statement

KashCube supports multiple linked devices (primary + one or more secondaries).
All devices can create invoices, quotes, and delivery challans.
GST requires that these serial numbers are:

- **Unique** — no two documents may share the same number in a FY
- **Sequential** — gaps are frowned upon; order must reflect creation date
- **Non-repeating** — cancelled docs still "use" a number (stub required)

The previous single-device implementation used `MAX(invoice_no)` scan on SQLite
which is inherently racy across two concurrent devices.

---

## 2. Core Design Decisions

### 2a. UUID identity, sequential GST number

Every document gets a UUID as its primary key at creation time (already the case).
The GST-visible number (`invoice_no`, `quote_no`, `challan_no`) is assigned later,
by the **primary device only**, using an atomic counter in the
`invoice_number_cursors` table.

### 2b. Two numbering paths

| Path | Condition | Flow |
|------|-----------|------|
| **Real-time** | Secondary is on same Wi-Fi / LAN as primary | Secondary sends `reserve_number` over TCP/WS → primary atomically increments cursor → returns formatted number → secondary saves with real number |
| **Deferred** | Secondary is offline | Secondary saves with `invoice_no = NULL`, `status = pending_number` → on delta upload, primary assigns numbers in `created_at` order |

Walk-in retail typically uses real-time (shop devices stay on Wi-Fi).
Field sales uses deferred when driving between clients.

### 2c. Primary device is the single source of truth

No distributed consensus needed. The primary's `invoice_number_cursors` table
is the authoritative counter. All number assignments go through it.

---

## 3. Database Schema

### New table: `invoice_number_cursors`

```sql
CREATE TABLE invoice_number_cursors (
  doc_type   TEXT PRIMARY KEY,   -- 'invoice' | 'quote' | 'dc'
  fy         TEXT NOT NULL,      -- '2025-26'
  prefix     TEXT NOT NULL,      -- 'INV-25-26-' (computed from format + FY)
  last_seq   INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
)
```

One row per document type per fiscal year.
When FY rolls over, a new row is inserted (old rows kept for audit).

### Modified columns (v67 migration, ALTER)

| Table | Column | Old | New |
|-------|--------|-----|-----|
| `invoices` | `invoice_no` | `TEXT NOT NULL UNIQUE` | `TEXT UNIQUE` |
| `invoices` | `pending_number_since` | — | `TEXT` (ISO8601) |
| `quotes` | `quote_no` | `TEXT NOT NULL UNIQUE` | `TEXT UNIQUE` |
| `quotes` | `pending_number_since` | — | `TEXT` (ISO8601) |
| `delivery_challans` | `challan_no` | `TEXT NOT NULL UNIQUE` | `TEXT UNIQUE` |
| `delivery_challans` | `pending_number_since` | — | `TEXT` (ISO8601) |

> SQLite does not support `DROP NOT NULL` via `ALTER TABLE`. The migration
> recreates each table via a `CREATE TABLE … SELECT` round-trip.

---

## 4. Wire Protocol

### reserve_number (secondary → primary)

```json
{
  "type": "reserve_number",
  "doc_type": "invoice",   // "invoice" | "quote" | "dc"
  "count": 1,
  "device_id": "abc123"
}
```

### number_reserved (primary → secondary)

```json
{
  "type": "number_reserved",
  "doc_type": "invoice",
  "numbers": ["INV-25-26-0042"]
}
```

### Error response

```json
{
  "type": "error",
  "message": "reserve_number_failed",
  "detail": "..."
}
```

Supported on both TCP (`SyncServer` / `SyncClient`) and WebSocket
(`WebServerService`) using the same JSON envelope.

---

## 5. NumberReservationService

`lib/data/services/number_reservation_service.dart`

```
reserveNext(db, docType, [count=1]) → List<String>
  - Runs in a BEGIN EXCLUSIVE transaction
  - SELECTs current cursor row (creates it if missing using FY/format from settings)
  - Increments last_seq by count
  - UPDATEs row
  - Returns formatted number(s)

assignPendingNumbers(db, fiscalYearService) → int
  - SELECTs invoices/quotes/DCs WHERE pending_number_since IS NOT NULL
    ORDER BY created_at ASC
  - For each, calls reserveNext() and UPDATEs the row
  - Clears pending_number_since, sets status back from pending_number → draft
  - Returns count of assigned rows
```

---

## 6. FiscalYearService changes

`nextInvoiceNo()`, `nextQuoteNo()`, `nextChallanNo()`, `nextCreditNoteNo()`,
`nextDebitNoteNo()` are refactored to delegate to
`NumberReservationService.reserveNext()` instead of the scan-based `MAX()` query.

The result is identical from the caller's perspective.

---

## 7. Sync flow for deferred assignment

In `_handleDeltaUpload` (TCP) and `_wsHandleDeltaUpload` (WS):

1. Apply incoming delta rows as before.
2. After commit, call `NumberReservationService.assignPendingNumbers()`.
3. Any rows that got numbers assigned are pushed back as a new delta to the
   requesting device in the `delta_upload_ack` response.

---

## 8. Status Enum Additions

| Enum | New value | DB string | Meaning |
|------|-----------|-----------|---------|
| `InvoiceStatus` | `pendingNumber` | `'pending_number'` | Saved without a number; awaiting assignment |
| `QuoteStatus` | `pendingNumber` | `'pending_number'` | Same |
| `ChallanStatus` | `pendingNumber` | `'pending_number'` | Same |

After number assignment the document reverts to `draft` (or its previous
non-pending status).

---

## 9. Cancelled number gaps

If a document is deleted while still in `pending_number` state → no gap is
created (number was never reserved).

If a document is cancelled **after** a number was already assigned → the number
is "used" (serial remains in DB with `status = 'cancelled'`). This satisfies GST
audit requirements.

---

## 10. Implementation Files Changed

| File | Change |
|------|--------|
| `lib/core/constants/app_constants.dart` | `dbVersion` → 67 |
| `lib/data/services/database_helper.dart` | v67 migration block |
| `lib/data/services/number_reservation_service.dart` | **NEW** |
| `lib/data/services/fiscal_year_service.dart` | Delegate to `NumberReservationService` |
| `lib/data/services/sync_server.dart` | `reserve_number` TCP handler |
| `lib/data/services/web_server_service.dart` | `reserve_number` WS handler |
| `lib/data/services/sync_client.dart` | `reserveNumber()` method |
| `lib/data/models/invoice.dart` | `pendingNumber` status; nullable `invoiceNo` |
| `lib/data/models/quote.dart` | `pendingNumber` status; nullable `quoteNo` |
| `lib/data/models/delivery_challan.dart` | `pendingNumber` status; nullable `challanNo` |
