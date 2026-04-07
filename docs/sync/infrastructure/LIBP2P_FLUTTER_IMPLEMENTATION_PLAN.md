# libp2p Flutter Implementation Plan

Date: 6 April 2026  
Status: Implementation brainstorming and planning  
Related: MESH_SYNC_STRATEGY_DECISION.md, CONDITIONAL_HOSTING_MESH_POLICY.md

## Executive Summary

This document outlines the practical implementation strategy for integrating libp2p as the transport layer for KashCube mesh sync. While the strategic decision has been made (see MESH_SYNC_STRATEGY_DECISION.md), this focuses on Flutter-specific challenges, library options, phased rollout, and technical implementation details.

**Key Decision**: ✅ **UPDATED:** Use **pure Dart implementation** via `dart_libp2p` package (v1.0.3, published Feb 2026). No FFI needed!

---

## 1. Flutter/Dart Integration Options

### ⚠️ UPDATE (6 April 2026): Pure Dart Implementation Available!

**Discovery**: The `dart_libp2p` package (v1.0.3) exists and is production-ready! Published Feb 22, 2026.

**New Recommendation**: Use **Option C** (pure Dart) instead of FFI approach.

See updated analysis below with dart_libp2p details. Options A-B preserved for reference only.

---

### Option A: Go-libp2p via FFI (DEPRECATED - kept for reference)

**Approach**: Use `dart:ffi` to call into Go-libp2p compiled as a shared library (.so/.dylib/.dll).

**Pros**:
- ✅ Most mature libp2p implementation (go-libp2p is reference)
- ✅ All transports supported (TCP, QUIC, WebSocket, WebRTC, etc.)
- ✅ Active development and strong community
- ✅ Known Flutter integration pattern (e.g., gomobile for mobile)
- ✅ Can compile to shared libraries for all platforms (Android, iOS, macOS, Windows, Linux)

**Cons**:
- ❌ Requires Go build toolchain in CI/CD
- ❌ Larger binary size (Go runtime included)
- ❌ FFI maintenance overhead (manual bindings or code generation)
- ❌ iOS requires special provisioning (dynamic frameworks)

**Implementation Path**:
1. Create Go wrapper package with C-style exports
2. Generate Dart FFI bindings using `ffigen`
3. Build shared libraries per platform (using `go build -buildmode=c-shared`)
4. Bundle libraries in Flutter assets or native build
5. Load and call via `dart:ffi`

**Example Go Wrapper**:
```go
package main

import "C"
import (
    "context"
    "github.com/libp2p/go-libp2p"
    "github.com/libp2p/go-libp2p/core/host"
)

var node host.Host

//export InitLibp2pNode
func InitLibp2pNode() *C.char {
    var err error
    node, err = libp2p.New()
    if err != nil {
        return C.CString(err.Error())
    }
    return nil
}

//export SendMessage
func SendMessage(peerID *C.char, message *C.char) *C.char {
    // Implementation
    return nil
}

func main() {}
```

**Example Dart FFI**:
```dart
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

typedef InitLibp2pNodeNative = ffi.Pointer<Utf8> Function();
typedef InitLibp2pNodeDart = ffi.Pointer<Utf8> Function();

class Libp2pNode {
  late ffi.DynamicLibrary _lib;
  late InitLibp2pNodeDart _init;

  Libp2pNode() {
    _lib = ffi.DynamicLibrary.open('liblibp2p.so');
    _init = _lib.lookupFunction<InitLibp2pNodeNative, InitLibp2pNodeDart>('InitLibp2pNode');
  }

  String init() {
    final result = _init();
    if (result.address != 0) {
      return result.toDartString();
    }
    return 'Success';
  }
}
```

### Option B: Rust-libp2p via FFI

**Approach**: Use rust-libp2p compiled to native libraries via `cargo build`.

**Pros**:
- ✅ Memory-safe implementation
- ✅ Good mobile support (smaller binari✅ **RECOMMENDED**

**Package**: `dart_libp2p` v1.0.3 (published Feb 22, 2026)  
**Repository**: https://github.com/stephanfeb/dart_libp2p  
**Status**: Production-ready, comprehensive libp2p implementation in pure Dart

**Features**:
- ✅ **Transports**: TCP and UDX (UDP-based with reliability)
- ✅ **Security**: Noise protocol (encryption + authentication)
- ✅ **Multiplexing**: Yamux for multi-stream over single connection
- ✅ **Discovery**: mDNS for local network, DHT via companion package
- ✅ **NAT Traversal**: Hole punching and relay support built-in
- ✅ **Protocols**: Ping, Identify, custom protocol support
- ✅ **Companion Packages**: `dart_libp2p_kad_dht`, `dart_libp2p_pubsub`
- ✅ **Event System**: Comprehensive monitoring and lifecycle hooks
- ✅ **Resource Management**: Protection against exhaustion

**Pros**:
- ✅ **No FFI complexity** — pure Dart, no C/Go/Rust bridges
- ✅ **No build toolchain** — no native compilation needed
- ✅ **Zero binary size overhead** — no Go/Rust runtime to bundle
- ✅ **Full Dart type safety** — compile-time safety, better IDE support
- ✅ **Same code all platforms** — Android, iOS, web, macOS, Windows, Linux
- ✅ **Easier debugging** — no native crashes, use Dart DevTools
- ✅ **Hot reload friendly** — faster development iteration
- ✅ **Well-documented** — comprehensive docs and examples
- ✅ **Active development** — rece

---

### ✅ FINAL DECISION: dart_lib (Updated for dart_libp2p)

### Layer Diagram

```
┌─────────────────────────────────────────────┐
│   Presentation Layer (Riverpod Providers)   │
│   - SyncStatusNotifier                      │
│   - PeerDiscoveryNotifier                   │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│   Domain Layer (Use Cases)                  │
│   - SyncTransactionsUseCase                 │
│   - DiscoverPeersUseCase                    │
│   - SendSyncEnvelopeUseCase                 │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│   Data Layer (Repositories)                 │
│   - SyncRepository (abstract interface)     │
│   - Libp2pSyncRepositoryImpl                │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│   Libp2p Service Layer (Pure Dart)          │
│   - Libp2pNode: Host wrapper                │
│   - Libp2pProtocol: /kash-sync/1.0.0        │
│   - Libp2pDiscovery: mDNS, DHT              │
│   - Libp2pRelay: Store-and-forward          │
└─────────────────┬───────────────────────────┘
                  │ dart imports
┌─────────────────▼───────────────────────────┐
│   dart_libp2p Package (Pure Dart)           │
│   - Host: Peer lifecycle                    │
│   - Network/Swarm: Connection management    │
│   - Upgrader: Security + mux negotiation    │
│   - Transports: TCP, UDX (UDP-based)        │
│   - Security: Noise protocol                │
│   - Multiplexer: Yamux streams              │
│   - Discovery: mDNS, DHT (companion pkg)    │
└─────────────────────────────────────────────┘
```

**Key Difference**: No FFI boundary! Everything is pure Dart, simplifying the stack significantly. p2p_config.Libp2p.listenAddrs([MultiAddr('/ip4/0.0.0.0/tcp/0')]),
  ];
  
  final host = await p2p_config.Libp2p.new_(options);
  await host.start();
  return host;
}
```
- ✅ No FFI complexity
- ✅ Full Dart type safety
- ✅ Easier debugging

**Cons**:
- ❌ **No implementation available** — would require building from scratch
- ❌ Massive scope (multiaddr, peer routing, DHT, relay, pubsub, etc.)
- ❌ Reinvents the wheel (violates strategic decision to use libp2p)

**Verdict**: Not recommended unless pure Dart implementation emerges.

### Option D: JavaScript libp2p via WebView (REJECTED)

**Approach**: Embed js-libp2p in WebView and communicate via message passing.

**Cons**:
- ❌ Terrible performance
- ❌ WebView overhead on mobile
- ❌ Complex lifecycle management
- ❌ Battery drain

**Verdict**: Explicitly rejected.

---
dart_libp2p for direct peer communication (no relay).

**Milestones**:

#### 1.1: Add dart_libp2p Dependency ✅ **SIMPLIFIED**
- [ ] Add to `pubspec.yaml`: `dart_libp2p: ^1.0.3`
- [ ] Add companion packages: `dart_libp2p_kad_dht: ^1.2.0` (optional for Phase 2)
- [ ] Run `flutter pub get`
- [ ] Verify import: `import 'package:dart_libp2p/dart_libp2p.dart';`

**No build infrastructure needed!** ~~Go toolchain~~, ~~FFI codegen~~, ~~Makefiles~~ all removed.

#### 1.2: Design KashCube Sync Protocol
- [ ] Define custom protocol ID: `/kash-sync/1.0.0`
- [ ] Design stream handler: `Future<void> handleSyncStream(Stream stream)`
- [ ] Define message envelope format (reuse existing sync envelope)
- [ ] Add protocol registration with Host

#### 1.3: Implement Dart Libp2p Service Layer
- [ ] Create `lib/data/services/libp2p_node.dart`
  - `init()`: Create Host with Ed25519 identity, TCP transport, Noise security
  - `start()`: Call `host.start()`, register `/kash-sync/1.0.0` handler
  - `dial(peerId)`: Connect to peer and open stream
  - `send(peerId, envelope)`: Write bytes to stream
  - `close()`: Graceful shutdown
- [ ] Create `lib/data/services/libp2p_protocol.dart`
  - Stream handler for incoming sync envelopes
  - Envelope deserialization and validation
- [ ] Create `lib/data/services/libp2p_discovery.dart`
  - mDNS-based local peer discovery
  - Emit discovered peers via Stream
                  │
┌─────────────────▼───────────────────────────┐
│   Libp2p Service Layer (Dart FFI)           │
│   - Libp2pNode: init, listen, dial          │
│   - Libp2pStream: send, receive             │
│   - Libp2pDiscovery: mDNS, DHT              │
└─────────────────┬───────────────────────────┘
                  │ dart:ffi
┌─────────────2-3 weeks ⚡ **(Cut in half — no FFI complexity!)**  
**Risk**: Low — pure Dart integration, no native code  
**Success Criteria**:
- Direct sync works as well as WebRTC
- No increase in battery drain
- Deterministic convergence maintained
- Works across all platforms (Android, iOS, web, desktop) with single codebase  │
└─────────────────────────────────────────────┘
```

### Repository Pattern Alignment

**Current**: `WebRTCSyncRepository` implements `SyncRepository`  
**Future**: `Libp2pSyncRepository` implements `SyncRepository`

**Migration Path**:
1. Create new `Libp2pSyncRepository` alongside existing WebRTC implementation
2. Add feature flag: `SettingsKeys.enableLibp2pSync` (default: false)
3. Provider conditionally creates WebRTC or libp2p repository based on flag
4. Test both implementations in parallel
5. Deprecate WebRTC once libp2p proven stable

---

## 3. Phased Implementation Plan

### Phase 0: Foundation (Pre-libp2p) ✅ **STRATEGICALLY COMPLETE**

**Goal**: Harden current sync system and prepare for migration.

**Tasks**:
- [x] ✅ Add sync columns to `loan_payments` table (v71, already complete)
- [x] ✅ Normalize event dedupe across all repositories (4 strategies documented)
- [x] ✅ Document current sync envelope format (WebRTC + P2P protocols)
- [x] ✅ Create `SyncRepository` abstract interface (188 lines, 10 methods)
- [x] ✅ Extract WebRTC implementation to `WebRTCSyncRepositoryImpl` (320 lines, 22 tests)
- [ ] ⏭️ Add comprehensive sync integration tests → **DEFERRED to post-Phase 1** (comparative testing)
- [ ] ⏭️ Profile current sync performance → **DEFERRED to post-Phase 1** (comparison report)

**Duration**: 1 week (5 days elapsed)  
**Risk**: Low — foundation complete, Tasks 6-7 better as comparative tests  
**Status**: 5/5 critical tasks complete, 2 deferred for better ROI  
**Deliverables**: 4,341 lines added (repository + tests + docs)

**Strategic Decision**: Tasks 6-7 moved to post-Phase 1
- **Rationale**: Test suite works with SyncRepository interface → can validate both WebRTC + libp2p
- **Benefit**: Write tests once, compare implementations side-by-side
- **Savings**: ~5 days accelerated timeline, earlier dart_libp2p validation

### Phase 1: libp2p Foundation (Direct Peer Sync Only)

**Goal**: Replace WebRTC with libp2p for direct peer communication (no relay).

**Milestones**:

#### 1.1: Set Up Build Infrastructure
- [ ] Add Go build to CI/CD pipeline
- [ ] Create `native/go-libp2p-bridge/` directory structure
- [ ] Set up `Makefile` targets for shared library compilation
- [ ] Configure platform-specific builds (Android: .so, iOS: .framework, macOS: .dylib, etc.)
- [ ] Add FFI code generation with `ffigen`

#### 1.2: Implement Go Wrapper
- [ ] Initialize libp2p host with Ed25519 key pair
- [ ] Export C-style functions: `InitNode`, `StartListening`, `DialPeer`, `SendMessage`, `ReceiveMessage`, `Shutdown`
- [ ] Implement KashCube custom protocol: `/kash-sync/1.0.0`
- [ ] Add mDNS discovery for local network peers
- [ ] Add error handling and result marshalling

#### 1.3: Implement Dart FFI Layer
- [ ] Create `lib/data/services/libp2p_node.dart` with FFI bindings
- [ ] Wrap native calls in async Dart API
- [ ] Implement Stream<SyncEnvelope> for incoming messages
- [ ] Add connection lifecycle management
- [ ] Handle platform-specific library loading (Android vs iOS vs desktop)

#### 1.4: Implement libp2p Repository
- [ ] Create `Libp2pSyncRepositoryImpl` implementing `SyncRepository`
- [ ] Port all sync methods from WebRTC version
- [ ] Reuse existing sync envelope serialization
- [ ] Add retry logic and connection resilience
- [ ] Implement peer discovery via mDNS

#### 1.5: Integration and Testing
- [ ] Add feature flag in Settings: "Use libp2p Sync (Experimental)"
- [ ] Test direct sync between 2 devices (Android-Android, Android-iOS, Android-Web)
- [ ] Verify basic connectivity and message passing
- [ ] Initial smoke tests (single table sync)

#### 1.6: Comprehensive Testing (Phase 0 Tasks 6-7 Revised) 🔄 **COMPARATIVE**
- [ ] **Task 6 (Revised)**: Integration tests for BOTH WebRTC + libp2p
  - Test suite uses SyncRepository interface (works with both implementations)
  - 2-device sync convergence (all 40+ tables)
  - Deduplication verification (send duplicate rows)
  - Disconnect/reconnect resilience (mid-sync failure recovery)
  - Conflict resolution (same row edited on both sides)
  - Run tests against WebRTC implementation
  - Run tests against libp2p implementation
  - Compare results and identify functional differences
- [ ] **Task 7 (Revised)**: Performance comparison report
  - WebRTC baseline: latency, battery, memory, convergence time
  - libp2p measurements: same metrics
  - Side-by-side comparison table
  - Migration impact analysis
  - Recommendation: continue with libp2p or fallback to WebRTC

**Duration**: 4-6 weeks  
**Risk**: Medium — FFI integration complexity  
**Success Criteria**:
- Direct sync works as well as WebRTC
- No increase in battery drain
- Deterministic convergence maintained
- Build pipeline stable across all platforms

### Phase 2: Multi-hop Relay ✅ **SOLVED**

**Problem**: ~~iOS doesn't support `.dylib` embedding~~ **OBSOLETE** — no native libraries needed!

**Solution**: dart_libp2p is pure Dart, works identically on iOS without any restrictions.

**Action**: None requiredONDITIONAL_HOSTING_MESH_POLICY.md)
- [ ] Implement TTL decrementing and forwarding logic
- [ ] Add message deduplication cache (store envelope IDs already seen)

#### 2.2: Envelope Encryption
- [ ] Implement end-to-end envelope encryption (NaCl box or Age)
- [ ] Generate per-device key pairs (store in my_identity table)
- [ ] Add envelope signature verification (origin device must sign)
- [ ] Implement replay protection (nonce + timestamp window)
- [ ] Add key rotation on device unlink

#### 2.3: Conditional Hosting Policy
- [ ] Define authorization scopes (business-level, user-level)
- [ ] Implement policy engine: can this device relay/decrypt this envelope?
- [ ] Add relay queue with bounded retention (max 1000 messages, 24h TTL)
- [ ] Implement backpressure (stop accepting relays if queue full)
- [ ] Add audit log for policy decisions

#### 2.4: Routing and Discovery
- [ ] Implement peer routing (maintain routing table of known peers)
- [ ] Add DHT bootstrap for discovering peers outside local network
- [ ] Implement rendezvous protocol for meeting points
- [ ] Add peer scoring (prefer reliable, low-latency relays)
- [ ] Graceful degradation: fall back to direct if relay fails

#### 2.5: Testing and Validation
- [ ] Test 3-hop relay scenario (A → B → C where A and C not directly connected)
- [ ] Test store-and-forward (B offline, C queues messages, B comes online)
- [ ] Verify relay nodes cannot decrypt payloads
- [ ] Test envelope signature verification blocks tampered messages
- [ ] Profile battery impact of relay queue management

**Duration**: 6-8 weeks  
**Risk**: High — Complex distributed systems challenges  
**✅ Use dart_libp2p's built-in mDNS for local network (already included!)
- ✅ Use dart_libp2p_kad_dht for internet-based discovery (companion package)
- Implement BLE-based discovery for offline proximity (future enhancement, use `flutter_blue_plus`)
- Use QR code pairing for initial peer exchange (manual bootstrap)
- Support static peer list (user can manually add relay peers)
- Cache known good relays and try them on startup

**Action**: Test built-in mDNS first ✅ **POTENTIAL SOLVED**

**Problem**: ~~Web doesn't support FFI~~ **OBSOLETE** — no FFI needed!

**Solution**: dart_libp2p is pure Dart, *likely* works on web with TCP/WebSocket transport (needs verification).

**Action**: 
- Test dart_libp2p on Flutter web (compile and run in browser)
- If TCP/UDX don't work: configure WebSocket transport (dart_libp2p may support)
- If not supported: Use relay-only mode (connect to mobile/desktop peer as relay)
- Report findings to dart_libp2p maintainer if web issues found
- [ ] Comprehensive monitoring: sync latency, message throughput, relay hop count
- [ ] Add user-facing sync health dashboard (show peer status, last sync time, pending messages)
- [ ] Security audit: pen test relay policy enforcement, encryption implementation

**Duration**: 4-6 weeks  
**Risk**: Medium  
**Success Criteria**:
- Production-ready reliability
- Battery drain negligible
- User-facing sync transparency

---

## 4. Technical Challenges and Solutions

### Challenge 1: iOS Dynamic Library Restrictions

**Problem**: iOS doesn't support `.dylib` embedding in sandboxed apps.

**Solution**:
- Use static framework (`.framework` with static linking)
- OR: Compile Go code directly into Dart native extension (experimental)
- OR: Use iOS-specific Swift wrapper around libp2p (if Swift bindings exist)

**Action**: Research gomobile and Flutter iOS FFI best practices.

### Challenge 2: Background Sync on Mobile

**Problem**: Android/iOS kill background processes aggressively.

**Solution**:
- Use WorkManager (Android) and BackgroundTasks (iOS) for periodic sync
- Keep libp2p node running only during active sync windows
- Implement efficient wake-up: push notification from relay → trigger sync → shutdown
- Alternative: Persistent WebSocket connection with aggressive reconnect

**Action**: Design sync scheduling policy (e.g., sync every 15 minutes when on Wi-Fi, hourly on cellular).

### Challenge 3: NAT Traversal and Firewall Punching

**Problem**: Direct connections may fail if both peers behind NAT.
 ✅ **SOLVED**

**Problem**: ~~Go runtime adds ~10-15 MB~~ **OBSOLETE** — no native runtime bundled!

**Solution**: dart_libp2p is pure Dart, compiled with Flutter. Size overhead is minimal (< 500 KB estimated).

**Action**: Measure APK size before/after adding dart_libp2p to confirm minimal impact.

**Expected Impact**: 
- dart_libp2p package + dependencies: ~300-500 KB
- Comparable to any Dart package (e.g., riverpod, sqflite)
- **No binary bloat** from native runtimes
**Problem**: DHT won't work if device has no internet; mDNS only works on same subnet.

**Solution**:
- Implement BLE-based peer discovery for local proximity (borrow from BitChat ideas)
- Use QR code pairing for initial peer exchange (manual bootstrap)
- Support static peer list (user can manually add relay peers)
- Cache known good relays and try them on startup

**Action**: Prototype BLE discovery service (use `flutter_blue_plus`).

### Challenge 5: Flutter Web Support

**Problem**: Web doesn't support FFI; needs JavaScript interop.

**Solution**:
- Compile libp2p to WASM and load in web worker
- Use js-libp2p (JavaScript implementation) for web platform
- OR: Web uses WebSocket-only transport to connect to relay peer (degraded mode)
- Abstract platform differences behind `SyncRepository` interface

**Action**: Create platform-specific implementations (mobile: FFI, web: JS interop).

### Challenge 6: Binary Size Bloat

**Problem**: Go runtime adds ~1 ✅ **SIMPLIFIED**

### ~~Native Layer~~ **NOT NEEDED**

~~Go, Rust, FFI infrastructure~~ **REMOVED** — pure Dart approach eliminates this entirely.

### Flutter Layer (Dart)

```yaml
dependencies:
  # Core libp2p
  dart_libp2p: ^1.0.3
  
  # Optional: DHT for internet-based peer discovery (Phase 2)
  dart_libp2p_kad_dht: ^1.2.0
  
  # Optional: Pubsub for broadcast patterns (future enhancement)
  dart_libp2p_pubsub: ^1.1.0
  
  # Existing KashCube dependencies (no changes)
  flutter_riverpod: ^2.4.0
  sqflite: ^2.3.0
  # ... rest unchanged
```

**Removed Dependencies**:
- ~~ffi~~ — not needed
- ~~ffigen~~ — not needed
- ~~path_provider~~ (for finding native libs) — not needed

**Net Impact**: +1 primary dependency, -3 FFI dependencies, much simpler!
### Flutter Layer (Dart)

```yaml
dependencies:
  ffi: ^2.1.0                  # FFI bindings
  path_provider: ^2.1.0        # Find native library path
  
dev_dependencies:
  ffigen: ^11.0.0              # Generate Dart bindings from C headers
```

**Note**: No new network packages needed (libp2p replaces flutter_webrtc reliance).

---

## 6. Testing Strategy

### Unit Tests
- [ ] Test Go wrapper functions in isolation (using Go test suite)
- [ ] Test Dart FFI layer with mock native calls
- [ ] Test sync envelope serialization/deserialization
- [ ] Test conditional hosting policy enforcement

### Integration Tests
- [ ] Test 2-peer direct sync (Android emulator + iOS simulator)
- [ ] Test 3-peer relay scenario (A → B → C)
- [ ] Test store-and-forward (offline peer comes back online)
- [ ] Test discovery: mDNS, DHT, manual peer add

### Performance Tests
- [ ] Benchmark sync latency (direct vs relay)
- [ ] Measure battery drain over 1-hour sync session
- [ ] Profile memory usage with 1000-message relay queue
- [ ] Test convergence time with 10,000 transactions

### Security Tests
- [ ] Verify relay cannot decrypt envelopes
- [ ] Test signature verification rejects tampered messages
- [ ] Test replay protection (resend old message, should be rejected)
- [ ] Test device unlink revokes decryption access

### Platform Tests
- [ ] Android: ARM64, ARMv7, x86_64
- [ ] iOS: Real device (not just simulator)
- [ ] macOS: Intel + Apple Silicon
- [ ] Linux: x86_64
- [ ] Windows: x86_64
- [ ] Web: Browser WebSocket fallback

---

## 7. Migration Path from WebRTC

### Coexistence Strategy

**Phase 1**: Both implementations available behind feature flag.

```dart
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final settings = ref.watch(settingsProvider);
  final useLibp2p = settings.getBool(SettingsKeys.enableLibp2pSync) ?? false;
  
  if (useLibp2p) {
    return Libp2pSyncRepositoryImpl(
      database: ref.read(databaseProvider),
      node: ref.read(libp2pNodeProvider),
    );
  } else {
    return WebRTCSyncRepositoryImpl(
      database: ref.read(databaseProvider),
      webrtc: ref.read(webRTCProvider),
    );
  }
});
```

**Phase 2**: Default to libp2p, keep WebRTC as fallback.

**Phase 3**: Remove WebRTC code entirely (deprecation notice 2 releases prior).

### Data Migration

**Good news**: No data migration needed!

Sync protocol is preserved — only transport layer changes. All sync watermarks, device identities, and table schemas remain unchanged.

### User Communication

**Settings Screen**:
- Add "Sync Transport" option: WebRTC (Legacy) | libp2p (Recommended)
- Show info dialog explaining libp2p benefits (better reliability, multi-hop support)
- Prompt users to enable libp2p on next sync

**Deprecation Timeline**:
- v1.10: Introduce libp2p as opt-in experimental
- v1.11: Default to libp2p for new users
- v1.12: Migrate all users, deprecation warning for WebRTC
- v1.13: Remove WebRTC code

---

## 8. Performance and Battery Considerations

### Battery Optimization Strategies

1. **Adaptive Sync Intervals**:
   - Active use: Real-time sync (immediate)
   - Background: Sync every 15 minutes on Wi-Fi, 1 hour on cellular
   - Battery saver mode: Sync only on app open

2. **Connection Keep-Alive**:
   - Use QUIC for connection multiplexing (avoid TCP handshake overhead)
   - Reuse connections for multiple sync operations
   - Close idle connections after 5 minutes

3. **Relay Queue Management**:
   - Limit queue size: 1000 messages max
   - Bounded retention: 24 hours max
   - Drop lowest-priority messages first (order: loan payments > transactions > catalog updates)

4. **Background Task Scheduling**:
   - Use WorkManager constraints: require Wi-Fi, require charging (optional)
   - Exponential backoff on sync failures (1s → 2s → 4s → max 60s)
   - Cancel background sync if battery < 15%

### Performance Targets

| Metric | Target | Current (WebRTC) | Measurement Method |
|--------|--------|------------------|-------------------|
| Direct sync latency | < 500ms | ~300ms | Time from send to ACK |
| 3-hop relay latency | < 2s | N/A | Time for A → B → C → D delivery |
| Convergence time (40 tables) | < 10s | ~5s | Time to fully sync 2 fresh devices |
| Battery drain (1h background) | < 2% | ~1.5% | Android Battery Historian |
| Binary size increase | < 10 MB | N/A | APK size diff |
| Memory overhead | < 50 MB | ~30 MB | Android Profiler peak RSS |

---

## 9. Security Considerations

### Threat Model

**Threats in scope**:
- Malicious relay attempting to decrypt financial data
- Man-in-the-middle tampering with sync envelopes
- Replay attacks (resend old transaction to trigger duplicate)
- Device compromise (stolen phone used to impersonate owner)

**Threats out of scope** (handled by Android/iOS OS):
- Physical device access (mitigated by PIN + biometric)
- Local SQLite encryption (Android Keystore, iOS Keychain)

### Mitigation Strategies

1. **End-to-End Encryption**:
   - Use NaCl box or Age for envelope encryption
   - Derive per-device keys from Ed25519 identity
   - Relay peers only see encrypted blob, cannot decrypt

2. **Signature Verification**:
   - Every envelope signed by origin device
   - Receiver verifies signature before processing
   - Reject unsigned or invalid signatures

3. **Replay Protection**:
   - Include nonce + timestamp in envelope
   - Accept only messages within 5-minute window
   - Cache seen envelope IDs (last 10,000) to reject duplicates

4. **Device Revocation**:
   - On device unlink: mark device as revoked in my_identity table
   - Rotate dataset encryption keys
   - Sync revocation to all trusted peers
   - Revoked device cannot decrypt new envelopes

5. **Audit Logging**:
   - Log all relay decisions (accept/reject with reason)
   - Log all signature verification failures
   - Log all policy denials
   - Expose audit log in developer settings

---

## 10. Open Questions and Research Tasks

### Questions for Investigation

1. **Go vs Rust FFI performance**: Which has better call overhead? (Benchmark required)
2. **iOS bitcode compatibility**: Does gomobile + bitcode work? (Test on real device)
3. **Flutter web WASM support**: Can we compile go-libp2p to WASM? (Prototype needed)
4. **BLE discovery range**: How far does Android BLE work in practice? (Field test)
5. **Relay incentive model**: Should relay peers get credits/rewards? (UX research)
6. **Mesh topology limits**: How many hops before latency unacceptable? (Simulation)

### Research Tasks

- [ ] ~~Survey existing Flutter FFI + libp2p projects~~ ✅ **OBSOLETE** — using pure Dart
- [ ] ~~Test gomobile compilation~~ ✅ **OBSOLETE** — no FFI needed
- [ ] ~~Prototype Rust-libp2p FFI bindings~~ ✅ **OBSOLETE** — no FFI needed
- [ ] Test dart_libp2p on Flutter web (browser compatibility)
- [ ] Review dart_libp2p source code quality (code review before adoption)
- [ ] Benchmark dart_libp2p performance (latency, throughput, memory)
- [ ] Check dart_libp2p test coverage (assess stability)
- [ ] Research BLE transport for dart_libp2p (offline proximity sync)
- [ ] Study Hypercore/Dat project for conflict-free replication ideas
- [ ] Review Tailscale architecture for NAT traversal techniques
- [ ] Explore dart_libp2p customization: fork feasibility assessment

---

## 11. Success Metrics

### Technical Metrics

- **Reliability**: 99.9% successful sync operations (no data loss)
- **Latency**: P95 sync latency < 2s for 3-hop relay
- **Battery**: < 2% drain per hour of background sync
- **Size**: App size  ⚡ **ACCELERATED**

- **Week 1-2**: Phase 0 (Foundation hardening)
- **Week 3-4**: Phase 1.1-1.3 (Add dart_libp2p + Service layer) — **2 weeks instead of 4!**
- **Week 5-6**: Phase 1.4-1.5 (Repository + integration testing)
- **Week 7-8**: Alpha testing with 10 internal users
- **Week 9-12**: Phase 2 start (Relay + encryption) — **ahead of schedule!**

**Deliverable**: libp2p direct sync working on **all platforms** (not just Android!)y" user survey
- **Performance**: No increase in "app slow" complaints

---

## 12. Timeline and Milestones
 ⚡ **ACCELERATED**

- **Week 1-4**: ~~iOS port~~ **SKIP** (already works!) + Phase 2.1-2.2 (Relay + encryption)
- **Week 5-8**: Phase 2.3-2.4 (Policy + routing)
- **Week 9-12**: Phase 3 start (Optimization) — **ahead of schedule!**

**Deliverable**: Multi-hop relay working across all platforms (no separate iOS port needed!)

**Deliverable**: libp2p direct sync working on Android

### Q3 2026 (Jul-Sep)

- **Week 1-4**: iOS port + cross-platform testing
- **Week 5-8**: Phase 2.1-2.2 (Relay + encryption)
- **Week 9-12**: Phase 2.3-2.4 (Policy + routing)

**Deliverable**: Multi-hop relay working across all platforms

### Q4 2026 (Oct-Dec)

- **Week 1-4**: Phase 3 (Optimization + hardening)
- **Week 5-8**: Beta testing with 100 users
- **Week 9-10**: Security audit
- **Week 11-12**: Production rollout (v1.10 release)

**Deliverable**: libp2p sync in production as opt-in feature

### Q1 2027 (Jan-Mar)

- **Month 1**: Default to libp2p for new users (v1.11)
- **Month 2**: Migrate all existing users (v1.12)
- **Month 3**: Remove WebRTC code (v1.13)

**Deliverable**: WebRTC fully deprecated, libp2p is only sync transport

---

## 13. Risks and Mitigation
~~FFI integration fails on iOS~~ | ~~Medium~~ | ~~High~~ | ✅ **ELIMINATED** — no FFI, pure Dart |
| dart_libp2p bugs/immaturity | Medium | High | Extensive testing, keep WebRTC as fallback, contribute fixes upstream |
| Battery drain unacceptable | Low | High | Benchmark early, adaptive scheduling, pure Dart likely better than FFI |
| ~~Binary size > 15 MB~~ | ~~High~~ | ~~Medium~~ | ✅ **ELIMINATED** — Dart overhead minimal (<500KB) |
| NAT traversal fails often | Medium | High | Robust relay fallback, test across networks, use built-in relay support |
| ~~Team lacks Go/FFI expertise~~ | ~~High~~ | ~~Medium~~ | ✅ **ELIMINATED** — team already knows Dart! |
| User confusion during migration | Medium | Low | Clear messaging, gradual rollout |
| dart_libp2p web support issues | Medium | Medium | Test early, use relay mode if needed, file upstream issuesllback |
| NAT traversal fails often | Medium | High | Robust relay fallback, test across networks |
| Team lacks Go/FFI expertise | High | Medium | Training, pair programming, external consult |
| User confusion during migration | Medium | Low | Clear messaging, gradual rollout |

--- ✅ **SIMPLIFIED**

1. ~~**Prototype Go FFI**~~ → **Add dart_libp2p**: `flutter pub add dart_libp2p`
2. ~~**Review gomobile**~~ → **Read dart_libp2p docs**: Study examples and API
3. ~~**Spike Rust option**~~ → **Test basic Host**: Create Hello World peer connection
4. ~~**Set up build pipeline**~~ → **Verify platforms**: Test on Android, iOS, web, macOS
1. **Prototype Go FFI**: Create minimal "hello world" FFI bridge and test on Android
2. **Review gomobile**: Study gomobile docs and existing Flutter projects using it
3. ~~**Create ADR**~~ → **Create integration spike**: Build 2-peer sync demo with dart_libp2p
4. ~~**Assign team**~~ → **Single owner**: One Dart dev can own entire stack (no native expertise needed!)shared libraries

### Short-Term (Next 2 Weeks)

1. **Complete Phase 0**: Clo ⚡ **FASTER**

1. **Implement Phase 1.1-1.3**: Add dependency + Service layer (pure Dart, 2 weeks)
2. **Test first message**: Send one sync envelope A → B using dart_libp2p
3. **Measure baseline**: Profile latency, battery, memory vs WebRTC
4. **Cross-platform validation**: Confirm works on Android, iOS, web, desktop
### Medium-Term (Next Month)

1. **Implement Phase 1.1-1.3**: Build infrastructure + Go wrapper + FFI layer
2. **Test first message**: Send one sync envelope A → B using libp2p
3. **Measure baseline**: Profile latency, battery, memory vs WebRTC

---
✅ **[dart_libp2p Package](https://pub.dev/packages/dart_libp2p)** — Main package
- ✅ **[dart_libp2p GitHub](https://github.com/stephanfeb/dart_libp2p)** — Source code and docs
- ✅ **[dart_libp2p_kad_dht](https://pub.dev/packages/dart_libp2p_kad_dht)** — DHT companion package
- ✅ **[dart_libp2p_pubsub](https://pub.dev/packages/dart_libp2p_pubsub)** — Pubsub companion package
- [libp2p Connectivity](https://connectivity.libp2p.io/) - Test NAT traversal

### ~~Flutter FFI Resources~~ **NOT NEEDED**

~~All FFI resources removed — using pure Dart implementation instead!~~
### Flutter FFI Resources

- [Dart FFI Documentation](https://dart.dev/guides/libraries/c-interop)
- [ffigen Package](https://pub.dev/packages/ffigen)
- [gomobile Documentation](https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile)
- [Flutter FFI Examples](https://github.com/dart-lang/samples/tree/main/ffi)

### Related KashCube Docs

- [MESH_SYNC_STRATEGY_DECISION.md](./MESH_SYNC_STRATEGY_DECISION.md) - Strategic decision baseline
- [CONDITIONAL_HOSTING_MESH_POLICY.md](./CONDITIONAL_HOSTING_MESH_POLICY.md) - Replication policy
- [MESH_ENVELOPPure Dart Call Flow Example (Updated)

### Scenario: Sync one transaction from Device A to Device B

```
[Device A - Dart]
1. User saves new transaction
   └─> TransactionRepository.create(transaction)
       └─> Triggers syncProvider
           └─> SyncRepository.sendEnvelope(envelope)
               └─> Libp2pNode.send(peerId, envelope)
                   └─> host.newStream(peerId, "/kash-sync/1.0.0")
                       └─> stream.write(envelopeBytes)
                           └─> dart_libp2p (pure Dart)
                               └─> Noise encryption
                                   └─> TCP/UDX transport

[Network]
2. Encrypted bytes travel A → B (direct or via relay)
   All handled by dart_libp2p's Network/Swarm layer

[Device B - Dart]
3. Stream handler receives bytes (registered protocol handler)
   └─> Libp2pProtocol.handleStream(stream)
       └─> Read envelope bytes from stream
           └─> Parse and deserialize envelope
               └─> Verify signature
                   └─> SyncRepository._onEnvelopeReceived(envelope)
                       └─> Apply to local database
                           └─> TransactionRepository.upsert(transaction)
                               └─> UI updates (Riverpod notifies listeners)
```

**Key Difference**: No FFI boundary crossing! Everything stays in Dart from UI to network.└─> SyncRepository._onEnvelopeReceived(envelope)
       └─> Verify signature
           └─> Apply to local database
               └─> TransactionRepository.upsert(transaction)
                   └─> UI updates (Riverpod notifies listeners)
```
~~Example Makefile for Native Builds~~ **NOT NEEDED**

~~All native build infrastructure removed!~~ 

With `dart_libp2p`, the build process is simply:
```bash
flutter pub get
flutter build apk    # Android
flutter build ios    # iOS
flutter build web    # Web
flutter build macos  # macOS
```

**No custom build steps required.** Flutter's standard build handles everything.

---

## Appendix C: Quick Start Code Example

### Minimal KashCube libp2p Node

```dart
import 'package:dart_libp2p/dart_libp2p.dart';
import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/tcp_transport.dart';

class KashCubeLibp2pNode {
  late final Host host;
  
  Future<void> init() async {
    // Generate or load Ed25519 key pair (store in my_identity table)
    final keyPair = await crypto_ed25519.generateEd25519KeyPair();
    
    // Configure libp2p host
    final options = [
      p2p_config.Libp2p.identity(keyPair),
      p2p_config.Libp2p.transport(TCPTransport()),
      p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
      p2p_config.Libp2p.listenAddrs([MultiAddr('/ip4/0.0.0.0/tcp/0')]),
    ];
    
    host = await p2p_config.Libp2p.new_(options);
    
    // Register KashCube sync protocol handler
    host.setStreamHandler('/kash-sync/1.0.0', _handleSyncStream);
    
    await host.start();
    print('KashCube node started: ${host.id}');
  }
  
  Future<void> _handleSyncStream(Stream stream) async {
    // Handle incoming sync envelopes
    await for (final bytes in stream) {
      final envelope = SyncEnvelope.fromBytes(bytes);
      // Process envelope...
    }
  }
  
  Future<void> sendEnvelope(PeerId peerId, SyncEnvelope envelope) async {
    final stream = await host.newStream(peerId, '/kash-sync/1.0.0');
    await stream.write(envelope.toBytes());
    await stream.close();
  }
  
  Future<void> close() => host.close();
}
```

---

**Document Status**: Living document — **MAJOR UPDATE** after dart_libp2p discovery

**Next Review**: After Phase 1 spike (prototype with dart_libp2p)

**Owner**: KashCube Core Team

---

## Appendix D: Customization Strategy

### When to Fork vs Contribute Upstream

| Scenario | Recommended Action | Reasoning |
|----------|-------------------|-----------|
| Bug found | **Contribute upstream first** | Benefits everyone, maintainer may fix faster than you |
| Feature needed by many | **Contribute upstream** | Build community, reduce maintenance burden |
| KashCube-specific feature | **Custom protocol handler** | Keep it in app layer, no package change needed |
| Breaking change needed | **Fork** | Diverges from upstream, maintain separately |
| Maintainer unresponsive | **Fork** | Gain control, can always merge back later |
| Performance optimization | **Contribute upstream first** | Try collaboration, fork only if rejected |
| Security fix | **Contribute upstream ASAP** | Critical for ecosystem |

### Fork Maintenance Plan

**If we fork dart_libp2p:**

1. **Initial Fork**: 
   - Create `github.com/kashcube/dart_libp2p`
   - Branch: `main` (track upstream), `kashcube-custom` (our changes)

2. **Keep Sync with Upstream**:
   ```bash
   git remote add upstream https://github.com/stephanfeb/dart_libp2p.git
   git fetch upstream
   git merge upstream/main  # periodically merge upstream changes
   ```

3. **Contribution Flow**:
   - Develop features in `kashcube-custom` branch
   - For general features: cherry-pick to separate branch, PR to upstream
   - For KashCube-only: keep in custom branch

4. **Documentation**:
   - Maintain `KASHCUBE_CHANGES.md` documenting all divergences
   - Tag releases: `v1.0.3-kashcube.1`, `v1.0.3-kashcube.2`

### Customization Examples for KashCube

**Example 1: Add BLE Transport** (if needed for offline sync)

```dart
// In forked dart_libp2p:
// lib/p2p/transport/ble_transport.dart

class BLETransport implements Transport {
  @override
  Future<Connection> dial(MultiAddr addr) async {
    // Use flutter_blue_plus to establish BLE connection
    final device = await _findBLEDevice(addr);
    await device.connect();
    return BLEConnection(device);
  }
  
  @override
  Future<Listener> listen(MultiAddr addr) async {
    // Start BLE advertising
    return BLEListener();
  }
}
```

**Example 2: Add Custom Relay Policy** (conditional hosting)

```dart
// In KashCube app (no fork needed):
// lib/data/services/libp2p_relay_policy.dart

class KashCubeRelayPolicy {
  bool shouldRelay(PeerId peer, SyncEnvelope envelope) {
    // Check if peer is authorized to relay this envelope
    final scope = envelope.businessScope;
    final peerPerms = _trustedPeersRepo.getPermissions(peer);
    
    if (scope == BusinessScope.personal && peerPerms.hasPersonalAccess) {
      return true;
    }
    
    if (scope == BusinessScope.business && peerPerms.hasBusinessAccess) {
      return true;
    }
    
    return false;  // Deny by default
  }
}
```

**Example 3: Optimize for Finance Use Case** (if perf issues)

```dart
// In forked dart_libp2p (if upstream won't accept):
// lib/core/network/swarm.dart

class Swarm {
  // KashCube optimization: prioritize transaction sync streams
  Stream<Message> _prioritizeFinancialData(Stream<Message> incoming) {
    return incoming.transform(StreamTransformer.fromHandlers(
      handleData: (msg, sink) {
        if (msg.protocolID == '/kash-sync/1.0.0') {
          sink.add(msg);  // Process immediately
        } else {
          _lowPriorityQueue.add(msg);  // Defer non-financial data
        }
      },
    ));
  }
}
```

### License Check: Can We Fork?

**Next Action**: Verify dart_libp2p license (likely MIT or Apache 2.0, both fork-friendly).

```bash
curl -s https://raw.githubusercontent.com/stephanfeb/dart_libp2p/main/LICENSE
```

**If MIT/Apache**: ✅ Full freedom to fork, modify, redistribute  
**If GPL**: ⚠️ Must keep GPL (disclose source), usually fine for open source apps  
**If proprietary**: ❌ Cannot fork without permission (unlikely for pub.dev package)

---

**Changelog**:
- **6 April 2026**: Initial version with Go FFI approach
- **6 April 2026 (update)**: Pivoted to dart_libp2p after package discovery — eliminated entire FFI layer, accelerated timeline by 4-6 weeks
- **6 April 2026 (update 2)**: Added customization/fork strategy — confirmed full control over dependency
**Next Review**: After Phase 0 completion (2 weeks from now).

**Owner**: KashCube Core Team

