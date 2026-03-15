import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/services/gst_calculator.dart';

void main() {
  group('GstCalculator.calculate — intra-state', () {
    test('splits 18% GST into equal CGST + SGST for same state', () {
      final split = GstCalculator.calculate(
        sellerState: 'Maharashtra',
        buyerState: 'Maharashtra',
        taxableAmount: 1000,
        gstPct: 18,
      );
      expect(split.isInterState, isFalse);
      expect(split.igst, 0);
      expect(split.cgst, 90);
      expect(split.sgst, 90);
      expect(split.total, 180);
    });

    test('splits 5% GST correctly (no rounding drift)', () {
      final split = GstCalculator.calculate(
        sellerState: 'Karnataka',
        buyerState: 'Karnataka',
        taxableAmount: 1000,
        gstPct: 5,
      );
      expect(split.isInterState, isFalse);
      expect(split.total, 50);
      expect(split.cgst + split.sgst, 50);
    });
  });

  group('GstCalculator.calculate — inter-state', () {
    test('applies IGST when states differ', () {
      final split = GstCalculator.calculate(
        sellerState: 'Maharashtra',
        buyerState: 'Karnataka',
        taxableAmount: 1000,
        gstPct: 18,
      );
      expect(split.isInterState, isTrue);
      expect(split.igst, 180);
      expect(split.cgst, 0);
      expect(split.sgst, 0);
    });

    test('applies IGST when buyer state is null', () {
      final split = GstCalculator.calculate(
        sellerState: 'Maharashtra',
        buyerState: null,
        taxableAmount: 500,
        gstPct: 12,
      );
      expect(split.isInterState, isTrue);
      expect(split.igst, 60);
    });
  });

  group('GstCalculator.calculate — edge cases', () {
    test('returns zero split for 0% GST', () {
      final split = GstCalculator.calculate(
        sellerState: 'Karnataka',
        buyerState: 'Karnataka',
        taxableAmount: 1000,
        gstPct: 0,
      );
      expect(split.total, 0);
    });

    test('returns zero split for 0 taxableAmount', () {
      final split = GstCalculator.calculate(
        sellerState: 'Karnataka',
        buyerState: 'Karnataka',
        taxableAmount: 0,
        gstPct: 18,
      );
      expect(split.total, 0);
    });

    test('handles case-insensitive state comparison', () {
      final split = GstCalculator.calculate(
        sellerState: 'maharashtra',
        buyerState: 'MAHARASHTRA',
        taxableAmount: 1000,
        gstPct: 18,
      );
      expect(split.isInterState, isFalse);
    });

    test('handles state abbreviation "UP" as Uttar Pradesh', () {
      final split = GstCalculator.calculate(
        sellerState: 'UP',
        buyerState: 'Uttar Pradesh',
        taxableAmount: 1000,
        gstPct: 18,
      );
      expect(split.isInterState, isFalse);
    });
  });
}
