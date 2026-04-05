# KashCube — Web Companion Hardening Plan

**Version:** 1.0  
**Date:** 27 March 2026  
**Status:** Production Readiness Assessment  
**Objective:** Address 6 critical gaps preventing web companion ("Open on Laptop") from being production-ready  

---

## Executive Summary

Current implementation (v1.0 spec) is **architecturally sound** but **operationally fragile**. The Flask-equivalent HTTP server (`shelf`) works reliably while the app is in foreground, but fails inconsistently when:
- User minimizes KashCube
- Device enters doze mode
- Network stack deprioritizes process
- Port 50505 is already bound by another app
- Web build hasn't been extracted before first browser request

This plan addresses 6 specific gaps with concrete patches, prioritized by dependency order. **Priority 1 work is blocking** — assets, auth, and protocol hardening won't matter if the connection drops randomly.

---

## Implementation Status (28 March 2026)

### Completed code phases

1. **Phase 1 (Lifecycle foundation)** — ✅ implemented
  - Commit: `74607f1`
  - Delivered: wake-lock lifecycle service, browser connect/disconnect wiring, app lifecycle hooks

2. **Phase 2 (Asset pre-warm + readiness gate)** — ✅ implemented
  - Commit: `dcf0faf`
  - Delivered: eager web UI extraction, `/health` readiness route, QR wait-until-healthy flow

3. **Phase 3 (Port fallback)** — ✅ implemented
  - Commit: `3debe25`
  - Delivered: preferred-port bind then random fallback, runtime-port QR behavior

4. **Phase 4 (Docs + scripted QA foundation)** — ✅ implemented
  - Commit: `d9b3fbc`
  - Delivered: OEM hotspot support matrix in spec and executable checklist script

### Supporting commits

- `7d9cfb3` — hardening plan document + generated plugin registrant update

### Remaining work (manual / device validation)

- Run real-device hotspot matrix tests (Pixel, Samsung, Xiaomi, Redmi)
- Run 5+ minute background stability test on Android hardware
- Run explicit port-conflict test with port 50505 occupied
- Record outcomes in release notes / known-issues tracking

---

## Gap Analysis

### Gap 1: Lifecycle — Server Dies When App Backgrounded

**Severity:** 🔴 CRITICAL — Blocks all usage  
**Impact:** Browser loses WebSocket connection when user minimizes app or device dozes  
**Root Cause:** Server lifecycle tied to `P2pCoordinator` running in app foreground process; no foreground service or keep-alive policy  
**Current Behavior:** App in foreground → server runs; app backgrounded → process deprioritized → WebSocket drops within 10–30 seconds  

**Proposed Solution:** Migrate server lifecycle to dedicated `WebCompanionService` with foreground service or explicit [WorkManager](https://github.com/fluttercommunity/flutter_workmanager) keep-alive  

**Implementation Approach:**
1. Create `lib/data/services/web/web_companion_service.dart` — independent lifecycle
2. Wire into `main.dart` lifecycle observer (separate from P2pCoordinator)
3. Android: Use `WorkManager` with periodic tinyTask (5-min wake lock) if browser connected
4. Flutter: Add `wakelock` package to hold CPU/WiFi wake lock while browser active

**Effort:** 🟠 Medium (3–4 days)  
**Dependencies:** `wakelock_plus` package (add to pubspec)  
**Priority:** 1️⃣ **BLOCKING** — must complete before testing P2P features

**Code Locations to Modify:**
- Create: `lib/data/services/web/web_companion_service.dart`
- Modify: [lib/main.dart](lib/main.dart) (lifecycle observer)
- Modify: [lib/data/services/p2p/p2p_coordinator.dart](lib/data/services/p2p/p2p_coordinator.dart) (decouple server start/stop from coordinator)

**Implementation Checklist:**
- [ ] Create `WebCompanionService` as singleton
- [ ] Add `wakelock_plus: ^1.2.0` to pubspec
- [ ] Move `P2pServer.startServerOnly()` to `WebCompanionService.start()`
- [ ] Override `main.dart` lifecycle to call `WebCompanionService.holdWakeLock()` while browser connected
- [ ] Test: Minimize app → keep QR displayed on laptop → browser should remain connected for 5+ min
- [ ] Test: Device enters doze → browser remains connected

---

### Gap 2: Asset Serving — Lazy Extraction Creates Failure Window

**Severity:** 🟠 HIGH — Creates bad user experience; recovery unclear  
**Impact:** First browser request triggers extraction; if extraction slow (>30s) or fails, browser shows 500/timeout  
**Root Cause:** `WebUiExtractor.getExtractedPath()` called on first `GET /*` request, not during server startup  
**Current Behavior:** QR shown → user scans → browser connects → server busy extracting → 500 or timeout  

**Proposed Solution:** Extract web build **before** server starts; fail fast if extraction fails  

**Implementation Approach:**
1. Move extraction logic from lazy handler to `WebCompanionService.start()`
2. Extract synchronously during startup; throw exception if fails
3. Add pre-flight check: `WebCompanionService.isReady()` → used by `OpenOnLaptopScreen` before showing QR
4. Update QR screen to show "Extracting web build..." message until ready

**Effort:** 🟢 Small (1–2 days)  
**Dependencies:** None (uses existing `WebUiExtractor`)  
**Priority:** 2️⃣ (depends on Gap 1: need `WebCompanionService` first)

**Code Locations to Modify:**
- Modify: [lib/data/services/web/web_ui_extractor.dart](lib/data/services/web/web_ui_extractor.dart) (add sync extraction method)
- Modify: `lib/data/services/web/web_companion_service.dart` (call extraction in `start()`)
- Modify: [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) (add isReady check + loading UI)

**Implementation Checklist:**
- [ ] Add `Future<void> extractNow()` method to `WebUiExtractor`
- [ ] Call `WebUiExtractor.extractNow()` in `WebCompanionService.start()` before `P2pServer.start()`
- [ ] Add `WebCompanionService.isReady()` → returns `true` after extraction complete
- [ ] Update `OpenOnLaptopScreen` to show loading state until `isReady()`
- [ ] Test: Start server → browser connects immediately → no extraction latency visible
- [ ] Test: Simulate extraction failure → error message shown instead of QR

---

### Gap 3: Port Binding — Fixed 50505, No Fallback Strategy

**Severity:** 🟠 HIGH — Silent failure on shared networks / VPN  
**Impact:** Port 50505 already in use → P2pServer bind fails silently → browser gets "connection refused"  
**Root Cause:** [lib/core/constants/app_constants.dart](lib/core/constants/app_constants.dart) hardcodes `p2pPort = 50505`; no fallback  
**Current Behavior:** If 50505 occupied, server doesn't start; QR still shows 50505 → user scans → error  

**Proposed Solution:** Implement dynamic port binding: try 50505, then random OS-assigned port with automatic retry  

**Implementation Approach:**
1. Modify `P2pServer.start()` to use `InternetAddress.loopbackIPv4.bind()` with port 0 (random) as fallback
2. Store actual bound port in `P2pServer.boundPort`
3. Update `OpenOnLaptopScreen` to read actual port (not constant) when generating QR
4. Log port binding attempt/success in server startup

**Effort:** 🟢 Small (1 day)  
**Dependencies:** None (uses Dart `dart:io`)  
**Priority:** 3️⃣ (independent; implement after Gap 1+2 for completeness)

**Code Locations to Modify:**
- Modify: [lib/data/services/p2p/p2p_server.dart](lib/data/services/p2p/p2p_server.dart) (`startServer()` method)
- Modify: [lib/core/constants/app_constants.dart](lib/core/constants/app_constants.dart) (mark as fallback default, not guarantee)
- Modify: [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) (use bound port, not constant)

**Implementation Checklist:**
- [ ] Modify `P2pServer._startServer()` to attempt port 50505, retry with port 0
- [ ] Store `_boundPort` as instance variable
- [ ] Add getter `int get boundPort`
- [ ] Update QR generation to use `P2pServer.instance.boundPort` instead of constant
- [ ] Test: Manually bind port 50505 → server falls back to random → QR shows random port → browser connects
- [ ] Test: Port available → server binds 50505 successfully

---

### Gap 4: Readiness Probe — No Validation Before QR Display

**Severity:** 🟡 MEDIUM — User scans QR, gets "connection refused" error  
**Impact:** QR shown immediately after `startServerOnly()`; server may not be fully ready  
**Root Cause:** No explicit health check before advertising port/token to browser  
**Current Behavior:** QR displayed → user scans → browser tries to connect → static handler not ready yet → 500  

**Proposed Solution:** Add explicit readiness probe (`GET /health`) that validates socket, static serve, and WS route  

**Implementation Approach:**
1. Add route `GET /health` to `P2pServer` → returns `200 OK` only after all handlers ready
2. Call `GET /health` from `OpenOnLaptopScreen` before showing QR
3. If probe fails, show retry UI instead of QR
4. Poll `/health` every 2s until ready (max 30s timeout)

**Effort:** 🟢 Small (1–2 days)  
**Dependencies:** Gap 1+2 (need async readiness context)  
**Priority:** 2️⃣ (implement alongside Gap 2)

**Code Locations to Modify:**
- Modify: [lib/data/services/p2p/p2p_server.dart](lib/data/services/p2p/p2p_server.dart) (add `/health` route)
- Modify: [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) (add health check before QR)

**Implementation Checklist:**
- [ ] Add `/health` route to P2pServer router → checks:
  - [ ] Static handler cache populated (assets extracted)
  - [ ] Shelf server accepting connections
  - [ ] WebSocket handler registered
- [ ] Add async `Future<bool> isHealthy()` method to `P2pServer`
- [ ] In `OpenOnLaptopScreen.initState()`, poll health until ready
- [ ] Test: Server starting → backend shows "Server warming up..." → after 2–5s, QR appears
- [ ] Test: Simulate handler failure → health probe returns 500 → UI shows error + retry button

---

### Gap 5: Hotspot Mode — OEM-Specific Variance Not Documented

**Severity:** 🟡 MEDIUM — Works on Pixel/Samsung, fails on Xiaomi/Redmi hotspots  
**Impact:** User tested feature on device A (works) → shares with friend on device B (fails) → no clear reason  
**Root Cause:** Android hotspot isolation varies by OEM; no per-device testing or documentation  
**Current Behavior:** Hotspot on Pixel connects reliably; Xiaomi hotspot isolation blocks LAN device → WS drops  

**Proposed Solution:** Document OEM support matrix; recommend WiFi Direct / Bluetooth as fallback for unsupported devices  

**Implementation Approach:**
1. Add section to `WEB_COMPANION_SPEC.md`: "Known OEM Limitations"
2. Test on: Pixel 7, Samsung S24, Xiaomi 13, Redmi Note 12
3. Document workaround: "If hotspot fails, ask browser user to connect to same WiFi router (not hotspot)"
4. Future v2: Add WiFi Direct fallback channel (separate track, not this plan)

**Effort:** 🟡 Medium (testing) + 🟢 Small (doc) = **2–3 days**  
**Dependencies:** Gap 1 (need stable connection to test thoroughly)  
**Priority:** 4️⃣ (implement after core hardening to validate on stable connection)

**Code Locations to Modify:**
- None (no code changes, testing + documentation only)
- Add: section in `WEB_COMPANION_SPEC.md`

**Testing Checklist:**
- [ ] Pixel 7 hotspot → browser on laptop → expect ✅ stable connection
- [ ] Samsung S24 hotspot → expect ✅ stable
- [ ] Xiaomi 13 hotspot → expect ⚠️ intermittent (document limitation)
- [ ] Redmi Note 12 hotspot → expect ⚠️ intermittent
- [ ] Workaround test: Both devices on same WiFi router → expect ✅ stable
- [ ] Add findings to `KNOWN_ISSUES.md` / OEM support matrix

---

### Gap 6: Architecture — Web Server Lifecycle Coupled to P2P Sync

**Severity:** 🟡 MEDIUM — Can't run web companion without P2P sync enabled  
**Impact:** User may want pure web companion on air-gapped network; P2P sync features reserved for other network  
**Root Cause:** `P2pServer` instance and `P2pCoordinator` logic are interdependent; no clean separation  
**Current Behavior:** P2P sync disabled → web companion disabled automatically  

**Proposed Solution:** Decouple `WebCompanionService` from `P2pCoordinator`; allow independent startup  

**Implementation Approach:**
1. This is achieved by implementing Gap 1 (`WebCompanionService` as independent service)
2. User can disable P2P sync in settings but leave web companion enabled
3. Settings UI: "Enable Web Companion" (independent toggle from "Enable LAN Sync")

**Effort:** 🟢 Small (1 day; achieved via Gap 1 refactor)  
**Dependencies:** Gap 1  
**Priority:** 3️⃣ (implement as part of Gap 1 refactor)

**Code Locations to Modify:**
- Achieved by: `WebCompanionService` implementation (Gap 1)
- Modify: [lib/presentation/screens/settings/settings_screen.dart](lib/presentation/screens/settings/settings_screen.dart) (add independent toggle if exists)

**Implementation Checklist:**
- [ ] Ensure `WebCompanionService` starts independently (no P2pCoordinator required)
- [ ] Test: LAN sync disabled → web companion still runs
- [ ] Test: LAN sync enabled → both features coexist

---

## Patch List (Execution Order)

### Phase 1: Lifecycle Foundation (Gap 1)
*Blocking dependency for all other phases*

| Patch ID | File | Change | Lines | Est. Hours |
|----------|------|--------|-------|-----------|
| P1-001 | `pubspec.yaml` | Add `wakelock_plus: ^1.2.0` | - | 0.25 |
| P1-002 | Create `lib/data/services/web/web_companion_service.dart` | New service singleton for web companion lifecycle | - | 3 |
| P1-003 | [lib/main.dart](lib/main.dart) | Modify lifecycle observer to hold wake lock while browser connected | ~30 | 1 |
| P1-004 | [lib/data/services/p2p/p2p_coordinator.dart](lib/data/services/p2p/p2p_coordinator.dart) | Decouple `P2pServer` start/stop from coordinator; add callout to `WebCompanionService` | ~50 | 1.5 |
| **Phase 1 Total** | | | | **≈ 5.75 hours** |

### Phase 2: Asset Pre-Warming & Readiness (Gaps 2 + 4)
*Depends on Phase 1*

| Patch ID | File | Change | Lines | Est. Hours |
|----------|------|--------|-------|-----------|
| P2-001 | [lib/data/services/web/web_ui_extractor.dart](lib/data/services/web/web_ui_extractor.dart) | Add sync `extractNow()` method | ~20 | 0.5 |
| P2-002 | `lib/data/services/web/web_companion_service.dart` | Call extraction in `start()` before server init; add `isReady()` getter | ~15 | 1 |
| P2-003 | [lib/data/services/p2p/p2p_server.dart](lib/data/services/p2p/p2p_server.dart) | Add `GET /health` route; add `isHealthy()` method | ~30 | 1 |
| P2-004 | [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) | Add health check loop before QR display; show loading state | ~40 | 1.5 |
| **Phase 2 Total** | | | | **≈ 4 hours** |

### Phase 3: Port Binding (Gap 3)
*Independent; can run parallel to Phase 2*

| Patch ID | File | Change | Lines | Est. Hours |
|----------|------|--------|-------|-----------|
| P3-001 | [lib/data/services/p2p/p2p_server.dart](lib/data/services/p2p/p2p_server.dart) | Implement port fallback logic (try 50505 → random) | ~40 | 1.5 |
| P3-002 | [lib/core/constants/app_constants.dart](lib/core/constants/app_constants.dart) | Update doc comment to clarify port is fallback default | ~5 | 0.25 |
| P3-003 | [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) | Use `P2pServer.instance.boundPort` instead of constant | ~10 | 0.5 |
| **Phase 3 Total** | | | | **≈ 2.25 hours** |

### Phase 4: Testing & Documentation (Gaps 5 + validation)
*Depends on Phases 1–3*

| Task ID | Scope | Est. Hours |
|---------|-------|-----------|
| P4-001 | Test on Pixel 7, Samsung S24 hotspots (expect stable) | 2 |
| P4-002 | Test on Xiaomi 13, Redmi Note 12 (document OEM variance) | 2 |
| P4-003 | Update `WEB_COMPANION_SPEC.md` with OEM support matrix + known issues | 1.5 |
| P4-004 | Create test plan for web companion feature (regression suite) | 2 |
| **Phase 4 Total** | | **≈ 7.5 hours** |

---

## Implementation Timeline

| Phase | Duration | Start | End | Blocker? |
|-------|----------|-------|-----|----------|
| Phase 1: Lifecycle | 5.75 hrs | Day 1 AM | Day 1 PM | 🔴 YES — blocks phases 2–4 |
| Phase 2: Asset + Readiness | 4 hrs | Day 2 AM | Day 2 PM | 🟡 Partial (depends P1) |
| Phase 3: Port Binding | 2.25 hrs | Day 2 PM | Day 2 End | 🟢 NO (parallel to P2) |
| Phase 4: Testing + Docs | 7.5 hrs | Day 3–4 | Day 4 End | 🟢 Validation (can start Day 2 P2 launch) |
| **Total Effort** | **≈ 19.5 hours (2.5 dev days)** | | | |

---

## Success Criteria

### Functional Requirements
- ✅ Browser stays connected while app is backgrounded (5+ min test)
- ✅ Device enters doze mode → browser remains connected (no reconnect required)
- ✅ Web QR shows real port (not hardcoded)
- ✅ Port 50505 unavailable → falls back to random; user sees correct port in QR
- ✅ QR only displayed after server is healthy (no 500 errors on first load)
- ✅ Browser can refresh page → session persists via sessionStorage (no re-auth needed)

### Performance Targets
- ✅ `WebCompanionService.start()` completes within 5 seconds (including asset extraction)
- ✅ `/health` probe responds within 1 second
- ✅ First `GET /` from browser completes within 2 seconds

### Operational Requirements
- ✅ Test documenting OEM hotspot variance (Pixel, Samsung, Xiaomi, Redmi)
- ✅ Error messages are user-friendly ("Server warming up...", "Port already in use, retrying...")
- ✅ Logs capture server lifecycle events (start, stop, health check, port bind attempts)

### Regression Prevention
- ✅ Existing P2P sync tests pass (no breakage)
- ✅ Web companion feature disabled → no crashes or warnings
- ✅ LAN sync disabled, web companion enabled → works independently

---

## Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Wake lock battery drain | 2–5% per hour | Document user setting; auto-disable after 30 min idle |
| Port binding race condition (concurrent start calls) | Server already running → bind fails | Use singleton pattern + no-op if already started |
| Asset extraction slow on older devices | First extraction 30+ seconds | Pre-warm during app startup before showing QR; show "Preparing..." |
| Hotspot mode only works 60% of time on Xiaomi | User frustration; support burden | Document clearly; provide workaround (WiFi router instead) |
| Foreground service permission | Requires Android 12+ targetSdkVersion bump | Use `wakelock_plus` which handles compat; test on API 28+ |

---

## Testing Plan

### Unit Tests
```dart
// test/data/services/web/web_companion_service_test.dart
test('holds wake lock while browser connected', () async {
  // Verify wakelock.toggle called when session active
});

test('releases wake lock when browser disconnects', () async {
  // Verify wakelock.toggle(false) called
});

// test/data/services/p2p/p2p_server_test.dart
test('binds port 50505 on first attempt', () async {
  // Mock serverSocket.bind(port: 50505) → success
});

test('falls back to random port if 50505 unavailable', () async {
  // Mock serverSocket.bind(port: 50505) → fails
  // Verify second call with port: 0 → succeeds
});

test('health check returns 200 when ready', () async {
  // Verify /health after extraction complete
});

test('health check returns 503 when extracting', () async {
  // Verify /health while extraction in progress
});
```

### Integration Tests
```dart
// test/integration/web_companion_lifecycle_test.dart
testWidgets('browser session persists when app backgrounded', (tester) async {
  // 1. Launch app → tap "Open on Laptop"
  // 2. Simulate browser connection via mock WebSocket
  // 3. Send app to background (didChangeAppLifecycleState → paused)
  // 4. Verify browser session still active (ping responds)
  // 5. Wait 5 minutes → verify still connected
});

testWidgets('web build extracted before QR shown', (tester) async {
  // 1. Launch app → tap "Open on Laptop"
  // 2. Verify loading state shown
  // 3. Wait for extraction → QR appears
  // 4. Verify no 500 errors on first browser GET /
});

testWidgets('port fallback on conflict', (tester) async {
  // 1. Bind port 50505 externally (pre-test setup)
  // 2. Launch KashCube → "Open on Laptop"
  // 3. Verify server started on random port (not 50505)
  // 4. Verify QR shows random port (not 50505)
  // 5. Browser connects to random port → success
});
```

### Manual QA Checklist
- [ ] **Lifecycle test:** Open on laptop → tap browser to background → minimize KashCube → wait 5 min → KashCube foreground → browser still connected
- [ ] **Asset test:** Force clear app cache → tap "Open on Laptop" → verify 2–3 sec loading state → QR appears → browser loads within 2s
- [ ] **Port test:** `lsof -i :50505` (use another port) → start KashCube → verify server starts on fallback
- [ ] **Health check test:** Start server → immediately QR → GET /health in browser console → returns 200
- [ ] **Session refresh test:** Connected via QR → refresh browser page → no re-auth (sessionStorage persists)
- [ ] **Hotspot test:** Test on Pixel 7, Samsung S24 (expect ✅); Xiaomi 13, Redmi Note 12 (expect ⚠️ note variance)

### Network Diagnosis (Quick Triage)
Use this 4-step check from Mac when Web Companion fails to open over LAN. Replace `192.168.1.6` with the phone IP shown in QR/logs.

```bash
arp -an | grep 192.168.1.6 || true
ping -c 3 192.168.1.6
nc -vz -w 3 192.168.1.6 50505
curl -i --max-time 5 http://192.168.1.6:50505/health
```

Expected progression:
1. ARP resolves to a MAC address (not `incomplete`)
2. Ping succeeds
3. TCP connect to `:50505` succeeds
4. `/health` returns HTTP `200`

### Architectural Alternative: Hosted Shell + WebRTC

If local Web Companion continues to be operationally fragile, a hosted browser shell plus WebRTC data sync is a valid architectural alternative, but it must be evaluated precisely.

Important distinction:
1. Hosted shell fixes **browser asset delivery**.
2. WebRTC fixes or improves the **session transport/data plane**.
3. Hosted shell alone does **not** fix LAN neighbor discovery, routing, AP isolation, or other L2/L3 path failures between laptop and phone.

Implication for current reliability work:
1. If the dominant failure is slow asset extraction or phone-hosted static serving, hosted shell helps.
2. If the dominant failure is LAN reachability failure (`ARP -> ping -> TCP -> /health`), hosted shell does not solve the root cause.
3. In that case, the more meaningful architectural move is WebRTC transport with stronger signaling/reconnect behavior, not just moving the Flutter web bundle to a hosted origin.

Recommended product posture:
1. Keep **local-first** behavior as the default user experience.
2. Do **not** replace the current local shell with hosted shell as the only path.
3. Treat hosted shell as an explicit secondary mode, primarily aligned with Anywhere Mode or a future hosted-browser bootstrap path.

Recommended target architecture:
1. **Local mode (default):** local signaling + direct WebRTC data channel + phone-approved browser auth.
2. **Anywhere mode (opt-in):** hosted shell + cloud signaling + STUN/TURN fallback + explicit metadata disclosure.
3. Keep signaling/control plane separate from the sync data plane so shell delivery and transport can evolve independently.

Decision guidance:
1. Near term, continue hardening the current local shell path because it preserves the strongest privacy/local-first posture.
2. Mid term, prioritize WebRTC as the browser sync transport because that is the architectural change most likely to improve end-to-end session behavior.
3. Add hosted shell only when product/privacy policy accepts the tradeoff of a remote asset origin and when the goal is better browser bootstrap or Anywhere Mode reachability.

Non-goal:
1. Hosted shell must not turn KashCube into a remote processor of business data.
2. Any hosted origin, signaling service, or relay must remain transport/bootstrap infrastructure only.

---

## Implementation Notes

### Code Example: WebCompanionService (Gap 1 foundation)

```dart
// lib/data/services/web/web_companion_service.dart
import 'package:wakelock_plus/wakelock_plus.dart';

class WebCompanionService {
  static final WebCompanionService _instance = WebCompanionService._();
  factory WebCompanionService() => _instance;
  WebCompanionService._();

  bool _isRunning = false;
  bool _browserConnected = false;

  Future<void> start() async {
    if (_isRunning) return; // no-op if already running
    
    // 1. Extract web build (fail fast if missing)
    await WebUiExtractor.instance.extractNow();
    
    // 2. Start HTTP server
    await P2pServer.instance.startServerOnly();
    
    // 3. Mark as ready
    _isRunning = true;
    
    // 4. Hold wake lock while browser might connect (called by lifecycle observer)
    _ensureWakeLock();
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await P2pServer.instance.stopServerOnly();
    await WakelockPlus.disable();
  }

  void _ensureWakeLock() {
    if (_browserConnected) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void onBrowserConnected() {
    _browserConnected = true;
    WakelockPlus.enable();
  }

  void onBrowserDisconnected() {
    _browserConnected = false;
    WakelockPlus.disable();
  }

  bool get isReady => _isRunning;
  bool get isRunning => _isRunning;
}
```

### Code Example: Port Fallback (Gap 3)

```dart
// In P2pServer.startServer()
Future<void> startServer() async {
  try {
    // Try preferred port first
    _serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      kAppConstants.p2pPort, // 50505
    );
    _boundPort = kAppConstants.p2pPort;
    debugPrint('✅ Server bound to port $_boundPort');
  } catch (e) {
    // Fall back to random port
    _serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0, // OS assigns random available port
    );
    _boundPort = _serverSocket!.port;
    debugPrint('⚠️ Port 50505 unavailable, bound to random port $_boundPort');
  }
  
  // ... rest of startup
}
```

### Code Example: Health Check (Gap 4)

```dart
// In P2pServer, add route:
router.get('/health', (Request request) async {
  final extractorReady = await WebUiExtractor.instance.isReady();
  final serverReady = _staticHandler != null;
  
  if (extractorReady && serverReady) {
    return Response.ok('{"status":"healthy"}',
        headers: {'Content-Type': 'application/json'});
  } else {
    return Response.internalServerError(
      body: '{"status":"warming_up"}',
      headers: {'Content-Type': 'application/json'},
    );
  }
});
```

---

## Rollout Plan

### Internal Testing (Day 1–2)
- Dev team tests Phases 1–3 on personal devices
- Run manual QA checklist
- Regression tests pass

### Beta Testing (Day 3–4)
- Deploy to 5–10 beta testers
- Capture feedback on OEM variance (Pixel, Samsung, Xiaomi, Redmi)
- Monitor wake lock battery impact

### Production Release (Week 2)
- Deploy hardened web companion to stable channel
- Document OEM support matrix in help center
- Add warning: "Web companion is beta; please report connection issues"
- Monitor crash logs for new failure modes

---

## Acceptance Criteria (Definition of Done)

- [ ] All patches from Phase 1–3 merged to main
- [ ] Unit test pass rate ≥ 95%
- [ ] Integration tests pass on emulator + real devices (API 28, 30, 32, 34)
- [ ] Manual QA checklist completed (all items ✅)
- [ ] OEM hotspot matrix documented with workarounds
- [ ] Code review approved by tech lead
- [ ] Release notes updated with known limitations (Xiaomi/Redmi hotspot variance)
- [ ] Wake lock battery impact measured and documented (< 5% per hour)

---

## Appendix: Related Files & References

- [WEB_COMPANION_SPEC.md](WEB_COMPANION_SPEC.md) — Original spec (v1.0)
- [lib/data/services/p2p/p2p_server.dart](lib/data/services/p2p/p2p_server.dart) — HTTP server + router
- [lib/data/services/p2p/p2p_coordinator.dart](lib/data/services/p2p/p2p_coordinator.dart) — P2P sync orchestration
- [lib/main.dart](lib/main.dart) — App lifecycle + initialization
- [lib/presentation/screens/settings/open_on_laptop_screen.dart](lib/presentation/screens/settings/open_on_laptop_screen.dart) — QR UI
- [lib/data/services/web/web_browser_session.dart](lib/data/services/web/web_browser_session.dart) — WebSocket protocol
- [lib/data/services/web/web_session_service.dart](lib/data/services/web/web_session_service.dart) — Token lifecycle
- [docs/SMS_PARSING_SPEC.md](../../../SMS_PARSING_SPEC.md) — For reference (unrelated to web companion)
