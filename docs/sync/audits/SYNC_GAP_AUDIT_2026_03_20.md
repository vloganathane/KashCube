# Sync Gap Audit — 20 March 2026

## Summary

Audit of all 53 DB tables revealed **9 parent tables** missing sync columns
(sync_id, version, device IDs) and **6 child/item tables** with no timestamps
at all. These tables currently sync in degraded mode — either deltaTs-only
(no merge safety) or full snapshot every pull.

## Tables Missing Sync Columns (v71 Migration)

### Group A — Need ALL sync columns (only have `created_at`)

| Table | Has | Missing |
|-------|-----|---------|
| `loan_payments` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |
| `salary_payments` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |
| `party_addresses` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |
| `bill_attachments` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |
| `stock_movements` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |
| `document_templates` | created_at | sync_id, updated_at, deleted_at, version, created_by_device_id, updated_by_device_id |

### Group B — Need sync_id + deleted_at + version + device IDs (already have `updated_at`)

| Table | Has | Missing |
|-------|-----|---------|
| `staff` | created_at, updated_at | sync_id, deleted_at, version, created_by_device_id, updated_by_device_id |
| `bookings` | created_at, updated_at | sync_id, deleted_at, version, created_by_device_id, updated_by_device_id |
| `delivery_challans` | created_at, updated_at | sync_id, deleted_at, version, created_by_device_id, updated_by_device_id |

## Child Tables Missing Timestamps (v72 Migration)

These tables sync as full-snapshot mode (entire table dumped every pull)
because they have no timestamp column for delta detection. Adding
`created_at` + `updated_at` enables deltaTs mode; parent CASCADE handles
deletes so `deleted_at` is unnecessary.

| Table | PK | Missing |
|-------|-----|---------|
| `quote_items` | id (auto) | created_at, updated_at |
| `invoice_items` | id (auto) | created_at, updated_at |
| `booking_items` | id (auto) | created_at, updated_at |
| `delivery_challan_items` | id (auto) | created_at, updated_at |
| `purchase_bill_items` | id (auto) | created_at, updated_at |
| `item_stock` | (business_id, item_id) | created_at, updated_at |

## Other Issues

1. **SYNC_PLAN not handled on browser** — Phone sends `SYNC_PLAN` message
   after `AUTH_OK` but browser's `_onMessage` switch has no handler for it.
2. **Auto-refresh gaps** — `loan_payments`, `invoice_items`, `quote_items`,
   `booking_items` missing explicit cases (fall through to broad `default:`).
3. **Business mode on web** — Plumbing is correct (settings sync →
   `notifyChange('settings')` → `businessModeProvider` invalidated). If not
   working, likely a timing race on first sync.
4. **PIN lock on web** — Intentionally bypassed (`if (kIsWeb) return
   WebConnectScreen()`). Web uses QR token auth only.

## Implementation Plan

- **v71**: ALTER TABLE for 9 parent tables + backfill sync_id + indexes + triggers
- **v72**: ALTER TABLE for 6 child tables (add created_at, updated_at)
- Update fresh-install schemas in `database_helper_tables.dart`
- Bump `dbVersion` to 72
- Add `SYNC_PLAN` handler in `web_sync_provider.dart`
- Add missing auto-refresh cases
