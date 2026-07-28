import '../models/loan.dart';
import '../models/loan_payment.dart';

/// Generates a repayment schedule for a loan based on its frequency.
class ScheduleGenerator {
  ScheduleGenerator._();

  /// Generate installment schedule for a loan.
  ///
  /// [loan] must have [repaymentFrequency], [emiAmount], and [totalEmis] set.
  /// Returns a list of [LoanPayment] entries with due dates calculated
  /// from the loan date based on the frequency.
  static List<LoanPayment> generate({
    required int loanId,
    required DateTime startDate,
    required RepaymentFrequency frequency,
    required double installmentAmount,
    required int totalInstallments,
  }) {
    final payments = <LoanPayment>[];

    for (var i = 1; i <= totalInstallments; i++) {
      final dueDate = _calculateDueDate(
        startDate: startDate,
        frequency: frequency,
        installmentNumber: i,
      );

      payments.add(
        LoanPayment(
          loanId: loanId,
          installmentNumber: i,
          dueDate: dueDate,
          amount: installmentAmount,
        ),
      );
    }

    return payments;
  }

  /// Calculate the due date for a given installment number.
  static DateTime _calculateDueDate({
    required DateTime startDate,
    required RepaymentFrequency frequency,
    required int installmentNumber,
  }) {
    switch (frequency) {
      case RepaymentFrequency.daily:
        return startDate.add(Duration(days: installmentNumber));
      case RepaymentFrequency.weekly:
        return startDate.add(Duration(days: installmentNumber * 7));
      case RepaymentFrequency.monthly:
        // Add months, handling month-end edge cases
        var year = startDate.year;
        var month = startDate.month + installmentNumber;
        while (month > 12) {
          month -= 12;
          year++;
        }
        // Clamp the day to the last day of the target month
        final lastDay = DateTime(year, month + 1, 0).day;
        final day = startDate.day > lastDay ? lastDay : startDate.day;
        return DateTime(year, month, day);
    }
  }
}
