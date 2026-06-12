import '../models/invoice.dart';
import '../models/quote.dart';
import 'pdf_document_data.dart';

bool _isServiceSupply(Iterable<dynamic> items) {
  return items.isNotEmpty &&
      items.every((item) => item.hsnOrSac.toUpperCase() == 'SAC');
}

PdfCopyInfo buildGoodsCopyInfo() {
  return const PdfCopyInfo(
    heading: 'Supply of Goods',
    copyCount: 3,
    copyLabels: [
      '(ORGINAL FOR RECIPIENT)',
      '(Duplicate for Transporter)',
      '(Triplicate for Supplier)',
    ],
    copyLines: [
      'Original: Issued to the recipient (buyer).',
      'Duplicate: For the transporter (or to accompany the goods during transit).',
      'Triplicate: Retained by the supplier for their own records.',
    ],
  );
}

PdfCopyInfo buildServicesCopyInfo() {
  return const PdfCopyInfo(
    heading: 'Supply of Services',
    copyCount: 2,
    copyLabels: ['(ORGINAL FOR RECIPIENT)', '(Duplicate for Supplier)'],
    copyLines: [
      'Original: Issued to the recipient (customer).',
      'Duplicate: Retained by the supplier for their own records.',
    ],
  );
}

PdfCopyInfo buildInvoiceCopyInfo(Iterable<InvoiceItem> items) {
  return _isServiceSupply(items)
      ? buildServicesCopyInfo()
      : buildGoodsCopyInfo();
}

PdfCopyInfo buildQuoteCopyInfo(Iterable<QuoteItem> items) {
  return _isServiceSupply(items)
      ? buildServicesCopyInfo()
      : buildGoodsCopyInfo();
}
