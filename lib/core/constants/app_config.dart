/// Central configuration for Kash Cube.
///
/// ── Changing the base URL ──────────────────────────────────────────────────
/// When kashcube.com is live, update [baseUrl] here — ONE change, ONE place.
/// Everything else (QR generation, deep link parsing, App Links) picks it up.
///
/// Current status: placeholder domain — replace with 'https://kashcube.com'
/// once:
///   1. DNS is pointed to your static host (GitHub Pages / Cloudflare Pages).
///   2. `/.well-known/assetlinks.json` is served at that domain.
///   3. `/apple-app-site-association` is served (for iOS Universal Links).
/// ──────────────────────────────────────────────────────────────────────────
library;

class AppConfig {
  AppConfig._();

  // ── Deep link base URL ────────────────────────────────────────────────────

  /// Base URL used for contact-card deep links and QR codes.
  ///
  /// Change this single constant when your domain is ready.
  static const String baseUrl = 'https://kashcube.com';

  /// Path segment for contact-card links.
  /// Full link: baseUrl + contactPath + "?v=" + base64url_vcard
  static const String contactPath = '/c';

  // ── Android identifiers ───────────────────────────────────────────────────

  /// Used by the landing page to construct the Play Store install URL with
  /// a deferred deep link referrer (Option B acquisition flow).
  static const String androidPackage = 'com.kashcube.app';

  /// MethodChannel name for the install referrer bridge (MainActivity.kt).
  static const String installReferrerChannel = 'com.kashcube/install_referrer';

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true if [uri] is a Kash Cube contact deep link.
  static bool isContactLink(Uri uri) {
    final host = uri.host.toLowerCase();
    return (host == 'kashcube.com' || host == 'www.kashcube.com') &&
        uri.path == contactPath;
  }
}
