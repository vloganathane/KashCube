import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Tracks which month the reports screen is displaying.
final reportMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Monthly P&L summary for the selected month.
class MonthlyPnL {
  final double totalIncome;
  final double totalExpense;
  final double netProfitLoss;
  final Map<String, double> incomeByCat;
  final Map<String, double> expenseByCat;
  final List<PartyTotal> topParties;

  const MonthlyPnL({
    this.totalIncome = 0,
    this.totalExpense = 0,
    this.netProfitLoss = 0,
    this.incomeByCat = const {},
    this.expenseByCat = const {},
    this.topParties = const [],
  });
}

/// Provider for monthly P&L report.
final monthlyPnLProvider =
    StateNotifierProvider<MonthlyPnLNotifier, AsyncValue<MonthlyPnL>>(
  (ref) {
    final month = ref.watch(reportMonthProvider);
    return MonthlyPnLNotifier(TransactionRepositoryImpl(), month);
  },
);

class MonthlyPnLNotifier extends StateNotifier<AsyncValue<MonthlyPnL>> {
  final TransactionRepository _repo;
  final DateTime _month;

  MonthlyPnLNotifier(this._repo, this._month)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);

      final results = await Future.wait([
        _repo.getTotalIncome(start, end),
        _repo.getTotalExpense(start, end),
        _repo.getIncomeByCategorySummary(start, end),
        _repo.getExpenseByCategorySummary(start, end),
        _repo.getTopParties(start, end),
      ]);

      final income = results[0] as double;
      final expense = results[1] as double;
      final incomeCat = results[2] as Map<String, double>;
      final expenseCat = results[3] as Map<String, double>;
      final topParties = results[4] as List<PartyTotal>;

      state = AsyncValue.data(MonthlyPnL(
        totalIncome: income,
        totalExpense: expense,
        netProfitLoss: income - expense,
        incomeByCat: incomeCat,
        expenseByCat: expenseCat,
        topParties: topParties,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Monthly totals for the trend chart (last 6 months).
final monthlyTotalsProvider =
    StateNotifierProvider<MonthlyTotalsNotifier, AsyncValue<List<MonthlyTotal>>>(
  (ref) => MonthlyTotalsNotifier(TransactionRepositoryImpl()),
);

class MonthlyTotalsNotifier
    extends StateNotifier<AsyncValue<List<MonthlyTotal>>> {
  final TransactionRepository _repo;

  MonthlyTotalsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final totals = await _repo.getMonthlyTotals(months: 6);
      state = AsyncValue.data(totals);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Daily totals for the selected month (for line/bar chart).
final dailyTotalsProvider =
    StateNotifierProvider<DailyTotalsNotifier, AsyncValue<List<DailyTotal>>>(
  (ref) {
    final month = ref.watch(reportMonthProvider);
    return DailyTotalsNotifier(TransactionRepositoryImpl(), month);
  },
);

class DailyTotalsNotifier extends StateNotifier<AsyncValue<List<DailyTotal>>> {
  final TransactionRepository _repo;
  final DateTime _month;

  DailyTotalsNotifier(this._repo, this._month)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
      final totals = await _repo.getDailyTotals(start, end);
      state = AsyncValue.data(totals);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
