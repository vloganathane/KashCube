# Private Sync: Multi-Device Without a Server
# KashCube Architecture Brainstorm

**Version:** 1.0  
**Date:** 10 March 2026  
**Status:** Brainstorm / RFC — not yet committed to roadmap  
**Author:** Engineering

---

## 1. The Fundamental Tension

KashCube's core promise: **"Your data lives on YOUR phone. Forever."**  
Multi-device sync breaks this if done wrong — data leaves the device.

The question is not *whether* to sync, but *how* to sync without violating the privacy contract.

**The rule: data may only travel between devices the user explicitly owns and authorises. It must never touch a server we operate.**

---

## 2. Real-World Use Cases (Who Actually Needs This)

| Persona | Device 1 | Device 2 | Sync Pattern |
|---------|----------|----------|--------------|
| Shop owner | Android phone (billing POS) | Tablet (reports/dashboard) | Live sync on same Wi-Fi |
| Couple | Wife's phone (household expenses) | Husband's phone (business) | Manual file share once a week |
| Freelancer | Phone (personal + income tracking) | Laptop (invoice creation, reporting) | Daily or on-demand |
| Business owner + CA | Owner's phone | CA's phone | Read-only export once a month |
| One person, two phones | Personal phone | Work phone | Nightly backup-based sync |

**Key insight:** Most use cases are **same-network (home/shop Wi-Fi)** or **manual/periodic**. Real-time cross-internet sync is the minority case — and the hardest to do privately.

---

## 3. Sync Mechanism Options

### Option A — LAN / Wi-Fi P2P Sync ⭐ Recommended Primary Path

**Concept:** Two devices on the same Wi-Fi network discover each other using mDNS, pair with a PIN confirmation, then exchange encrypted delta changes over a local TCP socket. Zero internet. Zero server.

```
Device A (phone)                    Device B (tablet)
     │                                     │
     │  mDNS announce _kashcube._tcp       │
     │ ──────────────────────────────────► │
     │                                     │  (user confirms PIN on both)
     │  TLS handshake (self-signed, pinned)│
     │ ◄──────────────────────────────────►│
     │                                     │
     │  Sync manifest: {last_sync_ts,      │
     │    table_checksums, device_id}      │
     │ ──────────────────────────────────► │
     │                                     │
     │  Delta response: rows changed       │
     │  since last_sync_ts, AES-256-GCM    │
     │ ◄──────────────────────────────────►│
     │                                     │
     │  Conflict resolution + apply        │
     │ ◄──────────────────────────────────►│
     │                                     │
     │  Sync complete: update timestamps   │
```

**Privacy score:** ⭐⭐⭐⭐⭐ (LAN-only, E2E encrypted, no server)  
**Real-time?** Yes (while on same Wi-Fi)  
**New packages needed:** `nsd` (mDNS service discovery), `dart:io` ServerSocket  
**Effort:** 3–4 sprints (significant but tractable)  
**Constraints:** Both devices must be on same Wi-Fi. No internet fallback.

---

### Option B — Wi-Fi Direct (No Router Needed) ⭐ Best for On-the-Go

**Concept:** Android Wi-Fi Direct lets two phones form a P2P connection without any router or internet. Perfect for syncing in a shop without relying on router infrastructure.

```
Device A  ←—— Wi-Fi Direct group owner ——→  Device B
         (no router, no internet, 250m range)
```

**Privacy score:** ⭐⭐⭐⭐⭐  
**Real-time?** While physically close  
**Package:** `flutter_p2p_connection` (wraps Android Wi-Fi Direct API)  
**Limitation:** Android-only (iOS doesn't support Wi-Fi P2P in background)  
**Effort:** 2–3 sprints. Best combined with Option A (auto-fallback to Wi-Fi Direct if not on same router)

---

### Option C — BYOC: Bring Your Own Cloud (Manual E2E) ⭐ Lowest Effort

**Concept:** KashCube exports an AES-256-GCM encrypted `.kashcube` file. User copies it to their own Google Drive / iCloud / Dropbox / Telegram Saved Messages / USB cable. User manually imports on second device.

**KashCube never touches the cloud. The user is the sync carrier.**

```
Device A  →  Export .kashcube  →  User's Google Drive  →  Import on Device B
              (AES-256-GCM)        (user moves file)       (enters passphrase)
```

**Privacy score:** ⭐⭐⭐⭐ (depends on user's cloud provider, but data is encrypted at rest)  
**Real-time?** No — manual, batch  
**New packages needed:** None (EncryptedBackupService already does this)  
**Effort:** 0 sprints — **already implemented**. Just needs UX polish + "Import on another device" onboarding flow.  
**Constraint:** Not real-time. Conflicts possible if both devices write between syncs.

---

### Option D — Bluetooth Sync (Delta Only)

**Concept:** Use Bluetooth Classic or BLE to transfer only the delta (changes since last sync) between nearby devices.

**Privacy score:** ⭐⭐⭐⭐⭐  
**Real-time?** No — tap to sync  
**Package:** `flutter_bluetooth_serial` or `flutter_blue_plus`  
**Speed:** BLE: ~1 Mbps → a 1 MB delta takes ~8s. Fine for daily sync.  
**Effort:** 2 sprints  
**Use case:** Tap phones to sync. Elegant UX. But Bluetooth pairing UX is clunky on Android.

---

### Option E — NFC Tap-to-Sync (Tiny Delta)

**Concept:** Tap phones together → exchange last N transactions (say last 50 rows). QR-code-style hand-off of a small delta.

**Privacy score:** ⭐⭐⭐⭐⭐  
**Capacity:** NFC NDEF: 32 KB max → good for ~50–100 transaction rows  
**Package:** `flutter_nfc_kit`  
**Use case:** "Quick sync" — e.g., a shop owner taps their phone to their accountant's phone to share today's transactions.  
**Effort:** 1.5 sprints  
**Limitation:** Android only (iOS NFC very restricted). Too small for a full DB sync.

---

### Option F — QR Code Batch (Offline, Tiny Data)

**Concept:** Device A shows a sequence of QR codes encoding encrypted delta. Device B scans them in sequence.

**Privacy score:** ⭐⭐⭐⭐⭐  
**Capacity:** One QR = ~2 KB (alphanumeric mode, error correction L). 10 QRs in sequence = ~20 KB.  
**Use case:** Share a single invoice or a day's transactions with no connectivity at all.  
**Effort:** 1 sprint  
**Packages:** `qr_flutter` (already planned) + `mobile_scanner` (already in pubspec)  
**Limitation:** Very limited data; no good for full DB sync. Good for single-entity sharing.

---

### Option G — Self-Hosted Relay (Zero-Knowledge, Advanced)

**Concept:** User optionally sets up a relay server (Raspberry Pi at home, or a privacy-focused VPS). KashCube connects to **their own** relay. Data is E2E encrypted before leaving the device — the relay only passes opaque blobs.

```
Device A  →  AES-256-GCM encrypt  →  User's Relay  →  Device B decrypts
                (relay cannot read)         │
                                   (stores for async delivery)
```

**Privacy score:** ⭐⭐⭐⭐ (trust depends on who runs the relay)  
**Real-time?** Yes (async delivery)  
**Self-hosted relay code:** ~200 lines Go/Node.js — we'd publish an open-source Docker image  
**Effort:** 4–5 sprints (client + server code + pairing UX)  
**Target audience:** Power users / tech-savvy business owners  
**Constraint:** We publish the relay code; user deploys it. KashCube app never has a hardcoded server address.

---

### Option H — Syncthing Integration (Power User Path)

**Concept:** Syncthing is an open-source, P2P file sync tool that already does exactly what we need — encrypted, no server, cross-platform. KashCube exposes the `.kashcube` auto-backup as a Syncthing-compatible file path.

```
Auto-backup: backups/auto_kash_cube_<ts>.db  →  Syncthing folder  →  Device B
```

User installs Syncthing separately. KashCube writes to a known folder. Syncthing handles the rest.

**Privacy score:** ⭐⭐⭐⭐⭐ (Syncthing is open-source, audited, no server)  
**Effort (KashCube side):** 0.5 sprints — just write backup to a user-configurable path  
**Limitation:** User must install and configure Syncthing. Not beginner-friendly.  
**Target audience:** Technical users / privacy enthusiasts (they already use Syncthing)

---

## 4. The Hardest Problem: Conflict Resolution

No matter which transport you choose, **conflict resolution is the real engineering challenge.**

### 4.1 Why KashCube's current schema cannot support multi-device sync

**Problem:** All 49 tables use `INTEGER PRIMARY KEY AUTOINCREMENT`.

```sql
-- Device A creates transaction id=1, id=2, id=3
-- Device B creates transaction id=1, id=2, id=3
-- Sync → id=1 on A ≠ id=1 on B → COLLISION
```

This is a **blocking architectural prerequisite** that must be solved before any sync mechanism can work.

### 4.2 Solution: Add `sync_id` (non-breaking migration)

Do not change the existing `id` column (it's embedded in FK relationships everywhere). Instead, add a `sync_id` column to all syncable tables:

```sql
ALTER TABLE transactions ADD COLUMN sync_id TEXT UNIQUE 
  DEFAULT (lower(hex(randomblob(16))));

ALTER TABLE invoices ADD COLUMN sync_id TEXT UNIQUE 
  DEFAULT (lower(hex(randomblob(16))));

-- Repeat for all 10 core tables
-- Existing rows get auto-generated UUIDs on migration
-- New rows get sync_id on INSERT (model layer)
```

**Sync logic uses `sync_id` as the universal row identity across devices.** The local `id` stays local — it's just a fast index. Foreign keys referencing local `id` are rebased to `sync_id`-based lookups on import.

**Migration:** v50+ (can be done incrementally per table)

---

### 4.3 Conflict Resolution Strategy per Entity Type

| Entity | Conflict likelihood | Strategy |
|--------|-------------------|----------|
| `transactions` | Low (each device captures its own SMS) | Last-`updated_at` wins |
| `invoices` | Medium (both devices might edit same invoice) | Last-`updated_at` wins + audit log |
| `credits` | Medium (payments from different devices) | Append-only payments sub-ledger; balances recomputed |
| `parties` | Low | Last-`updated_at` wins |
| `categories` | Rare | Last-`updated_at` wins |
| `settings` | Per-device (never sync) | Skip entirely |
| `budgets` | Low | Last-`updated_at` wins |
| `scheduled_payments` | Low | Last-`updated_at` wins |
| `purchase_bills` | Low | Last-`updated_at` wins |

**Key insight:** For financial data, **append-only patterns** (payment sub-ledger, stock movements, transaction log) naturally avoid most conflicts.

### 4.4 Soft-Delete Requirement

Multi-device sync requires **soft deletes everywhere**:

```sql
-- Instead of DELETE FROM transactions WHERE id = ?
-- Use:
UPDATE transactions SET deleted_at = CURRENT_TIMESTAMP WHERE id = ?

-- Sync propagates the deleted_at timestamp
-- On the receiving device: if deleted_at IS NOT NULL → hide from UI
-- GC: after 30 days post-delete, both devices agree to purge
```

Currently some tables already have `deleted_at`. All syncable tables need it.

---

## 5. Sync Data Model

### 5.1 Sync Manifest Schema (exchanged between devices at start of sync)

```json
{
  "device_id": "a3f9c2...",
  "device_name": "Loganathan's Phone",
  "app_version": "1.5.0",
  "db_version": 50,
  "last_sync_with": {
    "device_id": "b7e1d4...",
    "timestamp": "2026-03-10T18:30:00Z"
  },
  "table_manifests": {
    "transactions": { "count": 1240, "max_updated_at": "2026-03-10T17:00:00Z" },
    "invoices":     { "count": 87,   "max_updated_at": "2026-03-09T12:00:00Z" },
    "credits":      { "count": 34,   "max_updated_at": "2026-03-08T09:00:00Z" }
  }
}
```

### 5.2 Delta Request

```json
{
  "requesting_device": "b7e1d4...",
  "since_timestamp": "2026-03-09T06:00:00Z",
  "tables": ["transactions", "invoices", "parties", "credits"]
}
```

### 5.3 Delta Response (encrypted payload)

```json
{
  "encrypted": true,
  "algorithm": "AES-256-GCM",
  "iv": "...",
  "payload": "<base64_of_encrypted_delta_json>"
}
```

Decrypted payload:
```json
{
  "transactions": [
    { "sync_id": "...", "amount": 450.0, "type": "expense", "updated_at": "...", "deleted_at": null, ... }
  ],
  "invoices": [ ... ],
  ...
}
```

---

## 6. Pairing UX Design

The pairing flow must be secure and simple. Inspired by AirDrop + WhatsApp Web.

### Step 1: Initiating device (Device A)
- Go to Settings → Sync → "Add a Device"
- KashCube shows a **6-digit numeric PIN** + **QR code** containing `{ip, port, public_key, pin}`
- PIN expires in 2 minutes

### Step 2: Receiving device (Device B)
- Scan QR code **or** enter IP:port manually + PIN
- Verify PIN matches Device A display → user confirms on both devices
- Devices exchange public keys (ECDH key exchange for shared AES key)
- Device pair is stored in `sync_peers` table: `{peer_id, peer_name, peer_public_key, last_sync_at, auto_sync_enabled}`

### Step 3: First sync
- Full sync (all tables, all history)
- Progress bar; can take 30–60s for large DBs

### Step 4: Subsequent syncs
- Delta sync (only changes since last sync)
- Auto-triggers when both devices are on same Wi-Fi
- Manual trigger: Settings → Sync → "Sync Now"

### Unpair: Settings → Sync → [Device] → "Remove Device"  
→ Removes `sync_peer` entry; next sync attempt from that device is rejected.

---

## 7. Architecture Components Needed

### New Service: `SyncService`
```
lib/data/services/sync_service.dart
├── SyncServer         — mDNS announcement + TCP socket server (Device A)
├── SyncClient         — mDNS discovery + TCP socket client (Device B)  
├── SyncProtocol       — Manifest exchange, delta calculation, conflict resolution
├── SyncEncryption     — ECDH key exchange + AES-256-GCM encrypt/decrypt
└── SyncStateNotifier  — Riverpod provider for sync status UI
```

### New DB Table: `sync_peers`
```sql
CREATE TABLE sync_peers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  peer_id TEXT NOT NULL UNIQUE,           -- UUID of the paired device
  peer_name TEXT NOT NULL,                -- "Loganathan's Tablet"
  peer_public_key TEXT NOT NULL,          -- ECDH public key (base64)
  last_sync_at TEXT,                      -- ISO8601
  auto_sync_enabled INTEGER DEFAULT 1,   -- 0 or 1
  created_at TEXT DEFAULT (datetime('now'))
);
```

### DB Migration v50: Add `sync_id` to all core tables + `sync_peers` table + `deleted_at` where missing

### New Packages
| Package | Purpose | Network? |
|---------|---------|---------|
| `nsd` | mDNS service discovery (LAN) | LAN only |
| `pointycastle` or native crypto | ECDH key exchange + AES-GCM | None |
| `flutter_p2p_connection` | Wi-Fi Direct fallback | None |

---

## 8. Selective Sync (Privacy Within Sync)

Not every table needs to sync everywhere. Let users control granularity.

**Use case:** Business owner shares billing data with accountant's device but NOT personal transactions or loan tracker.

**Sync scope presets:**

| Preset | Tables included |
|--------|----------------|
| **Full** | Everything |
| **Business only** | invoices, purchase_bills, parties, categories, products |
| **Ledger only** | credits, parties |
| **Read-only mirror** | All tables, but receiving device cannot push changes back |

Stored per peer in `sync_peers.sync_scope TEXT DEFAULT 'full'`.

---

## 9. Prioritized Implementation Plan

### Phase 0: Foundation (prerequisite, ~1 sprint)
- [ ] Add `sync_id TEXT UNIQUE DEFAULT (lower(hex(randomblob(16))))` to all 10 core tables (DB v50)
- [ ] Add `deleted_at TEXT` to tables missing it
- [ ] Add `updated_at TEXT DEFAULT (datetime('now'))` triggers to all syncable tables
- [ ] Create `sync_peers` table
- [ ] Update all INSERT/UPDATE model methods to set `sync_id` and `updated_at`

### Phase 1: BYOC Polish (~0.5 sprint)
- Already working (`EncryptedBackupService`)
- Add "Import from file" prominent onboarding step
- Add "Share with another device" option that explains the "copy to Drive / share file" flow
- This ships as "Manual Sync" — sets user expectations correctly

### Phase 2: LAN Sync (~3 sprints)
- `SyncServer` + `SyncClient` using `dart:io` ServerSocket
- mDNS using `nsd` package
- Pairing UI (PIN QR flow)
- Delta protocol implementation
- Conflict resolution engine
- Sync status screen in Settings

### Phase 3: Wi-Fi Direct Fallback (~1 sprint)
- Fallback when devices are not on same router
- Reuse Phase 2 delta protocol; only transport changes

### Phase 4: Selective Sync + Read-Only Mode (~1 sprint)
- Scope presets UI
- Enforce on delta response: only include tables in scope
- Read-only peer: reject incoming changes from read-only devices

---

## 10. What NOT to Build

| Option | Why not |
|--------|---------|
| **Our own cloud relay** | Violates privacy promise; ongoing server maintenance; attack surface |
| **Google Drive / iCloud API integration** | Requires OAuth credentials stored in app; third-party cloud dependency |
| **Real-time sync over internet** | Needs a server. If user self-hosts (Option G), document it — don't ship it as default |
| **Shared access / multi-user on same account** | This is G3 from the gap analysis — architecture is fundamentally different from sync |
| **Sync to Tally / Zoho** | Export is fine; live sync is out of scope |

**Multi-user ≠ Multi-device sync.** Multi-device sync = same person, multiple devices, same data. Multi-user = different people, different roles, shared data. They require completely different architectures. Do not conflate them.

---

## 11. Privacy Guarantees Under Each Phase

| Phase | What data leaves the device? | Encrypted? | Who can read it? |
|-------|------------------------------|-----------|------------------|
| Phase 1 (BYOC) | User-initiated file to user's own cloud | Yes — AES-256-GCM | Only devices knowing passphrase |
| Phase 2 (LAN) | LAN socket, never leaves home/office network | Yes — AES-256-GCM | Only paired device |
| Phase 3 (Wi-Fi Direct) | Radio, 250m max range | Yes — AES-256-GCM | Only paired device |
| Phase 4 (Selective) | Subset of tables only | Yes | Only paired device, scoped |

**In all phases: KashCube servers see zero data. No telemetry. No relay.**

---

## 12. Open Questions

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | Should `sync_id` be UUID v4 (random) or ULID (sortable)? | **ULID** — sortable means delta queries can use `WHERE sync_id > ?` instead of timestamp comparisons |
| Q2 | What happens when DB schema version differs between devices (e.g., v49 vs v50)? | Refuse sync if `db_version_device_A ≠ db_version_device_B`. Show "Update KashCube on both devices first." |
| Q3 | Should Settings be excluded from sync entirely? | **Yes** — settings are per-device (theme, PIN, biometric). Never sync settings. |
| Q4 | How to handle invoice attachments (PDFs, photos) in sync? | Sync metadata only (file hash + filename). User explicitly taps "Sync attachments" for large files. |
| Q5 | Can a device be in both SERVER and CLIENT role simultaneously? | **Yes** — symmetric protocol. Both devices run Server+Client. The one that initiates is the "requester". |
| Q6 | What is the max delta payload size before we chunk it? | 4 MB per chunk (safe for TCP on LAN). Compress with gzip before encryption. |
| Q7 | Should we build LAN sync or BYOC-polish first? | **BYOC polish first** — zero risk, ships fast, satisfies 60% of use cases. LAN sync for Phase 2. |

---

## 13. Summary Recommendation

**Recommended path:**

```
Today:     BYOC already works — polish the UX, add "Import on new device" flow (0.5 sprint)
Sprint 1:  DB Foundation — sync_id + deleted_at + updated_at triggers on all tables (v50)
Sprint 2:  LAN Sync — mDNS discovery + TCP socket + delta protocol + pairing PIN UI
Sprint 3:  Wi-Fi Direct fallback + Selective Sync scopes
Future:    Self-hosted relay (open-source Docker image) for cross-internet use
Never:     Our own cloud relay
```

**The privacy story becomes stronger, not weaker:**  
Sync via LAN means your data never leaves your home network. This is *more private* than Vyapar's mandatory cloud sync. Make it a headline feature: **"Sync across your devices — zero cloud, zero server."**

---

*Last updated: 10 March 2026*  
*Next review: After Phase 0 (DB Foundation) is scoped*
