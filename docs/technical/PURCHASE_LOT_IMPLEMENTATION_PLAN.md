# Purchase Lot Handling Implementation Plan

**Date:** 26 Mar 2026  
**Scope:** Local-only inventory lot tracking for Purchase Bills + Invoice/Challan consumption  
**Architecture Fit:** MVVM + Repository + SQLite (`sqflite`) + existing `InventoryService`

---

## 1) Goals

Implement lot-level inventory with FEFO allocation while preserving current quantity-based behavior and compatibility.

### Functional goals
- Track stock by lot (batch no, expiry, cost, remaining qty).
- Inward stock from Purchase Bills should create lot records.
- Outward stock from Invoices / Delivery Challans should consume lots using FEFO.
- Preserve full movement audit (including lot-level movement rows).
- Keep everything offline/local (no network calls).

### Non-goals (Phase 1)
- Multi-location warehouse logic.
- Barcode/QR lot scanning.
- Automatic valuation accounting exports.

---

## 2) Current State (baseline)

Current implementation is aggregate stock only:
- `item_stock` holds per-item quantity per business.
- `stock_movements` logs quantity deltas per item.
- Purchase Bill adds stock via `InventoryService.addStock(...)`.
- Invoice / Challan deduct stock via `InventoryService.deductStock(...)`.
- Reverse flows call `reverseMovementsFor(...)`.

No lot tables/columns currently exist.

---

## 3) Data Model Design

## 3.1 New tables

### `stock_lots`
Represents each purchasable lot for an item.

Suggested columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `business_id INTEGER NOT NULL REFERENCES businesses(id)`
- `item_id INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE`
- `purchase_bill_id INTEGER REFERENCES purchase_bills(id) ON DELETE SET NULL`
- `purchase_bill_item_id INTEGER REFERENCES purchase_bill_items(id) ON DELETE SET NULL`
- `lot_no TEXT` (nullable to support no-batch purchases)
- `expiry_date TEXT` (ISO date, nullable)
- `mfg_date TEXT` (nullable)
- `unit_cost REAL NOT NULL DEFAULT 0`
- `qty_in REAL NOT NULL DEFAULT 0`
- `qty_remaining REAL NOT NULL DEFAULT 0`
- `status TEXT NOT NULL DEFAULT 'active'` (`active`, `depleted`, `expired`, `blocked`)
- `notes TEXT`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `updated_at TEXT`
- `deleted_at TEXT`
- `sync_id TEXT UNIQUE DEFAULT (lower(hex(randomblob(16))))`
- `version INTEGER NOT NULL DEFAULT 0`
- `created_by_device_id TEXT`
- `updated_by_device_id TEXT`

Indexes:
- `idx_stock_lots_item_business` on `(business_id, item_id)`
- `idx_stock_lots_fefo` on `(business_id, item_id, expiry_date, created_at, id)`
- `idx_stock_lots_bill` on `(purchase_bill_id)`
- `idx_stock_lots_remaining` on `(business_id, item_id, qty_remaining)`

Uniqueness guard (optional but recommended):
- Unique on `(business_id, item_id, COALESCE(lot_no,''), COALESCE(expiry_date,''), unit_cost, purchase_bill_item_id)`

### `lot_movements`
Lot-level movement ledger (granular audit trail).

Suggested columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `business_id INTEGER NOT NULL REFERENCES businesses(id)`
- `item_id INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE`
- `lot_id INTEGER NOT NULL REFERENCES stock_lots(id) ON DELETE CASCADE`
- `movement_type TEXT NOT NULL` (`purchase_in`, `sale_out`, `challan_out`, `adjustment`, `reversal`, `physical_count`)
- `qty REAL NOT NULL` (positive for inward, negative for outward)
- `lot_qty_after REAL NOT NULL`
- `reference_type TEXT` (`purchase_bill`, `invoice`, `challan`, etc.)
- `reference_id INTEGER`
- `reference_line_id INTEGER` (e.g., invoice item row)
- `notes TEXT`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`

Indexes:
- `idx_lot_mov_lot` on `(lot_id, created_at DESC)`
- `idx_lot_mov_ref` on `(reference_type, reference_id)`
- `idx_lot_mov_item_business` on `(business_id, item_id, created_at DESC)`

## 3.2 Existing table extensions

### `purchase_bill_items`
Add:
- `lot_no TEXT`
- `expiry_date TEXT`
- `mfg_date TEXT`
- `unit_cost REAL` (if different from `unit_price` handling)

### `invoice_items`
Add:
- `lot_allocation_json TEXT` (array of `{lot_id, qty, lot_no, expiry_date}` snapshot)

### `stock_movements`
Keep existing table for aggregate movement continuity.
Add nullable:
- `meta_json TEXT` (optional summary of lot splits)

---

## 4) Migration Plan

## 4.1 Versioning strategy
- Bump DB version once (e.g., `79 -> 80`) for all lot features.
- Add creation calls in both:
  - fresh install path (`_onCreate`)
  - upgrade path (`_onUpgrade` oldVersion < 80)

## 4.2 Migration SQL sequence
1. Create `stock_lots`.
2. Create `lot_movements`.
3. Add new columns to `purchase_bill_items`, `invoice_items`, `stock_movements` using `ALTER TABLE ... ADD COLUMN` guarded by try/catch.
4. Create indexes.
5. Insert schema_version note.

## 4.3 Backfill behavior
No synthetic lot backfill required for old data in Phase 1.
- Historical stock remains valid at aggregate level.
- Lot logic applies to new inward transactions after migration.
- For existing stock, use a virtual fallback lot created lazily at first outbound if needed:
  - lot_no = `LEGACY-OPENING`
  - expiry = null
  - qty_in = current stock snapshot

(Alternative: disable FEFO strict mode until at least one lot exists for an item.)

---

## 5) FEFO Allocation Design

## 5.1 Allocation order
For an item + business, select candidate lots where `qty_remaining > 0` and `status='active'`, then order by:
1. `expiry_date IS NULL` last (non-expiring lots consumed after expiring lots)
2. `expiry_date ASC` (earliest expiry first)
3. `created_at ASC`
4. `id ASC`

## 5.2 Allocation algorithm (transactional)
Input: `itemId`, `requiredQty`, `businessId`, `referenceType`, `referenceId`

Pseudo:
1. Begin DB transaction.
2. Query candidate lots with FEFO ordering.
3. Loop through lots and consume min(`qty_remaining`, `qtyNeeded`).
4. Update each lot `qty_remaining`.
5. Mark lot `depleted` when remaining becomes 0.
6. Insert `lot_movements` row for each split.
7. Insert one aggregate `stock_movements` row (existing behavior) with `meta_json` allocation summary.
8. Return allocation list for storing in `invoice_items.lot_allocation_json`.
9. Commit.

## 5.3 Insufficient stock policy
Configurable policy (Phase 1 default recommended: strict for tracked items):
- If total available lot qty < required qty:
  - throw domain error `InsufficientLotStockException(itemId, required, available)`
  - block send/dispatch action

Fallback policy (optional setting): allow negative aggregate only when lot tracking is disabled for item.

---

## 6) Service/Repository Integration

## 6.1 New service
Create `LotAllocationService` in data/services:
- `createLotFromPurchaseBillItem(...)`
- `allocateFefo(...)`
- `reverseAllocation(referenceType, referenceId)`
- `getLotsForItem(...)`
- `getExpiringLots(...)`

## 6.2 InventoryService changes
Keep existing API stable where possible and add lot-aware paths:
- `addStock(...)`:
  - if lot info present, create/update `stock_lots` + `lot_movements`
  - always maintain aggregate `item_stock` + `stock_movements`
- `deductStock(...)`:
  - if lot tracking enabled for item, route through FEFO allocation
  - else current aggregate deduction behavior
- `reverseMovementsFor(...)`:
  - also reverse lot movements and restore `qty_remaining` by replaying inverse in reverse chronological order

## 6.3 Purchase Bill integration
On add/edit/remove in `purchase_bill_provider.dart` + repository:
- Add/Edit:
  - for each catalog item row, call inward lot creation
  - include lot fields from form (`lot_no`, `expiry_date`, `mfg_date`)
- Edit/Remove:
  - reverse lot movements for `reference_type='purchase_bill'` before re-apply

## 6.4 Invoice integration
On `markSent(...)` and edit flows in `invoice_provider.dart`:
- For each stock-tracked catalog item:
  - call FEFO allocation for required qty
  - persist allocation to `invoice_items.lot_allocation_json`
- On invoice edit/remove reversal:
  - use stored allocations where available
  - fallback to `lot_movements` by reference for robust reversal

## 6.5 Delivery Challan integration
Same as invoice, with `reference_type='challan'`.

---

## 7) UI/UX Integration

## 7.1 Purchase Bill form
Add optional fields per item row:
- Batch/Lot No
- Expiry Date
- MFG Date
- Unit Cost (if needed)

Behavior:
- If item is inventory-tracked and lot tracking enabled, show lot fields.
- Validate expiry >= bill date when provided.

## 7.2 Invoice / Challan form + detail
- No mandatory lot picker for Phase 1 (auto FEFO).
- In detail view, show lot allocation chip/list per item from `lot_allocation_json`.
- On insufficient lot stock, show actionable error with available qty.

## 7.3 Inventory screen
Add:
- Lots tab per item showing `lot_no`, expiry, remaining qty, status.
- Expiry warning badges (`<=30`, `<=15`, `<=7` days).

---

## 8) Validation Rules

- `qty_in > 0`, `qty_remaining >= 0`
- `expiry_date` nullable, but if set should parse valid ISO date
- For strict FEFO mode, outbound cannot exceed total lot-available qty
- Reversal idempotency: prevent double reverse by checking existing reversal marker/reference

---

## 9) Testing Plan (must-have)

## 9.1 Unit tests
- FEFO ordering with mixed expiry/null lots.
- Split allocation across multiple lots.
- Exact depletion status transitions.
- Reversal restores lot quantities correctly.
- Insufficient stock exception path.

## 9.2 Repository/service tests
- Purchase bill creates lots + movement rows + aggregate stock.
- Invoice send consumes lots and stores allocation JSON.
- Invoice edit reverse+reapply behavior.
- Challan conversion/invoice flows preserve ownership of deduction.

## 9.3 Widget/integration tests
- Purchase bill lot fields validation.
- Invoice send blocking message on insufficient lot stock.
- Inventory item lot list rendering and expiry indicators.

---

## 10) Rollout Plan

### Phase A (Schema + backend foundation)
- Add tables, migration, model classes, repository methods.
- No UI changes yet; behind feature flag `lotTrackingEnabled`.

### Phase B (Purchase inward lots)
- Add lot fields on purchase bill item form.
- Create lots on purchase bill save/edit.

### Phase C (Invoice/challan FEFO outward)
- Enable FEFO allocation on send/dispatch.
- Persist allocation snapshots.
- Add reversal hardening.

### Phase D (Visibility + expiry UX)
- Inventory lots tab and expiry indicators.
- Optional report for expiring lots.

---

## 11) Risks & Mitigations

- **Risk:** Reverse logic drift between aggregate and lot ledgers.  
  **Mitigation:** single transactional function updates both ledgers.

- **Risk:** Legacy stock with no lots causes first-send failures.  
  **Mitigation:** lazy `LEGACY-OPENING` lot bootstrap or controlled fallback mode.

- **Risk:** Performance on large lot sets.  
  **Mitigation:** FEFO indexes + bounded queries + transaction batching.

---

## 12) Recommended first code tasks

1. Add schema (v80) and migration wiring in database helper tables + upgrade path.  
2. Add models: `StockLot`, `LotMovement`.  
3. Implement `LotAllocationService.allocateFefo(...)` with unit tests.  
4. Integrate purchase bill inward lot creation.  
5. Integrate invoice/challan send-time FEFO deduction + reversal.  
6. Add minimal UI fields for lot input in purchase bill items.

---

## 13) Definition of Done

- New purchase bills can capture lots and expiry.
- Sending invoice/challan consumes lots by FEFO.
- Reversing/editing invoice/challan/purchase bill correctly restores lot balances.
- Aggregate stock and lot stock stay consistent after all tested flows.
- No regressions in existing inventory flows for non-lot items.