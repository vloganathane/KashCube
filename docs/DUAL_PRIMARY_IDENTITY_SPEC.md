# Dual-Primary Identity Model
# KashCube Architecture Spec

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** DECIDED — Long-term target architecture (v63+); extends ARCHITECTURE_DECISIONS.md  
**Author:** Engineering  
**Depends on:** `ARCHITECTURE_DECISIONS.md`, `LINKED_DEVICES_BRAINSTORM.md`, `USER_PERMISSIONS_BRAINSTORM.md`

---

## 1. The Paradigm Shift

### The Hidden Assumption in the Current Model

Every architecture doc written so far — LINKED_DEVICES, USER_PERMISSIONS, ARCHITECTURE_DECISIONS —
was written with one implicit assumption:

> **"There is one owner. Everyone else gets limited access to the owner's world."**

This was the right starting point for v1. It is the wrong ending point for v3+.

### Why the Current Model Breaks for Real Users

Consider Ravi, a cashier at "Ravi's Shop" (owned by the shop owner, Suresh).

Suresh pairs Ravi's phone as a Staff Terminal. Ravi sees the shop's data through his phone.
Now Ravi wants to track his own expenses — groceries, rent, personal loans.

**Problem:** In the current model, Ravi's phone is Suresh's secondary device. There is no concept
of Ravi having his own identity, his own data, his own KashCube. The architecture treats Ravi as
an extension of Suresh's app.

This is wrong. Ravi is a person, not a terminal.

### The New Mental Model

```
Current assumption:                    New model:
═══════════════════════════════════    ═══════════════════════════════════════
Suresh's KashCube                      Suresh's KashCube
  ├── Suresh's data                      ├── Suresh's data (context: personal)
  └── Ravi's tablet                      └── Suresh's Shop (context: business)
       (secondary, borrows Suresh's
        authority)
                                       Ravi's KashCube (separate app)
                                         ├── Ravi's data (context: personal)
                                         └── Linked: Suresh's Shop (overlay)
                                              (Ravi sees only what Suresh grants)
```

**The shift: every KashCube install is its own primary.**

Linking to a business session is an *overlay* — a second context layered on top of the person's own
identity. Not a demotion from primary to secondary. Not a replacement of identity.

This is how Slack works: you are always yourself. You join workspaces. You leave workspaces. Your
direct messages and personal notes don't disappear when you leave a workspace.

---

## 2. Core Concepts

### 2.1 Identity (my_identity)

Every install has one permanent identity. This is set up on first run:

```
"Hi! Let's set up your KashCube."
"What's your name?" → "Ravi Kumar"
```

This creates:
- A UUID `identity_id` (permanent: survives app upgrades, restore from backup)
- An Ed25519 keypair (private key in `flutter_secure_storage`, public key in `my_identity` table)
- A `my_identity` row in the local DB

The owner's existing KashCube is NOT affected — they already have an identity (just not formally
labelled). The v63 migration generates identity for all existing installs silently.

### 2.2 Context (context_id)

Every row in every syncable table carries a `context_id INTEGER`:

| context_id | Meaning |
|------------|---------|
| `NULL` | This device's own personal data. Owned by `my_identity`. Never shared. |
| `N > 0` | Data belonging to linked business session N. FK to `linked_business_sessions`. |

Think of it as "whose world does this row belong to?"

```
Ravi's device:
  context_id IS NULL            → Ravi's personal transactions, parties, credits
  context_id = 1                → Suresh's shop data (only what Ravi can see)
  context_id = 2                → Sharma's Bakery data (Ravi works part-time too)
```

### 2.3 Linked Business Session (linked_business_sessions)

When Ravi links to Suresh's shop, a `linked_business_sessions` row is created on Ravi's device.
This replaces the single-row `device_session` table from the previous model.

Key difference: **there can be multiple sessions** (Ravi linked to 2 employers simultaneously).
Also: the relationship is now identity-to-identity, not device-to-device. Suresh's app recognises
Ravi's identity (`identity_id`), not just a device UUID.

### 2.4 Context Switcher

The app UI offers a context switcher — the same way browsers have separate profiles:

```
App bar:
  ┌─────────────────────────────────────────────┐
  │  [👤 Ravi Kumar ▾]  KashCube               │
  └─────────────────────────────────────────────┘

Tap ▾ →
  ┌──────────────────────────────┐
  │  👤 Ravi Kumar               │  ← personal context (current)
  │  🏪 Ravi's Shop              │  ← linked session 1
  │  🏪 Sharma's Bakery          │  ← linked session 2
  │                              │
  │  + Link to a business        │
  └──────────────────────────────┘
```

Switching context changes the active `context_id` in the Riverpod state. All providers re-filter
to show only rows matching that context. The navigation and available actions change accordingly
(personal context: full personal features; business session context: role-restricted view of that
business).

---

## 3. Architecture Changes

### 3.1 New Table: my_identity (Every Device)

```sql
CREATE TABLE my_identity (
  id               INTEGER PRIMARY KEY,          -- always exactly 1 row
  identity_id      TEXT    NOT NULL UNIQUE,      -- UUID; permanent across reinstalls
  display_name     TEXT    NOT NULL,             -- "Ravi Kumar"
  avatar_seed      TEXT,                         -- optional: seed for generated avatar
  public_key       TEXT    NOT NULL,             -- Ed25519 public key (safe to store)
  created_at       TEXT    DEFAULT (datetime('now')),
  updated_at       TEXT    DEFAULT (datetime('now'))

  -- Ed25519 private key is stored in flutter_secure_storage under key:
  --   'identity_private_key'
  -- NOT in this table. It never enters SQLite.
);
```

Migration for existing installs (v63):
```sql
-- Generate identity for existing primary devices
INSERT OR IGNORE INTO my_identity (
  id, identity_id, display_name, public_key
) VALUES (
  1,
  lower(hex(randomblob(16))),  -- generated UUID
  COALESCE((SELECT value FROM settings WHERE key = 'owner_name'), 'My KashCube'),
  ''                           -- placeholder; Ed25519 keypair generated in Dart on upgrade
);
```

The keypair generation happens in Dart upgrade logic, not SQL — `dart:isolate` + `cryptography`
package generates the keypair and writes to `flutter_secure_storage`. The public key is then
written back to the `my_identity` row.

### 3.2 New Column: context_id on All Syncable Tables

Added alongside `sync_id` in Phase D2 (v64). Null = personal, positive integer = linked session.

```sql
-- Added to ALL syncable tables in v64 migration:
ALTER TABLE transactions          ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE invoices               ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE credits                ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE credit_payments        ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE parties                ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE accounts               ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE categories             ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE budgets                ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE item_catalog           ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;
ALTER TABLE purchase_bills         ADD COLUMN context_id INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE;

-- Backfill: all existing rows are personal context
UPDATE transactions     SET context_id = NULL WHERE context_id IS NULL;   -- already NULL; explicit
-- (repeat for all tables — all existing rows stay personal context)
```

**The `ON DELETE CASCADE` is critical:** if a linked session is unlinked/revoked, all rows with
that `context_id` are automatically cleaned up. Ravi's personal data (context_id IS NULL) is
never touched.

**The existing `business_id IS NULL` convention is unchanged.** `context_id` is orthogonal:

```
context_id IS NULL  AND  business_id IS NULL  → personal transaction (no business)
context_id IS NULL  AND  business_id = 5      → Ravi's own business (if he owns one)
context_id = 2      AND  business_id = 3      → data from linked session 2, business 3
```

### 3.3 New Table: linked_business_sessions (Replaces device_session)

```sql
-- Replaces the single-row device_session table from v58/v62.
-- Multiple sessions per device are now supported.
CREATE TABLE linked_business_sessions (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id           TEXT    NOT NULL UNIQUE,          -- UUID; the "context_id" for rows
  primary_identity_id  TEXT    NOT NULL,                 -- owner's identity_id (their UUID)
  primary_public_key   TEXT    NOT NULL,                 -- Ed25519 pubkey to verify tokens
  primary_device_name  TEXT,                             -- "Suresh's Phone" (display only)
  business_name        TEXT    NOT NULL,                 -- "Ravi's Shop" (display only)
  business_ids         TEXT    NOT NULL DEFAULT '[]',    -- JSON array of accessible business IDs
  token_payload        TEXT    NOT NULL,                 -- last received signed token (JSON)
  token_signature      TEXT    NOT NULL,                 -- base64 Ed25519 signature
  permission_scope     TEXT    NOT NULL DEFAULT '{}',    -- permission blob from last token
  offline_grace_days   INTEGER NOT NULL DEFAULT 7,
  issued_at            TEXT    NOT NULL,
  last_sync_at         TEXT,
  is_read_only_forced  INTEGER DEFAULT 0,
  display_order        INTEGER DEFAULT 0,                -- user-set ordering in context switcher
  unlinked_at          TEXT,                             -- NULL = active; set when session removed
  created_at           TEXT    DEFAULT (datetime('now'))
);
```

**Migration from device_session (v63):**
```sql
-- If device_session has a row (this was a secondary device in old model):
INSERT INTO linked_business_sessions (
  session_id, primary_identity_id, primary_public_key,
  business_name, business_ids, token_payload, token_signature,
  permission_scope, offline_grace_days, issued_at, last_sync_at, is_read_only_forced
)
SELECT
  lower(hex(randomblob(16))),   -- new session_id
  primary_device_id,             -- was device_id, repurposed as identity_id placeholder
  primary_public_key,
  'Linked Business',             -- placeholder; updated on next sync
  business_scope,
  token_payload,
  token_signature,
  permission_scope,
  offline_grace_days,
  issued_at,
  last_sync_at,
  is_read_only_forced
FROM device_session
LIMIT 1;

DROP TABLE device_session;      -- after migration
```

### 3.4 Changes on the Primary (Owner's) Device

On Suresh's device — the business owner's "primary" — the `linked_devices` table gains an
`identity_id` column to reference Ravi's identity, not just a device UUID:

```sql
ALTER TABLE linked_devices ADD COLUMN secondary_identity_id TEXT;
-- FK to the secondary's identity_id (their my_identity.identity_id)
-- Populated during pairing (secondary sends identity QR; primary stores it)
```

**Why `identity_id` and not just device_id?**

Ravi might reinstall KashCube or get a new phone. In the old model, a new device = new pairing.
In the new model, Ravi restores his backup → same `identity_id` → same `secondary_identity_id`
on Suresh's `linked_devices` row → no re-pairing required (just re-sync on LAN). The identity
is portable. The device is not.

The pairing QR from the secondary now embeds:
```json
{
  "pairing_token":      "one-time token, expires 2min",
  "device_id":          "hardware UUID of this device",
  "identity_id":        "Ravi's permanent KashCube identity UUID",
  "identity_public_key": "Ravi's Ed25519 public key",
  "display_name":       "Ravi Kumar",
  "app_version":        "2.3.0"
}
```

---

## 4. The Four Device States

Any KashCube install can be in one of four states:

| State | Description | What user sees |
|-------|-------------|----------------|
| **1. Personal only** | Fresh install, never linked. Identity set up, no sessions. | Full personal KashCube. Own transactions, credits, parties. |
| **2. Linked only** | Dedicated shop tablet. Identity exists but no personal use. | Business overlay only. No personal context used. |
| **3. Personal + Linked** | Ravi's own phone: personal use AND linked to boss. | Context switcher: Ravi's KashCube ↔ Shop. Personal and shop data siloed. |
| **4. Own business + Linked** | Business owner who also works elsewhere. | Own business context + linked employer context. |

**State transitions are reversible.** Unlinking a session removes it and cascades-deletes all
its rows. Personal data is never affected.

---

## 5. Personal Data Isolation Rules

### What "personal" means in the new model

Rows with `context_id IS NULL` are personal. They:
1. Live only on this device (never pushed to any linked session's primary)
2. Are not visible in any linked business session view
3. Survive session revocation (CASCADE DELETE only removes `context_id = N` rows)
4. Are included in THIS device's own backup

### The two-backup principle (v65+)

When Ravi backs up his KashCube:
```
RAVI'S BACKUP (.kashcube):
  ├── Ravi's personal data  (context_id IS NULL)    ← always included
  └── Linked session data   (context_id = 1, 2)     ← optional; user can exclude
```

The `exclude_linked_contexts` export flag (default: `false` for full backup, `true` for "personal
only" export) allows Ravi to back up just his personal data when sharing the backup file with
family or on a new personal phone (while keeping the shop data on a dedicated tablet).

### Cascading unlink

When Ravi unlinks from Suresh's shop:
1. `linked_business_sessions.unlinked_at = NOW()` (soft delete)
2. All rows with `context_id = <that session's id>` are deleted (hard cascade)
3. Ravi's personal data: completely unchanged

Ravi does not need to worry about "will unlinking delete my personal expenses?" The answer is no,
and the architecture enforces it structurally.

---

## 6. Cross-Context Features

### 6.1 Payroll Loop (Opt-In Income Notification)

The most natural cross-context interaction: Suresh pays Ravi's salary → Ravi's personal KashCube
records it as income.

```
Suresh's KashCube (owner):
  1. Adds/confirms payroll Transaction:
       type = expense
       category = Payroll
       party = Ravi Kumar (staff party)
       amount = ₹18,000
       context_id = NULL (shop expense, Suresh's own data)
  
  2. "Notify payee?" toggle (default OFF — explicit opt-in each time)
     If toggled ON:
       → Queues to sync_outbox:
         {
           type: 'payroll_notification',
           target_identity_id: '<Ravi's identity_id>',
           amount: 18000,
           business_name: 'Ravi\'s Shop',
           paid_on: '2026-03-28',
           reference: 'MAR-2026 Salary'
         }

Ravi's KashCube (employee), on next LAN sync with Suresh's device:
  3. Receives payroll_notification event
  4. Shows: "₹18,000 received from Ravi's Shop. Add to your income?"
                                                [Add Income]  [Dismiss]
  
  5a. If [Add Income] tapped:
        Transaction created in personal context:
          context_id = NULL
          business_id = NULL
          type = income
          category = Salary
          party = 'Ravi\'s Shop' (auto-created or matched in Ravi's personal parties)
          amount = ₹18,000
          notes = 'MAR-2026 Salary'
  
  5b. If [Dismiss]:
        Notification marked as dismissed; no Transaction created
```

**Privacy properties:**
- Suresh does NOT see Ravi's personal income records or financial state
- Ravi can see this one notification; he does not see Suresh's full books
- Ravi explicitly taps [Add Income] — income is never created automatically
- If Ravi dismisses, he can retrieve it from "Payroll Notifications" in settings
- Cross-device notification requires both parties to have KashCube + be on same LAN once

### 6.2 KashCube Business Card (Identity Exchange)

When Suresh wants to link Ravi, instead of showing a generic QR:

```
"Ravi, open KashCube → Profile → Show My QR"
Suresh scans Ravi's identity QR → primary sees Ravi Kumar, identity_id confirmed
Suresh assigns role → Ravi's KashCube receives the pairing token
```

This is identity-first pairing (vs. the old device-first pairing). The flow is more natural
because it maps to how humans already think: "I'm linking Ravi, not Ravi's Samsung Galaxy."

---

## 7. Subscription: The Slack Model

### Rule: Linked session features are governed by the session owner's plan

```
Suresh has:  Pro plan (3 linked devices, LAN sync, full reports)
Ravi has:    Free plan (personal use only, no linking OUT)

When Ravi is linked to Suresh's shop:
  → Ravi's view of the shop gets Pro features (because Suresh is Pro)
  → Suresh's device counts Ravi as 1 of his 3 linked devices
  → Ravi's own personal context remains Free-plan constrained

When Ravi starts his own business:
  → Under Ravi's own account: Free plan constraints apply to his personal businesses
  → To link others to his own business: Ravi needs his own Pro plan
```

```
Suresh (Pro)                     Ravi (Free)
  ├── Linked device 1: Ravi ──────→  Linked session: "Ravi's Shop"
  │     (uses Suresh's Pro quota)        (Pro features while in this context)
  └── his own phone                  └── Personal context (Free constraints)
```

### How to enforce in code

The `activeContextProvider` + `PlanGate` become context-aware:

```dart
// NEW: context-aware PlanGate
class PlanGate {
  // For personal context (context_id IS NULL):
  bool canDo(String feature) =>
    _localPlan.canDo(feature);           // local subscription table
  
  // For a linked session context:
  bool canDoInSession(String feature, int sessionId) =>
    _sessionsCache[sessionId]?.planFeatures.canDo(feature) ?? false;
    // plan features are received in the session token payload and cached locally
}
```

The session token (signed by Suresh's Ed25519 key) includes the plan feature set Suresh is
granting Ravi's session. Ravi's device cannot forge or elevate this. On every sync, the token is
refreshed with the latest plan state.

---

## 8. Migration Path

### Pre-condition: v58–v62 Must Complete First

The dual-primary model REQUIRES all of the following to be in place:

| Version | What it adds | Why D1 needs it |
|---------|-------------|-----------------|
| v58 | sync_id + version + triggers on all tables | D2's context_id migration depends on already having sync_id |
| v59 | Cashier Mode (U1) | Lower-risk, ships value faster |
| v60 | app_users + RBAC (U2) | app_users is the user identity foundation D1 extends |
| v61 | Owner Mirror (L1) | First working sync; validates LAN sync before D1 complexity |
| v62 | Staff Terminal (L2) | Full device-linking flows built and proven |
| **v63** | **D1: my_identity** | **Dual-primary starts here** |

### Summary Migration Sequence

```
v62 state:
  Primary device has: linked_devices, sync_outbox, app_users, user_permissions, ...
  Secondary device has: device_session (single row), ...

v63 migration adds:
  Both devices: my_identity table (1 row, generated)
  Secondary: linked_business_sessions created from device_session data; device_session dropped
  Primary: linked_devices.secondary_identity_id column added (NULL for existing rows)
  Both: identity_id column added to app_users (links app user to an identity)

v64 migration adds:
  All tables: context_id INTEGER NULL column
  All existing rows: context_id set to NULL (personal context, backward compatible)
  New triggers: update context_id-aware queries in existing indexes if needed
  UI: context switcher widget added to app bar

v65 migration adds:
  Primary: session_token gains plan_features payload (extend token schema)
  New: payroll_notifications table on both devices
  PlanGate: becomes context-aware

v66 (optional, high-value):
  Payroll loop event infrastructure (sync_outbox payroll_notification type)
  Cross-context income creation UX
```

---

## 9. Step-by-Step Implementation Plan

### Phase D1 (v63): My Identity Foundation

**Goal:** Every install has a permanent identity. No user-facing changes yet (except onboarding).

**DB changes:**
- New table: `my_identity` (1 row)
- New column: `linked_devices.secondary_identity_id TEXT`
- New column: `app_users.identity_id TEXT` (FK to my_identity for future cross-device user matching)
- Migration: generate identity for all existing installs silently in `_onUpgrade`
- `device_session` → `linked_business_sessions` (rename + schema evolution)

**Code changes:**
- `IdentityService` class: generates Ed25519 keypair, stores private key in `flutter_secure_storage`, stores public key in `my_identity` table
- `IdentityRepository`: read/update `my_identity`
- `identityProvider` (Riverpod): `FutureProvider<MyIdentity>` — always returns the 1 row
- Onboarding (new install only): `IdentitySetupScreen` — "What's your name?" before PIN setup
- Backup: include `my_identity` row in `.kashcube` backup export; restore flow re-imports it

**Migration touchpoints:**
- `DatabaseHelper._onUpgrade` for v58→v63: generate identity in Dart, then write public key to DB
- `BackupService.exportBackup`: add `identity` section to JSON
- `BackupService.importBackup`: restore `my_identity` on new device (old backups: gracefully generate a new identity if section absent)

**No UI change for existing users** (identity is background infrastructure). New users get the `IdentitySetupScreen` on first run.

---

### Phase D2 (v64): Context Layer

**Goal:** All data is context-tagged. The context switcher UI exists.

**DB changes:**
- `context_id INTEGER NULL` added to all 13+ syncable tables (ALTER in `_onUpgrade`)
- Backfill: `UPDATE <table> SET context_id = NULL WHERE context_id IS NULL`
- New table: none (context_id references `linked_business_sessions.id` which exists from D1)

**Code changes:**
- `activeContextProvider`: `StateProvider<int?>(null)` — `null` = personal, `N` = session ID
- All repository query methods: add `contextId` filter parameter
  ```dart
  // Before:
  Future<List<Transaction>> getAll({int? businessId})
  // After:
  Future<List<Transaction>> getAll({int? businessId, int? contextId = _kPersonal})
  const _kPersonal = -1; // sentinel meaning "contextId IS NULL"
  ```
- Context switcher widget: dropdown in app bar (`ContextSwitcherWidget`)
- `ContextSwitcherProvider`: exposes list of active sessions + personal context as options
- All screens: read `activeContextProvider` and pass to their repository calls
- Empty state for linked session context: "Waiting for first sync with [Business Name]"

**Permission scoping per context:**
- Personal context: full owner access (no permission table check)
- Linked session context: check `linked_business_sessions.permission_scope` (the cached token)

---

### Phase D3 (v65): Linked Business Sessions — Full Upgrade

**Goal:** Session token includes plan features. Identity-first pairing. Multiple sessions.

**DB changes:**
- `linked_devices.secondary_identity_id` is now populated during pairing (was NULL in D1)
- Token payload schema extended: add `plan_features` section
- `subscription` on primary: add `shareable_plan_features` TEXT column (pre-serialized JSON for token inclusion)

**Code changes:**
- `TokenService`: extend `PairingToken` model to include plan features
- `PlanGate`: becomes context-aware (personal vs. session feature checks)
- Pairing flow: secondary QR now shows identity QR (from `my_identity`) in addition to device QR
- Primary `LinkDeviceScreen`: shows "Linking with: Ravi Kumar" (identity display name) after scan
- `linked_devices` list: shows "Ravi Kumar" (identity name) instead of "Ravi's Galaxy S23"
- Token refresh on sync: re-serialize `plan_features` into token on every LAN sync

**The "multiple sessions" upgrade:**
- `LinkedSessionSwitcherScreen`: shows all active sessions; add link button at bottom
- Deep link: `kashcube://link?session=<pairing_token>` (for desktop future use)

---

### Phase D4 (v66): Payroll Loop + Cross-Context Events

**Goal:** Opt-in payroll income notifications across identity boundaries.

**DB changes:**
- New table: `payroll_notifications`

```sql
CREATE TABLE payroll_notifications (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id    TEXT    NOT NULL UNIQUE,          -- UUID
  source_identity_id TEXT    NOT NULL,                 -- who sent it (employer's identity_id)
  business_name      TEXT    NOT NULL,                 -- display name
  amount             REAL    NOT NULL,
  currency           TEXT    NOT NULL DEFAULT 'INR',
  reference_label    TEXT,                             -- "MAR-2026 Salary"
  paid_on            TEXT    NOT NULL,
  received_at        TEXT    DEFAULT (datetime('now')),
  status             TEXT    NOT NULL DEFAULT 'pending', -- 'pending' | 'added' | 'dismissed'
  created_transaction_id INTEGER,                      -- FK to transactions if 'added'
  FOREIGN KEY (created_transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
);
```

**sync_outbox event type added:**
```dart
// In SyncEventType enum:
payrollNotification,   // employer → employee; carries payroll_notifications payload
```

**Code changes:**
- `PayrollNotificationRepository`: CRUD for `payroll_notifications` table
- Primary device: `PayrollScreen` / `StaffDetailScreen` "Notify" toggle on payroll Transaction confirmation
- Primary: `SyncServer` handles new event type → queues to `sync_outbox` for target `identity_id`
- Secondary: `SyncClient` receives and routes `payroll_notification` event → inserts to `payroll_notifications`
- New `PayrollNotificationsBanner` widget: shows "N new payroll notifications" on home screen
- New `PayrollNotificationsSheet`: lists pending notifications with [Add Income] / [Dismiss] per item
- On [Add Income]: creates Transaction(context_id=NULL, type=income, category='Salary') in personal context

**Privacy guard on primary side:**
- Payroll notification is queued with `target_identity_id` filter
- On sync, primary filters `sync_outbox` by `target_identity_id == secondary.identity_id`
- Only the targeted person receives their notification; no broadcasts

---

## 10. Impact on Existing Architecture Decisions

### Decision 1 (Phase 0 sync_id) — Unchanged ✅
`context_id` is added in D2 (v64), AFTER sync_id is already on all tables in v58.

### Decision 3 (Ed25519) — Extended
`my_identity` table uses the same Ed25519 infrastructure. The primary now has TWO key pairs:
1. **Device signing key** (for `device_session` / `linked_business_sessions` tokens) — existing
2. **Identity key** (for identity-level pairing QR) — NEW in D1

Both are stored in `flutter_secure_storage` under separate keys:
- `device_signing_private_key` — existing
- `identity_private_key` — new (D1)

### Decision 5 (Disaster Recovery) — Extended
Backup now includes both key pairs:
```json
{
  "encrypted_signing_key":  "AES-GCM(device_signing_private_key, kek)",
  "encrypted_identity_key": "AES-GCM(identity_private_key, kek)"
}
```
Restoring from backup on a new device recovers BOTH keys. The `identity_id` (UUID) stays the same.
On next LAN sync with Suresh's device: Suresh's `linked_devices.secondary_identity_id` still matches → no re-pairing.

### Decision 6 (device_session table) — Replaced in D1
`device_session` (single-row) → `linked_business_sessions` (multi-row) in v63.
The token verification logic is identical; only the table name and row multiplicity change.

### Build Order — Extended
```
v58: Phase 0   (sync_id, triggers — THIS IS STILL FIRST)
v59: Phase U1  (Cashier Mode)
v60: Phase U2  (app_users + full RBAC)
v61: Phase L1  (Owner Mirror — first working LAN sync)
v62: Phase L2  (Staff Terminal — permission-scoped sync)
────────────────── dual-primary begins here ──────────────────
v63: Phase D1  (my_identity — identity foundation)
v64: Phase D2  (context_id column — context switcher UI)
v65: Phase D3  (linked_business_sessions upgrade — plan features, identity pairing)
v66: Phase D4  (payroll loop — cross-context income events)
```

---

## 11. UX Screen Inventory (D1–D4)

### New screens / widgets in D1 (v63)
| Component | Type | Description |
|-----------|------|-------------|
| `IdentitySetupScreen` | Screen | New install only: "What's your name?" before PIN setup |
| `ProfileScreen` | Screen | My profile (name, identity QR, public key fingerprint) |
| `MyIdentityQrWidget` | Widget | Shows scannable QR with identity_id for pairing |

### New screens / widgets in D2 (v64)
| Component | Type | Description |
|-----------|------|-------------|
| `ContextSwitcherWidget` | Widget | App bar dropdown: personal ↔ linked sessions |
| `LinkedSessionEmptyState` | Widget | "Waiting for first sync with [business]" placeholder |
| `ContextBannerWidget` | Widget | Subtle banner when in linked session context: "🏪 Ravi's Shop" |

### New screens / widgets in D3 (v65)
| Component | Type | Description |
|-----------|------|-------------|
| `LinkedSessionsScreen` | Screen | Settings → Linked Sessions (list of active sessions + add new) |
| `LinkToBusinessSheet` | Sheet | Camera + QR scanner for linking to a new business |
| `SessionDetailScreen` | Screen | Session info, permission summary, unlink button |

### New screens / widgets in D4 (v66)
| Component | Type | Description |
|-----------|------|-------------|
| `PayrollNotificationsBanner` | Widget | Home screen: "1 payroll notification pending" |
| `PayrollNotificationsSheet` | Sheet | List of pending notifications; Add Income / Dismiss actions |

---

## 12. Open Questions

These are known unknowns that don't need to be decided now but will surface during D3–D4:

| # | Question | Stakes | Deferred to |
|---|----------|--------|-------------|
| 1 | **Multiple employer conflict**: Ravi linked to 2 shops both using `business_id = 1` locally. How to namespace conflict? | Medium — context_id isolates it but `business_id` within each context starts at 1 | D3 design sprint |
| 2 | **Mutual identity verification**: Does Ravi know he's linked to the REAL Suresh and not a MITM QR spoof? | High for trust, low risk in practice (LAN, in-person QR) | D3 design |
| 3 | **Payroll loop spam**: What if Suresh accidentally sends 3 notifications for the same month? | UX annoyance; dedup on `notification_id` + `reference_label + paid_on` combo | D4 implementation |
| 4 | **Session backup**: Should linked session data be in Ravi's backup? If Ravi restores on a new phone, does he want the shop data? | Requires "exclude linked contexts on export" option | D2 design |
| 5 | **Own-business + linked**: If Ravi starts his own business (context_id IS NULL, business_id = 1) AND has linked session (context_id = 2, business_id = 1), queries using `business_id = 1` MUST also filter `context_id` to avoid mixing. | **High — this is a query correctness issue.** All repository methods must filter by context_id AND business_id together, never just business_id alone. | v64 implementation |
| 6 | **Desktop app**: The dual-primary model is designed to naturally extend to a KashCube desktop app (Windows/Mac). Desktop = another primary/secondary. Not in scope yet but keep in mind. | Architecture-level awareness | v66+ |

---

*Last updated: 12 March 2026*  
*Status: Decided — long-term target architecture (v63+)*  
*Pre-conditions: v58–v62 must complete first (see ARCHITECTURE_DECISIONS.md)*  
*Related: ARCHITECTURE_DECISIONS.md, LINKED_DEVICES_BRAINSTORM.md, USER_PERMISSIONS_BRAINSTORM.md*
