import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/budget.dart';
import '../../data/repositories/budget_repository_impl.dart';
import '../../domain/repositories/budget_repository.dart';
import 'report_provider.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (_) => BudgetRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// Budgets for a specific month — family provider
// ---------------------------------------------------------------------------

/// Holds the list of budgets for a given (year, month) key.
class BudgetsNotifier extends StateNotifier<AsyncValue<List<Budget>>> {
  BudgetsNotifier(this._repo, this._year, this._month)
    : super(const AsyncValue.loading()) {
    load();
  }

  final BudgetRepository _repo;
  final int _year;
  final int _month;

  Future<void> load() async {
    try {
      final list = await _repo.getBudgetsForMonth(_year, _month);
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upsert(Budget budget) async {
    await _repo.upsert(budget);
    await load();
  }

  Future<void> delete(int id) async {
    await _repo.delete(id);
    await load();
  }

  /// Copies budgets from the previous month for any category that doesn't
  /// yet have a budget in the current month.  Returns the number of budgets
  /// copied (0 if everything was already set up).
  Future<int> copyFromPreviousMonth() async {
    // Determine previous month
    final prevYear = _month == 1 ? _year - 1 : _year;
    final prevMonth = _month == 1 ? 12 : _month - 1;

    final prevBudgets = await _repo.getBudgetsForMonth(prevYear, prevMonth);
    if (prevBudgets.isEmpty) return 0;

    final existing = state.valueOrNull ?? [];
    final existingCategories = existing.map((b) => b.category).toSet();

    final toCopy = prevBudgets
        .where((b) => !existingCategories.contains(b.category))
        .toList();

    for (final prev in toCopy) {
      await _repo.upsert(
        Budget(
          year: _year,
          month: _month,
          category: prev.category,
          budgetAmount: prev.budgetAmount,
          alertAtPercentage: prev.alertAtPercentage,
          createdAt: DateTime.now(),
        ),
      );
    }

    if (toCopy.isNotEmpty) await load();
    return toCopy.length;
  }
}

/// Parameter-based provider keyed on (year, month).
final budgetsForMonthProvider =
    StateNotifierProvider.family<
      BudgetsNotifier,
      AsyncValue<List<Budget>>,
      ({int year, int month})
    >(
      (ref, key) => BudgetsNotifier(
        ref.read(budgetRepositoryProvider),
        key.year,
        key.month,
      ),
    );

/// Convenience provider that watches the reportMonth so budget section in
/// Reports automatically re-renders when the user changes the month.
final currentMonthBudgetsProvider =
    StateNotifierProvider<BudgetsNotifier, AsyncValue<List<Budget>>>((ref) {
      final month = ref.watch(reportMonthProvider);
      return BudgetsNotifier(
        ref.read(budgetRepositoryProvider),
        month.year,
        month.month,
      );
    });
