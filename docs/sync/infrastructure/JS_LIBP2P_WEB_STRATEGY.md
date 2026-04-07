# js-libp2p for Web Companion Strategy

Date: 6 April 2026  
Status: Technical evaluation  
Related: LIBP2P_FLUTTER_IMPLEMENTATION_PLAN.md, DART_LIBP2P_GAP_ANALYSIS.md

## Executive Summary

**Recommendation**: ✅ **Use hybrid approach** — dart_libp2p for mobile/desktop, js-libp2p for web companion.

**Rationale**:
- js-libp2p is the **official** JavaScript implementation (mature, battle-tested)
- Designed for browsers (WebSocket, WebRTC Browser-to-Server transports)
- Full interoperability with dart_libp2p via standard libp2p protocols
- Solves dart_libp2p's missing WebSocket transport
- Leverages existing KashCube web companion architecture

---

## Current Web Companion Architecture

### Existing Setup (as of v90)

**Tech Stack**:
- Flutter web compilation (same Dart codebase as mobile)
- Web-specific services:
  - `WebBrowserSession` — session management
  - `WebCompanionService` — wake-lock, lifecycle
  - `WebSessionService` — LAN connection to phone
  - `WebCompanionAuthQR` — QR code pairing

**Sync Model**:
- Web companion connects to phone app over **local network**
- Single-use token authentication via QR scan
- Sync happens phone ↔ web (phone is "primary" device)
- Web does NOT sync directly with other devices (always via phone)

**Current Transport**: Likely WebSocket or WebRTC (need to verify)

---

## Proposed: js-libp2p Integration

### Two Implementation Approaches

#### **Option A: JavaScript Interop** (Keep Flutter Web)

**Architecture**:
```
┌─────────────────────────────────────┐
│  Flutter Web UI (Dart)              │
│  - Business logic                   │
│  - State management (Riverpod)      │
│  - SQLite (sqflite_web via IndexedDB)│
└───────────────┬─────────────────────┘
                │ @JS() interop
┌───────────────▼─────────────────────┐
│  js-libp2p Wrapper (JavaScript)     │
│  - Load via <script> tag            │
│  - Expose API to Dart via window.jsLibp2p│
│  - Handle libp2p lifecycle          │
└───────────────┬─────────────────────┘
                │ libp2p protocols
┌───────────────▼─────────────────────┐
│  dart_libp2p Peers (Mobile/Desktop) │
│  - Phone app                        │
│  - Tablet app                       │
│  - Desktop app                      │
└─────────────────────────────────────┘
```

**How It Works**:
1. Flutter web compiles to JavaScript as usual
2. Load js-libp2p as external script in `index.html`:
   ```html
   <script src="https://cdn.jsdelivr.net/npm/libp2p@latest/dist/index.min.js"></script>
   <script src="libp2p_bridge.js"></script>
   ```
3. Dart uses `@JS()` annotations to call JavaScript functions:
   ```dart
   @JS('jsLibp2p.createNode')
   external Object createNode(JsObject config);
   
   @JS('jsLibp2p.dial')
   external void dial(String peerId, String protocol);
   ```
4. JavaScript bridge handles libp2p lifecycle, exposes promises to Dart

**Pros**:
- ✅ Keep existing Flutter web codebase
- ✅ Same Dart UI/business logic across all platforms
- ✅ Use js-libp2p only for transport layer
- ✅ Minimal code changes (just sync transport)

**Cons**:
- ⚠️ JavaScript interop boilerplate
- ⚠️ Type safety gaps at JS/Dart boundary
- ⚠️ Debugging across two languages
- ⚠️ Larger bundle size (Flutter + libp2p)

#### **Option B: Separate JavaScript App** (Rewrite Web Companion)

**Architecture**:
```
┌─────────────────────────────────────┐
│  React/Vue/Svelte Web App (JS/TS)   │
│  - UI components                    │
│  - State management (Redux/Zustand) │
│  - SQLite (sql.js via WASM)         │
│  - Direct js-libp2p integration     │
└───────────────┬─────────────────────┘
                │ native js-libp2p
┌───────────────▼─────────────────────┐
│  dart_libp2p Peers (Mobile/Desktop) │
└─────────────────────────────────────┘
```

**How It Works**:
1. Rewrite web companion as pure JavaScript app
2. Use js-libp2p directly (no Dart at all)
3. Implement sync logic in JavaScript
4. Maintain separate codebase from mobile/desktop

**Pros**:
- ✅ Native js-libp2p usage (idiomatic JavaScript)
- ✅ Smaller bundle size (no Flutter web overhead)
- ✅ Better browser debugging (Chrome DevTools)
- ✅ Easier to optimize for web

**Cons**:
- ❌ **Maintain two codebases** (Dart + JavaScript)
- ❌ Duplicate business logic
- ❌ Duplicate UI components
- ❌ More development effort
- ❌ Consistency issues between platforms

---

## Recommended: Option A (JavaScript Interop)

**Why**: Maintains "write once, run anywhere" philosophy while leveraging js-libp2p's browser strengths.

### Implementation Plan

#### Phase 1: JavaScript Bridge (1 week)

**Create `web/libp2p_bridge.js`**:
```javascript
// Wrapper around js-libp2p for Dart interop
(function() {
  let node = null;
  
  window.jsLibp2p = {
    async createNode(config) {
      const { createLibp2p } = await import('libp2p');
      const { webSockets } = await import('@libp2p/websockets');
      const { noise } = await import('@chainsafe/libp2p-noise');
      const { yamux } = await import('@chainsafe/libp2p-yamux');
      
      node = await createLibp2p({
        addresses: {
          listen: ['/ip4/0.0.0.0/tcp/0/ws']
        },
        transports: [webSockets()],
        connectionEncryption: [noise()],
        streamMuxers: [yamux()],
        ...JSON.parse(config)
      });
      
      await node.start();
      return node.peerId.toString();
    },
    
    async dial(peerIdStr, multiaddr) {
      const connection = await node.dial(multiaddr);
      return connection.id;
    },
    
    registerProtocol(protocol, handler) {
      node.handle(protocol, async ({ stream }) => {
        // Convert stream to Dart-friendly format
        handler(stream.id);
      });
    },
    
    async close() {
      await node.stop();
    }
  };
})();
```

**Update `web/index.html`**:
```html
<head>
  <!-- Existing KashCube meta tags... -->
  
  <!-- js-libp2p -->
  <script type="module" src="libp2p_bridge.js"></script>
</head>
```

#### Phase 2: Dart Interop Layer (1 week)

**Create `lib/data/services/web/js_libp2p_interop.dart`**:
```dart
@JS()
library js_libp2p;

import 'package:js/js.dart';

@JS('jsLibp2p.createNode')
external Object _createNode(String configJson);

@JS('jsLibp2p.dial')
external Object _dial(String peerId, String multiaddr);

@JS('jsLibp2p.registerProtocol')
external void _registerProtocol(String protocol, Function handler);

@JS('jsLibp2p.close')
external Object _close();

class JsLibp2pNode {
  Future<String> createNode(Map<String, dynamic> config) async {
    final configJson = jsonEncode(config);
    final result = await promiseToFuture(_createNode(configJson));
    return result as String;
  }
  
  Future<String> dial(String peerId, String multiaddr) async {
    final result = await promiseToFuture(_dial(peerId, multiaddr));
    return result as String;
  }
  
  void registerProtocol(String protocol, Function(String streamId) handler) {
    _registerProtocol(protocol, allowInterop(handler));
  }
  
  Future<void> close() async {
    await promiseToFuture(_close());
  }
}
```

#### Phase 3: Sync Repository (Web Platform) (2 weeks)

**Create `lib/data/repositories/sync_repository_web.dart`**:
```dart
/// Web-specific sync repository using js-libp2p
class WebLibp2pSyncRepository implements SyncRepository {
  final JsLibp2pNode _node = JsLibp2pNode();
  String? _peerId;
  
  @override
  Future<void> initialize() async {
    _peerId = await _node.createNode({
      'protocols': ['/kash-sync/1.0.0'],
    });
    
    _node.registerProtocol('/kash-sync/1.0.0', _handleSyncStream);
  }
  
  void _handleSyncStream(String streamId) {
    // Handle incoming sync messages
    // Same logic as mobile version, different transport
  }
  
  @override
  Future<void> sendEnvelope(String peerId, SyncEnvelope envelope) async {
    final multiaddr = '/ip4/192.168.1.100/tcp/4001/ws/p2p/$peerId';
    await _node.dial(peerId, multiaddr);
    // Send envelope bytes via stream...
  }
}
```

#### Phase 4: Platform Switching (1 week)

**Update `lib/data/providers/sync_providers.dart`**:
```dart
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  if (kIsWeb) {
    return WebLibp2pSyncRepository(
      database: ref.read(databaseProvider),
      node: JsLibp2pNode(),
    );
  } else {
    return Libp2pSyncRepositoryImpl(
      database: ref.read(databaseProvider),
      node: ref.read(libp2pNodeProvider),
    );
  }
});
```

---

## js-libp2p Feature Coverage

### ✅ What js-libp2p Provides (Browser Context)

| Feature | js-libp2p | dart_libp2p| Best For |
|---------|-----------|------------|----------|
| **WebSocket Transport** | ✅ Native | ❌ Missing | ✅ **js-libp2p** |
| **WebRTC Browser-to-Server** | ✅ Native | ❌ Missing | ✅ **js-libp2p** |
| **WebRTC Browser-to-Browser** | ✅ Via @libp2p/webrtc | ❌ | ✅ **js-libp2p** |
| **Noise Protocol** | ✅ @chainsafe/libp2p-noise | ✅ | Tie |
| **Yamux Multiplexing** | ✅ @chainsafe/libp2p-yamux | ✅ | Tie |
| **Circuit Relay v2** | ✅ @libp2p/circuit-relay-v2 | ✅ | Tie |
| **mDNS Discovery** | ⚠️ Limited (browser restrictions) | ✅ | ✅ **dart_libp2p** |
| **Kademlia DHT** | ✅ @libp2p/kad-dht | ✅ | Tie |
| **GossipSub** | ✅ @chainsafe/libp2p-gossipsub | ✅ | Tie |
| **Custom Protocols** | ✅ | ✅ | Tie |

**Verdict**: js-libp2p is **perfect for browsers** — has WebSocket + WebRTC that dart_libp2p lacks.

### Interoperability Matrix

| Scenario | dart_libp2p (Mobile) | js-libp2p (Web) | Protocol | Works? |
|----------|---------------------|-----------------|----------|--------|
| Web → Phone (direct) | TCP listener | WebSocket dial | ❌ Incompatible | ✅ Via relay |
| Web → Phone (relay) | Via relay server | Via relay server | Circuit Relay v2 | ✅ Yes |
| Web → Desktop | TCP listener | WebSocket dial | ❌ Incompatible | ✅ Via relay |
| Web → Web | WebRTC | WebRTC | WebRTC browser-to-browser | ✅ Yes |
| Phone → Phone | TCP/UDX | N/A | Direct | ✅ Yes |

**Key Insight**: Web companion would use **relay mode** to talk to mobile/desktop peers (since browsers can't initiate raw TCP connections).

---

## Architecture: Hybrid Approach

### Network Topology

```
┌──────────────────┐
│   Web Companion  │ (js-libp2p, WebSocket only)
│   (Browser)      │
└────────┬─────────┘
         │ WebSocket to relay
         │
    ┌────▼─────────────┐
    │  Relay Server    │ (go-libp2p or dart_libp2p peer)
    │  (Optional)      │ Can be phone/desktop in "relay mode"
    └────┬─────────────┘
         │
    ┌────▼──────────────┐
    │  Phone App        │ (dart_libp2p, TCP/UDX)
    │  (Primary Device) │
    └────┬──────────────┘
         │
    ┌────▼──────────────┐
    │  Tablet/Desktop   │ (dart_libp2p, TCP/UDX)
    └───────────────────┘
```

**Flow**:
1. Web companion dials phone via relay (WebSocket transport)
2. Phone acts as relay for web ↔ other devices
3. Web never talks raw TCP (browser sandboxing prevents it)
4. All sync envelopes encrypted end-to-end (relay can't decrypt)

---

## Bundle Size Impact

### Current (Flutter Web + WebRTC)

Typical Flutter web build:
- Main bundle: ~2-3 MB (compressed)
- Includes: Flutter engine, Dart SDK, app code

### With js-libp2p (Option A)

Additional size:
- js-libp2p core: ~180 KB (gzipped)
- @libp2p/websockets: ~15 KB
- @chainsafe/libp2p-noise: ~35 KB
- @chainsafe/libp2p-yamux: ~12 KB
- **Total added**: ~250 KB (gzipped)

**New total**: ~2.5-3.3 MB (acceptable for web app)

### With Separate JS App (Option B)

- React/Vue app: ~500 KB (base)
- js-libp2p: ~250 KB
- sql.js (WASM): ~800 KB
- App code: ~300 KB
- **Total**: ~1.8 MB (smaller, but duplicate codebase)

**Verdict**: Option A adds ~10% to bundle size but avoids codebase duplication.

---

## Development Effort Comparison

| Task | Option A (Interop) | Option B (Separate JS) |
|------|-------------------|----------------------|
| JavaScript bridge | 1 week | 0 (native JS) |
| Dart interop layer | 1 week | 0 (no Dart) |
| Web sync repository | 2 weeks | 3 weeks (rewrite in JS) |
| Platform switching | 1 week | 1 week |
| UI duplication | 0 (shared Dart UI) | **4-8 weeks** (rebuild UI) |
| Business logic duplication | 0 (shared Dart) | **4-6 weeks** (rewrite in JS) |
| **Total** | **5 weeks** | **12-18 weeks** |

**Savings**: Option A is **7-13 weeks faster** (2.4-3.6x speedup).

---

## Risks and Mitigation

### Risk 1: Dart ↔ JavaScript Boundary Issues

**Probability**: Medium  
**Impact**: Medium

**Symptoms**:
- Type conversion errors (Dart objects → JS objects)
- Async promise handling bugs
- Memory leaks from improper cleanup

**Mitigation**:
- Use `package:js` and `dart:js_util` (official Dart JS interop)
- Wrap all JS calls in try-catch with fallback
- Add integration tests for Dart ↔ JS boundary
- Profile memory usage during long-running sessions

### Risk 2: js-libp2p Version Compatibility

**Probability**: Low  
**Impact**: Medium

**Symptoms**:
- dart_libp2p (uses libp2p spec v1) ↔ js-libp2p (newer spec) incompatibility
- Protocol negotiation failures

**Mitigation**:
- Pin js-libp2p to specific version tested with dart_libp2p
- Test cross-compatibility before each release
- Use relay mode (relay handles protocol translation)
- Contribute compatibility fixes upstream if needed

### Risk 3: Browser Security Restrictions

**Probability**: High  
**Impact**: Low

**Symptoms**:
- Can't bind raw TCP sockets (browser limitation)
- CORS issues with WebSocket connections
- IndexedDB quota limits

**Mitigation**:
- ✅ Already planned: use relay mode (no raw TCP needed)
- Configure CORS headers on relay server
- Implement quota management (warn user at 80% storage)

---

## Migration Path

### Phase 0: Current State

- Web companion uses custom WebSocket/WebRTC sync
- Phone ↔ Web sync works via QR pairing

### Phase 1: Add js-libp2p to Web (Week 1-5)

- [ ] Add js-libp2p JavaScript bridge
- [ ] Implement Dart interop layer
- [ ] Create `WebLibp2pSyncRepository`
- [ ] Add feature flag: "Use libp2p for web sync"
- [ ] Test web ↔ phone relay sync

### Phase 2: Mobile/Desktop gets dart_libp2p (Week 6-11)

- [ ] Add dart_libp2p to mobile/desktop (per existing plan)
- [ ] Implement `Libp2pSyncRepositoryImpl`
- [ ] Test mobile ↔ mobile direct sync
- [ ] Test mobile relay mode

### Phase 3: Cross-Platform Testing (Week 12-14)

- [ ] Test web (js-libp2p) ↔ phone (dart_libp2p) via relay
- [ ] Test web ↔ desktop via relay
- [ ] Test web ↔ web (WebRTC browser-to-browser)
- [ ] Verify all 40+ tables sync correctly

### Phase 4: Production Rollout (Week 15-20)

- [ ] Alpha test (10 users, all platforms)
- [ ] Beta test (100 users)
- [ ] Monitor metrics (latency, errors, battery)
- [ ] Default to libp2p (v1.11)
- [ ] Deprecate old sync (v1.12)

---

## Alternative: Try dart_libp2p on Web First

**Before committing to js-libp2p**, test if dart_libp2p compiles to web at all.

**Quick Test** (30 minutes):
```yaml
# pubspec.yaml
dependencies:
  dart_libp2p: ^1.0.3

# Try to compile for web
flutter build web
```

**Possible Outcomes**:

1. **Compiles but WebSocket missing** → Use js-libp2p (as planned)
2. **Compiles with WebSocket via js interop** → Maybe stick with dart_libp2p!
3. **Doesn't compile due to dart:io usage** → Definitely use js-libp2p

**Action**: Test dart_libp2p web compilation before implementing js-libp2p bridge.

---

## Recommendation Summary

### ✅ **RECOMMENDED: Hybrid Approach**

**Mobile/Desktop**: dart_libp2p (pure Dart)  
**Web Companion**: js-libp2p via JavaScript interop (Option A)

**Rationale**:
1. Leverages best implementation for each platform
2. Maintains single Dart codebase (Flutter web)
3. Solves dart_libp2p's WebSocket gap elegantly
4. 5-week implementation (vs 12-18 weeks for separate JS app)
5. Official libp2p implementations (both mature)
6. Proven interoperability (js-libp2p ↔ go-libp2p, dart_libp2p ↔ go-libp2p)

**Trade-offs**:
- ⚠️ JavaScript interop complexity (acceptable)
- ⚠️ +250 KB bundle size (acceptable for web)
- ⚠️ Web uses relay mode (acceptable, already planned)

**Confidence**: **High (85%)** — Best pragmatic solution.

---

## Next Steps

### Immediate (This Week)

1. **Test dart_libp2p web compilation** (30 minutes)
   - Add dependency, try `flutter build web`
   - Check if WebSocket transport available
   - **Go/No-Go**: If works without js-libp2p, use pure dart_libp2p

2. **Prototype js-libp2p bridge** (1 day)
   - Create minimal `libp2p_bridge.js`
   - Test `window.jsLibp2p.createNode()` call from Dart
   - Verify @JS() interop works

### Short-Term (Next 2 Weeks)

1. **Decide on dart_libp2p vs js-libp2p for web** (after testing)
2. **If js-libp2p**: Implement full bridge + Dart interop
3. **If dart_libp2p**: Skip js-libp2p entirely, use pure Dart

### Medium-Term (Next Month)

1. **Implement web sync repository** (chosen transport)
2. **Test web ↔ phone relay sync**
3. **Benchmark performance** (latency, bundle size, battery on phone relay mode)

---

**Decision Date**: 6 April 2026  
**Test Deadline**: 7 April 2026 (dart_libp2p web compilation test)  
**Review Date**: After web compilation test + js-libp2p prototype  
**Owner**: KashCube Core Team

**Changelog**:
- 6 April 2026: Initial hybrid strategy proposal (dart_libp2p + js-libp2p)
