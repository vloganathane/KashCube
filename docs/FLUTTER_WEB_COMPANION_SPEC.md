# KashCube Web Companion — Single Codebase Spec

**Decision date:** 13 March 2026  
**Status:** Approved — implementation starting W2

---

## Core Decision

**One codebase. Zero JS. Flutter Web is the web companion.**

`flutter build web` produces the browser companion.  
`flutter build apk` produces the Android app.  
The `lib/` directory is 100% shared. No parallel web code ever written.

---

## Architecture Overview

```
lib/                         ← single Dart codebase
  core/                      ← zero platform forks
  data/
    services/
      db_factory.dart        ← NEW: kIsWeb → sqflite_common_ffi_web
                                         else → sqflite
      web_sync_client.dart   ← NEW: delta protocol over WebSocket
  presentation/              ← zero platform forks
  main.dart                  ← minimal kIsWeb boot guards

android/                     ← Android build config only
web/                         ← Flutter web target (index.html shell)

Deployed:
  Android APK   ← Play Store
  Flutter Web   ← Cloudflare Pages (web.kashcube.com)
                   serves only static JS/HTML — zero user data
```

---

## How the Browser Connects to the Phone

The phone is always the data source. The browser is a secondary device — architecturally identical to a linked secondary phone. The `linked_devices` row created for the web session (already implemented, commit `cb3ffb6`) makes this explicit.

```
┌─────────────────────────────────────────────────────────┐
│  User opens web.kashcube.com on laptop                  │
│  Flutter web loads from Cloudflare Pages (static only)  │
│                                                         │
│  App shows: "Scan QR from your KashCube phone"          │
│       ↓                                                 │
│  Phone QR encodes:                                      │
│    { "ws": "ws://192.168.x.x:8080/ws",                  │
│      "token": "<session>",                              │
│      "type": "kashcube_web_v1" }                        │
│       ↓                                                 │
│  Flutter web opens WebSocket to phone                   │
│  Runs WebSyncClient.connect() → pulls full delta        │
│  All data lives in browser memory (no IndexedDB yet)    │
│  Real-time WS push keeps state fresh                    │
│                                                         │
│  ALL DATA: browser ↔ phone directly, never leaves LAN  │
└─────────────────────────────────────────────────────────┘
```

---

## Platform Fork Map

Every item below is the **complete** list of platform differences. Everything else is shared with zero changes.

### 1. Database Factory

```dart
// lib/data/services/db_factory.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> initDatabaseFactory() async {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  // sqflite is the default on Android/iOS — no action needed
}
```

Called once in `main.dart` before `runApp()`.

### 2. SMS Capture

```dart
// lib/data/services/sms_service.dart
Future<List<SmsMessage>> fetchSms() async {
  if (kIsWeb) return [];   // silently disabled
  return _telephony.getInboxSms(...);
}
```

Web shows: "SMS auto-capture is available on the Android app."

### 3. Biometric / PIN Auth

```dart
// lib/data/services/auth_service.dart
Future<bool> authenticate() async {
  if (kIsWeb) return true;   // session token is the auth
  return _localAuth.authenticate(...);
}
```

Web auth model: possession of the QR session token = authenticated. Browser locks on WebSocket disconnect.

### 4. Local Notifications

```dart
if (!kIsWeb) {
  await FlutterLocalNotificationsPlugin().show(...);
}
```

No notification API in browser — silently skipped.

### 5. Path Provider / File Picker

`path_provider` handles web via OPFS automatically.  
`file_picker` handles web via `<input type="file">` automatically.  
No guard needed — packages handle it.

### 6. Sync Transport

| Platform | Transport | Class |
|---|---|---|
| Android secondary | Raw TCP socket | `SyncClient` |
| Browser | WebSocket `/ws` | `WebSyncClient` (new) |

`WebSyncClient` speaks the **identical delta JSON protocol** as `SyncClient` — same `DeltaRow` model, same `pullDeltas`/`pushDeltas` framing — only the transport changes.

```
Android SyncClient:
  Socket → 4-byte big-endian length + UTF-8 JSON

WebSyncClient:
  WebSocket frame → UTF-8 JSON (WebSocket handles framing)
```

`SyncNowNotifier` gets a transport abstraction:

```dart
abstract class SyncTransport {
  Future<void> connect(String host, int port, String token);
  Future<void> disconnect();
  Future<List<DeltaRow>> pullDeltas(String deviceId, DateTime? since);
  Future<void> pushDeltas(String deviceId, List<DeltaRow> rows);
}

class TcpSyncTransport implements SyncTransport { ... }   // existing SyncClient
class WsSyncTransport  implements SyncTransport { ... }   // new for web
```

### 7. Web-Only: QR Connect Screen

Web needs one screen that doesn't exist on Android: the initial pairing screen where the browser scans (or pastes) the phone's QR URL. This is the web entry point replacing `main.dart`'s normal home navigation.

```dart
// lib/presentation/screens/web_connect/web_connect_screen.dart
// Only used on kIsWeb — shows QR scanner + manual URL entry
// On successful WS handshake → navigate to HomeScreen normally
```

### 8. Web-Only: Connection Status Banner

A persistent `MaterialBanner` when the WebSocket is disconnected:

```
⚠  Disconnected from phone. Showing last synced data.  [Reconnect]
```

Writes are blocked while disconnected (phone is master).

---

## What is NOT Different on Web

- All 8 screens (Home, Transactions, Credits, Reports, Settings, etc.)
- All Riverpod providers
- All data models
- All repositories (read from local DB copy synced from phone)
- Theme, dark mode, Indian locale, ₹ formatting
- KashCube Web linked device row in `linked_devices`
- Revoke from phone works identically (already implemented)

---

## Deployment: Cloudflare Pages

```yaml
# .github/workflows/web.yml
- run: flutter build web --release --dart-define=KASHCUBE_PLATFORM=web
- uses: cloudflare/pages-action@v1
  with:
    directory: build/web
    projectName: kashcube-web
```

**What Cloudflare Pages receives:** Static HTML + compiled Dart JS.  
**What it never sees:** Any user data, any transaction, any sync packet.  
Privacy policy statement: *"web.kashcube.com serves only the app shell. All financial data flows directly between your phone and your browser over your local Wi-Fi. No data passes through or is stored on any KashCube server."*

---

## QR Payload Format (updated)

Current format (LAN REST):
```
http://192.168.x.x:8080?token=<token>
```

New format (Flutter Web WebSocket):
```json
{
  "type":    "kashcube_web_v1",
  "ws":      "ws://192.168.x.x:8080/ws",
  "api":     "http://192.168.x.x:8080/api/v1",
  "token":   "<session_token>",
  "version": 1
}
```

Backward compatible — old plain-URL format falls back to REST mode.

---

## APK Size Impact

| Artifact | What's bundled |
|---|---|
| `kash_cube.apk` | Zero web assets — Flutter web output goes to CF Pages only |
| `build/web/` | ~3–6 MB Flutter web output — deployed, never bundled in APK |

The current `assets/web_ui/index.html` (the JS SPA) will be **removed** once `WebSyncClient` is working. `WebServerService` simplifies to WebSocket-only — no SPA serving needed.

---

## Migration Path: Current JS SPA → Flutter Web

| Step | Work | When |
|---|---|---|
| **P1** | Add web platform target · `initDatabaseFactory()` · guard SMS/biometric/notifications · verify all screens render in Chrome | W2 |
| **P2** | `WebSyncClient` over `/ws` · `SyncTransport` abstraction · `WebConnectScreen` · `SyncNowNotifier` uses correct transport | W2 |
| **P3** | `flutter build web` CI → CF Pages · `web.kashcube.com` live · update QR payload to JSON format | W3 |
| **P4** | Remove `WebApiRoutes.dart` · remove `assets/web_ui/` · simplify `WebServerService` to WS-only | W3 cleanup |
| **Future** | Option B relay (blind WS pipe) for cross-network access — Flutter web already ready, only QR `ws://` URL changes to `wss://relay.kashcube.com/t/<id>` | v2.0 |

---

## Packages to Add

```yaml
dependencies:
  sqflite_common_ffi_web: ^2.3.0+2   # SQLite in browser via WASM

dev_dependencies:
  # No new dev deps — flutter build web is built-in
```

No network-calling packages. No Firebase. No analytics. The `web_socket_channel` package already present handles WS on all platforms.

---

## Cross-Network (Future: Option B)

When the relay is built, the **only change** to the Flutter web app is the WebSocket URL in the QR payload:

```
LAN mode:      ws://192.168.x.x:8080/ws
Cross-network: wss://relay.kashcube.com/t/<tunnelId>
```

`WebSyncClient` is transport-agnostic — it just opens a WebSocket to whatever URL the QR provides. Zero code change in the app.

The relay is a blind pipe — it routes encrypted WebSocket frames between phone and browser without decoding them. Phone initiates the outbound tunnel connection (solves CGNAT). Browser connects to the relay's public URL.

---

## Responsive Desktop Layout

**Decision date:** 22 March 2026  
**Status:** P1 implemented — `NavigationRail` on expanded (≥840 dp)

The web companion runs the same Flutter codebase as Android. On a desktop
browser the mobile layout (bottom `NavigationBar`, narrow columns) looks
stretched. A single `LayoutBuilder`-driven breakpoint gives a proper desktop
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

### P1 — NavigationRail in AppShell

`lib/presentation/app_shell.dart` — when `context.isExpanded`:

```
┌──────────────┬────────────────────────────────────────┐
│ NavigationRail│            Screen content              │
│              │  (IndexedStack — same screens as mobile)│
│  🏠 Home     │                                        │
│  📋 Transactions │                                   │
│  🏪 Business │                                        │
│  👥 Contacts │                                        │
│  ⚙  Settings │                                        │
│              │                                        │
│  [+ FAB]     │                                        │
└──────────────┴────────────────────────────────────────┘
```

- Zero screen code changed — all 5 screens are identical
- `NavigationBar` hidden on expanded; `NavigationRail` shown
- FAB stays on `Scaffold` at default `endFloat` position (bottom-right)
- Android build unaffected — `isExpanded` is false on a phone

### Phased Roadmap

| Phase | Work | Status |
|---|---|---|
| **P1** | `isExpanded` breakpoint · `NavigationRail` in `AppShell` | ✅ Done |
| **P2** | Adaptive bottom sheets -> `Dialog` on expanded (add `showAdaptiveSheet` helper) | ✅ Done |
| **P3** | Master-Detail: Transactions list + detail side panel | ✅ Done |
| **P4** | Transactions `DataTable` on expanded (sortable columns) | ✅ Done |
| **P5** | Settings two-pane layout (category list + pane) | Planned |

---

## Summary

| Before | After |
|---|---|
| Flutter app + separate JS SPA | Flutter app = Flutter web (one codebase) |
| `WebApiRoutes.dart` (REST) | `WebSyncClient` (delta sync over WS) |
| Phone serves HTML + REST API | Phone serves WS endpoint only |
| Browser: thin REST client | Browser: full Flutter app with local DB copy |
| Two UIs to maintain | Zero drift, ever |
| Mobile-only layout on desktop | Adaptive `NavigationRail` at ≥840 dp |
