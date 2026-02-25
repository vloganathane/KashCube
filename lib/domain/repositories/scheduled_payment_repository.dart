import '../../data/models/scheduled_payment.dart';

/// Abstract interface for [ScheduledPayment] persistence.
///
/// Replaces the legacy `BillScheduleRepository` and
/// `RecurringTransactionRepository`.
abstract class ScheduledPaymentRepository {
  /// All active, non-deleted scheduled payments, newest first.
  Future<List<ScheduledPayment>> getAll();

  /// Payments that are unpaid and whose [nextDate] is in the past.
  Future<List<ScheduledPayment>> getOverdue();

  /// Payments due within the next [days] days (unpaid, not yet overdue).
  Future<List<ScheduledPayment>> getUpcoming({int days = 7});

  /// Auto-create candidates: `autoCreate=true` and `nextDate <= now`.
  Future<List<ScheduledPayment>> getDueForAutoCreate();

  Future<ScheduledPayment?> getById(int id);

  /// Insert a new payment. Returns the new row id.
  Future<int> insert(ScheduledPayment payment);

  Future<void> update(ScheduledPayment payment);

  /// Soft-delete.
  Future<void> delete(int id);

  /// Total monthly outflow (expenses only, normalised by frequency).
  Future<double> getTotalMonthlyExpense();

  /// Monthly income + expense totals (normalised by frequency).
  Future<({double income, double expense})> getMonthlySummary();
}
