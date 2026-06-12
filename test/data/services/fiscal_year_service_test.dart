import 'package:flutter_test/flutter_test.dart';

import 'package:kash_cube/data/services/fiscal_year_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FiscalYearService.formatDocumentNumber', () {
    test('expands FY tokens and zero pads the sequence', () {
      final fy = DateRange(
        start: DateTime(2025, 4, 1),
        end: DateTime(2026, 3, 31),
      );

      final result = FiscalYearService.instance.formatDocumentNumber(
        'INV-{YY}-{YY+1}-{SEQ}',
        fy,
        7,
      );

      expect(result, 'INV-25-26-0007');
    });

    test('supports custom pad width', () {
      final fy = DateRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
      );

      final result = FiscalYearService.instance.formatDocumentNumber(
        'QT-{YYYY}-{SEQ}',
        fy,
        12,
        padWidth: 3,
      );

      expect(result, 'QT-2026-012');
    });
  });
}
