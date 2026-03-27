# KashCube Codebase Documentation (As-Built)

This folder documents the **actual implementation in code** (not roadmap intent).

## Scope

These documents are generated from current source files under `lib/` and describe:

- Architecture and runtime flow
- Database schema and table domains
- Riverpod state/provider structure
- UI/navigation structure
- Sync, identity, and multi-device plumbing

## Source Anchors

- `lib/main.dart`
- `lib/presentation/app_shell.dart`
- `lib/data/services/database_helper_tables.dart`
- `lib/domain/repositories/`
- `lib/data/repositories/`
- `lib/presentation/providers/`
- `lib/data/services/`
- `lib/presentation/screens/`

## Current Inventory (Code-Verified)

- Database tables: **56**
- Domain repository interfaces: **25**
- Data repository implementations: **25**
- Provider files: **50**
- Service files: **64**
- Screen files: **69**
- Data models: **48**

## Documents

### Phase 1 & 2 — Architecture, Database, State, Sync

1. `ARCHITECTURE_AS_BUILT.md` — Boot gate, layer map, AppShell navigation
2. `DATABASE_AS_BUILT.md` — All 56 SQLite tables grouped by domain, ER diagram
3. `STATE_AND_NAVIGATION_AS_BUILT.md` — 50 provider files, 69 screen navigation tree
4. `SYNC_AND_IDENTITY_AS_BUILT.md` — P2P LAN sync, web companion, sync engine topology

#### Architecture deep-dive pack (`architecture/`)

- `architecture/README.md` — entrypoint and reading guide
- `architecture/BOOT_AND_STARTUP_AS_BUILT.md` — startup sequence, gates, lifecycle, failure tolerance
- `architecture/APP_SHELL_AND_NAVIGATION_AS_BUILT.md` — tab shell internals, nested navigators, adaptive layout, overlays
- `architecture/STATE_AND_DATAFLOW_ARCHITECTURE_AS_BUILT.md` — provider/repository/service orchestration and sync invalidation model
- `architecture/RUNTIME_CROSS_CUTTING_AS_BUILT.md` — notifications, sync freshness, lifecycle reliability hooks

### Phase 3 — Service Deep Dives

5. `SMS_PIPELINE_AS_BUILT.md` — SMS parser (46 senders, 20+ regex patterns), confidence scoring, deduplication, auto-categorizer (9 expense + 5 income categories)
6. `PDF_PIPELINE_AS_BUILT.md` — PdfLayoutEngine (9 templates, 5 page sizes), invoice/challan/statement/report PDF services, cache manager
7. `GST_PIPELINE_AS_BUILT.md` — CGST/SGST/IGST calculator, GSTR-1 (T4/T5/T7/T9/T12/T13), GSTR-3B (Rule 88A ITC offset), e-Way Bill JSON export
8. `BACKUP_IDENTITY_AS_BUILT.md` — Plain SQLite backup, AES-256-GCM encrypted backup (PBKDF2, lockout), Ed25519 identity keypairs, FY date arithmetic
9. `INVOICE_NUMBERING_AS_BUILT.md` — Atomic SQLite cursor, FY prefix-change rollover, multi-device pending-number flow

## Reading Order

**New to the codebase:** 1 → 2 → 3 → 4  
**Understanding a specific feature:** jump directly to the Phase 3 doc for that pipeline

---

If implementation changes, update these docs in the same PR to keep docs and code aligned.
