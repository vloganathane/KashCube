/// Utilities for encoding and decoding Kash Cube contact deep links.
///
/// Format:  https://kashcube.com/c?v=base64url(utf8(vCard))
///
/// The vCard is UTF-8 encoded then base64url (no-padding) encoded so the URL
/// is safe for QR codes, Play Store referrer params, and browser links.
///
/// No network calls — purely local encode/decode.
library;

import 'dart:convert';

import '../constants/app_config.dart';

// ── Encode ────────────────────────────────────────────────────────────────────

/// Encodes a raw RFC 6350 vCard string into a Kash Cube contact URL.
///
/// ```
/// encodeVCardUrl(vcard) -> "https://kashcube.com/c?v=QkVHSU4..."
/// ```
String encodeVCardUrl(String vcard) {
  final b64 = base64Url.encode(utf8.encode(vcard)).replaceAll('=', '');
  return '${AppConfig.baseUrl}${AppConfig.contactPath}?v=$b64';
}

/// Returns the Play Store URL wired with an install-referrer that carries the
/// vCard — so on first launch after install the contact can be pre-filled.
///
/// The landing page at [AppConfig.baseUrl]/c should use this URL for the
/// "Get Kash Cube" button so the deferred deep link survives the install.
String playStoreUrlWithReferrer(String vcard) {
  final b64 = base64Url.encode(utf8.encode(vcard)).replaceAll('=', '');
  final referrer = Uri.encodeComponent(b64);
  return 'https://play.google.com/store/apps/details'
      '?id=${AppConfig.androidPackage}'
      '&referrer=$referrer';
}

// ── Decode ────────────────────────────────────────────────────────────────────

/// Decodes a contact deep link URL back to a raw vCard string.
///
/// Returns `null` if [url] is not a valid Kash Cube contact link or the
/// payload cannot be decoded.
String? decodeVCardUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return decodeVCardUri(uri);
  } catch (_) {
    return null;
  }
}

/// Same as [decodeVCardUrl] but accepts an already-parsed [Uri].
String? decodeVCardUri(Uri uri) {
  try {
    if (!AppConfig.isContactLink(uri)) return null;
    final b64 = uri.queryParameters['v'];
    if (b64 == null || b64.isEmpty) return null;
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(b64)));
    // Sanity check — must look like a vCard
    if (!decoded.trimLeft().toUpperCase().startsWith('BEGIN:VCARD')) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

/// Decodes a raw Play Store install referrer value (base64url-encoded vCard)
/// back to a vCard string.
///
/// The Play Store delivers the referrer URL-decoded, so the value is just
/// the base64url string set by the landing page.
///
/// Returns `null` if [referrer] is not a valid encoded vCard.
String? decodeInstallReferrer(String referrer) {
  try {
    if (referrer.isEmpty) return null;
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(referrer)));
    if (!decoded.trimLeft().toUpperCase().startsWith('BEGIN:VCARD')) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}
