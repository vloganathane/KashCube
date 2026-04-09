# libp2p Mesh Network Implementation

## Current State (Point-to-Point)

**Status**: ✅ Working but limited to single peer connection

**Architecture**:
- Auto-discovery via mDNS (port 5353, service `_p2p._udp`)
- Auto-connect to ALL discovered peers with trust checking
- **Limitation**: Only ONE active connection (`_connectedPeerId`, `_activeStream`)
- Connection model: Direct request/response over single stream

**Issue**: Doesn't scale beyond 2 devices. If Device A connects to Device B, and Device C appears, only one connection can be maintained.

## Target Architecture (Mesh Network)

### Phase 1: Multi-Peer Connection Management ✅ CURRENT

**Goal**: Support simultaneous connections to multiple peers (10+ devices)

**Key Changes**:
1. Replace single connection tracking with multi-peer tracking:
   - `String? _connectedPeerId` → `Set<String> _connectedPeerIds`
   - `dynamic _activeStream` → `Map<String, dynamic> _peerStreams`
   - Add `Map<String, ConnectionState> _peerConnectionStates`

2. Connection management:
   - Max peer limit (default: 10, configurable via settings)
   - Auto-connect respects peer limit
   - Priority: trusted peers > recently seen > lowest latency
   - Graceful disconnect handles all peers

3. Stream multiplexing:
   - Each peer gets dedicated stream
   - Independent failure handling per peer
   - Parallel read/write operations

**Implementation Files**:
- `lib/data/repositories/libp2p_sync_repository_impl.dart` (primary changes)
- `lib/data/services/libp2p/libp2p_protocol.dart` (stream handler per peer)
- `lib/data/models/sync_peer.dart` (add connection state field)

### Phase 2: Gossipsub Broadcasting

**Goal**: Efficient change propagation across mesh (no need to notify each peer individually)

**Mechanism**:
- Enable gossipsub in `dart_libp2p` Host configuration
- Topic: `/kash-sync/1.0.0` (version for protocol evolution)
- Publish changes to topic instead of direct peer messaging
- All subscribed peers receive and apply changes
- Message deduplication via seen cache (24h TTL)

**Message Format**:
```json
{
  "msgId": "uuid-v4",
  "timestamp": 1234567890,
  "deviceId": "device-uuid",
  "changeType": "INSERT|UPDATE|DELETE",
  "table": "transactions",
  "rowData": {...},
  "vectorClock": {"device1": 5, "device2": 3}
}
```

**Advantages**:
- O(1) broadcast vs O(N) direct messaging
- Automatic redundancy (messages propagate via multiple paths)
- Natural fit for eventual consistency model

### Phase 3: Conflict Resolution

**Strategy**: Last-Write-Wins with vector clocks

**Components**:
1. **Vector Clock** per device:
   - Track logical time for each device in mesh
   - Increment on local change
   - Merge on message receive
   - Detect concurrent updates

2. **Conflict Detection**:
   - Same row updated by multiple devices concurrently
   - Vector clocks incomparable (neither dominates)
   - Flag for manual resolution or apply merge strategy

3. **Merge Strategies**:
   - Numeric fields: sum (amounts) or max (timestamps)
   - Text fields: longest non-empty or prompt user
   - Boolean fields: true wins (prefer enabling features)

### Phase 4: Resilience & Health

**Auto-Reconnection**:
- Health check every 30s (PING/PONG protocol)
- Detect stale connections (no data in 60s)
- Reconnect with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Network change detection (WiFi switch, airplane mode)

**Peer Quality Scoring**:
- Track per peer: latency, success rate, uptime
- Prefer high-quality peers for critical operations
- Evict low-quality peers when at max capacity

**Graceful Degradation**:
- Single peer available: direct sync (fallback to current model)
- No peers: queue changes for later broadcast
- Partial connectivity: sync via available paths

### Phase 5: DHT for Internet Sync (Optional)

**Goal**: Discover peers beyond LAN (internet-wide)

**Kademlia DHT**:
- Enable DHT in `dart_libp2p` configuration
- Bootstrap nodes: public libp2p nodes
- Peer routing: find peers by interest (e.g., "kash-sync users")
- Content routing: not used (we don't share files)

**Relay & NAT Traversal**:
- Circuit relay v2 for NAT traversal
- Hole punching via STUN/TURN
- Relay nodes as fallback for restricted networks

**Privacy Considerations**:
- DHT records are public → only store peer IDs, not data
- End-to-end encryption via Noise (already enabled)
- User opt-in required for internet sync

## Implementation Plan

### Week 1: Phase 1 (Multi-Peer Foundation)
- Days 1-2: Refactor connection tracking (maps, sets)
- Day 3: Implement max peer limit + priority logic
- Day 4: Update auto-connect to respect limits
- Day 5: Testing with 3-10 devices

### Week 2: Phase 2 (Gossipsub)
- Days 1-2: Enable gossipsub, topic subscription
- Day 3: Convert sync messages to pubsub
- Day 4: Deduplication + seen cache
- Day 5: Testing broadcast efficiency

### Week 3: Phase 3 (Conflicts)
- Days 1-2: Vector clock implementation
- Day 3: Conflict detection logic
- Day 4: Merge strategies
- Day 5: Testing concurrent updates

### Week 4: Phase 4 (Resilience)
- Days 1-2: Health checks + auto-reconnect
- Day 3: Peer quality scoring
- Day 4: Network change handling
- Day 5: Stress testing (disconnects, failures)

### (Optional) Week 5: Phase 5 (DHT)
- Days 1-3: DHT configuration + bootstrap
- Day 4: Relay setup
- Day 5: Internet sync testing

## Success Criteria

**Phase 1 Complete**:
- ✅ Can connect to 10 peers simultaneously
- ✅ Auto-connect respects max peer limit
- ✅ Connection state tracked per peer
- ✅ Disconnect cleanly removes per-peer state

**Full Mesh Complete**:
- ✅ 3+ devices sync changes across mesh
- ✅ Change on Device A propagates to B, C, D
- ✅ Device disconnect doesn't break others
- ✅ New device joining discovers and syncs with all
- ✅ Conflicts detected and resolved automatically
- ✅ Network interruption → auto-reconnect

## Testing Strategy

**Unit Tests**:
- Multi-peer connection manager
- Gossipsub message handling
- Vector clock operations
- Conflict resolution logic

**Integration Tests**:
- 2-device sync (baseline)
- 3-device mesh (triangle topology)
- 5-device mesh (full connectivity)
- 10-device mesh (max capacity)

**Stress Tests**:
- Rapid connects/disconnects
- Network partition (split mesh)
- Concurrent updates to same row
- High message throughput (100+ changes/sec)

**Real-World Scenarios**:
- Home: 2-3 devices (phone, tablet, desktop)
- Business: 5-10 devices (multiple employees)
- Network switch: WiFi → mobile data → WiFi
- Offline editing → reconnect → sync

## Privacy & Security

**Maintained Guarantees**:
- ✅ All data stays local (no cloud sync)
- ✅ mDNS only on LAN (no internet exposure)
- ✅ Noise encryption for all peer streams
- ✅ Trust checking before accepting changes

**New Considerations**:
- Gossipsub messages are encrypted (Noise handles this)
- DHT (Phase 5) exposes peer IDs publicly → user must opt-in
- Vector clocks leak device count → acceptable for UX

## Rollout Plan

1. **Dev build**: Enable mesh network, test internally
2. **Beta release**: Opt-in "Experimental: Mesh Sync" toggle
3. **Gradual rollout**: Enable by default after 2 weeks of stable beta
4. **Remove old WebRTC**: After 90% adoption of libp2p mesh
5. **DHT (internet sync)**: Separate opt-in, clearly labeled "Experimental"

## Current Implementation Status

- ✅ libp2p services (node, protocol, discovery)
- ✅ Auto-discovery (mDNS)
- ✅ Auto-connect (all peers with trust check)
- ✅ Point-to-point connection working
- ✅ **Phase 1 complete**: Multi-peer connection management
  - ✅ Simultaneous connections to 10 peers
  - ✅ Per-peer connection state tracking
  - ✅ Peer limit enforcement
  - ✅ Graceful multi-peer disconnect
- ✅ **Phase 2 complete**: Broadcast layer (direct mesh broadcasting)
  - ✅ LibP2pBroadcast layer for topic-based messaging
  - ✅ Message deduplication (24h TTL, 10k msg limit)
  - ✅ Auto re-broadcasting creates mesh propagation
  - ✅ BROADCAST frame type in protocol
  - ✅ All sync messages broadcast to all peers
  - ⚠️ **Note**: Uses direct broadcast, not gossipsub (dart_libp2p v1.0.3 limitation)
- ⏳ **Phase 3 next**: Conflict resolution (vector clocks)
- ⏳ Phase 4-5: Not started

**Commits**: 
- `ae6ed95` - Phase 1 mesh network foundation
- `f250221` - Phase 2 broadcast layer

---

**Last Updated**: 9 April 2026
**Status**: Phase 2 ✅ COMPLETE, Phase 3 next
**Target Completion**: Phase 3 in 1-2 days, full mesh with resilience in 2-3 weeks
