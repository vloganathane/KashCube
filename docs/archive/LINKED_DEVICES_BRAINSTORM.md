# Linked Devices: Primary-as-Authority, Permission-Scoped Sync
# KashCube Architecture Brainstorm

**Version:** 1.0  
**Date:** 12 March 2026  
**Status:** Brainstorm / RFC — not yet committed to roadmap  
**Author:** Engineering  
**Depends on:** `PRIVATE_SYNC_BRAINSTORM.md`, `USER_PERMISSIONS_BRAINSTORM.md`

---

## 1. The Core Idea

WhatsApp Web taught 2 billion users one pairing UX:

```
Primary (phone):  shows a QR code
Secondary (web):  scans QR → linked in 5 seconds
```

But WhatsApp Web is a **thin client** — close the phone and the web session dies. For KashCube, that's wrong. A cashier using a billing tablet cannot stop working when the shop owner walks away with their phone.

**The insight:** keep WhatsApp's *pairing UX*, but replace its thin-client execution with *full offline-capable local SQLite on every device*, gated by the primary's permission authority.

```
WhatsApp Web model         KashCube Linked Devices model
─────────────────────      ──────────────────────────────
Primary = relay server     Primary = auth authority + sync origin
Secondary = dumb display   Secondary = full local DB, permission-scoped
Phone offline → web dies   Phone offline → cashier works for N days
No RBAC                    Full RBAC per linked device
```

**Privacy rule is still absolute.** No KashCube server in this chain. The phone IS the server.

---

## 2. Mental Model: Three Device Archetypes

| Archetype | Who | Device | Connection need | Writes back? |
|-----------|-----|--------|-----------------|-------------|
| **Owner Mirror** | Same person | Tablet / laptop | Occasional (home Wi-Fi) | Yes — full bidirectional |
| **Staff Terminal** | Cashier / manager | Shared tablet at counter | Same-network Wi-Fi | Yes — within permission scope only |
| **Read-Only Viewer** | Accountant / CA | Their phone | Once a month (encrypted backup import) | Never |

All three can exist simultaneously. The owner's phone is always the primary. There is **one and only one primary device.** If the owner shifts to a new phone, primary migrates via a backup import — not a server transfer.

---

## 3. How Pairing Works (The WhatsApp-Inspired Flow)

### 3.1 On the Primary (Owner's Phone)

```
Settings → Linked Devices → "Link a Device"

┌─────────────────────────────────┐
│  Scan this QR on the new device │
│                                 │
│     ██████████████████████      │
│     ██  ██    ██  ████  ██      │
│     ██  ██████████  ██  ██      │  ← QR expires in 2 min
│     ██  ██  ████████    ██      │
│     ██████████████████████      │
│                                 │
│  Or enter pairing code: 7 4 2 9 │
└─────────────────────────────────┘

[Select permission level for this device]
  ○ Owner Mirror  (full access, bidirectional sync)
  ○ Manager       (full business, no settings)
  ○ Cashier       (create bills only, one business)
  ○ Custom        (configure manually)

[Link to staff member: Ravi Kumar ▾]   ← optional HRMS tie-in
```

The QR contains:
```json
{
  "pairing_token": "one-time token, expires 2min",
  "primary_device_id": "uuid-of-this-phone",
  "primary_public_key": "ECDH-base64",
  "connection": {
    "ip": "192.168.1.12",
    "port": 47200,
    "mdns_name": "_kashcube._tcp"
  },
  "permissions_preset": "cashier",
  "business_scope": [2]
}
```

### 3.2 On the Secondary (Tablet / Other Phone)

```
App install → first screen:

┌──────────────────────────────────┐
│  Welcome to KashCube             │
│                                  │
│  [Start fresh]                   │
│                                  │
│  [Link to existing device]  ←    │
│     Scan the QR on your          │
│     primary device               │
└──────────────────────────────────┘
```

Flow after scan:
```
Secondary scans QR
  → establishes TCP to primary (same Wi-Fi)
  → ECDH key exchange → shared AES-256-GCM session key
  → secondary sends its device_id + public_key
  → primary stores linked_devices record
  → primary issues device_session_token (signed with primary's private key)
  → primary sends: { session_token, permissions, initial_delta }
  → secondary stores session + full DB snapshot
  → secondary starts app in scoped mode
```

**From the user's perspective:** scan QR → app opens on tablet in Cashier view. 10 seconds total.

---

## 4. The Device Session Token

This is the key innovation. The session token is a **locally-signed authorization credential** — no server, no JWT authority, just the primary device's Ed25519 private key.

> ⚠️ Correction from original draft: HMAC-SHA256 is symmetric — both parties share the same key,
> so the secondary could forge tokens. Ed25519 is asymmetric: primary holds the private key (never
> leaves the device), secondary only has the public key — it can verify but never forge.

```
Token structure (serialized as JSON, signature appended):
{
  "token_id":           "uuid",
  "secondary_device_id": "uuid",
  "linked_user_id":      3,          // app_users.id; null = owner mode
  "linked_party_id":     12,         // parties.id for the staff member (optional)
  "permissions": {
    "business_scope":  [2],          // which business IDs this device can see
    "modules": {
      "transactions":  { "view": true,  "create": true,  "edit": false, "delete": false },
      "invoices":      { "view": true,  "create": true,  "edit": true,  "delete": false },
      "credits":       { "view": false, "create": false, "edit": false, "delete": false },
      "reports":       { "view": false, "create": false, "edit": false, "delete": false },
      "settings":      { "view": false, "create": false, "edit": false, "delete": false }
    }
  },
  "offline_grace_days": 7,
  "issued_at":   "2026-03-12T10:00:00",
  "expires_at":  null,               // null = no hard expiry; only revocation
  "primary_signature": "base64"      // HMAC-SHA256 of the above using primary's key
}
```

The secondary **verifies the signature on every app start** using the primary's cached public key. It cannot forge or elevate its own permissions without the primary's private key.

---

## 5. Offline Capability: The Grace Period Model

This is where we depart from WhatsApp Web fundamentally.

```
Timeline for a secondary device:

Day 0:    Paired. Full permission-scoped access. Last sync = now.
          │
Day 1-7:  Online or offline. Device uses local cached DB.
          Can create/edit within permission scope.
          Queues deltas for next sync.
          │
Day 7:    [If not synced in 7 days] → warning banner:
          "Sync with primary device to continue. 3 days left."
          │
Day 10:   [If still not synced] → device enters READ-ONLY mode.
          Can view data but cannot create or edit.
          "Link to primary to resume billing."
          │
Day 30:   [If still not synced] → soft lock.
          Shows unlink screen. Owner must re-pair from primary.
```

**Why this design?**
- Cashier in a shop works even if owner went home with their phone (7 days grace)
- Security: a stolen secondary device eventually becomes unusable without re-pairing
- No hard session expiry that breaks mid-shift

**Configurable per linked device** — owner can set grace to "Never" for a trusted home tablet or "1 day" for a cashier device.

---

## 6. Sync Architecture (Delta + Permission Filter)

### 6.1 Primary → Secondary ("push down")

Primary pushes only what the secondary is allowed to see:

```dart
// In SyncServer, when building delta for a secondary device:
DeltaResponse buildDelta(LinkedDevice device, DateTime since) {
  final perms = device.permissions;
  final delta = DeltaResponse();

  // Only include tables the device can view
  if (perms.modules['transactions']?.view == true) {
    delta.transactions = _repo.getModifiedSince(
      since: since,
      businessIds: perms.businessScope,   // ← scope filter
    );
  }
  if (perms.modules['invoices']?.view == true) {
    delta.invoices = _repo.getModifiedSince(since: since, businessIds: perms.businessScope);
  }
  // credits, inventory, etc. follow the same pattern
  // settings, personal transactions → NEVER sent to any secondary
  
  return delta;
}
```

**Personal data never crosses to a secondary device.** `business_id IS NULL` rows are owner-only.

### 6.2 Secondary → Primary ("push up")

Secondary queues writes locally, syncs back on connection. Primary validates each incoming row against the device's permission token before accepting:

```dart
// In SyncServer, when receiving delta from secondary:
void receiveSecondaryDelta(LinkedDevice device, List<SyncRow> rows) {
  for (final row in rows) {
    final table = row.table;
    final perm = device.permissions.modules[table];

    // Validate operation is within scope
    if (row.isNew     && (perm?.create != true)) { _reject(row, 'no create permission'); continue; }
    if (row.isUpdated && (perm?.edit   != true)) { _reject(row, 'no edit permission');   continue; }
    if (row.isDeleted && (perm?.delete != true)) { _reject(row, 'no delete permission'); continue; }

    // Validate business scope
    if (!device.permissions.businessScope.contains(row.businessId)) {
      _reject(row, 'outside business scope');
      continue;
    }

    // Accept and merge
    _mergeRow(row);
  }
}
```

This is the **server-side permission check** equivalent — done on the primary device, not a cloud server.

### 6.3 Conflict Resolution with Multi-User Writes

Primary is always the final authority. Conflict resolution table:

| Scenario | Resolution |
|----------|-----------|
| Same row edited on primary + secondary | Primary's version wins (last-updated_at) |
| Same row edited on two staff secondaries | Higher `updated_at` wins; loser gets notification |
| Secondary creates a row, primary deletes the same logical record | Primary's delete propagates |
| Secondary writes outside its permission scope | Primary rejects; secondary rolls back that row |
| Primary revokes secondary mid-delta | Secondary receives revocation event; session terminates |

---

## 7. Revocation and the "Unlink" Flow

### 7.1 Primary-initiated revocation (owner unlinking a device)

```
Settings → Linked Devices → [Ravi's Tablet] → Unlink

Primary:
  1. Sets linked_devices.revoked_at = NOW()
  2. Broadcasts sync event: { type: 'session_revoked', device_id: '...' }

Secondary (when online):
  3. Receives revocation event
  4. Deletes device_session table
  5. Deletes all business data from local SQLite
  6. Shows: "This device has been unlinked by the owner."
  7. Returns to "Link to existing device" screen

Secondary (while offline):
  3. Does not know immediately
  4. On next sync attempt → receives revocation → same steps 4-7 above
  5. Offline grace period does NOT protect against explicit revocation:
     after grace period expires, device locks regardless
```

**Data wipe on unlink:** Only business data is wiped. If the secondary was also used for personal KashCube data, personal data is preserved (but in practice, secondaries should never have personal data per the isolation rule).

### 7.2 Secondary-initiated unlink

```
Settings → About → Unlink this device

Secondary:
  1. Sends unlink_request to primary (if online) OR queues it
  2. Deletes device_session + business data locally
  3. Clears to fresh state

Primary (on receiving unlink_request):
  1. Sets linked_devices.revoked_at = NOW()
  2. Keeps the linked_devices record (for audit history)
```

---

## 8. DB Schema Additions (v58+)

### On Primary Device

```sql
-- Track all linked secondary devices
CREATE TABLE linked_devices (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id         TEXT    NOT NULL UNIQUE,       -- UUID of secondary
  device_name       TEXT    NOT NULL,              -- "Ravi's Tablet"
  device_type       TEXT,                          -- 'phone' | 'tablet' | 'desktop'
  device_os         TEXT,                          -- 'android' | 'ios' | 'windows'
  
  -- Who this device acts as
  user_id           INTEGER,                       -- FK app_users(id); NULL = owner mirror
  linked_party_id   INTEGER,                       -- FK parties(id) for HRMS correlation
  
  -- Crypto
  secondary_public_key TEXT NOT NULL,              -- ECDH public key of secondary
  session_token     TEXT,                          -- last issued signed token
  
  -- Permissions (snapshot at time of linking; refreshed on each sync)
  permission_scope  TEXT NOT NULL DEFAULT '{}',    -- JSON blob of perm set
  business_scope    TEXT NOT NULL DEFAULT '[]',    -- JSON array of business IDs
  
  -- Lifecycle
  offline_grace_days INTEGER DEFAULT 7,
  last_sync_at      TEXT,
  revoked_at        TEXT,                          -- NULL = active
  created_at        TEXT DEFAULT (datetime('now')),
  
  FOREIGN KEY (user_id)        REFERENCES app_users(id) ON DELETE SET NULL,
  FOREIGN KEY (linked_party_id) REFERENCES parties(id)  ON DELETE SET NULL
);

-- Sync queue for outbound events (revocations, permission updates)
CREATE TABLE sync_outbox (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  target_device_id TEXT,            -- NULL = broadcast to all
  event_type  TEXT NOT NULL,        -- 'delta' | 'revoke' | 'permission_update' | 'force_wipe'
  payload     TEXT,                 -- JSON
  created_at  TEXT DEFAULT (datetime('now')),
  delivered_at TEXT                 -- NULL = pending
);
```

### On Secondary Device

```sql
-- Stores the session this device was issued
CREATE TABLE device_session (
  id                 INTEGER PRIMARY KEY,          -- always 1 row max
  this_device_id     TEXT NOT NULL,
  primary_device_id  TEXT NOT NULL,
  primary_public_key TEXT NOT NULL,                -- for signature verification
  session_token      TEXT NOT NULL,                -- the signed token blob
  permission_scope   TEXT NOT NULL,                -- local cache of permissions
  business_scope     TEXT NOT NULL,
  offline_grace_days INTEGER NOT NULL DEFAULT 7,
  issued_at          TEXT NOT NULL,
  last_sync_at       TEXT,
  is_read_only_override INTEGER DEFAULT 0          -- set to 1 when grace expired
);
```

### Shared (Both Devices)

```sql
-- Already in PRIVATE_SYNC_BRAINSTORM.md — adding sync_id to all core tables
-- Also needed: updated_at + deleted_at on all syncable tables

-- Extend app_users (from USER_PERMISSIONS_BRAINSTORM.md) with device awareness
ALTER TABLE app_users ADD COLUMN default_device_id TEXT;
-- The preferred device for this user; shown in UserSelectionScreen
```

---

## 9. Full Startup Flow (Combined Auth + Sync)

```
App opens on secondary device
          │
    ┌─────▼──────────────────────────────────┐
    │ device_session table has valid session? │
    └─────┬──────────────────────────────────┘
          │ NO                  YES
          ▼                      ▼
   OnboardingScreen        Check grace period
   "Link a device"              │
          │               Within grace?
          │               YES ──────────────────────────────────► Load app
          │                                                        with permission_scope
          │               NO (grace expired)
          │                    ▼
          │               Show banner: "Sync required"
          │               App in read-only mode
          │                    │
          │               Try to reach primary (mDNS)
          │                    │
          │               Found?
          │               YES → sync → refresh token → full access restored
          │               NO  → remain read-only until primary found
          │
          ▼
   Scanner Screen
   (scan QR from primary)
          │
   ECDH handshake
   Token received
   Initial delta pulled
          │
          ▼
   App starts → Cashier/Manager view
```

---

## 10. UX Screens Required

### On Primary (Owner's Phone)

| Screen | Location | Description |
|--------|----------|-------------|
| `LinkedDevicesScreen` | Settings → Linked Devices | List of all linked devices; shows name, type, last sync, status (Active / Offline / Revoked) |
| `LinkDeviceScreen` | Settings → Linked Devices → "Link a Device" | QR generator + permission selector + staff tie-in |
| `DeviceDetailScreen` | Tap any linked device | Last sync time, permission summary, "Refresh Permissions", "Unlink" |
| `LinkedDevicePermissionsScreen` | From DeviceDetailScreen | Fine-grained CRUD per module (same UI as `UserPermissionsScreen` from user perms doc) |

### On Secondary (Tablet / Other Phone)

| Screen | When | Description |
|--------|------|-------------|
| `LinkDeviceOnboardingScreen` | Fresh install, no session | "Link to your primary device" with QR scanner + manual code entry |
| `GraceExpiryBannerWidget` | When grace < 3 days | Yellow banner: "Sync in N days or lose billing access" |
| `ReadOnlyModeBannerWidget` | When grace expired | Red banner: "Billing paused — connect to primary to resume" |
| `SessionRevokedScreen` | On receiving revocation | "Owner has unlinked this device" with "Link again" CTA |

### (Unchanged) Settings → Security path on primary

```
Settings
└── Security
    ├── App Lock (PIN / Biometric)          ← existing
    ├── Cashier Mode                        ← Phase U1
    └── Linked Devices                      ← new (this doc)
            └── [Device list]
```

---

## 11. Integration Map: Sync + Permissions + HRMS

This is where the three brainstorm docs intersect:

```
                    ┌──────────────────┐
                    │  Primary Phone   │
                    │  (Owner)         │
                    │                  │
                    │  ┌────────────┐  │
                    │  │ app_users  │  │  ← USER_PERMISSIONS_BRAINSTORM
                    │  │ permissions│  │
                    │  └────────────┘  │
                    │                  │
                    │  ┌────────────┐  │
                    │  │  parties   │  │  ← HRMS (staff members)
                    │  │  (staff)   │  │
                    │  └────────────┘  │
                    │                  │
                    │  ┌────────────┐  │
                    │  │  linked_   │  │  ← THIS DOC
                    │  │  devices   │  │
                    │  └────────────┘  │
                    └──────┬───────────┘
                           │ LAN / Wi-Fi Direct
                    ┌──────▼───────────┐
                    │  Secondary       │
                    │  (Ravi's Tablet) │
                    │                  │
                    │  ┌────────────┐  │
                    │  │device_     │  │
                    │  │session     │  │
                    │  │(perms baked│  │
                    │  │ into token)│  │
                    │  └────────────┘  │
                    │                  │
                    │  ┌────────────┐  │
                    │  │ Local DB   │  │
                    │  │ (scoped    │  │
                    │  │  subset)   │  │
                    │  └────────────┘  │
                    └──────────────────┘

Linking a staff member creates all three records in one flow:
  parties (Ravi, cashier)
    └── app_users (Ravi, role: cashier, PIN: 1234)
          └── linked_devices (Ravi's Tablet, permissions from app_user)
```

**The UX story:** "Ravi is already a staff member. Tap 'Grant App Access' → generates a one-time QR → Ravi scans on his tablet → done. His tablet shows only billing for Business A."

---

## 12. Owner Mirror Mode (Same Person, Multiple Devices)

When the owner links their own second device (e.g. home tablet):

```
Link a Device → Owner Mirror

• Full bidirectional sync
• All data including personal transactions
• No permission restrictions
• No grace period expiry (trust = maximum)
• Both devices can initiate sync (symmetric roles for this special case)
```

This is the "pure sync" case from `PRIVATE_SYNC_BRAINSTORM.md` — the permission layer is effectively disabled (Permission.full for all modules).

**Important:** Even in mirror mode, the original primary is still the authority. If there is a conflict, primary wins. If primary is ever decommissioned (device broken), run "Transfer Primary" wizard which requires biometric + re-signing all linked device tokens.

---

## 13. Security Analysis

| Threat | Mitigation |
|--------|----------|
| Secondary forges elevated session token | Token is HMAC-signed by primary's private key; secondary cannot forge without the private key |
| Attacker intercepts pairing QR | QR contains one-time `pairing_token` (1 min expiry); replay blocked |
| Secondary writes outside permission scope | Primary validates all incoming deltas against the device's stored permission_scope |
| Stolen secondary device | Grace period expires → read-only → then locks; owner can revoke instantly from primary |
| Primary device lost / stolen | Owner uses recovery PIN / biometric on replacement device + backup import; all secondaries need re-pairing |
| Eavesdropping on LAN sync | All sync traffic is AES-256-GCM encrypted with ECDH-derived per-session key |
| MITM during QR pairing | primary_public_key in QR + confirmation of pairing_token displayed on both screens protects against MITM |
| Staff escalates own permissions locally | Permissions are baked into the signed token; local modification doesn't pass signature verification |

### Key Cryptographic Operations (all local, no HSM needed)

| Operation | Algorithm | KashCube notes |
|-----------|-----------|---------------|
| Key exchange | ECDH (P-256) | Per-pairing, per-device |
| Session encryption | AES-256-GCM | Per-sync-session derived key |
| Token signing | Ed25519 (asymmetric) | Primary signs with private key; stored in FlutterSecureStorage |
| PIN hashing | Argon2id (via `cryptography` pkg) | Upgrade from current plain SHA-256 for user PINs |
| Token verification | Ed25519 verify | Secondary verifies with cached primary *public* key; cannot forge |

**Android Keystore integration:** Primary's signing key should be stored in Android Keystore (hardware-backed on devices with a secure element). The key never leaves the device; signing happens inside the keystore. Use `FlutterSecureStorage` + `local_auth_android` infrastructure already in `pubspec.yaml`.

---

## 14. What NOT to Build

| Idea | Why not |
|------|---------|
| KashCube relay server for cross-internet linking | Violates privacy promise. Use `PRIVATE_SYNC_BRAINSTORM.md` Option G (self-hosted relay) for power users |
| Secondary can be a primary for a third device | No cascading authority. Primary is always the origin phone. |
| Shared primary (two people co-own the authority) | Dual-authority is complex (split-brain consensus). Multi-owner = business partner = different architecture |
| Biometric auth on secondary | Android biometric is per-device, not per-user within an app |
| Primary pushes code/updates to secondary | App updates go through Play Store. Sync is data-only. |
| "Continue on phone" from desktop (reverse shell) | Out of scope; violates privacy; we're not building a desktop app (yet) |

---

## 15. Open Questions

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | What is the unit of "primary"? The device, or the data? | **The device.** If owner gets a new phone, run "Transfer Primary" wizard. |
| Q2 | Can a secondary upgrade to primary? | Only via explicit "Transfer Primary" on both devices simultaneously (like a WhatsApp account transfer). |
| Q3 | Maximum number of linked devices? | Soft limit: 5 (free tier), 10 (business tier). Practical: limited by RAM on primary during sync. |
| Q4 | Does primary need to be online to pair a new secondary? | **Yes** — pairing requires the ECDH handshake. But once paired, offline operation is independent. |
| Q5 | What if two staff members use the same linked device (shared tablet)? | Two options: (a) one app_user per device, (b) UserSelectionScreen on the secondary. Option (b) is better UX — see Phase L2. |
| Q6 | How are permission changes propagated to a secondary currently offline? | Permission update queued in `sync_outbox`. Delivered next time secondary reconnects. Until then, old permissions apply. |
| Q7 | Can primary push a "permission revoke" that makes secondary immediately read-only? | Yes — `sync_outbox` event `force_readonly`. Secondary checks inbox on every sync. |
| Q8 | Does sync need to be continuous, or on-demand? | **On-demand trigger** (user taps sync or app comes to foreground) + **auto on same Wi-Fi** (mDNS discovery). No background service. |

---

## 16. Implementation Phases

### Phase L0: Foundation (~1 sprint)
Prerequisites from parent docs:
- `sync_id` on all core tables (from `PRIVATE_SYNC_BRAINSTORM.md` Phase 0)
- `app_users` + `user_permissions` tables (from `USER_PERMISSIONS_BRAINSTORM.md` Phase U0)
- Android Keystore key generation for primary signing key

New work:
- [ ] `linked_devices` table (DB v58)
- [ ] `device_session` table (on secondary)
- [ ] `sync_outbox` table
- [ ] `LinkedDevice` model + `LinkedDeviceRepository`
- [ ] `DeviceSession` model + `DeviceSessionRepository`
- [ ] ECDH key generation + HMAC token signing/verification service
- [ ] `linkedDevicesProvider` in Riverpod

### Phase L1: Pairing + Owner Mirror (~2 sprints)
- [ ] `LinkDeviceScreen` (QR generator on primary)
- [ ] `LinkDeviceOnboardingScreen` (QR scanner on secondary; fresh install flow)
- [ ] TCP pairing handshake (reuses `SyncServer`/`SyncClient` from private sync Phase 2)
- [ ] Token issuance + signature verification
- [ ] Initial full delta push (primary → secondary)
- [ ] `LinkedDevicesScreen` + `DeviceDetailScreen`
- [ ] Owner mirror mode (full sync, no permission restriction)
- [ ] Revocation flow + data wipe on secondary

### Phase L2: Staff Terminal Mode (~2 sprints)
- [ ] Permission-scoped delta (primary sends only allowed tables/businesses)
- [ ] Secondary sender validation on incoming delta
- [ ] `permission_scope` enforcement on secondary (provider layer)
- [ ] Grace period countdown + `GraceExpiryBannerWidget`
- [ ] `ReadOnlyModeBannerWidget` + soft lock
- [ ] `SessionRevokedScreen`
- [ ] HRMS integration: "Grant App Access" → QR from StaffDetailScreen
- [ ] UserSelectionScreen on secondary (for shared-tablet scenario – Q5)

### Phase L3: Permission Live-Update + Audit (~1 sprint)
- [ ] `sync_outbox` events: `permission_update`, `force_readonly`, `revoke`
- [ ] Primary pushes permission updates to secondary on next sync
- [ ] Audit trail: `created_by_user_id` on transactions / invoices
- [ ] `LinkedDevicePermissionsScreen` (fine-grained edit from primary)
- [ ] "Transfer Primary" wizard (phase for future)

---

## 17. Comparison Matrix: How This Differs From Existing Models

| Feature | WhatsApp Web | Google Drive sync | KashCube Linked Devices |
|---------|-------------|-------------------|------------------------|
| Primary offline → secondary works? | ❌ No | ✅ Yes | ✅ Yes (grace period) |
| Per-device permissions | ❌ No | ❌ No | ✅ Yes (RBAC) |
| Data encrypted in transit | ✅ | ✅ | ✅ (AES-256-GCM) |
| Data on cloud server | ❌ (Meta's) | ✅ (Google's) | ❌ Never |
| Fine-grained data scope | ❌ | ❌ | ✅ per module + business |
| Revoke device access | ✅ | Indirect | ✅ + data wipe |
| Works on local LAN | ❌ | ❌ | ✅ (primary use case) |
| Staff vs owner distinction | ❌ | ❌ | ✅ core feature |
| Audit trail (who did what) | ❌ | ❌ | ✅ Phase L3 |

---

## 18. Summary

```
The mental model in one sentence:
"Your phone is the bank vault. Other devices are safety deposit box keys —
 each key only opens the boxes the owner gave it access to."

Recommended build order:
  Phase L0  → Crypto + DB foundation (prerequisite)
  Phase L1  → Owner mirror (same-person multi-device; the easy win)
  Phase L2  → Staff terminal (the competitive differentiator)
  Phase L3  → Live permission updates + audit trail
  Never     → Cloud relay with user directory
  Future    → "Transfer Primary" when owner changes phone
```

**The competitive story:**  
"Ravi works the billing counter. He has your app on the shop tablet. He can create invoices and bills. He cannot see your loan tracker, personal expenses, or other businesses. When you unlink his tablet, every business record on it is wiped. Your data stays yours — and so does your privacy from your own staff."

---

*Last updated: 12 March 2026*  
*Next review: After PRIVATE_SYNC Phase 2 (LAN sync) is implemented*  
*Related docs: `PRIVATE_SYNC_BRAINSTORM.md`, `USER_PERMISSIONS_BRAINSTORM.md`, `HRMS_STAFF_SPEC.md`*
