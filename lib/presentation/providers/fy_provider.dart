import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/fiscal_year_service.dart';

/// Non-null when a year-end warning banner should be shown on the Home screen.
///
/// Returns null when:
///  - FY is not within 7 days of ending, AND
///  - `isResetDue` is false (old FY has already been handled)
///
/// Returns a record when either condition is true.
final yearEndWarningProvider =
    FutureProvider<({String fyLabel, DateTime fyEnd, bool isResetDue})?>((
      ref,
    ) async {
      final isApproaching = await FiscalYearService.instance
          .isApproachingYearEnd(daysBeforeEnd: 7);
      final isResetDue = await FiscalYearService.instance.isResetDue();

      if (!isApproaching && !isResetDue) return null;

      final fy = await FiscalYearService.instance.currentFiscalYear;
      final label = await FiscalYearService.instance.getFYLabel(fy);
      return (fyLabel: label, fyEnd: fy.end, isResetDue: isResetDue);
    });
