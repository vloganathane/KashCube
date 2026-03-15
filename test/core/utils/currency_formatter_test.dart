import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter.format', () {
    test('formats sub-1000 amount', () {
      expect(CurrencyFormatter.format(450), '₹450');
    });

    test('formats 4-digit amount with thousands separator', () {
      expect(CurrencyFormatter.format(1234), '₹1,234');
    });

    test('formats lakhs in Indian system (not ₹1,50,000 western)', () {
      expect(CurrencyFormatter.format(150000), '₹1,50,000');
    });

    test('formats crore in Indian system', () {
      expect(CurrencyFormatter.format(10000000), '₹1,00,00,000');
    });

    test('formats negative amount as absolute value (no sign)', () {
      expect(CurrencyFormatter.format(-500), '₹500');
    });

    test('formats zero', () {
      expect(CurrencyFormatter.format(0), '₹0');
    });

    test('formats with decimals when showDecimals=true', () {
      expect(CurrencyFormatter.format(1234.50, showDecimals: true), '₹1,234.50');
    });
  });

  group('CurrencyFormatter.formatSigned', () {
    test('positive amount gets + prefix', () {
      expect(CurrencyFormatter.formatSigned(25000), '+₹25,000');
    });

    test('negative amount gets - prefix', () {
      expect(CurrencyFormatter.formatSigned(-450), '-₹450');
    });

    test('zero gets + prefix', () {
      expect(CurrencyFormatter.formatSigned(0), '+₹0');
    });
  });

  group('CurrencyFormatter.formatCompact', () {
    test('formats thousands as K', () {
      expect(CurrencyFormatter.formatCompact(25000), '₹25K');
    });

    test('formats lakhs as L', () {
      expect(CurrencyFormatter.formatCompact(150000), '₹1.5L');
    });

    test('formats exact lakh without decimal', () {
      expect(CurrencyFormatter.formatCompact(100000), '₹1L');
    });

    test('formats crore as Cr', () {
      expect(CurrencyFormatter.formatCompact(15000000), '₹1.5Cr');
    });

    test('formats negative lakhs with minus prefix', () {
      expect(CurrencyFormatter.formatCompact(-200000), '-₹2L');
    });

    test('formats sub-1000 amount as plain integer', () {
      expect(CurrencyFormatter.formatCompact(999), '₹999');
    });
  });
}
