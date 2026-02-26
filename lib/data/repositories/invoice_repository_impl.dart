import '../../data/models/invoice.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../domain/repositories/transaction_repository.dart';

// ---------------------------------------------------------------------------
// Quote
// ---------------------------------------------------------------------------

class QuoteRepositoryImpl implements QuoteRepository {
  final _db = DatabaseHelper.instance;

  @override
  Future<List<Quote>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('quotes', orderBy: 'created_at DESC');
    final List<Quote> result = [];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsForQuote(db, id);
      result.add(Quote.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<Quote?> getById(int id) async {
    final db = await _db.database;
    final rows =
        await db.query('quotes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await _itemsForQuote(db, id);
    return Quote.fromMap(rows.first, items: items);
  }

  Future<List<QuoteItem>> _itemsForQuote(dynamic db, int quoteId) async {
    final rows = await db.query('quote_items',
        where: 'quote_id = ?', whereArgs: [quoteId]);
    return rows.map<QuoteItem>(QuoteItem.fromMap).toList();
  }

  @override
  Future<int> insert(Quote quote, List<QuoteItem> items) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await txn.insert('quotes', quote.toMap());
      for (final item in items) {
        await txn.insert(
            'quote_items', item.copyWith(quoteId: id).toMap());
      }
      return id;
    });
  }

  @override
  Future<void> update(Quote quote, List<QuoteItem> items) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('quotes', quote.copyWith(updatedAt: DateTime.now()).toMap(),
          where: 'id = ?', whereArgs: [quote.id]);
      await txn
          .delete('quote_items', where: 'quote_id = ?', whereArgs: [quote.id]);
      for (final item in items) {
        await txn.insert(
            'quote_items', item.copyWith(quoteId: quote.id!).toMap());
      }
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('quotes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Invoice> convertToInvoice(int quoteId, String invoiceNo) async {
    final db = await _db.database;
    final quote = await getById(quoteId);
    if (quote == null) throw Exception('Quote $quoteId not found');

    final now = DateTime.now();
    final invoice = Invoice(
      invoiceNo: invoiceNo,
      quoteId: quoteId,
      customerPartyId: quote.customerPartyId,
      customerName: quote.customerName,
      status: InvoiceStatus.draft,
      issueDate: now,
      dueDate: now.add(const Duration(days: 30)),
      subtotal: quote.subtotal,
      taxTotal: quote.taxTotal,
      discountPct: quote.discountPct,
      total: quote.total,
      notes: quote.notes,
      createdAt: now,
      updatedAt: now,
    );

    final invoiceId = await db.transaction((txn) async {
      final id = await txn.insert('invoices', invoice.toMap());
      for (final qi in quote.items) {
        final ii = InvoiceItem(
          invoiceId: id,
          itemName: qi.itemName,
          description: qi.description,
          qty: qi.qty,
          unitPrice: qi.unitPrice,
          taxPct: qi.taxPct,
          discountPct: qi.discountPct,
          lineTotal: qi.lineTotal,
        );
        await txn.insert('invoice_items', ii.toMap());
      }
      // Mark quote as accepted
      await txn.update('quotes', {'status': QuoteStatus.accepted.dbValue},
          where: 'id = ?', whereArgs: [quoteId]);
      return id;
    });

    return invoice.copyWith(id: invoiceId);
  }
}

// ---------------------------------------------------------------------------
// Invoice
// ---------------------------------------------------------------------------

class InvoiceRepositoryImpl implements InvoiceRepository {
  InvoiceRepositoryImpl({required TransactionRepository transactionRepo})
      : _transactionRepo = transactionRepo;

  final _db = DatabaseHelper.instance;
  final TransactionRepository _transactionRepo;

  @override
  Future<List<Invoice>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('invoices', orderBy: 'created_at DESC');
    return _withItems(db, rows);
  }

  @override
  Future<List<Invoice>> getByStatus(InvoiceStatus status) async {
    final db = await _db.database;
    final rows = await db.query('invoices',
        where: 'status = ?',
        whereArgs: [status.dbValue],
        orderBy: 'created_at DESC');
    return _withItems(db, rows);
  }

  Future<List<Invoice>> _withItems(
      dynamic db, List<Map<String, dynamic>> rows) async {
    final List<Invoice> result = [];
    for (final row in rows) {
      final id = row['id'] as int;
      final itemRows = await db.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [id]);
      final items = itemRows.map<InvoiceItem>(InvoiceItem.fromMap).toList();
      result.add(Invoice.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<Invoice?> getById(int id) async {
    final db = await _db.database;
    final rows =
        await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final itemRows = await db.query('invoice_items',
        where: 'invoice_id = ?', whereArgs: [id]);
    final items = itemRows.map<InvoiceItem>(InvoiceItem.fromMap).toList();
    return Invoice.fromMap(rows.first, items: items);
  }

  @override
  Future<int> insert(Invoice invoice, List<InvoiceItem> items) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await txn.insert('invoices', invoice.toMap());
      for (final item in items) {
        await txn.insert(
            'invoice_items', item.copyWith(invoiceId: id).toMap());
      }
      return id;
    });
  }

  @override
  Future<void> update(Invoice invoice, List<InvoiceItem> items) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
          'invoices',
          invoice.copyWith(updatedAt: DateTime.now()).toMap(),
          where: 'id = ?',
          whereArgs: [invoice.id]);
      await txn.delete('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoice.id]);
      for (final item in items) {
        await txn.insert(
            'invoice_items', item.copyWith(invoiceId: invoice.id!).toMap());
      }
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> recordPayment(int invoiceId, double amount) async {
    final db = await _db.database;
    final rows =
        await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    if (rows.isEmpty) return;
    final inv = Invoice.fromMap(rows.first);
    final newPaid = (inv.paidAmount + amount).clamp(0, inv.total);
    final newStatus = newPaid >= inv.total
        ? InvoiceStatus.paid.dbValue
        : InvoiceStatus.partiallyPaid.dbValue;
    
    final now = DateTime.now();
    await db.update(
      'invoices',
      {
        'paid_amount': newPaid,
        'status': newStatus,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );

    // Create income transaction in main ledger
    final transaction = Transaction(
      type: TransactionType.income,
      mode: TransactionMode.business,
      amount: amount,
      category: 'Invoice Payment',
      partyName: inv.customerName,
      partyId: inv.customerPartyId,
      notes: 'Payment for invoice ${inv.invoiceNo}',
      date: now,
      createdAt: now,
      updatedAt: now,
    );
    await _transactionRepo.insert(transaction);
  }
}
