# Contact Deep Link & User Acquisition

## Overview

Contact QR codes in Kash Cube encode a URL (`https://kashcube.com/c?v=…`) instead of raw vCard bytes. This gives a contact share two roles simultaneously:

- **Existing user scans** → Android App Link opens the Add Party screen with pre-filled contact data.
- **New user scans** → browser opens a static landing page with "Save Contact" and "Get Kash Cube" buttons, driving installs.

After installing via the landing page, the contact is **automatically pre-filled on first launch** using the Play Store Install Referrer API (Option B deferred deep link — no server required).

---

## URL Format

```
https://kashcube.com/c?v=<base64url(utf8(vCard))>
```

- Scheme + host: `https://kashcube.com`
- Path: `/c`
- Query param `v`: the raw RFC 6350 vCard string, UTF-8 encoded then base64url-encoded (no padding `=`).

**Example** (simplified):
```
https://kashcube.com/c?v=QkVHSU46VkNBUkQKVkVSU0lPTjozLjAKRk46TG9nYW5hdGhhbmUgVgpURUw7VFlQRT1DRUxMOis5MTk1MDA2NjYwMTAKRU5EOlZDQVJE
```

Decodes to:
```
BEGIN:VCARD
VERSION:3.0
FN:Loganathane V
TEL;TYPE=CELL:+919500666010
END:VCARD
```

---

## Changing the Domain

**One file, one line:**

```dart
// lib/core/constants/app_config.dart
static const String baseUrl = 'https://kashcube.com';  // ← change here
```

This propagates automatically to:
- QR code generation (`vcard_qr_dialog.dart`)
- Deep link URL decoding (`deep_link_vcard.dart`)
- `AndroidManifest.xml` App Link host matching (must be updated separately — see below)
- Play Store referrer URL

---

## Architecture

### Files

| File | Role |
|------|------|
| `lib/core/constants/app_config.dart` | Single source of truth: `baseUrl`, `contactPath`, `androidPackage`, `installReferrerChannel` |
| `lib/core/utils/deep_link_vcard.dart` | Encode/decode helpers: `encodeVCardUrl`, `decodeVCardUri`, `decodeInstallReferrer`, `playStoreUrlWithReferrer` |
| `lib/presentation/providers/deep_link_provider.dart` | `pendingDeepLinkVCardProvider` — Riverpod `StateProvider<String?>` holding the pending vCard |
| `lib/presentation/app_shell.dart` | Orchestrates deep link listening, install referrer check, and shows the Party form sheet |
| `lib/presentation/widgets/vcard_qr_dialog.dart` | Generates QR using `encodeVCardUrl(vcard)` instead of raw vCard bytes |
| `lib/presentation/widgets/qr_scanner_sheet.dart` | Parses both raw vCard and URL-encoded vCard QR codes |
| `android/app/src/main/AndroidManifest.xml` | `intent-filter` with `autoVerify="true"` for `kashcube.com/c` |
| `android/app/src/main/kotlin/.../MainActivity.kt` | MethodChannel bridge to Play Install Referrer API |

### Data Flow

```
QR generated                     QR scanned (Kash Cube installed)
──────────                       ────────────────────────────────
vCardFromParty(party)            Camera detects URL
      ↓                                ↓
encodeVCardUrl(vcard)            decodeVCardUrl(raw)
      ↓                                ↓
QrImageView(data: url)           parseVCard(vcard)
                                       ↓
                                 PartyFormSheet (pre-filled)


QR scanned (not installed)       First launch after install
──────────────────────────       ──────────────────────────
Camera → browser                 MainActivity.getReferrer()
      ↓                                ↓
kashcube.com/c?v=...             decodeInstallReferrer(referrer)
      ↓                                ↓
Landing page                     pendingDeepLinkVCardProvider
      ↓                                ↓
"Get Kash Cube" button           AppShell._showPartyFromVCard()
(Play Store URL with referrer)         ↓
      ↓                          PartyFormSheet (pre-filled)
Install → first launch
```

---

## Android App Links Setup

### Current state (pre-domain)
`autoVerify="true"` is set in `AndroidManifest.xml`. Without the `assetlinks.json` file at the domain, Android falls back to showing a disambiguation dialog (app chooser). The app still opens — it just requires a tap.

### When `kashcube.com` is live

**Step 1 — Generate the SHA-256 fingerprint of your release keystore:**
```bash
keytool -list -v -keystore android/key.jks -alias <alias>
```
Copy the `SHA-256` value.

**Step 2 — Create `/.well-known/assetlinks.json` at the root of `kashcube.com`:**
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.kashcube.kash_cube",
    "sha256_cert_fingerprints": [
      "AA:BB:CC:DD:..."
    ]
  }
}]
```
Must be served at `https://kashcube.com/.well-known/assetlinks.json` with `Content-Type: application/json`.

**Step 3 — Update `AndroidManifest.xml`** if the domain name changes from `kashcube.com`:
```xml
<data android:scheme="https" android:host="yournewdomain.com" android:pathPrefix="/c"/>
```

### Verification
```bash
# After publishing assetlinks.json:
adb shell pm get-app-links com.kashcube.kash_cube
# Should show: verified
```

---

## iOS Universal Links (Future)

Not yet configured. When `kashcube.com` is live, add:

**`https://kashcube.com/apple-app-site-association`:**
```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "<TEAM_ID>.com.kashcube.kashcube",
      "paths": ["/c*"]
    }]
  }
}
```

Add `com.apple.developer.associated-domains` entitlement in Xcode:
```
applinks:kashcube.com
```

---

## Play Store Install Referrer (Option B)

### How it works

1. Landing page at `kashcube.com/c` constructs the Play Store install URL with the vCard embedded:
   ```
   https://play.google.com/store/apps/...?id=com.kashcube.kash_cube&referrer=<base64vcard>
   ```
   Use `playStoreUrlWithReferrer(vcard)` from `deep_link_vcard.dart` to generate this URL.

2. User installs from Play Store.

3. On the **first cold start**, `AppShell._checkInstallReferrer()`:
   - Calls `MainActivity.getReferrer()` via MethodChannel
   - `MainActivity.kt` uses `InstallReferrerClient` (Google Play library) to fetch the referrer string
   - Referrer is decoded via `decodeInstallReferrer()` back to a raw vCard
   - `pendingDeepLinkVCardProvider` is set to the vCard
   - `AppShell` listens and calls `_showPartyFromVCard()`

4. A `SharedPreferences` flag (`install_referrer_checked`) ensures this runs only once — never on subsequent launches.

### Privacy
- `InstallReferrerClient` communicates only with the Play Store process on-device. No data is sent to any Kash Cube server.
- The vCard data travels: **sharer's device → QR → scanner's browser → Play Store URL param → Play Store → app on-device**. At no point passes through a Kash Cube-controlled server.

### Referrer size limit
Google Play referrer supports up to ~2 KB. A typical vCard (name + phone + email + address) base64-encodes to ~400–600 bytes — well within limits. vCards with many social fields may approach the limit; `encodeVCardUrl` applies no truncation, but the landing page should be tested.

---

## Landing Page Requirements (`kashcube.com/c`)

Minimum viable static HTML page — no server, no analytics, no data collection:

| Element | Purpose |
|---------|---------|
| Parse `?v=` query param | Decode base64url to show the contact's name |
| "Save Contact" button | Triggers `.vcf` file download (`data:text/vcard;charset=utf-8,...`) |
| "Open in Kash Cube" link | `https://kashcube.com/c?v=…` — tapping on Android with app installed triggers App Link |
| "Get Kash Cube" button | Play Store URL using `referrer=<the same base64 v param>` |
| `Content-Security-Policy` | No external scripts. `default-src 'self'; script-src 'unsafe-inline'` for the minimal JS to parse the URL |

Recommended host: **GitHub Pages** or **Cloudflare Pages** — free, no server, no logs that capture user data.

---

## QR Code Backward Compatibility

The `qr_scanner_sheet.dart` scanner supports three input formats:

| Format | Detected by | Action |
|--------|------------|--------|
| Raw vCard (`BEGIN:VCARD …`) | String prefix check | `parseVCard()` directly |
| Kash Cube URL (`https://kashcube.com/c?v=…`) | `AppConfig.isContactLink()` | `decodeVCardUri()` → `parseVCard()` |
| Other text/URL | Fallback | Returned as `{name: rawValue}` |

Old raw-vCard QRs (printed business cards, existing screenshots) continue to work.

---

## Testing Checklist

- [ ] Generate party QR → scan with Kash Cube → party form pre-filled
- [ ] Generate party QR → scan with Google Lens → browser opens (once domain is live)
- [ ] Scan old raw-vCard QR → still works
- [ ] Scan unrelated QR (e.g. URL) → name field filled with raw value
- [ ] `decodeVCardUrl(encodeVCardUrl(vcard)) == vcard` (round-trip)
- [ ] Install referrer: sideload build, set referrer manually via `adb shell am broadcast`, verify party form appears once only
- [ ] `assetlinks.json` verification after domain is live
