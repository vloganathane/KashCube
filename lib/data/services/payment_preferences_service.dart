import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/app_logger.dart';

import '../models/transaction.dart';

/// Service for managing payment method preferences per customer.
/// Remembers the last payment method used for each customer to provide
/// smart defaults when recording invoice payments.
class PaymentPreferencesService {
  static const String _keyPrefix = 'payment_method_customer_';

  /// Get the last used payment method for a customer (by party ID).
  /// Returns null if no preference exists.
  static Future<PaymentMethod?> getLastUsedMethod(int? partyId) async {
    if (partyId == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final methodName = prefs.getString('$_keyPrefix$partyId');

    if (methodName == null) return null;

    // Convert string back to PaymentMethod enum
    try {
      return PaymentMethod.values.firstWhere((m) => m.name == methodName);
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to parse payment method enum',
        category: 'payment_preferences',
        error: e,
      );
      return null;
    }
  }

  /// Save the payment method used for a customer (by party ID).
  static Future<void> saveLastUsedMethod(
    int? partyId,
    PaymentMethod method,
  ) async {
    if (partyId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$partyId', method.name);
  }

  /// Clear the payment method preference for a customer.
  static Future<void> clearPreference(int? partyId) async {
    if (partyId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$partyId');
  }

  /// Clear all payment method preferences.
  static Future<void> clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_keyPrefix)) {
        await prefs.remove(key);
      }
    }
  }
}
