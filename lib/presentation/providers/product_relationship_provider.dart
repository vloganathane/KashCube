import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/product_relationship.dart';
import '../../data/repositories/product_relationship_repository_impl.dart';
import '../../domain/repositories/product_relationship_repository.dart';
import 'context_provider.dart';

// ── Repository Provider ──────────────────────────────────────────────────────

final productRelationshipRepositoryProvider =
    Provider<ProductRelationshipRepository>((ref) {
      final contextId = ref.watch(activeContextProvider);
      return ProductRelationshipRepositoryImpl(contextId: contextId);
    });

// ── State Notifier ───────────────────────────────────────────────────────────

/// Manages product relationships for a specific product.
/// Watches relationships where this product is the source.
class ProductRelationshipsNotifier
    extends StateNotifier<AsyncValue<List<ProductRelationship>>> {
  ProductRelationshipsNotifier(this._repo, this._productId)
    : super(const AsyncValue.loading()) {
    load();
  }

  final ProductRelationshipRepository _repo;
  final int _productId;

  /// Loads all relationships for [_productId].
  Future<void> load() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(
      () => _repo.getAllForProduct(_productId),
    );
    if (mounted) state = next;
  }

  /// Adds a new relationship.
  Future<void> add({
    required int relatedProductId,
    required ProductRelationshipType type,
  }) async {
    final relationship = ProductRelationship(
      productId: _productId,
      relatedProductId: relatedProductId,
      relationshipType: type,
      createdAt: DateTime.now(),
    );
    await _repo.insert(relationship);
    await load();
  }

  /// Removes a relationship by ID.
  Future<void> remove(int relationshipId) async {
    await _repo.delete(relationshipId);
    await load();
  }

  /// Updates the relationship type.
  Future<void> updateType(
    int relationshipId,
    ProductRelationshipType newType,
  ) async {
    final existing = state.value?.firstWhere((r) => r.id == relationshipId);
    if (existing == null) return;

    final updated = existing.copyWith(relationshipType: newType);
    await _repo.update(updated);
    await load();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Family provider that yields relationships for a specific product ID.
final productRelationshipsProvider =
    StateNotifierProvider.family<
      ProductRelationshipsNotifier,
      AsyncValue<List<ProductRelationship>>,
      int
    >((ref, productId) {
      final repo = ref.watch(productRelationshipRepositoryProvider);
      return ProductRelationshipsNotifier(repo, productId);
    });
