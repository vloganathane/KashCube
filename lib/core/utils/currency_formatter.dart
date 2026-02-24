import 'package:intl/intl.dart';

/// Formats amounts in the Indian numbering system with ₹ prefix.
///
/// Examples:
/// - `formatIndianCurrency(1234)` → `₹1,234`
/// - `formatIndianCurrency(150000)` → `₹1,50,000`
/// - `formatIndianCurrencySigned(25000)` → `+₹25,000`
/// - `formatIndianCurrencySigned(-450)` → `-₹450`
/// - `formatCompactCurrency(150000)` → `₹1.5L`
class CurrencyFormatter {
  CurrencyFormatter._();

  static final _indianFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _indianFormatWithDecimals = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Formats amount in Indian numbering system: ₹1,23,456
  static String format(double amount, {bool showDecimals = false}) {
    if (showDecimals) {
      return _indianFormatWithDecimals.format(amount.abs());
    }
    return _indianFormat.format(amount.abs());
  }

  /// Formats with sign prefix: +₹25,000 or -₹450
  static String formatSigned(double amount, {bool showDecimals = false}) {
    final prefix = amount >= 0 ? '+' : '-';
    return '$prefix${format(amount, showDecimals: showDecimals)}';
  }

  /// Compact format for summary cards: ₹1.5L, ₹25K, ₹1.2Cr
  static String formatCompact(double amount) {
    final abs = amount.abs();
    final prefix = amount < 0 ? '-' : '';

    if (abs >= 10000000) {
      // Crores
      final value = abs / 10000000;
      return '$prefix₹${_formatDecimal(value)}Cr';
    } else if (abs >= 100000) {
      // Lakhs
      final value = abs / 100000;
      return '$prefix₹${_formatDecimal(value)}L';
    } else if (abs >= 1000) {
      // Thousands
      final value = abs / 1000;
      return '$prefix₹${_formatDecimal(value)}K';
    }
    return '$prefix₹${abs.toStringAsFixed(0)}';
  }

  static String _formatDecimal(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}
