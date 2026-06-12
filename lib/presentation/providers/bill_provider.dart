import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bill_attachment.dart';
import '../../data/repositories/bill_repository_impl.dart';
import '../../data/services/bill_storage_service.dart';
import '../../domain/repositories/bill_repository.dart';

/// Provider for the bill repository instance.
final billRepositoryProvider = Provider<BillRepository>(
  (ref) => BillRepositoryImpl(),
);

/// Provider for the bill storage service.
final billStorageProvider = Provider<BillStorageService>(
  (ref) => BillStorageService.instance,
);

/// Provider that fetches a bill attachment for a given transaction ID.
///
/// Usage: `ref.watch(billForTransactionProvider(txnId))`
final billForTransactionProvider = FutureProvider.family<BillAttachment?, int>((
  ref,
  transactionId,
) {
  final repo = ref.read(billRepositoryProvider);
  return repo.getByTransactionId(transactionId);
});

/// Notifier for managing bill attachment operations.
class BillNotifier extends StateNotifier<AsyncValue<BillAttachment?>> {
  final BillRepository _repository;
  final BillStorageService _storage;
  final int transactionId;

  BillNotifier({
    required BillRepository repository,
    required BillStorageService storage,
    required this.transactionId,
  }) : _repository = repository,
       _storage = storage,
       super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final bill = await _repository.getByTransactionId(transactionId);
      state = AsyncValue.data(bill);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Save a new bill attachment (replaces existing if any).
  Future<void> saveBill({
    required String sourcePath,
    required String originalFileName,
  }) async {
    try {
      // Delete existing bill if present
      final existing = state.valueOrNull;
      if (existing != null) {
        await _storage.deleteFile(existing.filePath);
        await _repository.deleteByTransactionId(transactionId);
      }

      // Store file and create record
      final bill = await _storage.saveFile(
        transactionId: transactionId,
        sourcePath: sourcePath,
        originalFileName: originalFileName,
      );

      final id = await _repository.insert(bill);
      state = AsyncValue.data(bill.copyWith(id: id));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Remove the bill attachment.
  Future<void> removeBill() async {
    try {
      final existing = state.valueOrNull;
      if (existing != null) {
        await _storage.deleteFile(existing.filePath);
        await _repository.deleteByTransactionId(transactionId);
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refresh the bill data from database.
  Future<void> refresh() => _load();
}

/// Provider for a bill notifier scoped to a specific transaction ID.
///
/// Usage: `ref.watch(billNotifierProvider(txnId))`
final billNotifierProvider =
    StateNotifierProvider.family<
      BillNotifier,
      AsyncValue<BillAttachment?>,
      int
    >(
      (ref, transactionId) => BillNotifier(
        repository: ref.read(billRepositoryProvider),
        storage: ref.read(billStorageProvider),
        transactionId: transactionId,
      ),
    );
