// Offline GSTIN format validator — no network, no third-party libraries.
//
// GSTIN structure (15 characters):
//   Pos  1-2  : State code (01–38)
//   Pos  3-12 : PAN (5 uppercase letters + 4 digits + 1 uppercase letter)
//   Pos 13    : Entity number within PAN (1-9 or A-Z)
//   Pos 14    : Always 'Z'
//   Pos 15    : Checksum alphanumeric (0-9 or A-Z)
//
// Reference: GSTN registration specification, CBIC circular.

/// Offline GSTIN validation utility.
///
/// All methods are pure functions — no I/O, no network.
abstract class GstinValidator {
  GstinValidator._();

  // ─── GSTN state code → normalised state name ─────────────────────────────
  // Based on GSTN registration state master list.
  static const Map<String, String> _stateByCode = {
    '01': 'jammu & kashmir',
    '02': 'himachal pradesh',
    '03': 'punjab',
    '04': 'chandigarh',
    '05': 'uttarakhand',
    '06': 'haryana',
    '07': 'delhi',
    '08': 'rajasthan',
    '09': 'uttar pradesh',
    '10': 'bihar',
    '11': 'sikkim',
    '12': 'arunachal pradesh',
    '13': 'nagaland',
    '14': 'manipur',
    '15': 'mizoram',
    '16': 'tripura',
    '17': 'meghalaya',
    '18': 'assam',
    '19': 'west bengal',
    '20': 'jharkhand',
    '21': 'odisha',
    '22': 'chhattisgarh',
    '23': 'madhya pradesh',
    '24': 'gujarat',
    '26': 'dadra & nh',
    '27': 'maharashtra',
    '28': 'andhra pradesh',
    '29': 'karnataka',
    '30': 'goa',
    '31': 'lakshadweep',
    '32': 'kerala',
    '33': 'tamil nadu',
    '34': 'puducherry',
    '35': 'andaman & nicobar',
    '36': 'telangana',
    '37': 'andhra pradesh',
    '38': 'ladakh',
    '97': 'other territory',
    '99': 'centre jurisdiction',
  };

  // Alternate spellings accepted when matching a state name input
  static const Map<String, String> _stateAliases = {
    'j&k': 'jammu & kashmir',
    'jammu and kashmir': 'jammu & kashmir',
    'hp': 'himachal pradesh',
    'uk': 'uttarakhand',
    'uttaranchal': 'uttarakhand',
    'hr': 'haryana',
    'rj': 'rajasthan',
    'up': 'uttar pradesh',
    'bihar': 'bihar',
    'ar': 'arunachal pradesh',
    'nl': 'nagaland',
    'mn': 'manipur',
    'mz': 'mizoram',
    'tr': 'tripura',
    'ml': 'meghalaya',
    'as': 'assam',
    'wb': 'west bengal',
    'jh': 'jharkhand',
    'or': 'odisha',
    'orissa': 'odisha',
    'cg': 'chhattisgarh',
    'mp': 'madhya pradesh',
    'gj': 'gujarat',
    'dnh': 'dadra & nh',
    'dadra and nagar haveli': 'dadra & nh',
    'dadra & nagar haveli': 'dadra & nh',
    'mh': 'maharashtra',
    'ap': 'andhra pradesh',
    'ka': 'karnataka',
    'kl': 'kerala',
    'tn': 'tamil nadu',
    'py': 'puducherry',
    'pondicherry': 'puducherry',
    'an': 'andaman & nicobar',
    'andaman and nicobar': 'andaman & nicobar',
    'ts': 'telangana',
  };

  // Regex: exactly the GSTN format
  static final RegExp _gstinRegex = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
  );

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Returns `true` if [gstin] is a structurally valid GSTIN.
  ///
  /// Checks:
  ///   1. Length == 15
  ///   2. Full GSTN regex
  ///   3. State code is a known GSTN state code
  static bool isValid(String gstin) {
    final g = gstin.trim().toUpperCase();
    if (g.length != 15) return false;
    if (!_gstinRegex.hasMatch(g)) return false;
    return _stateByCode.containsKey(g.substring(0, 2));
  }

  /// Returns the 2-digit GSTN state code from [gstin], or `null` if invalid.
  static String? stateCodeFrom(String gstin) {
    if (gstin.length < 2) return null;
    final code = gstin.trim().substring(0, 2);
    return _stateByCode.containsKey(code) ? code : null;
  }

  /// Returns the state name for [gstin]'s state code, or `null` if not found.
  static String? stateNameFrom(String gstin) {
    final code = stateCodeFrom(gstin);
    return code != null ? _stateByCode[code] : null;
  }

  /// Returns `true` if [gstin]'s embedded state code matches [stateName].
  ///
  /// [stateName] is compared case-insensitively; common aliases are accepted.
  /// Returns `true` when [stateName] is null or empty (no check possible).
  static bool stateMatches(String gstin, String? stateName) {
    if (stateName == null || stateName.trim().isEmpty) return true;
    final gstinState = stateNameFrom(gstin.trim().toUpperCase());
    if (gstinState == null) return false;
    final inputNorm = _normaliseState(stateName);
    return gstinState == inputNorm;
  }

  /// Validator for use directly in `TextFormField.validator`.
  ///
  /// Returns `null` (valid) when:
  ///   - The value is null or empty (field is optional)
  ///   - The value is a structurally valid GSTIN
  ///
  /// Returns an error string when format is invalid.
  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final g = value.trim().toUpperCase();
    if (g.length != 15) {
      return 'GSTIN must be exactly 15 characters';
    }
    if (!_gstinRegex.hasMatch(g)) {
      return 'Invalid GSTIN format (e.g. 29AABCU9603R1ZL)';
    }
    if (!_stateByCode.containsKey(g.substring(0, 2))) {
      return 'Invalid state code in GSTIN (first 2 digits)';
    }
    return null;
  }

  /// Validator that also warns when [gstin]'s state code doesn't match
  /// [selectedState]. Useful on the party form where state is also entered.
  ///
  /// Mismatch is returned as a warning string (non-null), so the form blocks
  /// save. Set [warnOnStateMismatch] to `false` to skip this check.
  static String? validateWithState(
    String? value, {
    String? selectedState,
    bool warnOnStateMismatch = true,
  }) {
    final base = validate(value);
    if (base != null) return base;
    if (value == null || value.trim().isEmpty) return null;
    if (!warnOnStateMismatch || selectedState == null || selectedState.isEmpty) {
      return null;
    }
    if (!stateMatches(value.trim().toUpperCase(), selectedState)) {
      final expected = stateNameFrom(value.trim().toUpperCase()) ?? '?';
      return "GSTIN state code doesn't match selected state "
          "(GSTIN is from $expected)";
    }
    return null;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static String _normaliseState(String s) {
    final lower = s.trim().toLowerCase();
    return _stateAliases[lower] ?? lower;
  }
}
