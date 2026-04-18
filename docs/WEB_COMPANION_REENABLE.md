# Web Companion Re-enablement Guide

## Overview

The Web Companion feature (LAN-based browser interface, "Open on Laptop") is currently **disabled** to reduce APK size for the Play Store release.

**Savings**: ~44MB removed from Android APK

When disabled:
- `assets/web_ui/` is not bundled (44MB saved)
- HTTP server does not auto-start on app launch
- "Open on Laptop" screen remains hidden in Settings (already commented out)

## What is Web Companion?

Web Companion allows users to access their KashCube data via a browser on the same LAN network (similar to WhatsApp Web). Key features:

- **100% local**: Browser connects directly to phone over LAN (HTTP server on phone)
- **No cloud**: Zero network calls to external servers
- **Privacy-first**: All data stays on-device; browser is a thin client
- **Real-time sync**: WebSocket-based bi-directional sync between phone and browser

## Re-enablement Steps

### 1. Uncomment Web UI Assets

**File**: `pubspec.yaml` (lines ~168-178)

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/logo.png
    - assets/logo-white.png
    - assets/data/in_pincodes.json
    - assets/hns_sac/HSN_SAC - HSN_MSTR.csv
    - assets/hns_sac/HSN_SAC - SAC_MSTR.csv
    # ── Uncomment these lines ──
    - assets/web_ui/
    - assets/web_ui/assets/
    - assets/web_ui/assets/assets/
    - assets/web_ui/assets/assets/data/
    - assets/web_ui/assets/assets/hns_sac/
    - assets/web_ui/assets/fonts/
    - assets/web_ui/assets/packages/world_flags/shaders/
    - assets/web_ui/assets/shaders/
    - assets/web_ui/canvaskit/
    - assets/web_ui/canvaskit/chromium/
    - assets/web_ui/icons/
```

### 2. Re-enable Web Companion Service Attachment

**File**: `lib/main.dart` (line ~80)

```dart
// Uncomment this line:
if (!kIsWeb) WebCompanionService.instance.attach();
```

### 3. Re-enable HTTP Server Auto-start

**File**: `lib/main.dart` (line ~238)

```dart
// Uncomment this line inside KashCubeApp.build():
if (!kIsWeb) ref.watch(httpServerInitProvider);
```

### 4. Re-enable HTTP Server Init Provider

**File**: `lib/presentation/providers/p2p_provider.dart` (lines ~193-217)

Uncomment the entire `httpServerInitProvider` definition:

```dart
final httpServerInitProvider = FutureProvider<void>((ref) async {
  try {
    final db = await DatabaseHelper.instance.database;
    await ref.read(identityInitProvider.future);
    final identity = await ref.read(identityServiceProvider.future);
    final settings = ref.read(settingsRepositoryProvider);
    final name = await settings.get(SettingsKeys.ownerName);

    await P2pCoordinator.instance.startServerOnly(
      db: db,
      identity: identity,
      displayName: (name == null || name.trim().isEmpty)
          ? 'KashCube'
          : name.trim(),
    );
    debugPrint(
      '[HttpServerInit] Server started on port ${P2pServer.instance.port}',
    );
  } catch (e) {
    debugPrint('[HttpServerInit] Failed to start server: $e');
    // Non-fatal — allows app to continue; /health can be retried later.
  }
});
```

### 5. Uncomment "Open on Laptop" Screen in Settings

**File**: `lib/presentation/screens/settings/settings_screen.dart` (line ~33)

```dart
// Uncomment this import:
import 'open_on_laptop_screen.dart';
```

Then find the settings item for "Open on Laptop" and uncomment the navigation:

```dart
SettingItem(
  title: 'Open on Laptop',
  subtitle: 'Access KashCube from your browser',
  icon: Icons.computer,
  sectionLabel: 'General',
  keywords: ['browser', 'web', 'laptop', 'desktop', 'lan'],
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const OpenOnLaptopScreen()),
  ),
),
```

### 6. Rebuild Web UI Assets (If Updated)

If the Flutter web build has changed, regenerate `assets/web_ui/`:

```bash
# From project root:
bash scripts/build_web_ui.sh
```

This script:
1. Builds the Flutter web app (`flutter build web`)
2. Copies output to `assets/web_ui/`
3. Generates `manifest.txt` for asset extraction

### 7. Test the Feature

1. **Build and install** the app with web companion enabled
2. **Open Settings** → verify "Open on Laptop" appears
3. **Tap "Open on Laptop"** → should show QR code and LAN URL
4. **Open browser** on the same Wi-Fi network → navigate to the URL
5. **Scan QR code** from phone camera → browser should connect and show data

## Architecture Notes

### How It Works

1. **App startup**: HTTP server starts on a random port (8080-8100 range)
2. **User taps "Open on Laptop"**: Shows LAN IP + port + auth QR code
3. **Browser navigates** to `http://<phone-ip>:<port>/`
4. **Phone serves** static web UI from `assets/web_ui/` (extracted to temp dir)
5. **Browser displays** QR code for phone to scan (mutual auth handshake)
6. **Phone scans** browser's QR → establishes session token
7. **WebSocket upgrade**: Browser and phone establish bi-directional sync

### Key Components

- **`WebUiExtractor`**: Lazily extracts `assets/web_ui/` to temp directory
- **`WebCompanionService`**: Manages wake-lock and browser session lifecycle
- **`P2pServer`**: HTTP server with shelf middleware (static files + WebSocket)
- **`WebBrowserSession`**: Sync bridge for browser-to-phone DB operations
- **`OpenOnLaptopScreen`**: QR code + URL display + phone-side QR scanner

### Permissions Required (Android)

- **`INTERNET`**: Already declared (for LAN HTTP server)
- **`ACCESS_NETWORK_STATE`**: Already declared (to show LAN IP)
- **`ACCESS_WIFI_STATE`**: Already declared (for mDNS discovery)
- **`CAMERA`**: Already declared (for QR scanner)

No new permissions needed.

## Play Store Considerations

**Why disabled for Play Store**:
- Adds 44MB to APK (canvaskit + compiled Dart → JS)
- Feature may confuse non-technical users
- Increases review surface area (HTTP server, WebSocket, camera for QR)

**When to re-enable**:
- For internal/beta builds where team members want browser access
- For F-Droid or direct APK distribution where size is less critical
- After user feedback shows demand for the feature

**Alternative**: Consider dynamic delivery (Android App Bundle) to make web companion an optional on-demand module.

## Troubleshooting

### Assets not found errors
- Run `flutter clean && flutter pub get`
- Verify `assets/web_ui/manifest.txt` exists
- Rebuild web UI: `bash scripts/build_web_ui.sh`

### Server fails to start
- Check `adb logcat` for "[HttpServerInit] Failed to start server"
- Verify port range 8080-8100 is not blocked
- Check device firewall settings

### Browser can't connect
- Verify phone and laptop are on **same Wi-Fi network**
- Some corporate/guest Wi-Fi networks block device-to-device communication
- Try mobile hotspot from phone → laptop connects to phone's hotspot

## Related Files

- `lib/data/services/web/web_ui_extractor.dart` — Asset extraction
- `lib/data/services/web/web_companion_service.dart` — Wake-lock + session manager
- `lib/data/services/p2p/p2p_server.dart` — HTTP server (shelf)
- `lib/data/services/web/web_browser_session.dart` — Browser sync bridge
- `lib/presentation/screens/settings/open_on_laptop_screen.dart` — UI
- `lib/presentation/web/web_connect_screen.dart` — Browser-side entry point
- `scripts/build_web_ui.sh` — Web build automation

## Changelog

- **2026-04-18**: Web Companion disabled for Play Store release (APK size optimization)
