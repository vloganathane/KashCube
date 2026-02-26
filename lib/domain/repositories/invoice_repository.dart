import '../../data/models/quote.dart';
import '../../data/models/invoice.dart';

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
  Future<void> recordPayment(int invoiceId, double amount);
}
