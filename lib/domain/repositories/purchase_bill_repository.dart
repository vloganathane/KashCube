import '../../data/models/purchase_bill.dart';

abstract class PurchaseBillRepository {
  /// Insert a new bill with its line items. Returns the new bill id.
  Future<int> insert(PurchaseBill bill, List<PurchaseBillItem> items);

  /// Update an existing bill and replace its line items.
  Future<void> update(PurchaseBill bill, List<PurchaseBillItem> items);

  /// Delete a bill and all its line items (CASCADE).
  Future<void> delete(int id);

  /// Fetch a single bill with items by id. Returns null if not found.
  Future<PurchaseBill?> fetchById(int id);

  /// All bills for [businessId], newest first.
  Future<List<PurchaseBill>> fetchForBusiness(int businessId);

  /// Bills for [businessId] whose [billDate] falls within [[from], [to]] inclusive.
  /// Used by GSTR-3B aggregation service.
  Future<List<PurchaseBill>> fetchForPeriod({
    required int businessId,
    required DateTime from,
    required DateTime to,
  });

  /// All unpaid / partially-paid bills for [businessId].
  Future<List<PurchaseBill>> fetchUnpaid(int businessId);

  /// Record a payment against a bill. Updates [paidAmount] and [status].
  ///
  /// [amount] — the amount being paid now (cumulative with existing [paidAmount]).
  Future<void> recordPayment({
    required int billId,
    required double amount,
    required DateTime paidAt,
  });

  /// Mark ITC as availed for [billId].
  Future<void> markItcAvailed(int billId, {required bool availed});
}
