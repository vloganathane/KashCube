import '../../data/models/quote.dart';
import '../../data/models/invoice.dart';
import '../../data/models/transaction.dart';

abstract class QuoteRepository {
  Future<List<Quote>> getAll();
  Future<Quote?> getById(int id);
  Future<int> insert(Quote quote, List<QuoteItem> items);
  Future<void> update(Quote quote, List<QuoteItem> items);
  Future<void> delete(int id);
  Future<Invoice> convertToInvoice(int quoteId, String invoiceNo);
}

abstract class InvoiceRepository {
  Future<List<Invoice>> getAll();
  Future<List<Invoice>> getByStatus(InvoiceStatus status);
  Future<Invoice?> getById(int id);
  Future<int> insert(Invoice invoice, List<InvoiceItem> items);
  Future<void> update(Invoice invoice, List<InvoiceItem> items);
  Future<void> delete(int id);
  
  /// Mark invoice as paid and automatically create transaction in main ledger.
  /// 
  /// Returns the created transaction ID.
  /// 
  /// [partialAmount] - If provided, records partial payment. If null, marks as fully paid.
  /// [bookingId] - Optional booking ID to link (for booking invoices).
  Future<int> markAsPaid({
    required Invoice invoice,
    required PaymentMethod paymentMethod,
    required DateTime paidDate,
    double? partialAmount,
    int? bookingId,
  });
}
