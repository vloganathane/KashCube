# KashCube — P2P LAN Sync Specification

**Version:** 1.0  
**Date:** 17 March 2026  
**Status:** Approved — ready for implementation  
**Reference material:** `sample/wifi-mirror/` — Bonsoir mDNS pattern, conditional import pattern, TXT-record parsing, IP detection utility  

---

## Table of Contents

1. [Overview](#1-overview)
2. [Design Principles](#2-design-principles)
3. [Package Inventory](#3-package-inventory)
4. [Architecture Overview](#4-architecture-overview)
5. [Identity & Pairing](#5-identity--pairing)
6. [Network Discovery (mDNS)](#6-network-discovery-mdns)
7. [Transport Layer](#7-transport-layer)
8. [Authentication & Request Security](#8-authentication--request-security)
9. [HELLO Handshake & Schema Gating](#9-hello-handshake--schema-gating)
10. [Sync Protocol](#10-sync-protocol)
11. [Conflict Resolution](#11-conflict-resolution)
12. [Deletion Handling](#12-deletion-handling)
13. [Invoice Events (Audit Log)](#13-invoice-events-audit-log)
14. [Background Sync](#14-background-sync)
15. [Database Migration — v69](#15-database-migration--v69)
16. [File Structure](#16-file-structure)
17. [Riverpod Providers](#17-riverpod-providers)
18. [Implementation Order](#18-implementation-order)
19. [Open Risks & Mitigations](#19-open-risks--mitigations)

---

## 1. Overview

KashCube P2P sync allows two Android devices to exchange financial data (transactions, invoices, credits, parties, etc.) over the **same local Wi-Fi network** — with no cloud servers, no relay, no internet required. All data stays on-device; only trusted paired devices exchange rows directly, device-to-device.

### Key goals

| Goal | Decision |
|---|---|
| Fully offline | ✅ LAN-only, no internet |
| Privacy-first | ✅ HMAC-signed requests, no external service |
| Resilient to interruption | ✅ Cursor-resumable, ephemeral connections |
| No silent data corruption | ✅ State machine for invoice status, LWW for all other fields |
| Audit trail | ✅ `invoice_events` append-only log |
| Business-scoped | ✅ Sync filtered per `business_id` |

---

## 2. Design Principles

1. **Ephemeral connections** — Device A discovers Device B, opens HTTP connection, syncs, closes. No persistent socket. Avoids OS background-kill issues.
2. **Foreground-first** — Primary sync trigger is app-foreground and explicit user action. WorkManager is secondary.
3. **LWW is the default** — Last-Write-Wins using `updated_at`. Applied to all fields except `invoice.status`.
4. **State machine for status** — Invoice/quote status advances only forward (no going back from paid to draft).
5. **Soft deletes** — `deleted_at` is already uniform across all tables. Deleted rows sync like normal updates.
6. **Watermark-based delta** — No outbox consumer needed. Query is `WHERE updated_at > last_synced_at`. `sync_outbox` table stays dormant.
7. **Fiscal-year scope** — First sync pulls current FY rows only. Full history import is a separate user-initiated action.

---

## 3. Package Inventory

All packages below are **already in `pubspec.yaml`** unless flagged.

| Package | Version | Role in sync |
|---|---|---|
| `bonsoir` | ^5.1.2 | mDNS broadcast + discovery |
| `shelf` | ^1.4.2 | HTTP server on both devices |
| `shelf_router` | ^1.1.4 | Route `/hello`, `/sync/push`, `/sync/pull` |
| `shelf_web_socket` | ^3.0.0 | Not needed for sync (web-only concern) |
| `crypto` | ^3.0.6 | HMAC-SHA256 request signing |
| `cryptography` | ^2.7.0 | HKDF shared-secret derivation during pairing |
| `workmanager` | ^0.6.0 | Periodic background sync (Android) |
| `qr_flutter` | ^4.1.0 | Show own identity QR during pairing |
| `mobile_scanner` | ^6.0.4 | Scan peer QR during pairing |
| `path_provider` | ^2.1.0 | (existing) |
| **`device_info_plus`** | **^10.1.0** | **⚠️ ADD to pubspec** — read device model for `peer_name` |

`device_info_plus` is the only missing package. Add one line to `pubspec.yaml`:
```yaml
  device_info_plus: ^10.1.0
```

---

## 4. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  DEVICE A  (foreground)                                              │
│                                                                       │
│  ┌──────────────┐   ┌──────────────────┐   ┌────────────────────┐  │
│  │  Bonsoir     │   │  SyncHttpServer  │   │  SyncHttpClient    │  │
│  │  Broadcast   │   │  shelf + router  │   │  dart:io HttpClient│  │
│  │  _kashcube   │   │  port: OS-assign │   │                    │  │
│  │  ._tcp       │   │  /hello          │   │  POST /hello       │  │
│  └──────────────┘   │  /sync/pull      │   │  POST /sync/push   │  │
│                     │  /sync/push      │   │  POST /sync/pull   │  │
│                     └──────────────────┘   └────────────────────┘  │
│                              │                         │             │
│                      ┌───────▼─────────────────────────▼──────┐    │
│                      │           P2pMergeService               │    │
│                      │   LWW + State Machine + Dedup           │    │
│                      └──────────────┬──────────────────────────┘    │
│                                     │                                │
│                           ┌─────────▼──────────┐                   │
│                           │      SQLite         │                   │
│                           │  trusted_peers      │                   │
│                           │  sync_watermarks    │                   │
│                           │  invoice_events     │                   │
│                           │  + all data tables  │                   │
│                           └────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
              ↕  Wi-Fi LAN (mDNS + HTTP/JSON)
┌─────────────────────────────────────────────────────────────────────┐
│  DEVICE B  (same structure, symmetric)                               │
└─────────────────────────────────────────────────────────────────────┘
```

Both devices are **equal peers** — no primary/secondary distinction. Both run a server; both can act as client.

---

## 5. Identity & Pairing

### Device identity

Each device already has an **Ed25519 key pair** managed by `lib/data/services/identity_service.dart`. The public key hex string serves as the stable `device_id`.

```dart
final myDeviceId = await IdentityService.instance.getIdentityId();
// e.g. "a3f8c21d9e4b7..." (32-byte hex, always same per install)
```

### Device name

On first pairing, call `device_info_plus` once to read the device model string (e.g., "Redmi Note 12") and store it as `my_device_name` in the `settings` table. This name is sent in the HELLO handshake as `device_name`.

```dart
final info = await DeviceInfoPlugin().androidInfo;
final name = info.model; // "Redmi Note 12"
```

### Pairing flow (QR code)

```
Device A (shows QR)                     Device B (scans QR)
─────────────────────────────────────────────────────────────────
1. Show QR of:
   {
     "device_id": "a3f8c21d...",
     "device_name": "Ravi's Redmi",
     "app_version": "1.4.2",
     "schema_version": 68
   }

                                        2. Scan QR → parse JSON
                                        3. POST /hello to Device A's IP:port
                                           (obtained fr mDNS TXT record)
                                        4. A verifies B's HELLO response
                                        5. Both store each other in trusted_peers
```

QR display: `qr_flutter` (already in pubspec).  
QR scan: `mobile_scanner` (already in pubspec).

### Shared secret derivation (after pairing)

```
shared_secret = HKDF-SHA256(
  ikm   = own_private_key_bytes XOR peer_public_key_bytes,
  salt  = "kashcube-p2p-v1",
  info  = sort([own_device_id, peer_device_id]).join(":"),
  length = 32 bytes
)
```

Both devices independently compute the same `shared_secret` without transmitting it. Store encrypted in `trusted_peers.shared_secret_enc` (encrypted with the app's local key store).

---

## 6. Network Discovery (mDNS)

Adapted from `sample/wifi-mirror/lib/data/services/network_discovery_service.dart` — the conditional import pattern and TXT record approach are reused directly.

### Service advertisement

```
Service type:  _kashcube._tcp
Service name:  <device_name>   (e.g., "Ravi's Redmi")
Port:          OS-assigned (stored in TXT record)
TXT records:
  device_id    = "a3f8c21d..."
  device_name  = "Ravi's Redmi"
  sync_port    = "51234"
  schema_ver   = "68"
  app_ver      = "1.4.2"
```

### Why port in TXT record?

An OS-assigned port (port 0) avoids conflicts. The actual bound port is stored in the TXT record so peers can connect without hardcoding a port number. wifi-mirror uses `port: 50123` hardcoded; KashCube uses dynamic ports to avoid conflicts on devices that run multiple apps.

### Platform support

| Platform | mDNS Library | Notes |
|---|---|---|
| Android | Bonsoir (NsdManager) | Full support |
| iOS | Bonsoir (Bonjour) | Full support |
| macOS | Bonsoir (Bonjour) | Dev/test use |
| Web | Not supported | KashCube is mobile-only |

### Conditional import pattern (from wifi-mirror)

```dart
// p2p_discovery_service.dart
import 'p2p_discovery_service_stub.dart'
    if (dart.library.io) 'p2p_discovery_service_io.dart'
    as platform_impl;
```

`_io.dart` contains real Bonsoir code; `_stub.dart` returns empty streams (no-op for web/test).

---

## 7. Transport Layer

**Decision: HTTP + JSON over `shelf` (already in pubspec).**

Both devices start a `shelf` HTTP server on app foreground. The server binds to `0.0.0.0:0` (OS-assigns port), then broadcasts the port in mDNS TXT records.

### Why HTTP over raw TCP?

- `shelf` is already a dep (was used by the removed web server).
- HTTP gives structured request/response with status codes — easier error handling than raw framing.
- Retries are trivial (`dart:io HttpClient` has built-in retry support).
- Better debuggability (Charles Proxy, curl, etc.).

### Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/hello` | Exchange identity + schema version check |
| `GET` | `/sync/tables` | Discovery: list of tables with `row_count` + `latest_updated_at` |
| `POST` | `/sync/pull` | Request rows newer than watermark |
| `POST` | `/sync/push` | Send rows to peer for merge |

### Request/Response format

All bodies are JSON. Content-Type: `application/json`.

**Pull request:**
```json
{
  "table": "transactions",
  "since_updated_at": "2026-04-01T00:00:00.000Z",
  "cursor_id": null,
  "business_id": "biz_xyz",
  "limit": 100
}
```

**Pull response:**
```json
{
  "table": "transactions",
  "rows": [ {...}, {...} ],
  "next_cursor_id": "txn_abc123",
  "is_final": false
}
```

**Push request:**
```json
{
  "table": "transactions",
  "rows": [ {...}, {...} ],
  "is_final": true
}
```

**Push response:**
```json
{
  "accepted": 47,
  "skipped": 3,
  "errors": []
}
```

### Connection lifecycle

```
1. App enters foreground → start SyncHttpServer (shelf, port 0)
2. Get assigned port → update Bonsoir TXT record
3. Foreground sync: discover peers → for each paired peer:
   a. POST /hello
   b. GET /sync/tables
   c. For each table: POST /sync/pull (paginated)
   d. For each table: POST /sync/push (paginated)
   e. Update sync_watermarks
4. App goes background → server.close()
```

No persistent connection. Each sync is a fresh HTTP session.

---

## 8. Authentication & Request Security

Every request from Device A to Device B must be signed. Device B rejects unsigned or tampered requests.

### HMAC-SHA256 request signing

```
Signature = HMAC-SHA256(
  key     = shared_secret,
  message = HTTP_METHOD + "\n" + PATH + "\n" + TIMESTAMP + "\n" + SHA256(body_bytes)
)
```

Headers on every request:
```
X-Kash-Device-Id: <sender_device_id>
X-Kash-Ts: <unix_timestamp_seconds>       // reject if abs(now - ts) > 30s
X-Kash-Sig: <hex(HMAC-SHA256)>
```

### Server-side validation

```dart
// In shelf middleware
1. Check X-Kash-Device-Id is in trusted_peers
2. Load shared_secret for that peer
3. Recompute signature
4. Compare with X-Kash-Sig (constant-time compare)
5. Check timestamp skew ≤ 30 seconds
6. Reject with 401 on any failure — no body in error response
```

Requests from unknown device IDs return `403 Forbidden` immediately without disclosing any information.

---

## 9. HELLO Handshake & Schema Gating

### HELLO request body

```json
{
  "type": "HELLO",
  "device_id": "a3f8c21d...",
  "device_name": "Ravi's Redmi Note 12",
  "app_version": "1.4.2",
  "schema_version": 68,
  "min_accepted_schema": 65,
  "business_ids": ["biz_xyz", "biz_abc"]
}
```

### HELLO response

```json
{
  "type": "HELLO_ACK",
  "device_id": "b9d1e3f2...",
  "device_name": "Priya's Galaxy A54",
  "schema_version": 68,
  "min_accepted_schema": 65,
  "business_ids": ["biz_xyz"],
  "sync_tables": ["transactions", "invoices", "parties", ...]
}
```

### Schema gating rules

| Condition | Action |
|---|---|
| `remote.schema_version > local.schema_version` | Abort — "Please update KashCube to sync" |
| `remote.schema_version < local.min_accepted_schema` | Abort — "Peer device needs to update KashCube" |
| Both versions compatible | Proceed → compute `business_ids` intersection |

`min_accepted_schema` = current DB version - 3 (by convention — supports 3 versions of backward compat). When DB bumps to 69, `min_accepted_schema` = 66.

### Business-scoped sync

Only tables linked to a `business_id` in the intersection of `business_ids` are synced. A shop owner with two businesses only shares the relevant one with their accountant's device if both list that business ID.

---

## 10. Sync Protocol

### Syncable tables

```
transactions, credits, credit_payments, loans, parties, accounts,
categories, invoices, invoice_items, quotes, quote_items,
item_catalog, businesses, purchase_bills
```

Tables excluded from sync: `settings`, `trusted_peers`, `sync_watermarks`, `invoice_events` (events sync separately), `sync_outbox` (dormant), `my_identity`.

### Watermark-based delta

```sql
-- Pull rows from a table that peer hasn't seen yet
SELECT * FROM transactions
WHERE updated_at > ?       -- last_synced_at for this peer+table
  AND business_id = ?
ORDER BY updated_at ASC, id ASC
LIMIT 100;
```

On success, update `sync_watermarks` with the `MAX(updated_at)` of rows actually merged.

### Cursor-resumable pagination

```json
// First request: cursor_id = null
{ "since_updated_at": "2026-01-01T00:00:00Z", "cursor_id": null, "limit": 100 }

// Subsequent: cursor_id = last row's primary key from previous response
{ "since_updated_at": "2026-01-01T00:00:00Z", "cursor_id": "txn_abc123", "limit": 100 }
```

If the connection drops mid-sync, the next attempt resumes from the last successful cursor stored in `sync_watermarks.last_sync_cursor`.

### First sync scope

When `last_synced_at` is NULL (first ever sync with this peer):
- Use `since_updated_at = <current FY start>` (April 1 of current fiscal year)
- This limits first sync to ~1 year of data, manageable for most SMBs
- User can trigger "Sync full history" from Settings which uses `since_updated_at = 2000-01-01`

### Row deduplication

Each row has a `sync_id` (UUID assigned at creation). Before inserting a received row, check:
```sql
SELECT id FROM transactions WHERE sync_id = ? LIMIT 1;
```
If found → conflict resolution. If not found → insert.

---

## 11. Conflict Resolution

### Default: Last-Write-Wins (LWW)

For all tables except invoice/quote status fields: the row with the higher `updated_at` wins entirely.

```dart
if (remote.updatedAt.isAfter(local.updatedAt)) {
  await db.update(table, remote.toMap(), where: 'sync_id = ?', whereArgs: [remote.syncId]);
  row['updated_by_device_id'] = remote.updatedByDeviceId;
}
```

### Invoice status: State machine

Status values ordered by priority (lowest to highest):

```
draft(0) → sent(1) → viewed(2) → partial(3) → paid(4) → cancelled(5)
```

`cancelled` has highest priority because it is an intentional override by the business owner. Once cancelled, no other device can silently revert it.

```dart
int _statusPriority(String status) => switch (status) {
  'draft'      => 0,
  'sent'       => 1,
  'viewed'     => 2,
  'partial'    => 3,
  'paid'       => 4,
  'cancelled'  => 5,
  _            => 0,
};

String resolveInvoiceStatus(String local, String remote) {
  return _statusPriority(remote) > _statusPriority(local) ? remote : local;
}
```

Amount, items, notes, party, dates: LWW (timestamp comparison) applied **after** status is resolved independently.

### Quote status: Same state machine

```
draft(0) → sent(1) → accepted(2) → rejected(3) → expired(4)
```

### Conflict for `updated_by_device_id`

After merge, set `updated_by_device_id = winner_device_id`. This enables future audit ("this record was last changed on Device B").

---

## 12. Deletion Handling

All core tables already have `deleted_at TEXT` and soft-delete convention. Confirmation:

| Table | `deleted_at` | Notes |
|---|---|---|
| transactions | ✅ | Confirmed in DB |
| credits | ✅ | Confirmed |
| credit_payments | ✅ | Added in v65 |
| loans | ✅ | Confirmed |
| parties | ✅ | Confirmed |
| accounts | ✅ | Confirmed |
| invoices | ✅ | Confirmed |
| item_catalog | ✅ | Confirmed |

Deleted rows are synced as normal updates. The `deleted_at` timestamp and `updated_at` bump are set on deletion. The merge service applies LWW on `deleted_at` — the row with an earlier `deleted_at` (first to soft-delete) wins.

**Hard deletes are forbidden** in any code path that touches syncable tables.

---

## 13. Invoice Events (Audit Log)

A new `invoice_events` table tracks status transitions and edits. This provides:
- GST audit trail (required for compliance)
- Conflict debugging across devices
- Customer-facing history ("Sent on Mar 15, Paid on Mar 17")

### Schema

```sql
CREATE TABLE invoice_events (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id   TEXT NOT NULL,
  event_type   TEXT NOT NULL,
  event_data   TEXT,
  occurred_at  TEXT NOT NULL,
  device_id    TEXT NOT NULL,
  sync_id      TEXT NOT NULL UNIQUE
);

-- event_type values:
--   CREATED | SENT | VIEWED | PARTIAL | PAID | CANCELLED | EDITED | DELETED
--
-- event_data (JSON blob examples):
--   EDITED:    {"changed_fields": ["amount", "due_date"], "old_amount": 5000}
--   PAID:      {"payment_method": "UPI", "reference": "GPay-XXXX"}
```

### Sync of `invoice_events`

`invoice_events` is append-only. Merge rule: use `sync_id` to dedup; if not present, insert. Never update or delete an event row.

Pull uses the same watermark: `WHERE occurred_at > last_synced_at`.

---

## 14. Background Sync

### Android — WorkManager foreground service

```dart
// lib/data/services/p2p_background_sync_task.dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'p2p_sync_periodic') {
      // Show ongoing notification (required Android 14+)
      await _showSyncNotification();
      await P2pSyncCoordinator.instance.runForegroundSync();
      await _cancelSyncNotification();
    }
    return Future.value(true);
  });
}
```

Registration (on app start):
```dart
Workmanager().registerPeriodicTask(
  'p2p_sync_periodic',
  'p2p_sync_periodic',
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.unmetered), // Wi-Fi only
  existingWorkPolicy: ExistingWorkPolicy.keep,
);
```

The periodic task fires only on Wi-Fi (`NetworkType.unmetered`), conserving battery.

### iOS — BGAppRefreshTask

Register in `AppDelegate.swift`:
```swift
BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.kashcube.p2psync", using: nil) { task in
    // Call Flutter method channel → P2pSyncCoordinator.runForegroundSync()
}
```

iOS best-effort — the OS decides when to run it. Do not rely on it for time-sensitive sync.

### Foreground triggers (primary path)

These run in the main isolate, no notification needed:

| Trigger | Action |
|---|---|
| App enters foreground | `P2pSyncCoordinator.onAppResume()` |
| Invoice saved/edited | `P2pSyncCoordinator.syncTable('invoices')` |
| User pulls to refresh on Transactions screen | `P2pSyncCoordinator.syncAll()` |
| User taps "Sync now" in Settings | `P2pSyncCoordinator.syncAll(forceFullFY: false)` |

---

## 15. Database Migration — v69

Bump `AppConstants.dbVersion` from `68` → `69`.

### New tables

```sql
-- Trusted paired devices
CREATE TABLE IF NOT EXISTS trusted_peers (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  peer_identity_id TEXT    NOT NULL UNIQUE,
  peer_name        TEXT,
  business_id      TEXT,
  shared_secret_enc TEXT   NOT NULL,
  paired_at        TEXT    NOT NULL,
  last_seen_at     TEXT,
  last_synced_at   TEXT,
  is_active        INTEGER NOT NULL DEFAULT 1
);

-- Per-table sync watermarks per peer
CREATE TABLE IF NOT EXISTS sync_watermarks (
  peer_identity_id TEXT NOT NULL,
  table_name       TEXT NOT NULL,
  last_synced_at   TEXT NOT NULL,
  last_sync_cursor TEXT,
  PRIMARY KEY (peer_identity_id, table_name)
);

-- Invoice audit log (append-only)
CREATE TABLE IF NOT EXISTS invoice_events (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id   TEXT NOT NULL,
  event_type   TEXT NOT NULL,
  event_data   TEXT,
  occurred_at  TEXT NOT NULL,
  device_id    TEXT NOT NULL,
  sync_id      TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_invoice_events_invoice
  ON invoice_events(invoice_id, occurred_at);
```

### New column: `updated_by_device_id`

Add to all 14 syncable tables (mirrors the `created_by_device_id` pattern from v65):

```sql
ALTER TABLE transactions     ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE credits          ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE credit_payments  ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE loans            ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE parties          ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE accounts         ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE categories       ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE budgets          ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE item_catalog     ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE scheduled_payments ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE businesses       ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE invoices         ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE purchase_bills   ADD COLUMN updated_by_device_id TEXT;
ALTER TABLE quotes           ADD COLUMN updated_by_device_id TEXT;
```

### `sync_outbox` table

Leave dormant — already exists in production DB installs. Nothing writes to it in v2 sync. Schedule removal for v72+.

---

## 16. File Structure

```
lib/data/
  models/
    peer_device.dart             # Discovered mDNS device (not yet paired)
    trusted_peer.dart            # Paired peer stored in DB
    sync_watermark.dart          # Per-peer per-table watermark
    sync_message.dart            # HELLO / HELLO_ACK / pull/push DTOs
    invoice_event.dart           # invoice_events row model

  repositories/
    trusted_peer_repository.dart         # Interface
    sync_watermark_repository.dart       # Interface
    invoice_event_repository.dart        # Interface
    impl/
      trusted_peer_repository_impl.dart
      sync_watermark_repository_impl.dart
      invoice_event_repository_impl.dart

  services/
    p2p_discovery_service.dart      # Conditional import facade
    p2p_discovery_service_io.dart   # Bonsoir mDNS broadcast + discovery
    p2p_discovery_service_stub.dart # No-op stub (web / test)
    p2p_sync_server.dart            # shelf HTTP server, route handlers
    p2p_sync_client.dart            # dart:io HttpClient, pull/push methods
    p2p_auth_service.dart           # HMAC signing, verification, HKDF
    p2p_merge_service.dart          # LWW + state machine merge logic
    p2p_sync_coordinator.dart       # Orchestrates discovery → sync sequence
    p2p_background_sync_task.dart   # WorkManager callback dispatcher

lib/presentation/
  screens/
    sync/
      devices_screen.dart          # List of discovered + paired devices
      pair_device_screen.dart      # QR show (own) + scan (peer)
      sync_log_screen.dart         # Recent sync sessions with row counts
  providers/
    p2p_provider.dart              # Riverpod providers for all sync services
```

---

## 17. Riverpod Providers

```dart
// lib/presentation/providers/p2p_provider.dart

// Discovery service — auto-disposes when no listeners
final p2pDiscoveryServiceProvider = Provider.autoDispose<P2pDiscoveryService>(
  (ref) {
    final svc = P2pDiscoveryService();
    ref.onDispose(svc.dispose);
    return svc;
  },
);

// Discovered (unpaired) peers stream
final discoveredPeersProvider =
    StreamProvider.autoDispose<List<PeerDevice>>((ref) {
  return ref.watch(p2pDiscoveryServiceProvider).discoveredDevices;
});

// Trusted (paired) peers list
final trustedPeersProvider = FutureProvider<List<TrustedPeer>>((ref) {
  return ref.read(trustedPeerRepositoryProvider).getAll();
});

// Sync coordinator — singleton, not autoDispose
final p2pSyncCoordinatorProvider = Provider<P2pSyncCoordinator>((ref) {
  return P2pSyncCoordinator(
    discovery: ref.read(p2pDiscoveryServiceProvider),
    peerRepo: ref.read(trustedPeerRepositoryProvider),
    watermarkRepo: ref.read(syncWatermarkRepositoryProvider),
    mergeService: ref.read(p2pMergeServiceProvider),
    authService: ref.read(p2pAuthServiceProvider),
  );
});

// Sync state — drives UI progress indicators
final syncStateProvider = StateProvider<P2pSyncState>((ref) => P2pSyncState.idle);
```

---

## 18. Implementation Order

The layers are independent enough to implement and test in isolation.

### Step 1 — `device_info_plus` + pubspec (5 min)
Add `device_info_plus: ^10.1.0` to `pubspec.yaml`. Run `flutter pub get`.

### Step 2 — v69 DB migration (30 min)
- Add all `CREATE TABLE` and `ALTER TABLE` statements to `database_helper.dart`
- Bump `AppConstants.dbVersion` to 69
- Test: cold install + upgrade from v68

### Step 3 — Models + auth utilities (1 hr)
- `peer_device.dart`, `trusted_peer.dart`, `sync_watermark.dart`, `sync_message.dart`
- `p2p_auth_service.dart` (HMAC sign/verify + HKDF) — pure Dart, unit-testable
- Unit tests for auth service using `crypto` package

### Step 4 — Discovery service (1 hr)
- `p2p_discovery_service_io.dart` — adapted from wifi-mirror's `network_discovery_service_io.dart`
- `p2p_discovery_service_stub.dart` — empty stream returns
- Test: two devices on same Wi-Fi, one discovers the other

### Step 5 — HTTP server + client (2 hr)
- `p2p_sync_server.dart` — shelf routes with HMAC middleware
- `p2p_sync_client.dart` — HELLO, pull, push
- Repository impls for `trusted_peers`, `sync_watermarks`
- Test: two emulators, HELLO exchange, schema gating rejection

### Step 6 — Merge service (1 hr)
- `p2p_merge_service.dart` — LWW + invoice state machine
- Unit tests for all conflict scenarios (especially status priority)

### Step 7 — Coordinator + background (1 hr)
- `p2p_sync_coordinator.dart` — orchestration logic
- `p2p_background_sync_task.dart` — WorkManager registration + callback

### Step 8 — UI screens (2 hr)
- `devices_screen.dart` — show discovered + paired devices
- `pair_device_screen.dart` — QR show/scan + pairing flow
- `sync_log_screen.dart` — history of sync sessions
- Wire into Settings navigation

---

## 19. Open Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Android kills background WorkManager | Medium | Use `FOREGROUND_SERVICE` notification (required Android 14+); accept that background is best-effort |
| iOS BGAppRefreshTask unreliable timing | High | iOS sync is foreground-only in practice; document this to users |
| mDNS not available on some Android ROMs | Low | Fall back to manual IP entry (text field in pair screen) |
| Schema drift between devices (long-unsynced) | Medium | HELLO handshake rejects incompatible versions; user shown clear "update app" message |
| Large first-sync (multi-year history) | Low | FY-scoped by default; full history is opt-in from Settings |
| Invoice conflict on two devices editing simultaneously | Low | State machine prevents regression; LWW on non-status fields; `invoice_events` log provides trace |
| Shared secret storage compromised (rooted device) | Low | Encrypted via platform keystore; sync is LAN-only (no remote attacker) — acceptable risk for the threat model |
| `sync_outbox` table confusion with old code | Very Low | Table is dormant; nothing reads or writes it; document in code comment |

---

## Appendix A — wifi-mirror Reference Map

| wifi-mirror component | KashCube equivalent | Change |
|---|---|---|
| `NetworkDiscoveryService` (Bonsoir mDNS) | `P2pDiscoveryService` | Service type `_kashcube._tcp`; dynamic port in TXT |
| `network_discovery_service_io.dart` | `p2p_discovery_service_io.dart` | Direct adaptation |
| `network_discovery_service_stub.dart` | `p2p_discovery_service_stub.dart` | Direct copy |
| `NetworkDevice` model | `PeerDevice` model | Add `schemaVersion`, `businessIds` from TXT records |
| `WebServerService._getLocalIpAddress()` | Reused in `p2p_sync_server.dart` | Identical algorithm |
| `SignalingService` TCP server | `P2pSyncServer` (shelf HTTP) | Different protocol, same lifecycle pattern |
| WebRTC + STUN | **Not used** | LAN-only, HTTP is sufficient |
| `web_socket_channel` | **Not used for sync** | No web client for KashCube sync |

---

*End of spec. Next action: implement Step 1 (add `device_info_plus`) and Step 2 (v69 migration).*
