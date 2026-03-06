import '../../data/models/invoice.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/invoice_repository.dart';

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
  Future<List<Quote>> getByCustomer(String customerName) async {
    final db = await _db.database;
    final rows = await db.query(
      'quotes',
      where: 'customer_name = ?',
      whereArgs: [customerName],
      orderBy: 'created_at DESC',
    );
    final List<Quote> result = [];
    for (final row in rows) {
      final id = row['id'] as int;
      final items = await _itemsForQuote(db, id);
      result.add(Quote.fromMap(row, items: items));
    }
    return result;
  }

  @override
  Future<void> markSent(int id) async {
    final db = await _db.database;
    await db.update(
      'quotes',
      {'status': QuoteStatus.sent.dbValue},
      where: 'id = ? AND status = ?',
      whereArgs: [id, QuoteStatus.draft.dbValue],
    );
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
  InvoiceRepositoryImpl();

  final _db = DatabaseHelper.instance;

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

  @override
  Future<List<Invoice>> getByCustomer(String customerName) async {
    final db = await _db.database;
    final rows = await db.query('invoices',
        where: 'customer_name = ?',
        whereArgs: [customerName],
        orderBy: 'issue_date DESC');
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
  Future<int> markAsPaid({
    required Invoice invoice,
    required PaymentMethod paymentMethod,
    required DateTime paidDate,
    double? partialAmount,
    int? bookingId,
  }) async {
    if (invoice.id == null) {
      throw ArgumentError('Invoice must have an ID to mark as paid');
    }

    final db = await _db.database;
    final amountToRecord =
        partialAmount ?? (invoice.total - invoice.paidAmount);

    if (amountToRecord <= 0) {
      throw ArgumentError('Payment amount must be greater than zero');
    }

    // Execute atomic update: invoice + transaction in one database transaction
    return await db.transaction((txn) async {
      // 1. Calculate new paid amount and status
      final newPaidAmount = invoice.paidAmount + amountToRecord;
      final isFullyPaid = newPaidAmount >= invoice.total;
      final newStatus = isFullyPaid
          ? InvoiceStatus.paid
          : InvoiceStatus.partiallyPaid;

      // 2. Update invoice
      await txn.update(
        'invoices',
        {
          'status': newStatus.dbValue,
          'paid_amount': newPaidAmount,
          'paid_at': isFullyPaid ? paidDate.toIso8601String() : invoice.paidAt?.toIso8601String(),
          'payment_method': paymentMethod.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invoice.id],
      );

      // 3. AUTO-CREATE TRANSACTION
      final transaction = Transaction(
        type: TransactionType.income,
        mode: TransactionMode.business,
        amount: amountToRecord,
        category: 'Business Income', // Default category for invoice payments
        partyName: invoice.customerName,
        partyId: invoice.customerPartyId,
        paymentMethod: paymentMethod,
        linkedInvoiceId: invoice.id,
        linkedBookingId: bookingId,
        businessId: invoice.businessId,
        date: paidDate,
        notes: partialAmount != null
            ? 'Partial payment (₹${amountToRecord.toStringAsFixed(0)}) - Invoice ${invoice.invoiceNo}'
            : 'Invoice ${invoice.invoiceNo}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final transactionId = await txn.insert('transactions', transaction.toMap());

      // Note: Booking remains in 'completed' status - invoice payment tracked separately
      
      return transactionId;
    });
  }

  @override
  Future<void> markReminderSent(int invoiceId) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {'reminder_sent_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  @override
  Future<void> markSent(int id) async {
    final db = await _db.database;
    // Only promote draft → sent; never demote paid/overdue/partiallyPaid.
    await db.update(
      'invoices',
      {'status': InvoiceStatus.sent.dbValue},
      where: 'id = ? AND status = ?',
      whereArgs: [id, InvoiceStatus.draft.dbValue],
    );
  }
}
