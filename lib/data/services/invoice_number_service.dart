import '../services/database_helper.dart';

/// Generates sequential invoice/quote numbers: INV-2026-001, QUO-2026-001
class InvoiceNumberService {
  InvoiceNumberService._();
  static final InvoiceNumberService instance = InvoiceNumberService._();

  final _dbHelper = DatabaseHelper.instance;

  Future<String> nextInvoiceNo() async {
    final year = DateTime.now().year;
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT invoice_no FROM invoices WHERE invoice_no LIKE 'INV-$year-%' "
      'ORDER BY id DESC LIMIT 1',
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['invoice_no'] as String;
      final parts = last.split('-');
      if (parts.length == 3) seq = (int.tryParse(parts[2]) ?? 0) + 1;
    }
    return 'INV-$year-${seq.toString().padLeft(3, '0')}';
  }

  Future<String> nextQuoteNo() async {
    final year = DateTime.now().year;
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT quote_no FROM quotes WHERE quote_no LIKE 'QUO-$year-%' "
      'ORDER BY id DESC LIMIT 1',
    );
    int seq = 1;
    if (result.isNotEmpty) {
      final last = result.first['quote_no'] as String;
      final parts = last.split('-');
      if (parts.length == 3) seq = (int.tryParse(parts[2]) ?? 0) + 1;
    }
    return 'QUO-$year-${seq.toString().padLeft(3, '0')}';
  }
}
