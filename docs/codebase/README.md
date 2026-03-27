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

1. `ARCHITECTURE_AS_BUILT.md`
2. `DATABASE_AS_BUILT.md`
3. `STATE_AND_NAVIGATION_AS_BUILT.md`
4. `SYNC_AND_IDENTITY_AS_BUILT.md`

## Reading Order

1) Architecture → 2) Database → 3) State & Navigation → 4) Sync & Identity

---

If implementation changes, update these docs in the same PR to keep docs and code aligned.
