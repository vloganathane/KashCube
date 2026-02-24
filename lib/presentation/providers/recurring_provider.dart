import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/recurring_transaction.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/recurring_transaction_repository_impl.dart';
import '../../domain/repositories/recurring_transaction_repository.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final recurringTransactionRepositoryProvider =
    Provider<RecurringTransactionRepository>(
  (_) => RecurringTransactionRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// All recurring transactions (active + inactive).
final recurringTransactionsProvider = StateNotifierProvider<
    RecurringTransactionsNotifier,
    AsyncValue<List<RecurringTransaction>>>(
  (ref) => RecurringTransactionsNotifier(
    ref.read(recurringTransactionRepositoryProvider),
  ),
);

class RecurringTransactionsNotifier
    extends StateNotifier<AsyncValue<List<RecurringTransaction>>> {
  final RecurringTransactionRepository _repository;

  RecurringTransactionsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _repository.getAll();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(RecurringTransaction recurring) async {
    try {
      await _repository.insert(recurring);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(RecurringTransaction recurring) async {
    try {
      await _repository.update(recurring);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> remove(int id) async {
    try {
      await _repository.delete(id);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggleActive(int id, bool isActive) async {
    try {
      await _repository.toggleActive(id, isActive);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ---------------------------------------------------------------------------
// Auto-generation service
// ---------------------------------------------------------------------------

/// Processes due recurring transactions and creates actual transactions.
///
/// Should be called on app startup (e.g. from AppShell.initState).
Future<int> processDueRecurringTransactions(WidgetRef ref) async {
  final recurringRepo = ref.read(recurringTransactionRepositoryProvider);
  final transactionRepo = ref.read(transactionRepositoryProvider);

  final dueItems = await recurringRepo.getDue();
  var generated = 0;

  for (final item in dueItems) {
    try {
      // Create a transaction from the template
      final transaction = Transaction(
        amount: item.amount,
        date: item.nextDate,
        type: item.type == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        category: item.category,
        partyName: item.partyName,
        paymentMethod: item.paymentMethod != null
            ? PaymentMethod.fromDb(item.paymentMethod!)
            : PaymentMethod.cash,
        notes: '${item.notes ?? ''} [Auto: ${item.frequency.label}]'.trim(),
        autoDetected: false,
      );

      await transactionRepo.insert(transaction);

      // Advance to next occurrence
      final nextDate = item.frequency.nextOccurrence(item.nextDate);
      await recurringRepo.update(
        item.copyWith(
          nextDate: nextDate,
          lastGenerated: DateTime.now(),
        ),
      );

      generated++;
    } catch (e) {
      debugPrint('Failed to generate recurring txn ${item.id}: $e');
    }
  }

  if (generated > 0) {
    debugPrint('Generated $generated recurring transactions');
    // Refresh transaction list
    ref.invalidate(transactionsProvider);
  }

  return generated;
}
