import '../../data/models/bill.dart';

/// Abstract interface for scheduled bill payment persistence.
abstract class BillScheduleRepository {
  /// Returns all active, non-deleted bills.
  Future<List<Bill>> getAll();

  /// Returns bills that are unpaid and overdue.
  Future<List<Bill>> getOverdue();

  /// Returns bills upcoming within [days].
  Future<List<Bill>> getUpcoming({int days = 7});

  /// Returns a single bill by [id].
  Future<Bill?> getById(int id);

  /// Inserts a new bill. Returns its row id.
  Future<int> insert(Bill bill);

  /// Updates an existing bill.
  Future<void> update(Bill bill);

  /// Soft-deletes a bill by [id].
  Future<void> delete(int id);

  /// Marks a bill as paid for the current period.
  Future<void> markPaid(int id);

  /// Marks a bill as unpaid (clears last_paid_date).
  Future<void> markUnpaid(int id);

  /// Returns total monthly bill outflow (active bills normalized to monthly).
  Future<double> getTotalMonthly();
}
