# KashCube: Final Architecture Decisions
# Sync + Permissions + Device Trust

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** DECIDED — supersedes RFC sections in PRIVATE_SYNC, USER_PERMISSIONS, LINKED_DEVICES  
**Author:** Engineering

---

## THE MOST IMPORTANT RULE TO CHECK BEFORE READING

The incoming recommendation set was excellent — but borrowed several patterns from cloud-based
systems (1Password server, Stripe webhooks, push notifications via FCM, "server verifies hash").

**KashCube has no server. Not now. Not ever (by choice).**

Every decision in this doc is adapted for **100% local, offline-first, no-KashCube-server**.
Where the cloud model says "server" → read "primary device".
Where it says "push notification" → read "QR or PIN over LAN".
Where it says "Stripe" → read "Google Play Billing (one purchase-time network call to Play, nothing ongoing)".

---

## Decision 1: Phase 0 — sync_id on All Tables

**Status: START IMMEDIATELY (DB v58 blocker)**

### What to add to every syncable table

```sql
-- These four columns are added to ALL core tables:
sync_id      TEXT UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16))))
updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
deleted_at   TEXT                         -- NULL = alive; non-NULL = soft-deleted
version      INTEGER NOT NULL DEFAULT 0  -- monotonic counter; incremented on every UPDATE
```

### What NOT to do

**Do NOT replace `id INTEGER PRIMARY KEY AUTOINCREMENT` with `sync_id`.**

Reason: every FK in the existing schema (and all SQLite query plans) depend on the integer `id`. Changing it is a full schema rewrite. `sync_id` is a *secondary unique key* used exclusively for cross-device identity. Local joins still use the fast integer `id`.

```sql
-- WRONG:
CREATE TABLE transactions (sync_id UUID PRIMARY KEY, ...);

-- RIGHT:
CREATE TABLE transactions (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,  -- local fast FK target (unchanged)
  sync_id  TEXT UNIQUE NOT NULL DEFAULT (...), -- cross-device identity
  ...
);
```

### `device_id` per row — YES, include it

```sql
created_by_device_id TEXT  -- which device CREATE-d this row (for conflict attribution)
```

This is 16 bytes per row. On a year of daily transactions (~1,500 rows), that's ~24 KB. Worth it for deterministic conflict attribution. When a secondary creates a record while offline, the primary knows the row came from that device — not from a clock comparison.

### Version counter (Lamport-style) — YES

`version` is incremented on every UPDATE. Conflict resolution rule:
- `incoming.version > local.version` → accept (remote is newer)
- `incoming.version == local.version && incoming.updated_at > local.updated_at` → accept
- `incoming.version < local.version` → reject (stale; log for debug)

This is far more reliable than pure wall-clock timestamps because **Android clocks are user-settable**. Version counters are monotonic regardless of clock drift.

### SQLite triggers are mandatory — DEFAULT doesn't work for updates

`DEFAULT (datetime('now'))` fires **only on INSERT**, not UPDATE. You need explicit triggers:

```sql
-- One trigger per syncable table in _onCreate (and add in v58 migration):
CREATE TRIGGER trg_transactions_updated_at
  AFTER UPDATE ON transactions
  FOR EACH ROW
  BEGIN
    UPDATE transactions
    SET updated_at = datetime('now'),
        version    = OLD.version + 1
    WHERE id = NEW.id;
  END;
```

This is ~12–15 trigger definitions. The alternative (updating `updated_at` in Dart before every `db.update()` call) is error-prone. Triggers are the right answer.

### Tables that need Phase 0 treatment

| Table | Has deleted_at? | Needs sync_id | Priority |
|-------|----------------|---------------|----------|
| `transactions` | ✅ | ✅ | P0 |
| `invoices` | ✅ | ✅ | P0 |
| `credits` | ✅ | ✅ | P0 |
| `credit_payments` | ? | ✅ | P0 |
| `parties` | ✅ | ✅ | P0 |
| `accounts` | ? | ✅ | P0 |
| `categories` | ? | ✅ | P1 |
| `budgets` | ? | ✅ | P1 |
| `item_catalog` | ? | ✅ | P0 |
| `scheduled_payments` | ? | ✅ | P1 |
| `purchase_bills` | ? | ✅ | P0 |
| `businesses` | ? | ✅ | P0 |
| `loans` | ✅ | ✅ | P1 |
| `linked_devices` | ✅ (revoked_at) | ✅ | P0 |
| `app_users` | is_active flag | ✅ | P0 |
| `settings` | — | ❌ Never sync | — |

**Cost if deferred past v58:** Every additional table (staff payslips, attendance, etc.) added before Phase 0 means one more ALTER + trigger to write. This is already 7 versions overdue. Freeze one sprint.

---

## Decision 2: Subscription Gating

**Status: plan_features table YES. Stripe NO.**

### The Stripe Problem

The incoming recommendation included `stripe_customer_id` and `stripe_subscription_id`. These require:
- A KashCube backend server to handle Stripe webhooks
- HTTP calls from the app to check subscription status
- A "Stripe Customer" concept that implies KashCube operates a billing platform

**None of this is compatible with our privacy architecture.** KashCube does not operate servers.

### Correct Local Approach: Google Play In-App Purchase

```
User taps "Upgrade to Pro"
    │
    ├── Google Play Billing SDK (in_app_purchase Flutter package)
    │   → one-time call to Google Play (not KashCube servers)
    │   → Play returns a purchase_token (opaque blob)
    │
    └── KashCube stores purchase_token locally
         → verified on-device using Play's public signature
         → no ongoing KashCube server calls ever
```

The `in_app_purchase` package makes calls to **Google's** servers, not ours. This is the same privacy boundary as `local_auth` calling Android biometric APIs — an OS service, not our infrastructure.

### Schema

```sql
CREATE TABLE subscription (
  id             INTEGER PRIMARY KEY,     -- always exactly ONE row
  plan           TEXT    NOT NULL DEFAULT 'free',
                                          -- 'free' | 'pro' | 'team'
  source         TEXT    DEFAULT 'none',  -- 'play_store' | 'promo_code' | 'trial' | 'none'
  purchase_token TEXT,                    -- Google Play opaque token; NULL for free
  plan_started_at TEXT,
  plan_expires_at TEXT,                   -- NULL = lifetime; non-NULL = subscription renewal
  is_trial       INTEGER NOT NULL DEFAULT 0,
  trial_ends_at  TEXT
);

CREATE TABLE plan_features (
  plan         TEXT    NOT NULL,
  feature      TEXT    NOT NULL,
  enabled      INTEGER NOT NULL DEFAULT 1,
  limit_value  INTEGER,                   -- NULL = unlimited
  PRIMARY KEY (plan, feature)
);
```

### Seed data (inserted in _seedCategories equivalent at app startup / migration)

```sql
-- Devices
INSERT INTO plan_features VALUES ('free',  'linked_devices',   1, 0);   -- 0 = no linking
INSERT INTO plan_features VALUES ('pro',   'linked_devices',   1, 2);   -- up to 2
INSERT INTO plan_features VALUES ('team',  'linked_devices',   1, 10);

-- Multi-user
INSERT INTO plan_features VALUES ('free',  'app_users',        1, 0);
INSERT INTO plan_features VALUES ('pro',   'app_users',        1, 3);
INSERT INTO plan_features VALUES ('team',  'app_users',        1, 20);

-- Cashier mode (simplified single-mode, no named users)
INSERT INTO plan_features VALUES ('free',  'cashier_mode',     1, 1);   -- free: 1 kiosk mode
INSERT INTO plan_features VALUES ('pro',   'cashier_mode',     1, 1);
INSERT INTO plan_features VALUES ('team',  'cashier_mode',     1, 1);

-- Businesses
INSERT INTO plan_features VALUES ('free',  'businesses',       1, 1);
INSERT INTO plan_features VALUES ('pro',   'businesses',       1, 3);
INSERT INTO plan_features VALUES ('team',  'businesses',       1, 10);

-- Reports history depth (months)
INSERT INTO plan_features VALUES ('free',  'report_history_months', 1, 3);
INSERT INTO plan_features VALUES ('pro',   'report_history_months', 1, 24);
INSERT INTO plan_features VALUES ('team',  'report_history_months', 1, 0); -- unlimited

-- Sync
INSERT INTO plan_features VALUES ('free',  'lan_sync',         1, 0);   -- BYOC backup only
INSERT INTO plan_features VALUES ('pro',   'lan_sync',         1, 1);
INSERT INTO plan_features VALUES ('team',  'lan_sync',         1, 1);
```

### Feature gate check pattern in Dart

```dart
// SubscriptionRepository (synchronous, cached in memory)
class PlanGate {
  static final instance = PlanGate._();
  PlanGate._();

  bool canDo(String feature) => _features[feature]?.enabled == true;
  int   limit(String feature) => _features[feature]?.limitValue ?? 0;

  Future<void> reload(Database db) async {
    final plan = await db.query('subscription', limit: 1);
    final currentPlan = plan.isEmpty ? 'free' : plan.first['plan'] as String;
    final rows = await db.query('plan_features', where: 'plan = ?', whereArgs: [currentPlan]);
    _features = { for (final r in rows) r['feature'] as String: _Feature.fromRow(r) };
  }

  Map<String, _Feature> _features = {};
}

// Usage anywhere:
if (!PlanGate.instance.canDo('linked_devices')) {
  showUpgradeSheet(context, feature: 'linked_devices');
  return;
}
if (currentLinkedDevices >= PlanGate.instance.limit('linked_devices')) {
  showUpgradeSheet(context, feature: 'linked_devices', reason: 'limit_reached');
  return;
}
```

---

## Decision 3: Token Signing — Ed25519

**Status: Ed25519 CHOSEN, with Android hardware constraint documented**

### Why Ed25519 over ECDSA P-256

| Property | Ed25519 | ECDSA P-256 |
|----------|---------|-------------|
| Signature size | 64 bytes | ~71 bytes (DER) |
| Key size | 32 bytes private | 32 bytes private |
| Signing speed | ~70k/s | ~15k/s |
| Verification speed | ~25k/s | ~8k/s |
| Deterministic | ✅ Yes | ❌ No (requires CSPRNG per sign) |
| Android Keystore (HW) | ❌ < API 33 | ✅ All versions |
| Dart package | `cryptography` | `pointycastle` / `cryptography` |

### The Android Keystore Reality

Android hardware-backed key storage (Keystore with StrongBox/TEE) supports ECDSA on all Android 6+ devices, but **Ed25519 hardware backing requires Android 13+ (API 33)**. India's device ecosystem still has significant Android 10–12 population.

**Decision: Use Ed25519 + `flutter_secure_storage` for key storage.**

Rationale:
- Ed25519 keys stored in `FlutterSecureStorage` are encrypted at rest using Android AES-256-GCM (hardware-backed AES key, even if the Ed25519 key itself isn't directly in the Keystore)
- This is the same protection level as all other secrets in KashCube (PIN hash, backup key)
- Not using hardware-backed key execution is a known, acceptable tradeoff at this scale
- When compiling against minSdk 33 in the future (say, 2027), hardware backing becomes free

### Key lifecycle

```
Primary device, first run:
  1. Generate Ed25519 keypair via `cryptography` package (Dart `Ed25519().newKeyPair()`)
  2. private_key → stored in FlutterSecureStorage key 'primary_signing_key'
  3. public_key  → stored in settings table as 'primary_public_key' (plaintext; public is public)

When issuing a device session token:
  1. Serialize token payload as JSON
  2. Sign with Ed25519 private key → 64-byte signature
  3. Transmit: {payload, signature} → secondary stores both

Secondary, on every app start:
  1. Load cached primary_public_key from device_session table
  2. Verify signature of stored token
  3. If valid → load permission_scope from token and start app
  4. If invalid → show "Session invalid — contact owner"
```

### Flutter package

```yaml
dependencies:
  cryptography: ^2.7.0   # pure Dart, no network, Ed25519 + AES-256-GCM + ECDH
  flutter_secure_storage: ^9.0.0  # already in pubspec; used for key storage
```

`cryptography` package is pure Dart — no platform channels, no network, 100% local. ✅

---

## Decision 4: business_id = NULL Convention

**Status: KEEP AS IS — NULL means personal**

This convention is already load-bearing across 10+ tables. No change.

```sql
-- Personal data (no business context):
WHERE business_id IS NULL AND <other filters>

-- Business-scoped data:
WHERE business_id = ?
```

The `is_personal` flag alternative creates redundancy and potential inconsistency.
One exception: enforce it at the Dart repository layer — every `insert()` call must explicitly
pass `businessId: null` for personal or `businessId: activeBusinessId` for business. No implicit default.

---

## Decision 5: Disaster Recovery — Hybrid Encrypted Key in Backup

**Status: HYBRID MODEL CHOSEN, adapted for local-only**

### The incoming recommendation was correct in principle but assumed a server

The "server stores Argon2id(recovery_key)" and "server verifies hash" pattern is from 1Password's cloud model. In KashCube's local model:

**The encrypted backup IS the server.**

```
1Password model:           KashCube model:
─────────────────          ────────────────────────────────────────
Server stores hash         Backup file contains Argon2id(recovery_key)
Server issues new token    Primary device (restored from backup) issues new tokens
Server revokes old tokens  Restored primary (has linked_devices table) revokes old sessions
```

Same security properties. Zero server.

### Backup structure

```json
{
  "version": "2",
  "app_version": "1.5.0",
  "created_at": "2026-03-12T10:00:00Z",
  "encrypted_data": "<base64: AES-256-GCM(db_export, data_key)>",
  "encrypted_signing_key": "<base64: AES-256-GCM(ed25519_private_key, key_encryption_key)>",
  "recovery_key_hash": "<base64: Argon2id(recovery_key, salt=device_id)>",
  "device_registry": [
    { "device_id": "...", "device_name": "Ravi's Tablet", "linked_party_id": 12 }
  ],
  "kdf_params": {
    "algorithm": "argon2id",
    "memory_kib": 65536,
    "iterations": 3,
    "parallelism": 1,
    "salt": "<base64: 16 random bytes>"
  }
}
```

Where:
```
data_key            = Argon2id(passphrase, salt=kdf_params.salt, ...)[:32]
key_encryption_key  = Argon2id(passphrase + recovery_key, salt=device_id, ...)[:32]
```

This means:
- Backup passphrase alone → can decrypt data ✅
- Backup passphrase alone → **cannot** decrypt signing key ❌ (needs recovery key too)
- Recovery key alone → **cannot** decrypt signing key ❌ (needs passphrase too)
- Both together → can decrypt signing key, become new primary ✅

### Argon2id vs PBKDF2 in Dart

`cryptography` package v2.7+ includes Argon2id. Flutter-compatible, pure Dart, no network.
Do NOT use `argon2` package (requires native C build tools, problematic on iOS).

Parameters for a mobile device with ~3 GB RAM:
- `memory_kib: 65536` (64 MB) — hard for attacker GPUs; manageable on phones
- `iterations: 3`
- `parallelism: 1`

Derive key in a background isolate (`compute()`) to avoid blocking the UI.

### Recovery flow (device lost)

```
Step 1  Install KashCube fresh on new phone
Step 2  "Restore from backup" → file picker → select .kashcube file
Step 3  Enter backup passphrase → data decrypted → DB restored
Step 4  "This backup contains a linked device configuration.
         Enter your recovery key to become the new primary."
Step 5  Enter recovery key (e.g. W4X9-KJ7P-RT6M)
         → Argon2id(entered, salt) compared to stored recovery_key_hash
         → match: decrypt signing key → store in FlutterSecureStorage
         → new device becomes primary with same signing authority
Step 6  App shows: "3 linked devices found. They will reconnect automatically
         on next sync. If needed, you can revoke them individually."
```

Existing secondary devices (Ravi's tablet etc.) still have the same `primary_public_key` cached.
Since the signing key is the same (recovered from backup), their tokens remain valid.
They will sync normally on next LAN connection. **No re-pairing required.** ✅

---

## Decision 6: Device Trust Model — Adapted for Local-First

**Status: KEEP THE STRUCTURE, REMOVE ALL SERVER ASSUMPTIONS**

### The incoming recommendation had the right tables, wrong deployment model

The proposed `devices`, `recovery_keys`, and `device_pairing_requests` tables all assumed:
- A server storing device public keys
- Push notifications for pairing approval
- "Server verifies" the recovery key hash

In KashCube:
- `linked_devices` table (primary device) = the device registry
- `device_session` table (secondary device) = the session credential
- Pairing approval = in-person QR scan (no push, no internet)
- Recovery key hash verification = happens on the new primary after backup restore

### Final table set for v58

```sql
-- ══════════════════════════════════════════════════════
-- On PRIMARY device:
-- ══════════════════════════════════════════════════════

-- Replaces the cloud "devices" table
CREATE TABLE linked_devices (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  sync_id              TEXT    UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))),
  device_id            TEXT    NOT NULL UNIQUE,    -- UUID generated by secondary at install
  device_name          TEXT    NOT NULL,            -- "Ravi's Tablet"
  device_type          TEXT,                        -- 'phone' | 'tablet'
  device_os            TEXT,                        -- 'android' | 'windows'
  secondary_public_key TEXT    NOT NULL,            -- Ed25519 public key of secondary (future use)
  user_id              INTEGER,                     -- FK app_users(id); NULL = owner mirror
  linked_party_id      INTEGER,                     -- FK parties(id) for HRMS
  permission_scope     TEXT    NOT NULL DEFAULT '{}',  -- JSON permission blob
  business_scope       TEXT    NOT NULL DEFAULT '[]',  -- JSON array of business IDs
  offline_grace_days   INTEGER NOT NULL DEFAULT 7,
  last_sync_at         TEXT,
  revoked_at           TEXT,                        -- NULL = active
  created_at           TEXT    DEFAULT (datetime('now')),
  FOREIGN KEY (user_id)         REFERENCES app_users(id) ON DELETE SET NULL,
  FOREIGN KEY (linked_party_id) REFERENCES parties(id)  ON DELETE SET NULL
);

-- Replaces the cloud "recovery_keys" table
-- NOTE: In local model, recovery key hash is stored INSIDE the encrypted backup.
-- This table persists it locally on the primary for "update recovery key" UX flow.
CREATE TABLE device_recovery (
  id               INTEGER PRIMARY KEY,   -- always 1 row
  recovery_key_hash TEXT NOT NULL,        -- Argon2id(recovery_key, salt=device_id)
  kdf_salt         TEXT NOT NULL,         -- base64 random 16 bytes
  created_at       TEXT DEFAULT (datetime('now')),
  last_rotated_at  TEXT
);

-- Replaces the cloud "device_pairing_requests" table
-- NOTE: Pairing is synchronous over LAN (no async request queue needed).
-- This table records completed pairings for audit/history.
CREATE TABLE pairing_history (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id       TEXT    NOT NULL,
  device_name     TEXT    NOT NULL,
  permission_preset TEXT  NOT NULL,       -- 'owner_mirror' | 'manager' | 'cashier' | 'custom'
  paired_at       TEXT    DEFAULT (datetime('now')),
  paired_by       TEXT    DEFAULT 'owner' -- 'owner' always in current model
);

-- Outbound event queue for pushed events to secondaries
CREATE TABLE sync_outbox (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  target_device_id TEXT,                  -- NULL = broadcast all active devices
  event_type   TEXT NOT NULL,             -- 'revoke' | 'permission_update' | 'force_readonly' | 'data_delta'
  payload      TEXT,                      -- JSON
  created_at   TEXT DEFAULT (datetime('now')),
  delivered_at TEXT                       -- NULL = pending
);

-- ══════════════════════════════════════════════════════
-- On SECONDARY device:
-- ══════════════════════════════════════════════════════

CREATE TABLE device_session (
  id                  INTEGER PRIMARY KEY,   -- always exactly 1 row
  this_device_id      TEXT NOT NULL,
  primary_device_id   TEXT NOT NULL,
  primary_public_key  TEXT NOT NULL,         -- Ed25519 public key; used to verify tokens
  token_payload       TEXT NOT NULL,         -- JSON of the signed token payload
  token_signature     TEXT NOT NULL,         -- base64 Ed25519 signature
  permission_scope    TEXT NOT NULL,         -- local cache of permissions
  business_scope      TEXT NOT NULL,         -- local cache of accessible business IDs
  offline_grace_days  INTEGER NOT NULL DEFAULT 7,
  issued_at           TEXT NOT NULL,
  last_sync_at        TEXT,
  is_read_only_forced INTEGER DEFAULT 0
);

-- ══════════════════════════════════════════════════════
-- On BOTH devices (new in v58):
-- ══════════════════════════════════════════════════════

CREATE TABLE app_users (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  sync_id         TEXT    UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))),
  display_name    TEXT    NOT NULL,
  pin_hash        TEXT,                   -- Argon2id(PIN); NULL = no independent PIN
  role            TEXT    NOT NULL DEFAULT 'custom',
  linked_party_id INTEGER,
  is_active       INTEGER NOT NULL DEFAULT 1,
  default_device_id TEXT,                 -- preferred linked device for this user
  last_login_at   TEXT,
  created_at      TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (linked_party_id) REFERENCES parties(id) ON DELETE SET NULL
);

CREATE TABLE user_permissions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  business_id INTEGER,                    -- NULL = all businesses (explicit per-biz preferred)
  module      TEXT    NOT NULL,
  can_view    INTEGER NOT NULL DEFAULT 1,
  can_create  INTEGER NOT NULL DEFAULT 0,
  can_edit    INTEGER NOT NULL DEFAULT 0,
  can_delete  INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, business_id, module),
  FOREIGN KEY (user_id)     REFERENCES app_users(id)   ON DELETE CASCADE,
  FOREIGN KEY (business_id) REFERENCES businesses(id)  ON DELETE CASCADE
);

CREATE TABLE subscription (
  id             INTEGER PRIMARY KEY,
  plan           TEXT    NOT NULL DEFAULT 'free',
  source         TEXT    DEFAULT 'none',
  purchase_token TEXT,
  plan_started_at TEXT,
  plan_expires_at TEXT,
  is_trial       INTEGER NOT NULL DEFAULT 0,
  trial_ends_at  TEXT
);

CREATE TABLE plan_features (
  plan         TEXT NOT NULL,
  feature      TEXT NOT NULL,
  enabled      INTEGER NOT NULL DEFAULT 1,
  limit_value  INTEGER,
  PRIMARY KEY (plan, feature)
);
```

---

## Decision 7: business_id NULL + Permissions Wildcard Fix

**Status: CHANGE — explicit per-business rows only in user_permissions**

The `business_id = NULL` wildcard in `user_permissions` silently grants access to future businesses.
Fix: when granting manager/cashier access, insert one explicit row per business they can access.

```dart
// PermissionRepository.grantRole() implementation:
Future<void> grantRole({
  required int userId,
  required String role,
  required List<int> businessIds,  // explicit; never pass "all" as wildcard
}) async {
  final modules = _presetsFor(role);  // role preset → list of module permissions
  for (final bizId in businessIds) {
    for (final module in modules) {
      await _db.insert('user_permissions', {
        'user_id': userId,
        'business_id': bizId,         // explicit; never null except for personal data
        'module': module.name,
        'can_view':   module.canView   ? 1 : 0,
        'can_create': module.canCreate ? 1 : 0,
        'can_edit':   module.canEdit   ? 1 : 0,
        'can_delete': module.canDelete ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
```

For personal data (`business_id IS NULL`), use a sentinel constant `kPersonalBusinessId = -1`
in user_permissions rather than NULL, to allow the UNIQUE constraint to work:

```sql
UNIQUE (user_id, business_id, module)
-- NULL is not equal to NULL in SQL → two NULL rows don't conflict → UNIQUE won't fire
-- Use -1 as a sentinel for "personal data scope" in this table only
```

---

## The Dual Permission Store Policy (Most Important Runtime Decision)

When a device is offline, two permission sources exist:
1. The `device_session.token_payload` (last token issued by primary)
2. The `user_permissions` table (may or may not exist on secondary)

**Rule: The signed token is authoritative in offline mode.**

Rationale: The token was signed by the primary's Ed25519 private key. A secondary cannot forge it. The permissions baked into the token are the last thing the primary explicitly authorized. Accept them offline.

On next sync: primary sends an updated token (if permissions changed), secondary replaces its stored token. Permissions update takes effect immediately on next app foreground.

```
Offline:   secondary uses token_payload.permissions
Online:    primary sends new token → secondary verifies signature → replaces stored token
            → new permissions from DB take effect on next app launch or foreground
```

For immediate revocation (fire a cashier today): owner taps "Revoke Now" → primary queues
`force_readonly` event → next time secondary comes on LAN → receives event → session cleared.
Offline grace doesn't protect against explicit revocation.

---

## Phase 0 Implementation Sequence (v58)

Freeze all other features for this sprint.

```
v58 migration steps:

1. Create new tables (linked_devices, device_recovery, pairing_history,
   sync_outbox, device_session, app_users, user_permissions,
   subscription, plan_features)

2. ALTER existing tables — add Phase 0 columns:
   For each of: transactions, invoices, credits, credit_payments, parties,
   accounts, categories, budgets, item_catalog, scheduled_payments,
   purchase_bills, businesses, loans

   ADD sync_id TEXT UNIQUE DEFAULT (lower(hex(randomblob(16))))
   ADD updated_at TEXT DEFAULT (datetime('now'))   ← new rows
   ADD version INTEGER DEFAULT 0
   ADD created_by_device_id TEXT
   (deleted_at already exists on most; add where missing)

   UPDATE <table> SET
     sync_id    = lower(hex(randomblob(16))),
     updated_at = datetime('now'),
     version    = 0
   WHERE sync_id IS NULL;   ← backfill existing rows

3. CREATE all UPDATE triggers (one per syncable table)

4. INSERT INTO plan_features — seed all plan × feature combinations

5. INSERT INTO subscription (id=1, plan='free') — initial row

6. INSERT INTO device_recovery — skip; generated on first pairing or recovery
```

---

## Summary Decision Table

| Decision | Choice | Key reason |
|----------|--------|-----------|
| Phase 0 timing | Now (v58 blocker) | Every sprint deferred = more tables to retrofit |
| sync_id placement | Alongside integer PK, not replacing it | All FKs reference integer ID |
| Conflict resolution | version counter + updated_at fallback | Clock-skew immune |
| SQLite updated_at | Triggers (not DEFAULT) | DEFAULT only fires on INSERT |
| Subscription | plan_features + Play Billing | No Stripe (requires server) |
| Token signing | Ed25519 via `cryptography` package | Deterministic, fast, smaller keys |
| Key storage | FlutterSecureStorage (not hardware Keystore) | Ed25519 HW backing = Android 13+ only |
| Disaster recovery | Encrypted signing key in backup | No server; backup = recovery authority |
| KDF | Argon2id (via `cryptography`) | Industry standard; GPU-resistant |
| business_id NULL | Keep convention | Existing; load-bearing in every query |
| Permission wildcard | No NULL business_id in user_permissions | Prevents silent future-biz escalation |
| Permissions offline | Token is authoritative | Token is signed; can't be forged |
| Recovery key storage | Inside encrypted backup + device_recovery table on primary | No server |
| Push notifications | Not applicable | No server; in-person QR/PIN only |
| Stripe | Not applicable | KashCube has no backend server |
| Device pairing approval | Synchronous QR/PIN over LAN | No async push infrastructure |
| **Device identity model** | **Dual-primary (v63+): every install is its own primary** | **Ravi is a person, not a terminal** |
| **context_id** | **New column on all tables (v64); NULL = personal** | **Orthogonal to business_id; enables multi-employer** |
| **Personal data on secondary** | **context_id IS NULL rows never leave the device** | **CASCADE DELETE on session unlink; personal data untouched** |
| **Plan enforcement** | **Context-aware: personal = own plan; linked session = employer's plan** | **"Slack model" — workspace pays for workspace** |
| **Payroll loop** | **Opt-in cross-context income notification (v66)** | **Explicit user action required; no automatic income creation** |

---

## Decision 8: Device Identity Model — Dual-Primary (Long-Term)

**Status: DECIDED — Target architecture for v63+. Fully specified in DUAL_PRIMARY_IDENTITY_SPEC.md.**

### The One-Line Summary

> Every KashCube install is its own primary. Linking to a business is an overlay — not a
> replacement of identity.

### What changes in v63+

| Component | Current (v58–v62) | Future (v63+) |
|-----------|-------------------|----------------|
| Device identity | Implicit (device UUID only) | `my_identity` table, permanent UUID, Ed25519 keypair |
| Secondary session | `device_session` (1 row max) | `linked_business_sessions` (N rows; multi-employer) |
| Data ownership | `business_id IS NULL` = owner's personal data | Add: `context_id IS NULL` = this identity's personal data |
| Pairing | Device-first (scan QR from primary) | Identity-first (employee shows their QR; employer scans it) |
| Plan enforcement | Local subscription table only | Context-aware: personal context = own plan; linked session = employer's plan |
| Payroll | Salary Transaction on owner's device only | Optional cross-context income notification to employee's device |

### What does NOT change

- `business_id IS NULL` = personal data convention is **KEPT**. `context_id` is additive.
- Ed25519 via `cryptography` package (Decision 3) — extended with a second identity keypair
- Disaster recovery (Decision 5) — backup now encrypts both keypairs (device + identity)
- `sync_id` on all tables (Decision 1) — context_id is added in addition, not instead

### Phased implementation

```
v63: Phase D1  — my_identity table; IdentityService; identity QR; device_session → linked_business_sessions
v64: Phase D2  — context_id column on all tables; context switcher UI; context-aware providers
v65: Phase D3  — session token extended with plan_features; identity-first pairing; multi-session UX
v66: Phase D4  — payroll loop; payroll_notifications table; cross-context income event
```

**Full spec:** `DUAL_PRIMARY_IDENTITY_SPEC.md`

---

## Complete Build Order

```
━━━━━━━━━━━━━━━━━━━━━━ FOUNDATION ━━━━━━━━━━━━━━━━━━━━━━

v58: Phase 0   sync_id + version + triggers on all tables
               (CURRENT BLOCKER — DO FIRST)

━━━━━━━━━━━━━━━━━━━━━━ USERS & PERMISSIONS ━━━━━━━━━━━━━

v59: Phase U1  Cashier Mode (settings keys only, no DB changes)
v60: Phase U2  app_users + user_permissions + full RBAC

━━━━━━━━━━━━━━━━━━━━━━ LINKED DEVICES ━━━━━━━━━━━━━━━━━━

v61: Phase L1  Owner Mirror — first working LAN sync
v62: Phase L2  Staff Terminal — permission-scoped bidirectional sync

━━━━━━━━━━━━━━━━━━━━━━ DUAL-PRIMARY IDENTITY ━━━━━━━━━━━

v63: Phase D1  my_identity + linked_business_sessions (replaces device_session)
v64: Phase D2  context_id on all tables + context switcher UI
v65: Phase D3  session token extended + identity-first pairing + multi-session UX
v66: Phase D4  payroll loop + cross-context income events

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

No phase can be built correctly without all its predecessors.

---

## What Comes After Phase 0

```
v58: Phase 0 (sync foundation — this doc)
v59: Phase U1 (Cashier Mode — no DB changes needed)
v60: Phase U2 (app_users + RBAC + linked_devices full implementation)
v61: Phase L1 (Owner Mirror pairing + LAN sync)
v62: Phase L2 (Staff Terminal + permission-scoped sync)
v63–v66: Dual-Primary Identity (see Decision 8 above + DUAL_PRIMARY_IDENTITY_SPEC.md)
```

No Phase U2 or beyond can be built correctly without v58 Phase 0.

---

*Last updated: 12 March 2026*
*Status: Final decisions — no longer RFC/brainstorm*
*Related: PRIVATE_SYNC_BRAINSTORM.md, USER_PERMISSIONS_BRAINSTORM.md, LINKED_DEVICES_BRAINSTORM.md, DUAL_PRIMARY_IDENTITY_SPEC.md*
