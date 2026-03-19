# Generic Sync Engine MVP — Implementation Checklist

## Purpose
Build a generic web-companion sync engine so browser state becomes an exact mirror of phone data (subject to local-only safety exclusions), without hardcoded per-table sync lists.

Current baseline:
- DB version: `69`
- Existing sync foundation: `sync_outbox`, `sync_watermarks`, `trusted_peers`
- Current implementation uses hardcoded table arrays and provider invalidation lists.

---

## MVP Scope (Concrete)
- Discover syncable tables dynamically from SQLite schema.
- Compute per-table sync strategy automatically (`delta_ts`, `delta_version`, `snapshot`).
- Use one generic outbound query builder and one generic inbound merge path.
- Persist per-peer + per-table sync progress in a dedicated state table.
- Keep LAN-only privacy model unchanged.

### Out of scope (MVP)
- Cross-device conflict UX screens
- Historical/temporal merge tooling
- Compression/chunk retries beyond current batching behavior

---

## Table Policy (MVP)

### 1) Discovery
Use:
```sql
SELECT name
FROM sqlite_master
WHERE type='table'
  AND name NOT LIKE 'sqlite_%'
ORDER BY name;
```

### 2) Exclusion policy (hard denylist)
Do not sync these engine/device-local tables:
- `device_session`
- `device_recovery`
- `pairing_history`
- `trusted_peers`
- `sync_outbox`
- `sync_watermarks`
- `sync_table_state` (new engine table)

### 3) Mode selection policy
For each discovered table:
- `delta_ts` if table has `updated_at` or `created_at`
- else `delta_version` if table has `version`
- else `snapshot`

### 4) Key policy
- Primary key preference: `sync_id`
- Fallback: `id`
- If neither exists: treat table as `snapshot` only

### 5) Delete policy
- If `deleted_at` exists, include tombstones in delta mode.
- If no `deleted_at`, rely on snapshot reconciliation for removals.

---

## New Data Model

Create `sync_table_state` to store generic sync progress and schema fingerprint:
- `peer_identity_id` TEXT NOT NULL
- `table_name` TEXT NOT NULL
- `sync_mode` TEXT NOT NULL (`delta_ts|delta_version|snapshot`)
- `last_synced_at` TEXT
- `last_version` INTEGER
- `last_pk` TEXT
- `schema_fingerprint` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- PK: (`peer_identity_id`, `table_name`)

This table is engine metadata, not user/business data.

---

## Migration SQL (v70)

## SQL to add in upgrade path (`oldVersion < 70`)
```sql
CREATE TABLE IF NOT EXISTS sync_table_state (
  peer_identity_id   TEXT NOT NULL,
  table_name         TEXT NOT NULL,
  sync_mode          TEXT NOT NULL,
  last_synced_at     TEXT,
  last_version       INTEGER,
  last_pk            TEXT,
  schema_fingerprint TEXT NOT NULL,
  updated_at         TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (peer_identity_id, table_name)
);

CREATE INDEX IF NOT EXISTS idx_sync_table_state_table
  ON sync_table_state(table_name);

CREATE INDEX IF NOT EXISTS idx_sync_table_state_updated
  ON sync_table_state(updated_at);
```

## SQL to add in fresh-install table creation
Include the same `CREATE TABLE` + indexes inside the sync/identity table creation block so new installs at v70 have the table.

## schema_version insert (v70)
```sql
INSERT INTO schema_version(version, description, applied_at)
VALUES (70, 'Generic sync engine metadata table: sync_table_state', datetime('now'));
```

---

## Exact Task Breakdown Per File

## 1) `lib/core/constants/app_constants.dart`
- [ ] Bump `dbVersion` from `69` to `70`.

## 2) `lib/data/services/database_helper.dart`
- [ ] Add `if (oldVersion < 70)` migration block.
- [ ] Execute the v70 SQL for `sync_table_state` + indexes.
- [ ] Insert `schema_version` row for version `70`.
- [ ] Keep migration idempotent (`IF NOT EXISTS` + guarded inserts).

## 3) `lib/data/services/database_helper_tables.dart`
- [ ] Add `sync_table_state` creation SQL inside `_createSyncAndIdentityTables`.
- [ ] Add both indexes for `sync_table_state`.

## 4) `lib/data/services/p2p/p2p_coordinator.dart`
- [ ] Remove hardcoded `_webMirrorTables` usage.
- [ ] Read runtime sync plan from registry/service at startup and refresh on reconnect.
- [ ] Replace per-table watermark map with reads/writes to `sync_table_state`.
- [ ] Use generic mode-aware query builder (`delta_ts`/`delta_version`/`snapshot`).
- [ ] Preserve existing UTC normalization for timestamp comparisons.

## 5) `lib/presentation/providers/web_sync_provider.dart`
- [ ] Remove hardcoded `_pullTables` usage.
- [ ] Pull discovered table list from generic table registry over WS bootstrap.
- [ ] Replace `_outboundLastSentAt` map with `sync_table_state` metadata.
- [ ] Use same generic mode-aware outbound query builder as phone side.
- [ ] Keep batching behavior (limit/chunk size) unchanged for MVP.

## 6) `lib/data/services/web/web_browser_session.dart`
- [ ] Replace whitelist-based pull logic with policy-based validation.
- [ ] Expose/distribute discovered sync table plan to browser after AUTH.
- [ ] Route PULL/WRITE through generic planner and generic merge helpers.

## 7) `lib/presentation/providers/sync_auto_refresh_provider.dart`
- [ ] Replace static switch-based invalidation with registry map.
- [ ] Add fallback invalidation strategy for newly discovered tables (safe broad refresh).
- [ ] Ensure future schema additions do not require code edits here.

## 8) `lib/data/services/p2p/p2p_merge_service.dart`
- [ ] Add generic conflict resolver by sync mode:
  - `delta_ts`: latest timestamp wins
  - `delta_version`: highest version wins
  - `snapshot`: replace by key
- [ ] Keep current behavior for existing p0/p2p tables unchanged where equivalent.

## 9) New file: `lib/data/services/sync/sync_table_registry.dart`
- [ ] Discover table names via `sqlite_master`.
- [ ] Cache table columns via `PRAGMA table_info`.
- [ ] Apply denylist + mode/key policy.
- [ ] Generate `schema_fingerprint` per table.
- [ ] Expose read API used by phone and browser sync code.

## 10) New file: `lib/data/services/sync/sync_table_state_store.dart`
- [ ] Read/write `sync_table_state` rows.
- [ ] Upsert state atomically.
- [ ] Reset state if schema fingerprint changes.
- [ ] Provide helper APIs for watermark/cursor updates.

## 11) Optional new file: `lib/data/services/sync/generic_sync_query_builder.dart`
- [ ] Build mode-specific SQL for outbound/inbound selection.
- [ ] Centralize UTC normalization expression:
  `CASE WHEN col LIKE '%Z' THEN julianday(col) ELSE julianday(col, 'utc') END`
- [ ] Keep SQL parameterized only (no string interpolation for values).

## 12) Tests
### `test/data/services/sync/sync_table_registry_test.dart`
- [ ] Discovery/exclusion/mode selection tests.
- [ ] Schema-fingerprint change detection tests.

### `test/data/services/sync/sync_table_state_store_test.dart`
- [ ] Upsert/read/reset behaviors.

### `test/data/services/p2p/p2p_merge_service_test.dart`
- [ ] Add mode-specific conflict tests (`delta_ts`, `delta_version`, `snapshot`).

### `test/data/services/p2p/p2p_coordinator_test.dart`
- [ ] Replace hardcoded-table assumptions with discovered-table plan.

---

## Rollout Plan (Low Risk)

## Phase 0 — Instrument only
- [ ] Build registry and state-store, no behavior change.
- [ ] Log discovered table plan once at startup.

## Phase 1 — Dual read comparison
- [ ] Generic engine computes candidate rows in parallel with current engine.
- [ ] Compare counts and first/last keys in debug logs.

## Phase 2 — Generic outbound behind feature flag
- [ ] Enable phone→web generic path via local flag.
- [ ] Keep legacy path available for immediate rollback.

## Phase 3 — Generic inbound + merge
- [ ] Enable browser→phone generic path.
- [ ] Keep fallback for legacy merge route.

## Phase 4 — Remove hardcoded lists
- [ ] Delete static table arrays from coordinator/provider/session once parity confirmed.

---

## Acceptance Criteria
- [ ] New DB table added (with standard sync columns) syncs without code changes.
- [ ] No repeated push loops after watermark progression.
- [ ] Browser reconnect converges all eligible tables.
- [ ] Device-local internal tables never leave device.
- [ ] `flutter analyze` clean + targeted sync tests pass.

---

## Open Decisions (Before Coding)
- [ ] Final denylist confirmation (security-sensitive tables).
- [ ] Snapshot mode frequency for huge tables (event-driven only vs periodic).
- [ ] Whether to include `my_identity` in mirror (business requirement vs security).
