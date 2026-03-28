# KashCube — Web Companion Spec

**Version:** 1.0  
**Date:** 17 March 2026  
**Status:** Approved — implement as parallel track alongside P2P sync  
**Reference:** `sample/wifi-mirror/` — `WebServerService`, `SignalingPlatform._startWebSocketServer()`

---

## Table of Contents

1. [Core Concept](#1-core-concept)
2. [How the Browser Connects](#2-how-the-browser-connects)
3. [Why This Solves the HTTPS/Mixed-Content Problem](#3-why-this-solves-the-httpsmixed-content-problem)
4. [Package Inventory](#4-package-inventory)
5. [Architecture](#5-architecture)
6. [Server Routes](#6-server-routes)
7. [Web App Bundle Pipeline](#7-web-app-bundle-pipeline)
8. [WebSocket Sync Protocol](#8-websocket-sync-protocol)
9. [Platform Fork Map](#9-platform-fork-map)
10. [QR Connect Flow (V1 — Phone → Browser)](#10-qr-connect-flow-v1--phone--browser)
10b. [Reverse QR Flow (V2 — Browser → Phone)](#10b-reverse-qr-flow-v2--browser--phone)
11. [Session Auth (Browser)](#11-session-auth-browser)
12. [Web-Only Screens](#12-web-only-screens)
13. [What Is NOT Different on Web](#13-what-is-not-different-on-web)
14. [Relationship to P2P Sync Server](#14-relationship-to-p2p-sync-server)
15. [Implementation Order](#15-implementation-order)
16. [Responsive Desktop Layout](#16-responsive-desktop-layout)
17. [Open Risks](#17-open-risks)
18. [OEM Hotspot Support Matrix](#18-oem-hotspot-support-matrix)
19. [Phase 4 QA Execution Checklist](#19-phase-4-qa-execution-checklist)

---

## 1. Core Concept

**The phone serves the Flutter web app to the browser. There is no CDN, no cloud, no HTTPS.**

```
Phone:   p2p_sync_server.dart (shelf)
         Route GET /*   → serve Flutter web build (bundled in APK as assets/web_ui/)
         Route GET /ws  → WebSocket for browser ↔ phone data sync

Browser: http://192.168.x.x:<port>   ← loads the Flutter web app from the PHONE
         ws://192.168.x.x:<port>/ws  ← same origin → no mixed-content block
```

The browser does not go to the internet. It goes to the phone on the local Wi-Fi. All data stays on LAN. The phone is the source of truth — browser is read-mostly, write-sometimes.

This is identical to how wifi-mirror works. The host native app runs `WebServerService` (dart:io `HttpServer`) to serve its Flutter web build to browser viewers. KashCube uses `shelf` instead of raw `dart:io` but the concept is identical.

---

## 2. How the Browser Connects

```
1. User opens KashCube on phone → taps "Open on laptop"
2. Phone shows QR encoding:
     http://192.168.1.5:51234?token=<session_token>

3. User scans QR on laptop camera OR types URL manually
4. Browser opens: http://192.168.1.5:51234?token=<session_token>
5. Phone serves index.html + Flutter web assets from assets/web_ui/
6. Flutter web app loads in browser
7. App reads ?token= from URL → connects ws://192.168.1.5:51234/ws
8. WebSocket handshake with token → phone validates → sync begins
9. Browser renders KashCube UI with live data from phone
```

The `session_token` is a short-lived random token (32 bytes, base64url) generated fresh each time the QR is shown. It expires after 5 minutes of non-use, or immediately on WebSocket disconnect.

---

## 3. Why This Solves the HTTPS/Mixed-Content Problem

If the web app were hosted on Cloudflare Pages (`https://web.kashcube.com`), Chrome would block:
```
Mixed Content: The page at 'https://web.kashcube.com' was loaded over HTTPS,
but attempted to connect to the insecure WebSocket endpoint 'ws://192.168.1.5:51234/ws'.
This request has been blocked.
```

Because the web app is served from `http://192.168.1.5:51234` (the phone), the browser treats `ws://192.168.1.5:51234/ws` as **same-origin** — no block, no warning. This is the exact technique wifi-mirror uses.

---

## 4. Package Inventory

All packages below are **already in `pubspec.yaml`** unless flagged.

| Package | Version | Role |
|---|---|---|
| `shelf` | ^1.4.2 | HTTP server foundation (shared with P2P sync) |
| `shelf_router` | ^1.1.4 | Route `/ws`, `GET /*` |
| `shelf_web_socket` | ^3.0.0 | WebSocket upgrade handler for `/ws` |
| **`shelf_static`** | **^1.1.2** | **⚠️ ADD** — serve `assets/web_ui/` static files |
| `qr_flutter` | ^4.1.0 | Show QR on phone for browser to scan |
| `crypto` | ^3.0.6 | Random token generation (already in pubspec) |

One new package: `shelf_static`. Add to `pubspec.yaml`:
```yaml
  shelf_static: ^1.1.2
```

---

## 5. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  PHONE (foreground)                                              │
│                                                                   │
│  p2p_sync_server.dart  (shelf + shelf_router)                    │
│  Bound to: 0.0.0.0:0  (OS-assigned port)                        │
│                                                                   │
│  Routes:                                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  GET  /ws          WebSocket upgrade → WebBrowserSession   │  │
│  │  GET  /*           shelf_static → assets/web_ui/ extract   │  │
│  │  POST /hello       P2P sync (Android peer only, HMAC auth) │  │
│  │  POST /sync/pull   P2P sync (Android peer only, HMAC auth) │  │
│  │  POST /sync/push   P2P sync (Android peer only, HMAC auth) │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  WebBrowserSession:                                               │
│    Token validated on WS handshake                               │
│    Pushes delta rows as JSON frames to browser                   │
│    Receives write operations from browser                        │
│    On disconnect → session invalidated                           │
└───────────────────────────┬────────────────────────────────────-─┘
                            │ Wi-Fi LAN
                            │ http://192.168.x.x:<port>
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAPTOP BROWSER                                                  │
│                                                                   │
│  Flutter Web (loaded from phone, running in browser)            │
│  Connects to ws://192.168.x.x:<port>/ws                         │
│  Renders KashCube UI with live data                              │
│  kIsWeb = true → guards for SMS, biometrics, notifications      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Server Routes

### `/ws` — WebSocket (browser only)

```dart
// In p2p_sync_server.dart
router.get('/ws', webSocketHandler((WebSocketChannel channel) async {
  // 1. Read first message: { "type": "AUTH", "token": "..." }
  // 2. Validate token against active session
  // 3. If invalid → close with 4001
  // 4. If valid → start WebBrowserSession.attach(channel)
}));
```

The browser sends all requests as JSON WebSocket frames (no HMAC — token is the auth for browser sessions). Android P2P peers use the HMAC-authenticated HTTP routes only.

### `GET /*` — Static file serving

```dart
// shelf_static serves the extracted web_ui files
final staticHandler = createStaticHandler(
  webUiExtractedPath,
  defaultDocument: 'index.html',
  serveFilesOutsidePath: false,
);
router.mount('/', staticHandler);
```

Path traversal is blocked by `shelf_static` internally. No `..` access.

### CORS

Add a shelf middleware for `*` CORS on the static handler only — not on P2P sync routes (those are auth-gated):
```
Access-Control-Allow-Origin: *   // only for GET /* routes
```

---

## 7. Web App Bundle Pipeline

### Build step

```bash
# scripts/build_web_ui.sh
flutter build web --release --dart-define=KASHCUBE_PLATFORM=web
# Output: build/web/

# Copy to assets
rm -rf assets/web_ui/
cp -r build/web/ assets/web_ui/

# Generate manifest
find assets/web_ui -type f | sed 's|assets/web_ui/||' > assets/web_ui/manifest.txt
```

### Runtime extraction (mirror of wifi-mirror)

On first `GET /*` request (lazy, not on server start):

```dart
// Read manifest.txt from rootBundle
// For each path in manifest:
//   rootBundle.load('assets/web_ui/$path') → write to <tempDir>/web_ui/$path
// Cache the extracted path — skip on subsequent requests
// Return shelf_static handler pointing at <tempDir>/web_ui/
```

### pubspec.yaml assets declaration

```yaml
flutter:
  assets:
    - assets/web_ui/
    - assets/web_ui/manifest.txt
    # Note: nested paths in assets/web_ui/ are auto-included
```

The `flutter build web` output goes into `assets/web_ui/` at development time. The `build_web_ui.sh` script is run manually before cutting a release APK that includes the web UI.

---

## 8. WebSocket Sync Protocol

All messages are JSON. The WebSocket channel handles framing — no length prefix needed.

### Initial sync (on connect)

```
Browser → { "type": "AUTH", "token": "abc123" }
Phone  → { "type": "AUTH_OK", "device_name": "Ravi's Redmi", "schema_version": 69 }

Browser → { "type": "PULL", "table": "transactions", "since": "2026-04-01T00:00:00Z" }
Phone  → { "type": "ROWS", "table": "transactions", "rows": [...], "is_final": false }
Phone  → { "type": "ROWS", "table": "transactions", "rows": [...], "is_final": true }

Browser → { "type": "PULL", "table": "invoices", "since": "2026-04-01T00:00:00Z" }
...
```

### Real-time push (live updates)

When the phone receives a write (new transaction, invoice update) and a browser session is active:

```
Phone  → { "type": "PUSH", "table": "transactions", "rows": [{ ...new_row }] }
Browser receives → updates local state
```

### Browser writes

Browser can create/edit records. The message is forwarded to the phone's write path:

```
Browser → { "type": "WRITE", "table": "invoices", "row": { ... } }
Phone  → writes to SQLite → echoes back PUSH to browser
Phone  → { "type": "WRITE_OK", "sync_id": "inv_xyz123" }
```

The phone is always master for writes — the WebSocket is a conduit to the phone's repository layer.

### Keep-alive

Browser sends `{ "type": "PING" }` every 25 seconds. Phone replies `{ "type": "PONG" }`. Inspired by wifi-mirror's signaling ping/pong pattern.

---

## 9. Platform Fork Map

All `kIsWeb` guards are minimal. Everything works on both platforms by default.

| Feature | Android | Browser (kIsWeb) |
|---|---|---|
| Database | sqflite (local) | sqflite_common_ffi_web (OPFS) — reads delta from WS to local cache |
| SMS capture | ✅ telephony | `return []` — show banner "SMS on app only" |
| Biometrics | ✅ local_auth | `return true` — token = auth |
| Local notifications | ✅ flutter_local_notifications | no-op — skip silently |
| P2P sync (Android peers) | ✅ shelf HTTP + Bonsoir | n/a — browser is never a P2P peer |
| WS sync (browser) | n/a — phone hosts WS server | ✅ `web_socket_channel` connects to phone |
| path_provider | OPFS-transparent | OPFS-transparent (handled by package) |
| file_picker | native file dialog | `<input type="file">` (handled by package) |
| Connection status banner | n/a | ✅ shown when WS disconnected |

### DB strategy on web

The browser does not replicate the phone's full SQLite DB. It caches the current FY's data in-memory after the initial PULL. Writes go to phone via WebSocket and are echoed back. On WS disconnect the browser goes read-only (shows stale data banner). This avoids `sqflite_common_ffi_web` complexity entirely for the initial version.

---

## 10. QR Connect Flow (V1 — Phone → Browser)

**Primary flow. Implemented.**

```
Phone (QR screen):
  1. Generate session_token = crypto.random(32 bytes) → base64url
  2. Get own IP via NetworkInterface scan (same utility from P2P sync)
  3. Get shelf server port (already running)
  4. Show QR: http://<ip>:<port>?token=<session_token>
  5. Token valid for 5 minutes, single use

Browser:
  1. User scans QR with phone/laptop camera (or laptop camera via OS QR feature)
  2. Browser opens URL → phone serves Flutter web app
  3. Flutter web boot: reads `window.location.search` → extracts token
  4. Connects ws://<ip>:<port>/ws with AUTH message
```

**Limitation:** Requires the user to initiate from the phone every session. No persistent bookmark flow.

---

## 10b. Reverse QR Flow (V2 — Browser → Phone)

**Enhancement for returning users. Not yet implemented. Target: V2.**

This is the WhatsApp Web pattern applied locally: the browser shows a QR, the phone scans it to authorise the session. Once a user has bookmarked `http://ip:port`, they never need to touch the phone to initiate.

### Why it's possible

Because the browser already loaded from `http://ip:port` (served by the phone), it already knows the phone's full address and can poll a challenge endpoint on it. The chicken-and-egg problem that afflicts cloud-hosted QR auth does not exist here.

### Flow

```
1. User opens bookmark: http://<ip>:<port>  (no token)
2. WebConnectScreen detects no token in URL
3. Browser generates challenge_id = random 16 bytes → base64url
4. Browser shows QR encoding:
     kashcube://auth?challenge=<challenge_id>&origin=http://<ip>:<port>
5. Browser begins polling:  GET /auth/challenge/<challenge_id>  (every 2s)
   → 202 Accepted  (pending)
   → 200 OK { token: "..." }  (resolved)
   → 410 Gone  (expired after 5 min)

6. User opens KashCube on phone → taps "Scan browser QR"
7. Camera scans QR → deep link fires:
     kashcube://auth?challenge=<id>&origin=http://<ip>:<port>
8. App validates origin matches own server address
9. Phone mints a fresh session_token (same 32 bytes, same TTL)
10. Phone stores:  challenge_id → session_token  (in-memory, 5 min TTL)
11. Next browser poll resolves → receives token
12. Browser connects ws://<ip>:<port>/ws with AUTH message
13. Normal AUTH_OK flow proceeds
```

### Server routes required (V2 only)

```
GET  /auth/challenge/:id   → 202 (pending) | 200 {token} (resolved) | 410 (expired)
```

No POST needed — the phone resolves the challenge via deep link, writing directly to the in-memory map on the same process.

### New phone entry point

A "Scan browser QR" action added to the LAN Sync / web companion settings area. Launches `mobile_scanner` pointed at `kashcube://auth?challenge=...` QR codes only.

### Implementation components

| Component | Location | Notes |
|---|---|---|
| `PendingChallengeService` | `lib/data/services/web/pending_challenge_service.dart` | In-memory `Map<String, _Entry>` with 5 min TTL; `resolve(id, token)` and `poll(id)` methods |
| `GET /auth/challenge/:id` route | `p2p_sync_server.dart` | No auth guard — challenge ID is unguessable (128-bit); return 202/200/410 |
| Deep link scheme entry | `AndroidManifest.xml` | `kashcube://auth` intent filter |
| Deep link handler | `app_shell.dart` | Parse `origin`, validate matches own IP+port, mint token, call `PendingChallengeService.resolve()` |
| Browser polling loop | `web_connect_screen.dart` | `Timer.periodic(2s)` hits `GET /auth/challenge/:id`; cancel on 200 or 410 |
| "Scan browser QR" button | `open_on_laptop_screen.dart` or settings tile | Launches scanner; scoped to `kashcube://auth` scheme |

### Security notes

- `challenge_id` is 128-bit random — not enumerable
- Origin validation on phone: reject if `origin` host ≠ own IP (prevents a malicious QR on a different network from hijacking the token mint)
- Token TTL and single-use behaviour are identical to V1
- No token ever appears in browser history (it arrives via JSON poll response, not in the URL)
- This is **strictly better** than V1 for browser history privacy: V1 token appears in history as `http://ip:port?token=...`; V2 token never touches the URL bar

### Conditional import for URL parsing

Mirrors wifi-mirror's `quick_connect_card_web.dart` pattern:

```dart
// lib/presentation/widgets/web_connect/web_url_reader_stub.dart
Map<String, String> getUrlParams() => {};

// lib/presentation/widgets/web_connect/web_url_reader_web.dart
import 'dart:html' as html;
Map<String, String> getUrlParams() {
  final uri = Uri.parse(html.window.location.href);
  return uri.queryParameters;
}

// Usage:
import 'web_url_reader_stub.dart'
    if (dart.library.html) 'web_url_reader_web.dart'
    as url_reader;
```

---

## 11. Session Auth (Browser)

**Browser auth model: token possession = authenticated.**

- Token is 32 random bytes (256-bit entropy) — not guessable
- Token is single-use: consumed on first successful WS AUTH
- Token expires 5 minutes after generation if never used
- On WS disconnect: browser must scan new QR to reconnect (token not reusable)
- Phone can revoke: "Disconnect browser" button in Settings invalidates active token

No biometric required on browser. This is appropriate because:
1. The token requires physical QR scan (proximity proof)
2. Data never leaves the LAN
3. Session is transient — no persistent credential stored in browser

Token is stored in Flutter web app's in-memory state only — never in `localStorage`, `sessionStorage`, or cookies.

---

## 12. Web-Only Screens

### `WebConnectScreen` (web entry point)

Shown only on `kIsWeb` instead of normal home navigation on cold start:

```
┌──────────────────────────────────────┐
│  KashCube                            │
│                                      │
│  Open on your phone:                 │
│  Settings → Open on Laptop           │
│  Then scan the QR shown.             │
│                                      │
│  [  QR Scanner  ]                    │
│  or paste URL:  ________________     │
│                 [Connect]            │
└──────────────────────────────────────┘
```

On successful WS handshake → navigate to `HomeScreen` normally.

### `WebConnectionBanner`

Persistent `MaterialBanner` shown on ALL screens when WS is disconnected:

```
⚠  Disconnected from phone. Showing last synced data.  [Reconnect]
```

Writes are blocked while disconnected — all action buttons show disabled state with tooltip "Reconnect to phone to make changes."

---

## 13. What Is NOT Different on Web

This is the key point — the single-codebase advantage. Everything below works identically on both platforms with zero changes:

- All 8 screens (Home, Transactions, Add/Edit, Detail, Credits, Reports, Settings, etc.)
- All Riverpod providers and state management
- All data models
- All repositories (read from in-memory delta cache on web)
- Theme, dark mode, Material 3 components
- Indian number formatting (₹1,23,456)
- Empty states, confirmation dialogs, FAB
- Invoice create/edit flows
- Party, credit, category management

---

## 14. Relationship to P2P Sync Server

The web companion and P2P sync **share the same `shelf` server** (`p2p_sync_server.dart`). They are different route groups on the same running instance:

```
Same shelf server:
  /hello, /sync/*    ← P2P sync — HMAC-authenticated, Android peers only
  /ws                ← Web companion — token-authenticated, browser only
  /*                 ← Static web UI serving — no auth (public assets)
```

**This is why both should be built together.**

The shelf server startup, IP detection, port broadcasting via Bonsoir TXT records — all of this is the same infrastructure. Each route group is independently developed but runs on the same instance.

**Build dependency:**
1. `p2p_sync_server.dart` shell (shelf + router setup, IP detection, port 0 binding) — **needed by both**
2. P2P sync routes (`/hello`, `/sync/*`) — independent
3. Web companion routes (`/ws`, `/*`) — independent, can be done in parallel

---

## 15. Implementation Order

Web companion work that can start **immediately**, parallel to P2P sync:

### Track A (parallel — web UI pipeline, no server needed)
1. **Verify `flutter build web` works** — run `flutter build web --release`, check for errors  
2. **Create `scripts/build_web_ui.sh`** — build + copy to `assets/web_ui/` + generate manifest  
3. **Add `shelf_static: ^1.1.2` to pubspec**  
4. **Create `WebConnectScreen`** — QR scanner + URL paste + `kIsWeb` guard  
5. **Create `WebConnectionBanner`** widget  
6. **Wire `kIsWeb` guards** in SMS, biometrics, notifications (6 lines total)  
7. **`web_url_reader_stub.dart` + `web_url_reader_web.dart`** conditional import pair  

### Track B (needs P2P sync server foundation from Step 1 of P2P spec)
8. **Static file route** — extract `assets/web_ui/` to temp dir, `shelf_static` handler  
9. **Session token generation** — in `p2p_sync_server.dart`, `GET /qr` returns token  
10. **`/ws` WebSocket route** — AUTH, PULL, PUSH, WRITE message handlers  
11. **`WebBrowserSession`** class — manages active browser connection, live push  
12. **QR display screen on phone** — shows `qr_flutter` QR of `http://<ip>:<port>?token=...`  

---

## 16. Responsive Desktop Layout

**Decision date:** 22 March 2026  
**Status:** P1–P5 complete

The Flutter web app runs the same codebase as Android. On a desktop browser
the mobile layout (bottom `NavigationBar`, narrow columns) looks stretched.
A single breakpoint driven by `MediaQuery.sizeOf` gives a proper desktop
chrome without forking any screen code.

### Breakpoints (Material 3 Adaptive Window Classes)

| Class | Width | Behaviour |
|---|---|---|
| Compact | < 600 dp | Phone portrait — bottom `NavigationBar` (unchanged) |
| Medium | 600–839 dp | Tablet / small laptop — bottom `NavigationBar` |
| **Expanded** | **≥ 840 dp** | **Desktop — `NavigationRail` (left sidebar)** |

Added to `lib/core/extensions/context_extensions.dart`:
```dart
bool get isCompact  => MediaQuery.sizeOf(this).width < 600;
bool get isMedium   => MediaQuery.sizeOf(this).width >= 600 &&
                       MediaQuery.sizeOf(this).width < 840;
bool get isExpanded => MediaQuery.sizeOf(this).width >= 840;
```

### Phased Roadmap

| Phase | Work | Status |
|---|---|---|
| **P1** | `isExpanded` breakpoint · `NavigationRail` in `AppShell` | ✅ Done |
| **P2** | Adaptive bottom sheets → `Dialog` on expanded (`showAdaptiveSheet` helper) | ✅ Done |
| **P3** | Master-Detail: Transactions list + detail side panel | ✅ Done |
| **P4** | Transactions `DataTable` on expanded (sortable columns) | ✅ Done |
| **P5** | Settings two-pane layout (section nav + content pane) | ✅ Done |

### Key files changed

| File | Change |
|---|---|
| `lib/core/extensions/context_extensions.dart` | Added `isCompact` / `isMedium` / `isExpanded` getters |
| `lib/presentation/app_shell.dart` | `NavigationRail` on expanded; `NavigationBar` on compact/medium |
| `lib/core/utils/adaptive_sheet.dart` | `showAdaptiveSheet<T>()` — `showDialog` on expanded, `showModalBottomSheet` on compact/medium |
| `lib/presentation/screens/transactions/transaction_detail_screen.dart` | `TransactionDetailPanel` public widget with `onDeleted` callback |
| `lib/presentation/screens/transactions/transactions_screen.dart` | Master-detail split + sortable `DataTable` list pane on expanded |
| `lib/presentation/screens/settings/settings_screen.dart` | 260 dp section nav + content pane on expanded |

---

## 17. Open Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `flutter build web` has compile errors (web-incompatible packages) | Medium | Audit with `flutter build web` immediately; fix `kIsWeb` guards before anything else |
| assets/web_ui/ bloats APK significantly | Medium | Measure: typical Flutter web build is 3–8 MB compressed; acceptable for a POS app |
| Android router blocks LAN HTTP server port | Low | Use port > 49152 (ephemeral range); most firewalls allow this |
| Browser caches stale Flutter web build | Low | Version query param in URL: `?v=<schema_version>` busts cache |
| `shelf_static` path traversal | Very Low | `shelf_static` blocks `..` internally; additional validation in route middleware |
| Token stolen from URL in browser history | Low | Token in QR URL is single-use and expires in 5 min; history entry becomes useless immediately after use |

---

## 18. OEM Hotspot Support Matrix

Phase 4 validation tracks hotspot reliability explicitly by OEM family.  
Target network model remains: **phone and laptop on the same LAN**, with router Wi-Fi as preferred mode.

| Device family | Hotspot mode expectation | Router Wi-Fi expectation | Current tier | User-facing guidance |
|---|---|---|---|---|
| Pixel (Android 13/14) | Stable | Stable | Tier A (supported) | Use normally |
| Samsung One UI (S23/S24 class) | Stable | Stable | Tier A (supported) | Use normally |
| Xiaomi MIUI/HyperOS | Intermittent (isolation variance) | Stable | Tier B (best effort) | If hotspot fails, move both devices to the same router Wi-Fi |
| Redmi MIUI/HyperOS | Intermittent (isolation variance) | Stable | Tier B (best effort) | If hotspot fails, move both devices to the same router Wi-Fi |

Interpretation:
- Tier A: release blocker if unstable
- Tier B: known OEM variance accepted for MVP with documented workaround

---

## 19. Phase 4 QA Execution Checklist

Run the scripted checks first, then complete manual network/OEM validation:

```bash
./scripts/qa_web_companion_phase4.sh
```

### Manual checklist (record results in release notes)

1. Lifecycle stability
  - Start "Open on Laptop"
  - Connect browser
  - Minimise KashCube for 5+ minutes
  - Expected: browser remains connected, no forced re-auth

2. First-load readiness
  - Open "Open on Laptop" from cold app start
  - Expected: warm-up message appears briefly, QR shown only after readiness
  - Expected: no first-request 500/timeouts in browser

3. Port fallback
  - Occupy port 50505 before launching feature
  - Expected: server binds random port and QR uses the actual bound port

4. OEM hotspot matrix
  - Pixel + laptop on hotspot: verify stability
  - Samsung + laptop on hotspot: verify stability
  - Xiaomi/Redmi hotspot: if unstable, verify router Wi-Fi workaround succeeds

5. Session refresh behavior
  - Refresh browser tab after auth
  - Expected: reconnect via session token, no new QR required

Definition of done for Phase 4:
- Scripted checks pass
- Tier A devices stable in hotspot mode
- Tier B workaround validated and documented

---

## Appendix — wifi-mirror Reference Map

| wifi-mirror component | KashCube equivalent | Notes |
|---|---|---|
| `WebServerService` (`dart:io HttpServer`) | Static route on `p2p_sync_server.dart` (shelf) | `shelf_static` replaces manual file handler |
| `WebServerService._getLocalIpAddress()` | Reused in `p2p_sync_server.dart` | Identical algorithm |
| `WebServerService._prepareWebAppFiles()` | Same pattern but for `assets/web_ui/` | Lazy extraction to temp dir |
| `SignalingPlatform._startWebSocketServer()` | `/ws` route + `WebBrowserSession` | `shelf_web_socket` + `shelf_router` instead of raw `dart:io HttpServer` |
| `quick_connect_card_web.dart` URL parsing | `web_url_reader_web.dart` conditional import | Identical `dart:html window.location` approach |
| `viewing_screen_web.dart` / `_native.dart` split | `WebConnectScreen` (web only) | Simpler — just one extra boot screen |
| Ping/pong keepalive (25s) | `WebBrowserSession` ping/pong | Same interval |

---

*Next action: Run `flutter build web --release` to check for web compatibility errors. Address any `kIsWeb` guard gaps before building the web UI pipeline.*
