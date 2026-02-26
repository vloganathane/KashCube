import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import '../../data/models/item_catalog.dart';
import '../../data/models/quote.dart';
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
  (_) => InvoiceRepositoryImpl(),
);

// ── Filter ───────────────────────────────────────────────────────────────────

/// null = show all
final invoiceFilterProvider = StateProvider<InvoiceStatus?>((_) => null);

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

  Future<void> recordPayment(int invoiceId, double amount) async {
    await _repo.recordPayment(invoiceId, amount);
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
  final filter = ref.watch(invoiceFilterProvider);
  if (filter == null) return all;
  return all.whenData(
    (list) => list.where((inv) => inv.status == filter).toList(),
  );
});

/// Single invoice by id
final invoiceByIdProvider =
    FutureProvider.family<Invoice?, int>((ref, id) async {
  return ref.read(invoiceRepositoryProvider).getById(id);
});

/// Single quote by id
final quoteByIdProvider =
    FutureProvider.family<Quote?, int>((ref, id) async {
  return ref.read(quoteRepositoryProvider).getById(id);
});
