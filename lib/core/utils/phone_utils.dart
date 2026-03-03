/// Phone number utilities for KashCube.
///
/// All storage uses bare 10-digit numbers (no country code prefix).
/// This class handles normalisation for input, display, and URL building.
/// Currently targets India (+91) only — the default country code is +91.
class PhoneUtils {
  PhoneUtils._();

  static const String _countryCode = '91';
  static const String _dialPrefix = '+91';

  // ── Normalisation ─────────────────────────────────────────────────────────

  /// Strips any leading +91 / 91 / 0 prefix and returns a bare digit string.
  ///
  /// Returns `null` when [raw] is null, empty, or reduces to an empty string.
  /// Does NOT validate length — callers should validate 10 digits separately.
  static String? normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    // Keep only digits
    var s = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (s.length == 12 && s.startsWith(_countryCode)) s = s.substring(2);
    if (s.length == 11 && s.startsWith('0')) s = s.substring(1);
    return s.isEmpty ? null : s;
  }

  // ── Display ───────────────────────────────────────────────────────────────

  /// Returns `"+91 XXXXXXXXXX"` for display, or `null` when [phone] is empty.
  static String? formatDisplay(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final bare = normalize(phone) ?? phone.trim();
    return '$_dialPrefix $bare';
  }

  // ── URL builders ──────────────────────────────────────────────────────────

  /// `tel:+91XXXXXXXXXX` URI for use with `url_launcher`.
  static Uri? telUri(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone) ?? phone;
    return Uri.parse('tel:$_dialPrefix$bare');
  }

  /// `sms:+91XXXXXXXXXX?body=…` URI.
  static Uri? smsUri(String? phone, {String body = ''}) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone) ?? phone;
    final encoded = Uri.encodeComponent(body);
    return Uri.parse('sms:$_dialPrefix$bare?body=$encoded');
  }

  /// `https://wa.me/91XXXXXXXXXX?text=…` URI.
  static Uri? waUri(String? phone, {String message = ''}) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone) ?? phone;
    final encoded = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$_countryCode$bare?text=$encoded');
  }
}
