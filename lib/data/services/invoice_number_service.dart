import 'fiscal_year_service.dart';

/// Generates sequential invoice/quote numbers in FY-aware format.
///
/// Delegates entirely to [FiscalYearService], which reads the configured
/// `invoice_no_format` / `quote_no_format` from settings and scopes the
/// sequence to the current fiscal year.
///
/// Default formats (Indian GST-recommended):
///   Invoice: INV-{YY}-{YY+1}-{SEQ}  → "INV-25-26-0042"
///   Quote:   QT-{YY}-{YY+1}-{SEQ}   → "QT-25-26-0042"
///
/// This class is a thin facade kept for backward-compatibility so existing
/// call-sites do not need to change.
class InvoiceNumberService {
  InvoiceNumberService._();
  static final InvoiceNumberService instance = InvoiceNumberService._();

  Future<String> nextInvoiceNo() => FiscalYearService.instance.nextInvoiceNo();

  Future<String> nextQuoteNo() => FiscalYearService.instance.nextQuoteNo();

  Future<String> nextCreditNoteNo() =>
      FiscalYearService.instance.nextCreditNoteNo();

  Future<String> nextDebitNoteNo() =>
      FiscalYearService.instance.nextDebitNoteNo();
}
