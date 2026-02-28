import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import '../../data/models/item_catalog.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/invoice_repository_impl.dart';
import '../../data/repositories/item_catalog_repository_impl.dart';
import '../../data/services/invoice_number_service.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../domain/repositories/item_catalog_repository.dart';

// ── Repository providers ─────────────────────────────────────────────────────

final itemCatalogRepositoryProvider = Provider<ItemCatalogRepository>(
  (_) => ItemCatalogRepositoryImpl(),
);

final quoteRepositoryProvider = Provider<QuoteRepository>(
  (_) => QuoteRepositoryImpl(),
);

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepositoryImpl(),
);

// ── Filter ───────────────────────────────────────────────────────────────────

/// null = show all
final invoiceFilterProvider = StateProvider<InvoiceStatus?>((_) => null);

/// Search query for filtering invoices by customer name or invoice number
final invoiceSearchQueryProvider = StateProvider<String>((_) => '');

/// Date range for filtering invoices (null = all dates)
final invoiceDateRangeProvider = StateProvider<DateTimeRange?>((_) => null);

// ── Item Catalog ─────────────────────────────────────────────────────────────

class CatalogNotifier
    extends StateNotifier<AsyncValue<List<ItemCatalog>>> {
  CatalogNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final ItemCatalogRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<void> add(ItemCatalog item) async {
    await _repo.insert(item);
    await load();
  }

  Future<void> edit(ItemCatalog item) async {
    await _repo.update(item);
    await load();
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }

  Future<void> trackUsage(int itemId) async {
    await _repo.trackUsage(itemId);
    // Refresh list to reflect updated sort order (recently used items move up)
    await load();
  }

  Future<String> generateNextSku(ItemCategory category) async {
    return _repo.generateNextSku(category);
  }
}

final catalogProvider =
    StateNotifierProvider<CatalogNotifier, AsyncValue<List<ItemCatalog>>>(
  (ref) => CatalogNotifier(ref.read(itemCatalogRepositoryProvider)),
);

// ── Quotes ───────────────────────────────────────────────────────────────────

class QuotesNotifier extends StateNotifier<AsyncValue<List<Quote>>> {
  QuotesNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final QuoteRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<int> add(Quote quote, List<QuoteItem> items) async {
    final id = await _repo.insert(quote, items);
    await load();
    return id;
  }

  Future<void> edit(Quote quote, List<QuoteItem> items) async {
    await _repo.update(quote, items);
    await load();
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }

  Future<Invoice?> convertToInvoice(int quoteId) async {
    final invoiceNo =
        await InvoiceNumberService.instance.nextInvoiceNo();
    final invoice = await _repo.convertToInvoice(quoteId, invoiceNo);
    await load();
    return invoice;
  }
}

final quotesProvider =
    StateNotifierProvider<QuotesNotifier, AsyncValue<List<Quote>>>(
  (ref) => QuotesNotifier(ref.read(quoteRepositoryProvider)),
);

// ── Invoices ─────────────────────────────────────────────────────────────────

class InvoicesNotifier extends StateNotifier<AsyncValue<List<Invoice>>> {
  InvoicesNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final InvoiceRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<int> add(Invoice invoice, List<InvoiceItem> items) async {
    final id = await _repo.insert(invoice, items);
    await load();
    return id;
  }

  Future<void> edit(Invoice invoice, List<InvoiceItem> items) async {
    await _repo.update(invoice, items);
    await load();
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }

  /// Mark invoice as paid and automatically create transaction.
  /// Returns the created transaction ID.
  Future<int> markAsPaid({
    required Invoice invoice,
    required PaymentMethod paymentMethod,
    required DateTime paidDate,
    double? partialAmount,
    int? bookingId,
  }) async {
    final transactionId = await _repo.markAsPaid(
      invoice: invoice,
      paymentMethod: paymentMethod,
      paidDate: paidDate,
      partialAmount: partialAmount,
      bookingId: bookingId,
    );
    await load(); // Refresh invoice list
    return transactionId;
  }

  /// Record that a manual reminder (WhatsApp/SMS/Email) was sent for [invoiceId].
  Future<void> markReminderSent(int invoiceId) async {
    await _repo.markReminderSent(invoiceId);
    await load();
  }
}

final invoicesProvider =
    StateNotifierProvider<InvoicesNotifier, AsyncValue<List<Invoice>>>(
  (ref) => InvoicesNotifier(ref.read(invoiceRepositoryProvider)),
);

/// Filtered view of invoices
final filteredInvoicesProvider = Provider<AsyncValue<List<Invoice>>>((ref) {
  final all = ref.watch(invoicesProvider);
  final statusFilter = ref.watch(invoiceFilterProvider);
  final searchQuery = ref.watch(invoiceSearchQueryProvider);
  final dateRange = ref.watch(invoiceDateRangeProvider);

  return all.whenData((list) {
    var filtered = list;

    // Apply status filter
    if (statusFilter != null) {
      filtered = filtered.where((inv) => inv.status == statusFilter).toList();
    }

    // Apply search filter (customer name or invoice number)
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((inv) {
        return inv.customerName.toLowerCase().contains(query) ||
            inv.invoiceNo.toLowerCase().contains(query);
      }).toList();
    }

    // Apply date range filter
    if (dateRange != null) {
      filtered = filtered.where((inv) {
        final invDate = inv.issueDate;
        return invDate.isAfter(dateRange.start.subtract(const Duration(days: 1))) &&
            invDate.isBefore(dateRange.end.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  });
});

/// Single invoice by id
final invoiceByIdProvider =
    FutureProvider.family<Invoice?, int>((ref, id) async {
  return ref.read(invoiceRepositoryProvider).getById(id);
});

/// Filtered view of quotes (search + date range)
final filteredQuotesProvider = Provider<AsyncValue<List<Quote>>>((ref) {
  final all = ref.watch(quotesProvider);
  final searchQuery = ref.watch(invoiceSearchQueryProvider);
  final dateRange = ref.watch(invoiceDateRangeProvider);

  return all.whenData((list) {
    var filtered = list;

    // Apply search filter (customer name or quote number)
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((quote) {
        return quote.customerName.toLowerCase().contains(query) ||
            quote.quoteNo.toLowerCase().contains(query);
      }).toList();
    }

    // Apply date range filter (using createdAt for quotes)
    if (dateRange != null) {
      filtered = filtered.where((quote) {
        final quoteDate = quote.createdAt;
        return quoteDate.isAfter(dateRange.start.subtract(const Duration(days: 1))) &&
            quoteDate.isBefore(dateRange.end.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  });
});

/// Single quote by id
final quoteByIdProvider =
    FutureProvider.family<Quote?, int>((ref, id) async {
  return ref.read(quoteRepositoryProvider).getById(id);
});

// ---------------------------------------------------------------------------
// Overdue invoices summary (for home screen alert)
// ---------------------------------------------------------------------------

/// A lightweight record of overdue invoice count and total amount due.
typedef OverdueInvoicesSummary = ({int count, double totalDue});

/// Derives count + total pending from unpaid invoices (overdue or sent).
/// Returns null when invoices haven't loaded yet.
final overdueInvoicesSummaryProvider =
    Provider<OverdueInvoicesSummary?>((ref) {
  final all = ref.watch(invoicesProvider);
  return all.whenOrNull(data: (list) {
    final unpaid = list.where((inv) =>
        inv.status == InvoiceStatus.overdue ||
        inv.status == InvoiceStatus.sent ||
        inv.status == InvoiceStatus.partiallyPaid).toList();
    if (unpaid.isEmpty) return (count: 0, totalDue: 0.0);
    final totalDue = unpaid.fold(0.0, (sum, inv) => sum + inv.balanceDue);
    return (count: unpaid.length, totalDue: totalDue);
  });
});
