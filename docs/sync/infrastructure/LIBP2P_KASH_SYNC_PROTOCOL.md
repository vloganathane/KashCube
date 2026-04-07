# /kash-sync/1.0.0 Protocol Specification

**Status**: Phase 1.2 — Protocol Design  
**Author**: Phase 1 Implementation Team  
**Date**: 2026-02-24  
**Refs**: `PHASE_0_FOUNDATION_STATUS.md`, `SYNC_ENVELOPE_FORMAT.md`

---

## 1. Overview

The `/kash-sync/1.0.0` protocol enables **privacy-first, peer-to-peer financial data synchronization** for KashCube. It operates over **dart_libp2p** streams, supporting:

- **Multi-device sync**: Phones, tablets, desktops (Android, iOS, macOS, Windows, Linux)
- **Offline-first**: Direct P2P without internet connectivity (LAN, Bluetooth future)
- **Multi-hop relay**: Sync through intermediary peers when direct path unavailable
- **Zero central servers**: No KashCube servers involved; 100% P2P encrypted
- **Conflict resolution**: Last-Write-Wins (LWW) with version-based merge

---

## 2. Protocol Identity

```
Protocol ID:  /kash-sync/1.0.0
Transport:    dart_libp2p TCP, UDX (UDP-based)
Security:     Noise protocol (encryption + authentication)
Multiplexing: Yamux (multiple streams over single connection)
Discovery:    mDNS (LAN), DHT (optional, Phase 2+)
```

**Version Semantics**:
- `1.0.0` = Initial release (Phase 1)
- Breaking changes = major version bump (`/kash-sync/2.0.0`)
- Backward-compatible enhancements = minor bump (`/kash-sync/1.1.0`)

---

## 3. Stream Semantics

### 3.1 Stream Lifecycle

1. **Initiator dials peer** → Opens stream with protocol ID `/kash-sync/1.0.0`
2. **Responder accepts stream** → Registers protocol handler
3. **Bidirectional messaging** → Both sides send/receive frames
4. **Long-lived** → Stream persists for duration of sync session
5. **Graceful close** → Either side can close stream (EOF signal)

### 3.2 Stream States

```
IDLE → OPENING → ACTIVE → CLOSING → CLOSED
                    ↓
                 (Error) → ERROR
```

- **IDLE**: No stream to peer
- **OPENING**: Dialing peer, awaiting stream acceptance
- **ACTIVE**: Stream ready for bidirectional messaging
- **CLOSING**: Graceful shutdown in progress
- **CLOSED**: Stream terminated (can reopen)
- **ERROR**: Stream failed (connection lost, protocol error)

### 3.3 Stream Management

- **One stream per peer**: If stream exists to peer X, reuse it (don't open duplicate)
- **Reconnection**: On disconnect, retry with exponential backoff (1s, 2s, 4s, max 30s)
- **Idle timeout**: Close stream after 5 minutes of inactivity (no messages sent/received)
- **Heartbeat**: Send PING frame every 60 seconds to keep stream alive

---

## 4. Message Framing

### 4.1 Frame Format (Length-Prefixed JSON)

Every message is a **4-byte length prefix** + **JSON payload**:

```
┌────────────────┬──────────────────────────────┐
│ Length (4B)    │ JSON Payload (N bytes)       │
│ Big-endian u32 │ UTF-8 encoded JSON object    │
└────────────────┴──────────────────────────────┘
```

**Example**:
```json
Length: 0x00000045 (69 bytes)
Payload: {"type":"ROWS","table":"transactions","rows":[{"id":"abc123",...}]}
```

**Rationale**:
- **Length prefix** enables efficient streaming (know payload size upfront)
- **JSON** for human-readability during Phase 1 (Phase 2+ can migrate to binary)
- **UTF-8** standard for cross-platform compatibility

### 4.2 Maximum Frame Size

- **Default**: 1 MB per frame
- **Configurable**: `Libp2pSyncConfig.maxFrameSizeBytes` (range: 64 KB – 10 MB)
- **Large batches**: Split into multiple frames (e.g., 10,000 rows → 10 frames of 1,000 rows)

---

## 5. Frame Types (Reuse Existing Sync Envelope)

We **reuse the existing sync envelope format** from Phase 0 (WebRTC/P2P):

| Frame Type     | Direction        | Purpose                                      |
|----------------|------------------|----------------------------------------------|
| **SYNC_PLAN**  | Bidirectional    | Negotiate which tables to sync + watermarks |
| **ROWS**       | Sender → Receiver| Batch of rows for a table                    |
| **PUSH**       | Sender → Receiver| Real-time single row update                  |
| **WRITE_OK**   | Receiver → Sender| Acknowledge successful write                 |
| **ERROR**      | Bidirectional    | Signal protocol error or constraint failure  |
| **PING**       | Bidirectional    | Keepalive / heartbeat                        |
| **PONG**       | Response to PING | Heartbeat response                           |

**New Frames (libp2p-specific)**:
- **PING/PONG**: Keepalive for long-lived streams (not present in WebRTC)

---

## 6. Protocol Flow

### 6.1 Connection Establishment

```
Peer A (Initiator)                    Peer B (Responder)
─────────────────────────────────────────────────────────
1. Discover B via mDNS
2. Dial B's multiaddr
   → /ip4/192.168.1.10/tcp/9090/p2p/QmB123...
3. Open stream: /kash-sync/1.0.0
                                      4. Accept stream
                                      5. Register stream handler
                                      
6. Stream ACTIVE ← ─ ─ ─ ─ ─ ─ ─ ─ → Stream ACTIVE
```

### 6.2 Sync Negotiation (SYNC_PLAN Exchange)

```
Peer A                                Peer B
──────────────────────────────────────────────
1. Send SYNC_PLAN
   {
     "type": "SYNC_PLAN",
     "tables": ["transactions", "credits"],
     "watermarks": {
       "transactions": "2026-02-24T10:00:00Z",
       "credits": null  // Full sync
     },
     "device_id": "device_a_uuid"
   }
                                      2. Receive SYNC_PLAN
                                      3. Determine delta (rows newer than watermarks)
                                      
                                      4. Send SYNC_PLAN (response)
                                      {
                                        "type": "SYNC_PLAN",
                                        "tables": ["transactions", "credits", "loans"],
                                        "watermarks": {
                                          "transactions": "2026-02-24T09:30:00Z",
                                          "credits": null,
                                          "loans": "2026-02-23T15:00:00Z"
                                        },
                                        "device_id": "device_b_uuid"
                                      }
                                      
5. Receive SYNC_PLAN (response)
6. Determine delta for B's tables

Both peers now know what to send to each other.
```

### 6.3 Data Transfer (ROWS Frames)

```
Peer A                                Peer B
──────────────────────────────────────────────
1. Send ROWS (transactions)
   {
     "type": "ROWS",
     "table": "transactions",
     "rows": [
       {"sync_id": "tx_001", "amount": 5000, "updated_at": "2026-02-24T10:05:00Z", ...},
       {"sync_id": "tx_002", "amount": 1200, "updated_at": "2026-02-24T10:10:00Z", ...}
     ]
   }
                                      2. Receive ROWS
                                      3. Deduplicate (filter seen sync_ids)
                                      4. Upsert into SQLite (REPLACE conflict)
                                      5. Update watermark
                                      
                                      6. Send WRITE_OK
                                      {
                                        "type": "WRITE_OK",
                                        "table": "transactions",
                                        "count": 2
                                      }
                                      
7. Receive WRITE_OK
8. Mark table progress
```

**Concurrent Transfer**: Both peers send ROWS frames simultaneously (full-duplex).

### 6.4 Real-Time Sync (PUSH Frames)

After initial sync completes, real-time updates use **PUSH** frames:

```
Peer A                                Peer B
──────────────────────────────────────────────
1. User creates new transaction
2. Insert into SQLite
3. Send PUSH
   {
     "type": "PUSH",
     "table": "transactions",
     "row": {
       "sync_id": "tx_003",
       "amount": 2500,
       "updated_at": "2026-02-24T11:00:00Z",
       ...
     }
   }
                                      4. Receive PUSH
                                      5. Deduplicate (check sync_id)
                                      6. Upsert into SQLite
                                      7. Notify UI (Riverpod provider)
                                      
                                      8. Send WRITE_OK
                                      {
                                        "type": "WRITE_OK",
                                        "table": "transactions",
                                        "count": 1
                                      }
```

### 6.5 Keepalive (PING/PONG)

To prevent idle timeout:

```
Peer A                                Peer B
──────────────────────────────────────────────
(60 seconds of silence)

1. Send PING
   {
     "type": "PING",
     "timestamp": "2026-02-24T11:05:00Z"
   }
                                      2. Receive PING
                                      3. Send PONG
                                      {
                                        "type": "PONG",
                                        "timestamp": "2026-02-24T11:05:00Z"
                                      }
                                      
4. Receive PONG (stream still alive)
```

**Timeout**: If no PONG within 10 seconds, assume stream dead → reconnect.

---

## 7. Error Handling

### 7.1 Protocol Errors

**Malformed JSON**:
```json
{
  "type": "ERROR",
  "code": "MALFORMED_JSON",
  "message": "Failed to parse JSON: unexpected token at position 42"
}
```

**Unknown frame type**:
```json
{
  "type": "ERROR",
  "code": "UNKNOWN_FRAME_TYPE",
  "message": "Received frame type 'FOOBAR' (not in spec)"
}
```

**Frame too large**:
```json
{
  "type": "ERROR",
  "code": "FRAME_TOO_LARGE",
  "message": "Frame size 5242880 exceeds limit 1048576"
}
```

### 7.2 Database Errors

**Constraint violation** (e.g., foreign key):
```json
{
  "type": "ERROR",
  "code": "DB_CONSTRAINT_VIOLATION",
  "message": "SQLite FOREIGN KEY constraint failed for table 'credits'",
  "table": "credits",
  "sync_id": "credit_456"
}
```

**Action**: Sender should log error, **skip row**, continue with next row.

### 7.3 Stream Errors

- **Connection lost**: Automatic reconnection with exponential backoff
- **Timeout**: Close stream, reopen new stream
- **Unsupported protocol version**: Log warning, don't sync (backward compat future)

---

## 8. Security Considerations

### 8.1 Transport Security (Noise Protocol)

- **Encryption**: All streams encrypted via **Noise** (libp2p's default)
- **Authentication**: Peer identities verified via **PeerId** (derived from public key)
- **No plaintext**: Financial data never transmitted unencrypted

### 8.2 Authorization (Future: Phase 2+)

- **Phase 1**: No authorization (all peers with matching protocol can sync)
- **Phase 2+**: Device pairing with **authorized device list** in SQLite
  - Primary approves secondary via QR code
  - Only approved PeerIds can sync financial data
  - See `docs/sync/DEVICE_PAIRING_SPEC.md` (Phase 2)

### 8.3 Deduplication (Defense Against Replay)

- **sync_id**: Prevents duplicate row insertion
- **LRU cache**: Bounded memory (512 entries per table, evicts oldest)
- **Watermarks**: Prevents re-sending already-synced data

---

## 9. Performance Optimizations

### 9.1 Batching

- **ROWS frames**: Send 100-1000 rows per frame (not per-row)
- **Trade-off**: Larger batches = fewer round-trips, but higher latency before ack

### 9.2 Streaming Large Tables

For tables with >10,000 rows:
1. Send first 1,000 rows → Wait for WRITE_OK
2. Send next 1,000 rows → Wait for WRITE_OK
3. Repeat until complete

**Rationale**: Prevents memory exhaustion, provides progress feedback.

### 9.3 Compression (Future: Phase 2+)

- **Phase 1**: No compression (JSON plaintext)
- **Phase 2+**: Optional gzip compression of JSON payloads (reduce bandwidth by ~70%)

---

## 10. Integration with SyncRepository Interface

### 10.1 Mapping: Interface → Protocol

| SyncRepository Method      | Protocol Action                              |
|----------------------------|----------------------------------------------|
| `initialize()`             | Start libp2p host, register protocol handler |
| `connect(peer)`            | Dial peer's multiaddr, open `/kash-sync/1.0.0` stream |
| `disconnect()`             | Close all streams, stop host                 |
| `discoverPeers()`          | Start mDNS discovery, emit `SyncPeerDiscovered` events |
| `syncTable(table)`         | Send SYNC_PLAN for one table → ROWS frames  |
| `syncAllTables()`          | Send SYNC_PLAN for all tables → ROWS frames |
| `pushRow(table, row)`      | Send PUSH frame (real-time update)          |
| `pushRows(table, rows)`    | Send multiple PUSH frames (batch)           |
| `getSyncProgress()`        | Return current `_completedTables`, `_pendingTables`, `_rowsSynced` |
| `events` stream            | Emit `SyncEvent` on state changes (connected, rows received, etc.) |

### 10.2 LibP2P-Specific Components

**New Classes (Phase 1.3)**:
- `lib/data/services/libp2p_node.dart` — Wraps dart_libp2p Host (init, start, dial, send, close)
- `lib/data/services/libp2p_protocol.dart` — Stream handler for `/kash-sync/1.0.0`
- `lib/data/services/libp2p_discovery.dart` — mDNS peer discovery

**Libp2pSyncRepositoryImpl (Phase 1.4)**:
- Implements `SyncRepository` interface
- Owns `LibP2pNode`, `LibP2pProtocol`, `LibP2pDiscovery` instances
- Reuses deduplication, upsert, watermark logic from Phase 0
- Delegates frame construction/parsing to protocol layer

---

## 11. Testing Strategy

### 11.1 Unit Tests (Phase 1.4)

- **Frame serialization**: JSON encode/decode
- **Deduplication**: LRU cache eviction, sync_id filtering
- **Error handling**: Malformed JSON, unknown frame types, frame size limits

### 11.2 Integration Tests (Phase 1.5)

- **Two-device sync**: Phone A ↔ Phone B (2,000 rows)
- **Multi-table sync**: 40+ tables (convergence test)
- **Disconnect/reconnect**: Kill stream, verify reconnection
- **Conflict resolution**: Concurrent updates to same row (LWW wins)

### 11.3 Comparative Tests (Phase 1.6)

- **WebRTC baseline**: Measure latency, memory, battery
- **libp2p implementation**: Same metrics
- **Side-by-side table**: Compare results (validate migration decision)

---

## 12. Migration Path (WebRTC → libp2p)

### 12.1 Feature Flag

```dart
// lib/core/constants/settings_keys.dart
static const String enableLibp2pSync = 'enable_libp2p_sync';
```

**Settings UI**:
```
[ ] Use experimental peer-to-peer sync (libp2p)
    ⚠️  Requires app restart.
```

### 12.2 Provider Conditional

```dart
// lib/presentation/providers/sync_providers.dart
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final settings = ref.watch(settingsProvider);
  final useLibp2p = settings.getBool(SettingsKeys.enableLibp2pSync) ?? false;
  
  if (useLibp2p) {
    return ref.watch(libp2pSyncRepositoryProvider);
  } else {
    return ref.watch(webrtcSyncRepositoryProvider);
  }
});
```

### 12.3 Fallback Strategy

- **Phase 1**: libp2p is opt-in (default: WebRTC)
- **Phase 2**: libp2p is default (WebRTC fallback for incompatible devices)
- **Phase 3**: Remove WebRTC (all users migrated)

---

## 13. Future Enhancements (Phase 2+)

### 13.1 DHT Discovery

- Use `dart_libp2p_kad_dht` package for internet-wide peer discovery
- Find peers outside LAN (e.g., sync with home device while at office)

### 13.2 Relay Servers

- Public relay nodes for NAT traversal (hole punching)
- Multi-hop sync: Phone A → Relay → Phone B

### 13.3 Selective Sync

- Only sync specific tables (e.g., "Sync only transactions, not credits")
- Reduce bandwidth for limited data plans

### 13.4 Compression

- gzip JSON payloads (70% size reduction)
- Protobuf migration (50% size reduction vs uncompressed JSON)

### 13.5 Incremental Sync (Delta State)

- Send only changed fields (not full row)
- Requires schema versioning + field-level watermarks

---

## 14. Appendix: Example Frame Dumps

### 14.1 SYNC_PLAN Frame

```json
{
  "type": "SYNC_PLAN",
  "tables": ["transactions", "credits", "loans"],
  "watermarks": {
    "transactions": "2026-02-24T10:00:00.000Z",
    "credits": null,
    "loans": "2026-02-23T15:30:00.000Z"
  },
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "protocol_version": "1.0.0"
}
```

### 14.2 ROWS Frame

```json
{
  "type": "ROWS",
  "table": "transactions",
  "rows": [
    {
      "sync_id": "tx_2026_02_24_10_05_00_abc123",
      "id": "abc123",
      "amount": 5000.00,
      "type": "income",
      "category_id": "salary",
      "date": "2026-02-24",
      "notes": "February salary",
      "updated_at": "2026-02-24T10:05:00.123Z",
      "version": 1,
      "created_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
      "updated_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
      "deleted_at": null
    },
    {
      "sync_id": "tx_2026_02_24_10_10_00_def456",
      "id": "def456",
      "amount": 1200.00,
      "type": "expense",
      "category_id": "groceries",
      "date": "2026-02-24",
      "notes": "Weekly shopping",
      "updated_at": "2026-02-24T10:10:00.456Z",
      "version": 1,
      "created_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
      "updated_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
      "deleted_at": null
    }
  ]
}
```

### 14.3 PUSH Frame

```json
{
  "type": "PUSH",
  "table": "transactions",
  "row": {
    "sync_id": "tx_2026_02_24_11_00_00_ghi789",
    "id": "ghi789",
    "amount": 2500.00,
    "type": "expense",
    "category_id": "rent",
    "date": "2026-02-24",
    "notes": "Monthly rent partial payment",
    "updated_at": "2026-02-24T11:00:00.789Z",
    "version": 1,
    "created_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
    "updated_by_device_id": "550e8400-e29b-41d4-a716-446655440000",
    "deleted_at": null
  }
}
```

### 14.4 WRITE_OK Frame

```json
{
  "type": "WRITE_OK",
  "table": "transactions",
  "count": 2,
  "timestamp": "2026-02-24T10:15:00.999Z"
}
```

### 14.5 ERROR Frame

```json
{
  "type": "ERROR",
  "code": "DB_CONSTRAINT_VIOLATION",
  "message": "FOREIGN KEY constraint failed: credits.customer_id references parties.id",
  "table": "credits",
  "sync_id": "credit_jkl012",
  "timestamp": "2026-02-24T10:20:00.111Z"
}
```

### 14.6 PING/PONG Frames

```json
// PING
{
  "type": "PING",
  "timestamp": "2026-02-24T11:05:00.000Z"
}

// PONG (response)
{
  "type": "PONG",
  "timestamp": "2026-02-24T11:05:00.000Z"
}
```

---

## 15. References

- **Phase 0 Docs**:
  - `PHASE_0_FOUNDATION_STATUS.md` — Foundation tasks completed
  - `PHASE_0_TASK_3_ENVELOPE_FORMAT.md` — Existing sync frame specs (WebRTC/P2P)
  - `PHASE_0_TASK_4_REPOSITORY_INTERFACE.md` — SyncRepository interface definition

- **dart_libp2p**:
  - GitHub: https://github.com/aetherity/dart_libp2p
  - pub.dev: https://pub.dev/packages/dart_libp2p
  - Docs: https://pub.dev/documentation/dart_libp2p/latest/

- **libp2p Specs**:
  - Protocol IDs: https://docs.libp2p.io/concepts/protocols/
  - Stream Multiplexing: https://docs.libp2p.io/concepts/multiplex/
  - Noise Security: https://docs.libp2p.io/concepts/secure-comm/noise/

---

**Next Steps (Phase 1.3)**:
- Implement `LibP2pNode` service (host lifecycle, dialing, stream management)
- Implement `LibP2pProtocol` service (stream handler, frame parsing, routing)
- Implement `LibP2pDiscovery` service (mDNS peer discovery, PeerInfo construction)
