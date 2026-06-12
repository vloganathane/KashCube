import 'dart:convert';

import 'package:flutter/services.dart';

/// Result of a PIN code lookup.
class PincodeResult {
  const PincodeResult({required this.city, required this.state});

  /// District / city name, title-cased (e.g. "New Delhi", "Mumbai").
  final String city;

  /// Canonical state name matching [kIndianStates] (e.g. "Delhi", "Maharashtra").
  final String state;
}

/// Offline lookup service for Indian PIN codes.
///
/// Backed by `assets/data/in_pincodes.json` (~656 KB, ≈19 K entries).
/// The JSON is loaded once into a [Map] and never re-loaded, so subsequent
/// calls to [lookup] are O(1).
///
/// Usage:
/// ```dart
/// // In initState — warm up in the background so lookup is instant later.
/// PincodeLookupService.ensureLoaded();
///
/// // When notified that 6 digits were entered:
/// final result = PincodeLookupService.lookup(pin);
/// if (result != null) {
///   setState(() {
///     _city.text  = result.city;
///     _state.text = result.state;
///   });
/// }
/// ```
class PincodeLookupService {
  PincodeLookupService._();

  static Map<String, List<dynamic>>? _data;
  static Future<void>? _loading;

  static const _assetPath = 'assets/data/in_pincodes.json';

  /// Loads the asset in the background. Safe to call multiple times —
  /// subsequent calls return the same Future.
  static Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = json.decode(raw) as Map<String, dynamic>;
    _data = decoded.cast<String, List<dynamic>>();
  }

  /// Returns a [PincodeResult] for a valid 6-digit Indian PIN code,
  /// or `null` if not found / data not yet loaded.
  static PincodeResult? lookup(String pin) {
    final entry = _data?[pin];
    if (entry == null || entry.length < 2) return null;
    return PincodeResult(city: entry[0] as String, state: entry[1] as String);
  }

  /// `true` once the asset has been fully loaded into memory.
  static bool get isLoaded => _data != null;
}
