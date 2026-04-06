import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/product_group.dart';
import '../../data/repositories/product_group_repository_impl.dart';
import '../../domain/repositories/product_group_repository.dart';
import 'context_provider.dart';

// ── Repository Provider ──────────────────────────────────────────────────────

final productGroupRepositoryProvider = Provider<ProductGroupRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return ProductGroupRepositoryImpl(contextId: contextId);
  },
);

// ── State Notifier ───────────────────────────────────────────────────────────

/// Manages all product groups in the catalog.
class ProductGroupsNotifier extends StateNotifier<AsyncValue<List<ProductGroup>>> {
  ProductGroupsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final ProductGroupRepository _repo;

  /// Loads all product groups.
  Future<void> load() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() => _repo.getAll());
    if (mounted) state = next;
  }

  /// Creates a new product group.
  Future<void> add(ProductGroup group) async {
    await _repo.insert(group);
    await load();
  }

  /// Updates an existing product group.
  Future<void> edit(ProductGroup group) async {
    await _repo.update(group);
    await load();
  }

  /// Soft-deletes a product group.
  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final productGroupsProvider = StateNotifierProvider<ProductGroupsNotifier, AsyncValue<List<ProductGroup>>>(
  (ref) {
    final repo = ref.watch(productGroupRepositoryProvider);
    return ProductGroupsNotifier(repo);
  },
);
