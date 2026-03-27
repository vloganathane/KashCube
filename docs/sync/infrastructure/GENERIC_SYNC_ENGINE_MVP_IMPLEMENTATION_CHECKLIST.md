# Generic Sync Engine MVP — Implementation Checklist

## Purpose
Build a generic web-companion sync engine so browser state becomes an exact mirror of phone data (subject to local-only safety exclusions), without hardcoded per-table sync lists.

Current baseline:
- DB version: `70`
- Existing sync foundation: `sync_outbox`, `sync_watermarks`, `trusted_peers`
- Current implementation uses hardcoded table arrays and provider invalidation lists.

Progress snapshot:
- Phase 0 scaffolding: in place
- Startup discovery logs: in place (phone + web)

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
- [x] Bump `dbVersion` from `69` to `70`.

## 2) `lib/data/services/database_helper.dart`
- [x] Add `if (oldVersion < 70)` migration block.
- [x] Execute the v70 SQL for `sync_table_state` + indexes.
- [x] Insert `schema_version` row for version `70`.
- [x] Keep migration idempotent (`IF NOT EXISTS` + guarded inserts).

## 3) `lib/data/services/database_helper_tables.dart`
- [x] Add `sync_table_state` creation SQL inside `_createSyncAndIdentityTables`.
- [x] Add both indexes for `sync_table_state`.

## 4) `lib/data/services/p2p/p2p_coordinator.dart`
- [x] Remove hardcoded `_webMirrorTables` usage — replaced with registry-driven `_webMirrorTables()`.
- [x] Read runtime sync plan from registry at startup and refresh on reconnect.
- [x] Replace `SyncScope` denylist — `_peerSyncTables()` uses `isP2pEligible`, `_webMirrorTables()` uses `isWebEligible`.
- [x] Replace per-table in-memory watermark map (`_webLastPushedAt`) with `SyncTableStateStore` reads/writes.
- [x] Use `GenericSyncQueryBuilder` for all outbound queries (deltaTs, deltaVersion, snapshot).
- [x] Preserve UTC normalization — centralized in `GenericSyncQueryBuilder`.
- [ ] Remove legacy `_queryWebDeltaRows` / `_queryGenericDeltaTsRows` / comparison infrastructure (cleanup after full rollout).

## 5) `lib/presentation/providers/web_sync_provider.dart`
- [x] Remove hardcoded `_pullTables` — replaced with registry-driven `isWebEligible` filter.
- [x] Table list pulled from `SyncTableRegistry.discoverSyncPlans` on AUTH_OK bootstrap.
- [x] Replace `_outboundLastSentAt` with `SyncTableStateStore` reads/writes.
- [x] Use `GenericSyncQueryBuilder` for outbound queries across all modes.
- [x] Keep LIMIT 200 batching unchanged for MVP.

## 6) `lib/data/services/web/web_browser_session.dart`
- [x] Replace whitelist-based pull logic with `plan.isWebEligible` validation.
- [x] Transmit discovered sync plan to browser as `SYNC_PLAN` message after AUTH_OK.
- [x] `_queryRows` handles all three modes via `GenericSyncQueryBuilder`.

## 7) `lib/presentation/providers/sync_auto_refresh_provider.dart`
- [x] Replace static switch-based invalidation with registry map.
- [x] Add fallback invalidation strategy for newly discovered tables (safe broad refresh).
- [x] Ensure future schema additions do not require code edits here.

## 8) `lib/data/services/p2p/p2p_merge_service.dart`
- [x] `delta_ts`: LWW — latest `updated_at`/`created_at` wins.
- [x] `delta_version`: highest integer `version` field wins.
- [x] `snapshot`: remote always overwrites local unconditionally.
- [x] Soft-delete and invoice state-machine rules apply before mode dispatch.

## 9) New file: `lib/data/services/sync/sync_table_registry.dart`
- [x] Discover table names via `sqlite_master`.
- [x] Cache table columns via `PRAGMA table_info`.
- [x] Apply localOnly/phoneOnly/webOnly scope policy (replaces flat denylist).
- [x] Generate `schema_fingerprint` per table.
- [x] `SyncScope` enum + `isP2pEligible` / `isWebEligible` helpers on `SyncTablePlan`.
- [x] Expose read API used by phone and browser sync code.

## 10) New file: `lib/data/services/sync/sync_table_state_store.dart`
- [x] Read/write `sync_table_state` rows.
- [x] Upsert state atomically.
- [x] Reset state if schema fingerprint changes.
- [x] Provide helper APIs for watermark/cursor updates.
- [x] Wired into coordinator (replaces `_webLastPushedAt`) and web provider (replaces `_outboundLastSentAt`).

## 11) New file: `lib/data/services/sync/generic_sync_query_builder.dart`
- [x] `buildOutboundQuery` — mode-specific SQL for deltaTs, deltaVersion, snapshot.
- [x] `utcExpr` — centralized `CASE WHEN … julianday` UTC normalization.
- [x] All values parameterized (no string interpolation for values).
- [x] Used by coordinator, web_sync_provider, and web_browser_session.

## 12) Tests
### `test/data/services/sync/sync_table_registry_test.dart`
- [x] Scope assignment tests (localOnly excluded, phoneOnly/webOnly/all assigned correctly).
- [x] Mode selection tests (deltaTs/deltaVersion/snapshot).
- [x] `isP2pEligible` / `isWebEligible` helper tests.

### `test/data/services/sync/generic_sync_query_builder_test.dart`
- [x] deltaTs query with/without `since`, `created_at`-only, `COALESCE` cases.
- [x] deltaVersion query.
- [x] snapshot query.

### `test/data/services/p2p/p2p_merge_service_test.dart`
- [x] Mode-specific conflict resolution (deltaTs LWW, deltaVersion highest-wins, snapshot always-overwrite).
- [x] Soft-delete rule applied regardless of mode.

### `test/data/services/p2p/p2p_coordinator_test.dart`
- [ ] Replace hardcoded-table assumptions with discovered-table plan (deferred — requires in-memory DB fixture).

---

## Rollout Plan (Low Risk)

## Phase 0 — Instrument only
- [x] Build registry and state-store, no behavior change.
- [x] Log discovered table plan once at startup.

## Phase 1 — Dual read comparison
- [x] Generic engine computes candidate rows in parallel with current engine. *(read-only compare mode)*
- [x] Compare counts and first/last keys in debug logs. *(phone + web outbound loops)*

## Phase 2 — Generic outbound behind feature flag
- [x] Enable phone→web generic path via local flag.
- [x] Keep legacy path available for immediate rollback.

## Phase 3 — Generic inbound + merge
- [x] Enable browser→phone generic path.
- [x] Keep fallback for legacy merge route.

## Phase 4 — Remove hardcoded lists
- [x] Delete static table arrays from coordinator/provider/session once parity confirmed.

---

## Acceptance Criteria
- [x] New DB table added (with standard sync columns) syncs without code changes.
- [x] No repeated push loops after watermark progression — watermarks persisted in `sync_table_state`.
- [x] Browser reconnect converges all eligible tables — snapshot/deltaVersion paths implemented.
- [x] Device-local internal tables never leave device — `localOnly` scope enforced.
- [x] `flutter analyze` clean + targeted sync tests pass.

---

## Open Decisions (Before Coding)
- [x] Final denylist confirmation — resolved via `SyncScope` (localOnly/phoneOnly/webOnly/all).
- [ ] Snapshot mode frequency for huge tables (event-driven only vs periodic) — currently event-driven via `SyncEventBus`.
- [x] `my_identity` excluded — security requirement, stays `localOnly`.

---

## Completed Commits
- `9fd02e0` — feat(sync): stabilize web companion sync and add generic engine MVP checklist
- `5fd783a` — feat(sync): add v70 generic sync discovery/state scaffolding
- `02bfe9e` — chore(sync): log discovered generic sync plans at startup
- `d9f67c2` — feat(sync): generic outbound behind feature flag (Phase 2)
- `e908185` — feat(sync): generic inbound merge path (Phase 3)
- `147c937` — feat(sync): remove hardcoded table lists (Phase 4)
- `06c9432` — fix(sync): expand denylist + auto-refresh fallback
- `4a59695` — fix(sync): support text primary-key tables (settings)
- `1e4dba8` — feat(sync): introduce SyncScope — split P2P vs Web Companion table eligibility
- `(current)` — feat(sync): GenericSyncQueryBuilder + SyncTableStateStore wired; snapshot/deltaVersion outbound; sync plan broadcast
