# Phase 0: Foundation Status Report

**Date**: 6 April 2026  
**Status**: In Progress  
**Related**: [LIBP2P_FLUTTER_IMPLEMENTATION_PLAN.md](infrastructure/LIBP2P_FLUTTER_IMPLEMENTATION_PLAN.md)

##  Overview

Phase 0 prepares the sync system for libp2p migration by hardening the foundation, closing gaps, and creating clean abstraction layers.

---

## ✅ Task 1: Add Sync Columns to `loan_payments` Table — **COMPLETE**

**Status**: ✅ Done (v71 migration)  
**Location**: `lib/data/services/database_helper.dart` (line 2509)

All sync columns added:
- `sync_id TEXT UNIQUE DEFAULT (lower(hex(randomblob(16))))`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `updated_at TEXT`
- `deleted_at TEXT`
- `version INTEGER NOT NULL DEFAULT 0`
- `created_by_device_id TEXT`
- `updated_by_device_id TEXT`

**Schema confirmed** in `database_helper_tables.dart` (line 184-207).

---

## 🔄 Task 2: Normalize Event Dedupe Across All Repositories — **IN PROGRESS**

**Status**: 🔄 Analysis Complete, Implementation Pending  
**Issues Found**:

### Deduplication Inconsistencies

| Domain | Approach | Location | Key Column |
|--------|----------|----------|------------|
| **SMS Transactions** | Hash-based (SHA-256) | `sms_parser_service.dart` | `dedupe_hash` |
| **P2P Sync** | Database query | `p2p_merge_service.dart` | `sync_id` |
| **Web Sync** | Bounded cache (300) | `web_sync_provider.dart` | `sync_id` |
| **Invoice Events** | UNIQUE constraint | `invoice_events` table | `sync_id` |

### Current Dedupe Strategies Detailed

#### 1. SMS Deduplication (Transaction-specific)

```dart
// lib/data/services/sms_parser_service.dart
String generateDedupeHash(ParsedSms parsed) {
  final dateKey = '${year}-${month}-${day}-${hour}-${minute}';
  final merchantKey = partyName.toLowerCase().replaceAll(RegExp(r'\W'), '');
  final refKey = upiRefNo ?? referenceId ?? '';
  final key = '$amount-$dateKey-$merchantKey-${direction.name}-$refKey';
  return sha256.convert(utf8.encode(key)).toString();
}

// Used for SMS-specific duplicate prevention
await repository.existsByDedupeHash(hash);
```

**Database**: `dedupe_hash TEXT UNIQUE` in `transactions` table

#### 2. P2P Sync Deduplication (Sync-focused)

```dart
// lib/data/services/p2p/p2p_merge_service.dart
Future<Map<String, dynamic>?> _fetchByKey(
  Database db,
  String table,
  String keyColumn,  // Usually 'sync_id'
  Object keyValue,
) async {
  final rows = await db.query(
    table,
    where: '$keyColumn = ?',
    whereArgs: [keyValue],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}
```

**Database**: Query-based, no unique constraint required

#### 3. Web Sync Deduplication (Bounded cache)

```dart
// lib/presentation/providers/web_sync_provider.dart
final Map<String, Set<String>> _seenInboundRowIdsByTable = {};
final Map<String, ListQueue<String>> _seenInboundRowOrderByTable = {};
final int _inboundDedupeCapacity = 300;

List<Map<String, dynamic>> _filterNewInboundRows(
  String table,
  List<dynamic> rows,
) {
  final seenIds = _seenInboundRowIdsByTable[table] ??= {};
  final seenOrder = _seenInboundRowOrderByTable[table] ??= ListQueue();
  
  for (final row in rows) {
    final syncId = row['sync_id']?.toString();
    if (syncId == null || seenIds.contains(syncId)) continue;
    
    seenIds.add(syncId);
    seenOrder.addLast(syncId);
    
    // LRU eviction
    while (seenOrder.length > _inboundDedupeCapacity) {
      final evicted = seenOrder.removeFirst();
      seenIds.remove(evicted);
    }
  }
}
```

**Memory**: Bounded LRU cache per table, cleared on disconnect

#### 4. Invoice Events Deduplication (Database constraint)

```sql
-- lib/data/services/database_helper_tables.dart
CREATE TABLE invoice_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id  TEXT NOT NULL,
  event_type  TEXT NOT NULL,
  event_data  TEXT,
  occurred_at TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  sync_id     TEXT NOT NULL UNIQUE  -- Enforced at DB level
);
```

**Database**: UNIQUE constraint on `sync_id`

### Conflict Resolution (Related but Separate)

| Strategy | Location | Notes |
|----------|----------|-------|
| Last-Write-Wins (LWW) | `p2p_merge_service.dart` | `updated_at` timestamp comparison |
| Version-based LWW | `p2p_merge_service.dart` | `version` integer (monotonic) |
| Invoice State Machine | `p2p_merge_service.dart` | `cancelled` > `paid` > `viewed` > `sent` > `draft` |
| Soft-delete resolution | `p2p_merge_service.dart` | `deleted_at` set + newer wins |

**Key Insight**: Deduplication (prevent duplicate inserts) is **separate** from conflict resolution (which version wins on update).

### Recommendation: Unified Dedupe Strategy

**Proposed Approach**:
1. **All syncable entities**: Use `sync_id` (already in all tables)
2. **SMS transactions**: Keep `dedupe_hash` for UX (user confirmation), but also use `sync_id` for sync
3. **Dedupe layer**: Create `SyncDedupeService` to abstract:
   - SMS: Check `dedupe_hash` + `sync_id`
   - Sync: Check `sync_id` only
   - Configurable: Bounded cache (fast, session-scoped) vs database query (accurate, persistent)

**Implementation**:
```dart
// lib/data/services/sync/sync_dedupe_service.dart
class SyncDedupeService {
  static Future<bool> exists({
    required String table,
    required String syncId,
    Database? db,
  }) async {
    final database = db ?? await DatabaseHelper.instance.database;
    final count = Sqflite.firstIntValue(
      await database.query(
        table,
        columns: ['COUNT(*)'],
        where: 'sync_id = ?',
        whereArgs: [syncId],
      ),
    ) ?? 0;
    return count > 0;
  }
  
  // Bounded cache variant for real-time sync (web/p2p)
  static bool existsInCache({
    required String table,
    required String syncId,
    required Map<String, Set<String>> cache,
  }) {
    return cache[table]?.contains(syncId) ?? false;
  }
}
```

**Action Items**:
- [ ] Create `sync_dedupe_service.dart` with unified API
- [ ] Migrate `web_sync_provider.dart` to use service
- [ ] Migrate `p2p_merge_service.dart` to use service  
- [ ] Keep SMS `dedupe_hash` for user-facing duplicate detection (separate concern)
- [ ] Document when to use cache vs database query

**Timeline**: 2-3 days (part of Phase 0)

---

## 📝 Task 3: Document Current Sync Envelope Format — **IN PROGRESS**

**Status**: 🔄 Partially documented in P2P_SYNC_SPEC.md, needs consolidation  

### Current Sync Envelope Formats

#### WebRTC Sync Envelope (WebSyncNotifier)

**Message Types**:
```dart
// lib/core/constants/app_messages.dart (or equivalent)
enum SyncSignalingMessages {
  rows,          // Server → Client: snapshot/deltadata  push,          // Server → Client: live incremental write
  writeOk,       // Server → Client: ACK for client write
  syncPlan,      // Server → Client: list of syncable tables
  ping,          // Bidirectional: keepalive
  pong,          // Bidirectional: keepalive response
  signalOffer,   // WebRTC signaling
  signalAnswer,  // WebRTC signaling
  signalIceCandidate, // WebRTC signaling
  signalAck,     // WebRTC signaling acknowledgment
  signalError,   // WebRTC signaling error
  signalUnsupported, // WebRTC not available
  webRtcRuntime, // WebRTC runtime status
}
```

**ROWS Frame** (Snapshot or delta):
```json
{
  "type": "ROWS",
  "table": "transactions",
  "rows": [
    {
      "sync_id": "abc123...",
      "amount": 1000.0,
      "date": "2026-04-06",
      "updated_at": "2026-04-06T10:30:00.000Z",
      "version": 3,
      ...
    }
  ],
  "is_final": true
}
```

**PUSH Frame** (Live incremental):
```json
{
  "type": "PUSH",
  "table": "transactions",
  "rows": [
    {
      "sync_id": "xyz789...",
      "amount": 500.0,
      ...
    }
  ],
  "row": {  // Optional: single row shorthand
    "sync_id": "xyz789...",
    ...
  }
}
```

**WRITE_OK Frame** (Acknowledgment):
```json
{
  "type": "WRITE_OK",
  "table": "invoices",
  "sync_id": "def456..."  // Echoes client's write request
}
```

**SYNC_PLAN Frame** (Initial handshake):
```json
{
  "type": "SYNC_PLAN",
  "tables": [
    {
      "tableName": "transactions",
      "mode": "delta_ts",
      "keyColumn": " sync_id",
      "hasUpdatedAt": true,
      "hasCreatedAt": true,
      "hasDeletedAt": true
    },
    ...
  ]
}
```

#### P2P Coordinator Envelope (Direct peer-to-peer)

**Pull Request**:
```dart
// Sent via P2pLanClient.pullTable()
{
  "table": "parties",
  "after_ms": 1701234567890,  // Unix timestamp (ms)
  "after_version": null,      // Or integer for delta_version mode
  "limit": 100
}
```

**Pull Response**:
```dart
{
  "rows": [
    {
      "sync_id": "party-123",
      "name": "Zomato",
      "updated_at": "2026-04-06T10:00:00.000Z",
      "version": 5,
      ...
    }
  ]
}
```

**Push Frame**:
```dart
// Sent via P2pLanClient.push()
{
  "table": "transactions",
  "rows": [
    {
      "sync_id": "tx-456",
      "amount": 750.0,
      ...
    }
  ]
}
```

### Common Envelope Properties

| Field | Type | Purpose | Present In |
|-------|------|---------|------------|
| `type` | String | Message discriminator | WebRTC only |
| `table` | String | Target table name | All |
| `rows` | Array | List of row objects | All |
| `row` | Object | Single row (alt to `rows`) | WebRTC PUSH |
| `sync_id` | String | Global unique row ID | Every row |
| `updated_at` | ISO 8601 | Last write timestamp | Every row |
| `version` | Integer | Monotonic version counter | Tables with `delta_version` mode |
| `deleted_at` | ISO 8601 | Soft-delete timestamp | Tables with soft-delete |
| `device_id` | String | Originating device ID | Every row (via `created_by_device_id`) |
| `is_final` | Boolean | Last chunk of multi-batch | WebRTC ROWS |
| `after_ms` | Integer | Watermark for delta sync | P2P pull request |

### Envelope Security

**Current (Phase 0)**:
- **Transport**: LAN-only (mDNS discovery)
- **Authentication**: QR code pairing with shared secret
- **Encryption**: TLS/DTLS (WebRTC built-in for web), plain TCP for P2P (local network only)
- **Integrity**: None (trust LAN peers)

**Future (Phase 2 - libp2p)**:
- **Transport**: libp2p (TCP/UDX/relay)
- **Encryption**: Noise protocol (end-to-end)
- **Integrity**: Per-envelope HMAC or signature
- **Replay Protection**: Nonce + timestamp window

### Deduplication in Envelopes

**Current**:
- Each row has `sync_id` (globally unique)
- Receiver uses `sync_id` to dedupe before merge
- Web sync caches last 300 `sync_id` per table (bounded LRU)
- P2P queries database for `sync_id` existence

**Issue**: If connection drops mid-sync and reconnects, same rows may be resent (idempotent but wasteful).

**Future**: Add `envelope_id` or sequence numbers to detect duplicate envelopes (not just rows).

---

## 🏗️ Task 4: Create `SyncRepository` Abstract Interface — **NOT STARTED**

**Status**: ⏳ Pending  
**Depends On**: Task 3 (envelope format documentation)

**Goal**: Extract sync operations into clean repository interface to allow swapping WebRTC ↔ libp2p.

**Proposed Interface**:
```dart
// lib/domain/repositories/sync_repository.dart
abstract class SyncRepository {
  // ── Connection Lifecycle ────────────────────────────────────────────────
  
  Future<void> initialize();
  Future<void> connect({required String peerId});
  Future<void> disconnect();
  Stream<SyncConnectionState> get connectionState;
  
  // ── Discovery ───────────────────────────────────────────────────────────
  
  Stream<List<SyncPeer>> discoverPeers();
  Future<void> stopDiscovery();
  
  // ── Sync Operations ─────────────────────────────────────────────────────
  
  Future<void> syncTable(String tableName);
  Future<void> syncAllTables();
  Future<SyncProgress> getSyncProgress();
  
  // ── Real-time Push ──────────────────────────────────────────────────────
  
  Future<void> pushRow({
    required String table,
    required Map<String, dynamic> row,
  });
  
  Future<void> pushRows({
    required String table,
    required List<Map<String, dynamic>> rows,
  });
  
  // ── Events ──────────────────────────────────────────────────────────────
  
  Stream<SyncEvent> get events;
}

// Data Classes
class SyncPeer {
  final String peerId;
  final String displayName;
  final String? deviceType;
  final DateTime discoveredAt;
}

enum SyncConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  syncing,
  error,
}

class SyncProgress {
  final Set<String> completedTables;
  final Set<String> pendingTables;
  final int rowsSynced;
  final int rowsPending;
}

sealed class SyncEvent {}
class SyncStarted extends SyncEvent {}
class SyncTableCompleted extends SyncEvent {
  final String tableName;
  final int rowsProcessed;
}
class SyncCompleted extends SyncEvent {}
class SyncError extends SyncEvent {
  final String message;
  final Object? error;
}
```

**Implementations**:
- `WebRTCSyncRepositoryImpl` (current)
- `Libp2pSyncRepositoryImpl` (future)

**Timeline**: 1 day

---

## 🔧 Task 5: Extract WebRTC to `WebRTCSyncRepositoryImpl` — **NOT STARTED**

**Status**: ⏳ Pending  
**Depends On**: Task 4 (SyncRepository interface)

**Current State**:
- Sync logic mixed in `WebSyncNotifier` (presentation layer)
- Direct database calls (`DatabaseHelper.instance.database`)
- No clean separation of transport vs. sync protocol

**Refactor Plan**:
1. Create `lib/data/repositories/webrtc_sync_repository_impl.dart`
2. Move all WebRTC-specific code from `WebSyncNotifier`
3. Implement `SyncRepository` interface
4. Keep `WebSyncNotifier` as thin UI state holder (calls repository)
5. Move P2P coordinator logic to `Libp2pSyncRepositoryImpl` skeleton (empty for now)

**Timeline**: 2-3 days

---

## 🧪 Task 6: Add Comprehensive Sync Integration Tests — **NOT STARTED**

**Status**: ⏳ Pending  
**Depends On**: Task 5 (repository extraction)

**Test Coverage Needed**:

### Unit Tests (Repository layer)
- [ ] `WebRTCSyncRepository.syncTable()` with mock WebRTC channel
- [ ] Dedupe logic (bounded cache, database query)
- [ ] Envelope serialization/deserialization
- [ ] Conflict resolution (LWW, version-based, state machine)
- [ ] Soft-delete handling

### Integration Tests (End-to-end)
- [ ] 2-device sync (Android emulator + simulator via LAN)
- [ ] Convergence test: 1000 transactions, verify both devices match
- [ ] Conflict injection: Same row edited on both sides, verify resolution
- [ ] Disconnect/reconnect: Mid-sync failure, resume works
- [ ] Dedupe test: Same row sent twice, only merged once

**Test Infrastructure**:
- Mock `Database` via `sqflite_common_ffi` (in-memory)
- Mock WebRTC channel with controllable latency/drops
- Deterministic clock for timestamp testing

**Timeline**: 3-4 days

---

## 📊 Task 7: Profile Current Sync Performance (Baseline) — **NOT STARTED**

**Status**: ⏳ Pending  
**Depends On**: Task 6 (integration tests for reliable profiling)

**Metrics to Capture**:

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Direct sync latency | < 500ms | Time from `pushRow()` to ACK |
| 2-device convergence (40 tables) | < 10s | Full sync from scratch |
| Battery drain (1h background) | < 2% | Android Battery Historian |
| Memory overhead | < 50 MB | Android Profiler peak RSS |
| Network bandwidth (1000 rows) | < 500 KB | Wireshark packet capture |
| Database write latency (100 inserts) | < 100ms | SQLite profiler |

**Tools**:
- Android Studio Profiler (CPU, Memory, Network)
- Dart Observatory (isolate profiling)
- SQLite `EXPLAIN QUERY PLAN` analysis
- Custom benchmark harness (measure time in code)

**Baseline Report**:
- Document current performance in `PHASE_0_SYNC_BASELINE.md`
- Compare with libp2p after Phase 1 migration

**Timeline**: 2 days

---

## Summary Timeline

| Task | Status | Duration | Dependencies |
|------|--------|----------|--------------|
| 1. loan_payments sync columns | ✅ Complete | — | — |
| 2. Normalize dedupe | 🔄 50% | 2-3 days | — |
| 3. Document envelope format | 🔄 80% | 1 day | — |
| 4. Create SyncRepository interface | ⏳ Pending | 1 day | Task 3 |
| 5. Extract WebRTC repository | ⏳ Pending | 2-3 days | Task 4 |
| 6. Integration tests | ⏳ Pending | 3-4 days | Task 5 |
| 7. Performance baseline | ⏳ Pending | 2 days | Task 6 |

**Total Estimated Duration**: **1-2 weeks** (6-10 working days)

**Next Steps** (Priority Order):
1. ✅ Complete Task 2 (dedupe normalization) — create `SyncDedupeService`
2. ✅ Finish Task 3 (envelope docs) — consolidate into single reference
3. 🚀 Start Task 4 (SyncRepository interface) — enables parallel work on Phase 1

---

**Last Updated**: 6 April 2026  
**Owner**: KashCube Core Team  
**Reviewers**: TBD
