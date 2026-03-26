import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'context_provider.dart';

/// Provider for the transaction repository instance.
/// Rebuilds automatically when [activeContextProvider] changes.
final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) {
    final contextId = ref.watch(activeContextProvider);
    return TransactionRepositoryImpl(contextId: contextId);
  },
);

/// Provider for the transaction list state.
final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, AsyncValue<List<Transaction>>>(
  (ref) => TransactionsNotifier(ref.watch(transactionRepositoryProvider)),
);

/// Provider for recent transactions (home screen).
final recentTransactionsProvider =
    StateNotifierProvider<RecentTransactionsNotifier, AsyncValue<List<Transaction>>>(
  (ref) => RecentTransactionsNotifier(ref.watch(transactionRepositoryProvider)),
);

/// Manages the full transaction list state.
class TransactionsNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final TransactionRepository _repository;

  TransactionsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    try {
      final transactions = await _repository.getAll();
      if (!mounted) return;
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<int> addTransaction(Transaction transaction) async {
    try {
      final id = await _repository.insert(transaction);
      await loadTransactions();
      return id;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
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

// ---------------------------------------------------------------------------
// Ledger providers
// ---------------------------------------------------------------------------

/// Party-level ledger summaries (lent / borrowed / invested grouped by party).
final ledgerSummariesProvider =
    StateNotifierProvider<LedgerSummariesNotifier, AsyncValue<List<LedgerPartyEntry>>>(
  (ref) => LedgerSummariesNotifier(ref.read(transactionRepositoryProvider)),
);

/// Total outstanding lent amount (lent - received_back).
final totalOutstandingLentProvider = FutureProvider<double>((ref) async {
  // Re-derive whenever ledger summaries reload.
  ref.watch(ledgerSummariesProvider);
  return ref.read(transactionRepositoryProvider).getTotalOutstandingLent();
});

/// Total outstanding borrowed amount (borrowed - paid_back).
final totalOutstandingBorrowedProvider = FutureProvider<double>((ref) async {
  ref.watch(ledgerSummariesProvider);
  return ref.read(transactionRepositoryProvider).getTotalOutstandingBorrowed();
});

/// Transactions for a single party (detail drill-down).
final partyTransactionsProvider =
    StateNotifierProvider.family<PartyTransactionsNotifier, AsyncValue<List<Transaction>>, String>(
  (ref, partyName) => PartyTransactionsNotifier(
    ref.read(transactionRepositoryProvider),
    partyName,
  ),
);

class LedgerSummariesNotifier extends StateNotifier<AsyncValue<List<LedgerPartyEntry>>> {
  final TransactionRepository _repository;

  LedgerSummariesNotifier(this._repository) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final entries = await _repository.getPartyLedgerSummaries();
      state = AsyncValue.data(entries);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
}

class PartyTransactionsNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final TransactionRepository _repository;
  final String _partyName;

  PartyTransactionsNotifier(this._repository, this._partyName)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final txns = await _repository.getTransactionsByParty(_partyName);
      state = AsyncValue.data(txns);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
