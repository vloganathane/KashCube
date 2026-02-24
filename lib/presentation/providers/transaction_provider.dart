import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Provider for the transaction repository instance.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepositoryImpl(),
);

/// Provider for the transaction list state.
final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, AsyncValue<List<Transaction>>>(
  (ref) => TransactionsNotifier(ref.read(transactionRepositoryProvider)),
);

/// Provider for recent transactions (home screen).
final recentTransactionsProvider =
    StateNotifierProvider<RecentTransactionsNotifier, AsyncValue<List<Transaction>>>(
  (ref) => RecentTransactionsNotifier(ref.read(transactionRepositoryProvider)),
);

/// Manages the full transaction list state.
class TransactionsNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final TransactionRepository _repository;

  TransactionsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    state = const AsyncValue.loading();
    try {
      final transactions = await _repository.getAll();
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addTransaction(Transaction transaction) async {
    try {
      await _repository.insert(transaction);
      await loadTransactions();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      await _repository.update(transaction);
      await loadTransactions();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteTransaction(int id) async {
    try {
      await _repository.delete(id);
      await loadTransactions();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<List<Transaction>> search(String query) async {
    return _repository.search(query);
  }
}

/// Manages recent transactions for the home screen.
class RecentTransactionsNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final TransactionRepository _repository;

  RecentTransactionsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadRecent();
  }

  Future<void> loadRecent() async {
    try {
      final transactions = await _repository.getRecent(limit: 10);
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
