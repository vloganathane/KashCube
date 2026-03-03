/// Phone number utilities for KashCube.
///
/// All storage uses bare 10-digit (or local-format) numbers without country
/// code prefix. This class handles normalisation for input, display, and URL
/// building. Pass the [dialCode] string from the Party/Business model to
/// produce the correct prefix — defaults to '91' (India) when omitted.
class PhoneUtils {
  PhoneUtils._();

  static const String _defaultDialCode = '91';

  // ── Normalisation ─────────────────────────────────────────────────────────

  /// Strips any leading country-code prefix and returns a bare digit string.
  ///
  /// Handles:
  /// - Numbers starting with +<dialCode> or <dialCode> when 12+ digits (India)
  /// - Indian-specific: leading '0'
  /// Returns `null` when [raw] is null, empty, or reduces to empty.
  static String? normalize(String? raw, {String dialCode = _defaultDialCode}) {
    if (raw == null || raw.trim().isEmpty) return null;
    var s = raw.replaceAll(RegExp(r'[^\d]'), '');
    // Strip country code prefix when present
    if (s.startsWith(dialCode) && s.length > dialCode.length) {
      s = s.substring(dialCode.length);
    }
    // Legacy India: strip leading 0
    if (dialCode == '91' && s.length == 11 && s.startsWith('0')) {
      s = s.substring(1);
    }
    return s.isEmpty ? null : s;
  }

  // ── Display ───────────────────────────────────────────────────────────────

  /// Returns `"+<dialCode> <number>"` for display, or `null` when [phone] is
  /// null or empty. Defaults to `+91` (India).
  static String? formatDisplay(String? phone,
      {String dialCode = _defaultDialCode}) {
    if (phone == null || phone.trim().isEmpty) return null;
    final bare = normalize(phone, dialCode: dialCode) ?? phone.trim();
    return '+$dialCode $bare';
  }

  // ── URL builders ──────────────────────────────────────────────────────────

  /// `tel:+<dialCode><number>` URI for use with `url_launcher`.
  static Uri? telUri(String? phone, {String dialCode = _defaultDialCode}) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone, dialCode: dialCode) ?? phone;
    return Uri.parse('tel:+$dialCode$bare');
  }

  /// `sms:+<dialCode><number>?body=…` URI.
  static Uri? smsUri(String? phone,
      {String dialCode = _defaultDialCode, String body = ''}) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone, dialCode: dialCode) ?? phone;
    final encoded = Uri.encodeComponent(body);
    return Uri.parse('sms:+$dialCode$bare?body=$encoded');
  }

  /// `https://wa.me/<dialCode><number>?text=…` URI.
  static Uri? waUri(String? phone,
      {String dialCode = _defaultDialCode, String message = ''}) {
    if (phone == null || phone.isEmpty) return null;
    final bare = normalize(phone, dialCode: dialCode) ?? phone;
    final encoded = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$dialCode$bare?text=$encoded');
  }
}
