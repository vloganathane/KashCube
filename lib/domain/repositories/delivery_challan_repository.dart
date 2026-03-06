import '../../data/models/delivery_challan.dart';
import '../../data/models/invoice.dart';

abstract class DeliveryChallanRepository {
  Future<List<DeliveryChallan>> getAll();
  Future<DeliveryChallan?> getById(int id);
  Future<List<DeliveryChallan>> getByCustomer(String customerName);
  Future<int> insert(DeliveryChallan challan, List<ChallanItem> items);
  Future<void> update(DeliveryChallan challan, List<ChallanItem> items);
  Future<void> delete(int id);

  /// Promote a draft challan to [ChallanStatus.dispatched].
  Future<void> markDispatched(int id, {DateTime? dispatchDate});

  /// Mark a dispatched challan as returned.
  Future<void> markReturned(int id);

  /// Convert this DC to a Tax Invoice (GST Rule 55 — goods arrive, tax now due).
  ///
  /// Creates the invoice + invoice_items rows in a single transaction and
  /// marks the challan as [ChallanStatus.converted].
  /// Returns the newly created [Invoice] (with id populated).
  Future<Invoice> convertToInvoice(int challanId, String invoiceNo);
}
