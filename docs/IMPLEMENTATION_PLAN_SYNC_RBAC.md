# Implementation Plan: Sync Foundation → RBAC → Linked Devices → Dual-Primary
# Sprint-Level Coding Plan

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** Active  
**Depends on:** `ARCHITECTURE_DECISIONS.md`, `USER_PERMISSIONS_BRAINSTORM.md`, `LINKED_DEVICES_BRAINSTORM.md`, `DUAL_PRIMARY_IDENTITY_SPEC.md`

---

## Prerequisite Reading

Before starting any sprint, re-read the relevant sections of:
- `ARCHITECTURE_DECISIONS.md` — the definitive decisions for v58–v62
- `DUAL_PRIMARY_IDENTITY_SPEC.md` — the spec for v63–v66

Do not start a sprint without reading its referenced sections. Architecture decisions must not be re-litigated in code.

---

## Sprint 1 — v58: Phase 0 (Sync Foundation)
**Status: IN PROGRESS**  
**Estimate:** 3–5 days  
**File changes:** `app_constants.dart`, `database_helper.dart` only  
**No model/provider changes:** Phase 0 is pure DB infrastructure  
**Spec:** `ARCHITECTURE_DECISIONS.md` → Decision 1 + Phase 0 Implementation Sequence

### Tasks

#### S1.1 — Bump DB version
- **File:** `lib/core/constants/app_constants.dart`
- Change `dbVersion = 57` → `dbVersion = 58`

#### S1.2 — `_onUpgrade` v58 block
Add `if (oldVersion < 58)` block to `DatabaseHelper._onUpgrade`. This block must:

**Step A — ALTER existing tables (add sync columns):**

| Table | Add columns |
|-------|-------------|
| `transactions` | `sync_id TEXT`, `version INTEGER DEFAULT 0`, `created_by_device_id TEXT` |
| `credits` | same |
| `credit_payments` | same + `updated_at TEXT`, `deleted_at TEXT` |
| `loans` | same |
| `parties` | same |
| `accounts` | same |
| `categories` | same + `updated_at TEXT`, `deleted_at TEXT` |
| `budgets` | same + `updated_at TEXT` (no deleted_at — budgets are year+month scoped) |
| `item_catalog` | same + `deleted_at TEXT` (already has updated_at) |
| `scheduled_payments` | same |
| `businesses` | same + `deleted_at TEXT` (already has updated_at) |
| `invoices` | same + `deleted_at TEXT` (already has updated_at) |
| `purchase_bills` | same + `deleted_at TEXT` (already has updated_at) |

**Step B — Backfill existing rows:**
```sql
UPDATE <table> SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL
```
For all 13 tables above.

**Step C — Create unique indexes on sync_id:**
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_<table>_sync_id ON <table>(sync_id)
```

**Step D — Create UPDATE triggers** (one per syncable table):
```sql
CREATE TRIGGER IF NOT EXISTS trg_<table>_sync_updated
  AFTER UPDATE ON <table>
  FOR EACH ROW
  WHEN NEW.updated_at = OLD.updated_at OR OLD.updated_at IS NULL
  BEGIN
    UPDATE <table> SET
      updated_at = datetime('now'),
      version    = COALESCE(OLD.version, 0) + 1
    WHERE id = OLD.id;
  END
```
The `WHEN` clause prevents infinite recursion (only fires when `updated_at` wasn't explicitly set by the calling code).

**Step E — CREATE 9 new tables:**

1. `app_users` — multi-user identities
2. `user_permissions` — RBAC permission rows
3. `subscription` — local subscription state (1 row)
4. `plan_features` — plan × feature matrix
5. `linked_devices` — registry of paired secondary devices (primary only)
6. `device_recovery` — recovery key hash storage (primary only)
7. `pairing_history` — completed pairing audit log
8. `sync_outbox` — outbound event queue (primary only)
9. `device_session` — current session credential (secondary only)

Full SQL for all 9 tables is in `ARCHITECTURE_DECISIONS.md` → Decision 6.

**Step F — Seed plan_features:**
Insert all plan × feature rows (free/pro/team × linked_devices/app_users/cashier_mode/businesses/report_history_months/lan_sync).

**Step G — Seed subscription:**
```sql
INSERT OR IGNORE INTO subscription (id, plan) VALUES (1, 'free')
```

**Step H — Insert schema_version record:**
```sql
version: 58, description: 'Phase 0: sync_id + version + triggers on all P0 tables; 9 new auth/sync tables'
```

#### S1.3 — Update `_onCreate`
Fresh-install path must match the end state of all migrations:
- Add sync columns inline to each CREATE TABLE definition
- Add the 9 new CREATE TABLE calls after existing tables
- Add all triggers after table creation
- Add seed calls for plan_features + subscription
- Update `schema_version` seed insert from `version: 52` → `version: 58`

#### S1.4 — Smoke test
```bash
flutter run -d emulator-5554 --hot
# Should upgrade from v57 to v58 without crash
# ADB log should show: "Upgrading database from v57 to v58..."
```

---

## Sprint 2 — v59: Phase U1 (Cashier Mode)
**Status: NOT STARTED**  
**Estimate:** 3–4 days  
**DB changes:** Settings keys only — no schema migration  
**Spec:** `USER_PERMISSIONS_BRAINSTORM.md` → Option C + Section 11 Phase U1

### Tasks

#### S2.1 — Settings keys
Add to `SettingsRepository`:
```dart
static const String cashierModeEnabled    = 'cashier_mode_enabled';
static const String cashierModePinHash    = 'cashier_mode_pin_hash';
static const String cashierModeBusinessId = 'cashier_mode_business_id';
```

#### S2.2 — `CashierModeSetupScreen`
- Location: `lib/presentation/screens/settings/cashier_mode_setup_screen.dart`
- Owner enables cashier mode, creates 4-digit cashier PIN, selects which business
- PIN stored as Argon2id hash (same as owner PIN — use existing `PinHashService`)
- Route: Settings → Security → Cashier Mode

#### S2.3 — `CashierModeBannerWidget`
- Location: `lib/presentation/widgets/cashier_mode_banner.dart`
- Shown on home screen when `cashier_mode_enabled = true`
- Yellow banner: "Cashier Mode — tap to exit"
- Tapping shows `ExitCashierModeSheet` (requires owner PIN)

#### S2.4 — `ExitCashierModeSheet`
- 4-digit PIN entry that checks against owner's `pin_hash`
- On success: set `cashier_mode_enabled = false`

#### S2.5 — Provider filter
- `activeModeProvider` (StateProvider<String>) — 'owner' | 'cashier'
- All screen providers read `activeModeProvider` and filter/gate accordingly
- Cashier mode: hide Reports, Settings, Loans/Credits; show only Transactions + Invoices for the selected business

---

## Sprint 3 — v60: Phase U2 (Full RBAC)
**Status: NOT STARTED**  
**Estimate:** 5–7 days  
**DB changes:** `app_users` + `user_permissions` tables already created in v58  
**Spec:** `USER_PERMISSIONS_BRAINSTORM.md` → Option B + Section 8–11 Phase U2

### Tasks

#### S3.1 — Models
- `AppUser` model (`lib/data/models/app_user.dart`)
- `UserPermission` model
- `Permission` value object (canView, canCreate, canEdit, canDelete)
- `RolePreset` enum (owner/manager/cashier/auditor/custom) + preset definitions

#### S3.2 — Repositories
- `AppUserRepository` (abstract in domain/, implementation in data/)
- `UserPermissionRepository`

#### S3.3 — Providers
```dart
final activeAppUserProvider = StateProvider<AppUser?>((ref) => null);
// null = owner (full access)

final permissionProvider = Provider.family<Permission, ({String module, int? businessId})>(...)
```

#### S3.4 — Screens
- `UserSelectionScreen` — launch screen with user avatars
- `StaffPinScreen` — 4-digit PIN entry for app users
- `ManageUsersScreen` (Settings → Team)
- `AddEditUserSheet` — name, role, PIN, business assignment
- `UserPermissionsScreen` — per-module CRUD toggles
- Integration in `StaffDetailScreen`: "Grant App Access" section

#### S3.5 — Enforcement
Apply permission checks to:
- Bottom nav visibility (Layer 1 — UI)
- All existing Riverpod providers (Layer 2 — data access)
- All write actions in providers/use cases (Layer 3 — mutation guards)

---

## Sprint 4 — v61: Phase L1 (Owner Mirror — First LAN Sync)
**Status: NOT STARTED**  
**Estimate:** 10–14 days (largest sprint)  
**DB changes:** None (linked_devices + device_session already created in v58)  
**New packages:** `nsd` (mDNS service discovery), `cryptography: ^2.7.0`  
**Spec:** `LINKED_DEVICES_BRAINSTORM.md` + `ARCHITECTURE_DECISIONS.md` → Decision 3 + Decision 6

### Tasks

#### S4.1 — IdentityService
- `lib/data/services/identity_service.dart`
- On first run: generate Ed25519 keypair via `cryptography` package
- Store private key in `flutter_secure_storage` (key: `device_signing_private_key`)
- Store public key in `settings` table (key: `device_public_key`)
- Generate `device_id` UUID and store in settings
- Expose `sign(Uint8List data)` and `devicePublicKey` getter

#### S4.2 — TokenService
- `lib/data/services/token_service.dart`
- `issueToken(LinkedDevice device)` → signs permission payload with Ed25519
- `verifyToken(String tokenJson, String signature, String publicKeyB64)` → bool
- `parseToken(String tokenJson)` → `DeviceSessionToken` model

#### S4.3 — LAN Discovery (`nsd` package)
- `lib/data/services/lan_discovery_service.dart`
- Primary: register mDNS service `_kashcube._tcp`
- Secondary: browse for `_kashcube._tcp` on same Wi-Fi
- Resolve: extract IP + port from discovered service

#### S4.4 — SyncServer (primary)
- `lib/data/services/sync_server.dart`
- Listens on `dart:io` ServerSocket (random port)
- Accepts connections from secondaries
- Handles: pairing handshake, delta requests, delta uploads from secondary

#### S4.5 — SyncClient (secondary)
- `lib/data/services/sync_client.dart`
- Discovers primary via mDNS
- Connects to SyncServer
- Sends delta request (device_id + last_sync_timestamp)
- Applies received rows to local DB

#### S4.6 — Delta serialization
- `DeltaRow` model: table + sync_id + version + updated_at + operation + payload
- JSON serialization / deserialization
- Apply delta: for each row, if `incoming.version > local.version` → upsert

#### S4.7 — Screens (primary)
- `LinkedDevicesScreen` (Settings → Linked Devices)
- `LinkDeviceScreen` — QR code generator, shows device permission preset selector
- `DeviceDetailScreen` — last sync time, "Revoke" button

#### S4.8 — Screens (secondary)
- `LinkDeviceOnboardingScreen` — QR scanner, first-run only
- `GraceExpiryBannerWidget` — shown when offline > 7 days

#### S4.9 — Owner Mirror validation
- Full bidirectional sync for owner mirror (same permissions on both sides)
- Conflict resolution: `version` counter wins; `updated_at` as tiebreaker
- Smoke test: edit a transaction on device A → sync → see it on device B

---

## Sprint 5 — v62: Phase L2 (Staff Terminal — Permission-Scoped Sync)
**Status: NOT STARTED**  
**Estimate:** 5–7 days  
**Pre-condition:** Sprint 4 complete and stable  
**Spec:** `LINKED_DEVICES_BRAINSTORM.md` → Section 6 + Section 7

### Tasks

#### S5.1 — Permission-scoped delta on primary
- `SyncServer.buildDelta()`: filter rows by `device.business_scope` and `device.permission_scope`
- Never include `business_id IS NULL` rows for non-owner-mirror devices
- Never include rows for businesses outside `business_scope`

#### S5.2 — Token verification on secondary
- `DeviceSessionService` — verifies Ed25519 token on every app start
- Reads `device_session` table → validates signature → loads permissions to Riverpod
- `sessionPermissionProvider` replaces `permissionProvider` on secondary devices 

#### S5.3 — Grace period enforcement
- `GraceCheckService` — runs on app foreground (not on every frame)
- Computes days since `device_session.last_sync_at`
- After 7 days: sets `is_read_only_forced = 1` on `device_session`
- `ReadOnlyModeBannerWidget` — shown when `is_read_only_forced = 1`

#### S5.4 — Revocation
- Primary: "Revoke" → sets `linked_devices.revoked_at`, queues `sync_outbox` event
- Secondary: on sync, receives revocation → wipes session + business-scoped data

#### S5.5 — Staff terminal UX
- Secondary app bar shows: "🏪 [Business Name] — Staff Mode"
- All personal-context features hidden (no reports, no personal transactions)

---

## Sprint 6 — v63: Phase D1 (My Identity)
**Status: NOT STARTED**  
**Estimate:** 3–4 days  
**Pre-condition:** Sprint 5 complete  
**Spec:** `DUAL_PRIMARY_IDENTITY_SPEC.md` → Section 9 Phase D1

### Tasks

#### S6.1 — DB migration v63
- `CREATE TABLE my_identity` (1-row identity table)
- `ALTER TABLE linked_devices ADD COLUMN secondary_identity_id TEXT`
- `ALTER TABLE app_users ADD COLUMN identity_id TEXT`
- `DROP TABLE device_session` (after migrating data to `linked_business_sessions`)
- `CREATE TABLE linked_business_sessions` (replaces `device_session`)
- Migrate existing `device_session` row to `linked_business_sessions`

#### S6.2 — `IdentityService` v2
- On upgrade: generate Ed25519 identity keypair (separate from device signing key)
- Store private key in `flutter_secure_storage` (key: `identity_private_key`)
- Generate `identity_id` UUID → store in `my_identity`
- `identityPublicKey` getter
- `identityQrPayload()` → JSON for QR display

#### S6.3 — `IdentityRepository`
- `getMyIdentity()` → `MyIdentity`
- `updateDisplayName(String name)`

#### S6.4 — `identityProvider`
- `FutureProvider<MyIdentity>` — always returns the 1 row
- Used in ProfileScreen, pairing flow

#### S6.5 — `IdentitySetupScreen`
- Shown ONLY on fresh install (first run with `my_identity` table empty)
- "What's your name?" → creates `my_identity` + generates keypair
- Not shown to existing users (identity generated silently in migration)

#### S6.6 — `ProfileScreen`
- Settings → Profile
- Shows: display name, identity QR, public key fingerprint (last 8 chars)
- "Show My QR" button for pairing as secondary

#### S6.7 — Backup v2
- `BackupService.exportBackup()`: add `identity` section to JSON
- `BackupService.importBackup()`: restore `my_identity` + identity private key
- Old backups (no identity section): generate fresh identity on restore

---

## Sprint 7 — v64: Phase D2 (Context Layer)
**Status: NOT STARTED**  
**Estimate:** 7–10 days (touches all repositories)  
**Spec:** `DUAL_PRIMARY_IDENTITY_SPEC.md` → Section 9 Phase D2

### Tasks

#### S7.1 — DB migration v64
- `ALTER TABLE <all 13 syncable tables> ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE`
- All existing rows: `context_id` = NULL (personal context — backward compatible)
- No backfill needed (NULL is correct default for personal context)

#### S7.2 — `activeContextProvider`
```dart
final activeContextProvider = StateProvider<int?>((ref) => null);
// null = personal context; N = linked_business_sessions.id
```

#### S7.3 — All repository methods: add `contextId` parameter
```dart
// Signature change for all read methods:
Future<List<Transaction>> getAll({int? businessId, int? contextId = _kPersonal});
// _kPersonal is the sentinel meaning "contextId IS NULL"
```

Repositories to update:
- `TransactionRepository`
- `CreditRepository`
- `InvoiceRepository`
- `PartyRepository`
- `AccountRepository`
- `ItemCatalogRepository`
- `ScheduledPaymentRepository`
- `PurchaseBillRepository`
- `BusinessRepository`

#### S7.4 — All screens pass `activeContextProvider` to their providers

#### S7.5 — `ContextSwitcherWidget`
- App bar dropdown showing personal + active sessions
- `LinkedSessionsListProvider` — list of non-revoked `linked_business_sessions`
- Tap item → sets `activeContextProvider`

#### S7.6 — `ContextBannerWidget`
- Subtle persistent banner when in linked session context
- "🏪 [Business Name]" with sync status dot

#### S7.7 — Empty state for linked session contexts
- "Waiting for first sync with [Business Name]"
- Shown when context has no data yet

---

## Sprint 8 — v65: Phase D3 (Linked Sessions Upgrade)
**Status: NOT STARTED**  
**Estimate:** 5–7 days  
**Spec:** `DUAL_PRIMARY_IDENTITY_SPEC.md` → Section 9 Phase D3

### Tasks

#### S8.1 — Token schema extension
- `TokenService.issueToken()` now includes `plan_features` from `plan_features` table in payload
- `linked_business_sessions.token_payload` stores updated schema
- `PlanGate` reads plan_features from local table (personal) OR from session token (linked context)

#### S8.2 — `PlanGate` context-aware
```dart
class PlanGate {
  bool canDo(String feature) => /* personal context: local plan */;
  bool canDoInSession(String feature, int sessionId) => /* from session token */;
}
```

#### S8.3 — Identity-first pairing on secondary
- `ProfileScreen` shows identity QR
- When Suresh scans Ravi's QR: primary receives `identity_id` + `identity_public_key` + `display_name`
- `linked_devices.secondary_identity_id` populated during pairing

#### S8.4 — `LinkedDevicesScreen` shows identity display names
- List item: "Ravi Kumar" (not "Galaxy S23")

#### S8.5 — Multiple session management
- `LinkedSessionsScreen` (Settings → Linked Sessions)
- Shows all active sessions with business name + last sync
- "+ Link to a Business" button
- `SessionDetailScreen` — info, permissions, "Unlink" button

---

## Sprint 9 — v66: Phase D4 (Payroll Loop)
**Status: NOT STARTED**  
**Estimate:** 4–5 days  
**Spec:** `DUAL_PRIMARY_IDENTITY_SPEC.md` → Section 9 Phase D4 + Section 6.1

### Tasks

#### S9.1 — DB migration v66
```sql
CREATE TABLE payroll_notifications (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id    TEXT NOT NULL UNIQUE,
  source_identity_id TEXT NOT NULL,
  business_name      TEXT NOT NULL,
  amount             REAL NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'INR',
  reference_label    TEXT,
  paid_on            TEXT NOT NULL,
  received_at        TEXT DEFAULT (datetime('now')),
  status             TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'added' | 'dismissed'
  created_transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL
)
```

#### S9.2 — `SyncServer` new event type
- Add `payrollNotification` to `SyncEventType` enum 
- Filter by `target_identity_id` when delivering from `sync_outbox`
- Only the targeted person receives their notification

#### S9.3 — Primary UX: payroll opt-in
- `StaffDetailScreen` → "Pay Salary" flow: add "Notify [Name]?" toggle (default OFF)
- On confirm with toggle ON: queue `sync_outbox` event

#### S9.4 — Secondary UX
- `PayrollNotificationsBanner` widget on home screen
- `PayrollNotificationsSheet`: list of pending with [Add Income] / [Dismiss]
- On [Add Income]: creates `Transaction(context_id = NULL, type = income, category = 'Salary')`

---

## Summary Timeline

| Sprint | Version | Feature | Min days | Max days |
|--------|---------|---------|----------|----------|
| 1 | v58 | Phase 0: Sync Foundation | 3 | 5 |
| 2 | v59 | Phase U1: Cashier Mode | 3 | 4 |
| 3 | v60 | Phase U2: Full RBAC | 5 | 7 |
| 4 | v61 | Phase L1: Owner Mirror | 10 | 14 |
| 5 | v62 | Phase L2: Staff Terminal | 5 | 7 |
| 6 | v63 | Phase D1: My Identity | 3 | 4 |
| 7 | v64 | Phase D2: Context Layer | 7 | 10 |
| 8 | v65 | Phase D3: Sessions Upgrade | 5 | 7 |
| 9 | v66 | Phase D4: Payroll Loop | 4 | 5 |
| **Total** | | | **45 days** | **63 days** |

Sprint 4 (Owner Mirror) is the longest because it introduces the entire LAN sync infrastructure from scratch. Every other sprint builds on it.

---

## Dependency Graph

```
v58 (Phase 0)
  └── v59 (Cashier Mode)          ← can start as soon as v58 is stable
        └── v60 (Full RBAC)
  └── v61 (Owner Mirror)           ← requires v58 sync columns
        └── v62 (Staff Terminal)
              └── v63 (Identity)
                    └── v64 (Context Layer)
                          └── v65 (Sessions Upgrade)
                                └── v66 (Payroll Loop)
```

v59 (Cashier Mode) and v61 (Owner Mirror) can be started in parallel after v58. All other sprints are sequential.

---

## Definition of Done (per sprint)

- [ ] `flutter analyze` → 0 errors, 0 warnings
- [ ] `flutter test` → all existing tests pass
- [ ] Manual smoke test on emulator-5554
- [ ] DB migration tested (upgrade from previous version without crash)
- [ ] `git commit` with version tag (e.g. `feat(db): v58 Phase 0 — sync foundation`)

---

*Last updated: 12 March 2026*  
*Related: ARCHITECTURE_DECISIONS.md, DUAL_PRIMARY_IDENTITY_SPEC.md, USER_PERMISSIONS_BRAINSTORM.md, LINKED_DEVICES_BRAINSTORM.md*
