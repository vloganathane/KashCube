import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import '../../data/models/item_catalog.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/invoice_repository_impl.dart';
import '../../data/repositories/item_catalog_repository_impl.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/invoice_number_service.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../domain/repositories/item_catalog_repository.dart';
import 'business_provider.dart';
import 'context_provider.dart';

// ── Repository providers ─────────────────────────────────────────────────────

final itemCatalogRepositoryProvider = Provider<ItemCatalogRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return ItemCatalogRepositoryImpl(contextId: contextId);
  },
);

final quoteRepositoryProvider = Provider<QuoteRepository>(
  (_) => QuoteRepositoryImpl(),
);

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return InvoiceRepositoryImpl(contextId: contextId);
  },
);

// ── Filter ───────────────────────────────────────────────────────────────────

/// null = show all statuses
final invoiceFilterProvider = StateProvider<InvoiceStatus?>((_) => null);

/// null = show all types (Tax Invoice, Bill of Supply, Credit Note, Debit Note).
/// Set to [InvoiceType.creditNote] or [InvoiceType.debitNote] to narrow the list.
final invoiceTypeFilterProvider = StateProvider<InvoiceType?>((_) => null);

/// Search query for filtering invoices by customer name or invoice number
final invoiceSearchQueryProvider = StateProvider<String>((_) => '');

/// Date range for filtering invoices (null = all dates)
final invoiceDateRangeProvider = StateProvider<DateTimeRange?>((_) => null);

// ── Item Catalog ─────────────────────────────────────────────────────────────

class CatalogNotifier
    extends StateNotifier<AsyncValue<List<ItemCatalog>>> {
  CatalogNotifier(this._repo, this._businessId)
      : super(const AsyncValue.loading()) {
    load();
  }

  final ItemCatalogRepository _repo;
  final int? _businessId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.getAll(businessId: _businessId),
    );
  }

  Future<void> add(ItemCatalog item) async {
    await _repo.insert(item, activeBusinessId: _businessId);
    await load();
  }

  Future<void> edit(ItemCatalog item) async {
    await _repo.update(item, activeBusinessId: _businessId);
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
  (ref) {
    final businessId = ref.watch(activeBusinessProvider)?.id;
    return CatalogNotifier(ref.read(itemCatalogRepositoryProvider), businessId);
  },
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

  /// Promote a draft quote to [QuoteStatus.sent] after the user has confirmed
  /// sharing the PDF. No-op for quotes already past draft.
  Future<void> markSent(int id) async {
    await _repo.markSent(id);
    await load();
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
    // Reverse any stock movements before deleting so inventory stays accurate.
    await InventoryService.instance.reverseMovementsFor('invoice', id);
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

  /// Promote a draft invoice to [InvoiceStatus.sent] after the user has
  /// confirmed sharing the PDF. No-op for paid/overdue/partiallyPaid invoices.
  ///
  /// Deducts stock for catalog-linked items only when there is no linked DC
  /// (if a DC already existed the stock was deducted at DC save time).
  Future<void> markSent(int id) async {
    final invoice = await _repo.getById(id);
    if (invoice != null && invoice.challanId == null) {
      for (final item in invoice.items) {
        if (item.catalogItemId != null && item.qty > 0) {
          await InventoryService.instance.deductStock(
            item.catalogItemId!,
            item.qty,
            notes: 'Invoice ${invoice.invoiceNo}',
            referenceId: id,
            referenceType: 'invoice',
            businessId: invoice.businessId,
          );
        }
      }
    }
    await _repo.markSent(id);
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
  final typeFilter  = ref.watch(invoiceTypeFilterProvider);
  final searchQuery = ref.watch(invoiceSearchQueryProvider);
  final dateRange   = ref.watch(invoiceDateRangeProvider);

  return all.whenData((list) {
    var filtered = list;

    // Apply status filter
    if (statusFilter != null) {
      filtered = filtered.where((inv) => inv.status == statusFilter).toList();
    }

    // Apply invoice-type filter (Credit Note / Debit Note)
    if (typeFilter != null) {
      filtered = filtered.where((inv) => inv.invoiceType == typeFilter).toList();
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

/// Finds a Quote from the in-memory list by its ID.
/// Used by InvoiceDetailScreen to show the source quote card synchronously.
final quoteFromListByIdProvider = Provider.family<Quote?, int>((ref, id) {
  final all =
      ref.watch(quotesProvider).whenOrNull(data: (list) => list) ?? [];
  try {
    return all.firstWhere((q) => q.id == id);
  } catch (_) {
    return null;
  }
});

/// Finds the Invoice that was converted from a given Quote.
/// Used by QuoteDetailScreen to show the linked invoice card synchronously.
final invoiceByQuoteIdProvider = Provider.family<Invoice?, int>((ref, quoteId) {
  final all =
      ref.watch(invoicesProvider).whenOrNull(data: (list) => list) ?? [];
  try {
    return all.firstWhere((inv) => inv.quoteId == quoteId);
  } catch (_) {
    return null;
  }
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

/// All quotes for a given party name (used by Party Document Ledger).
final quotesByCustomerProvider =
    FutureProvider.family<List<Quote>, String>((ref, customerName) async {
  return ref.read(quoteRepositoryProvider).getByCustomer(customerName);
});
