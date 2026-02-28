import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Tracks which month the reports screen is displaying.
final reportMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Tracks which mode filter is active: null = All, 'personal', 'business', 'investment'.
final reportModeProvider = StateProvider<String?>((ref) => null);

/// Monthly P&L summary for the selected month.
class MonthlyPnL {
  final double totalIncome;
  final double totalExpense;
  final double netProfitLoss;
  final Map<String, double> incomeByCat;
  final Map<String, double> expenseByCat;
  final List<PartyTotal> topParties;
  final double totalInvested;
  final double totalRedeemed;
  final List<Transaction> largestTransactions;

  const MonthlyPnL({
    this.totalIncome = 0,
    this.totalExpense = 0,
    this.netProfitLoss = 0,
    this.incomeByCat = const {},
    this.expenseByCat = const {},
    this.topParties = const [],
    this.totalInvested = 0,
    this.totalRedeemed = 0,
    this.largestTransactions = const [],
  });

  /// Savings rate: (income − expense) / income, clamped 0–1.
  double get savingsRate =>
      totalIncome > 0
          ? ((totalIncome - totalExpense) / totalIncome).clamp(0.0, 1.0)
          : 0.0;
}

/// Provider for monthly P&L report.
final monthlyPnLProvider =
    StateNotifierProvider<MonthlyPnLNotifier, AsyncValue<MonthlyPnL>>(
  (ref) {
    final month = ref.watch(reportMonthProvider);
    final mode = ref.watch(reportModeProvider);
    return MonthlyPnLNotifier(TransactionRepositoryImpl(), month, mode);
  },
);

class MonthlyPnLNotifier extends StateNotifier<AsyncValue<MonthlyPnL>> {
  final TransactionRepository _repo;
  final DateTime _month;
  final String? _mode;

  MonthlyPnLNotifier(this._repo, this._month, this._mode)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);

      final results = await Future.wait([
        _repo.getTotalIncome(start, end, mode: _mode),
        _repo.getTotalExpense(start, end, mode: _mode),
        _repo.getIncomeByCategorySummary(start, end, mode: _mode),
        _repo.getExpenseByCategorySummary(start, end, mode: _mode),
        _repo.getTopParties(start, end, mode: _mode),
        _repo.getTotalInvested(start, end),
        _repo.getTotalRedeemed(start, end),
        _repo.getTopByAmount(start, end, limit: 5),
      ]);

      final income = results[0] as double;
      final expense = results[1] as double;
      final incomeCat = results[2] as Map<String, double>;
      final expenseCat = results[3] as Map<String, double>;
      final topParties = results[4] as List<PartyTotal>;
      final invested = results[5] as double;
      final redeemed = results[6] as double;
      final largest = results[7] as List<Transaction>;

      state = AsyncValue.data(MonthlyPnL(
        totalIncome: income,
        totalExpense: expense,
        netProfitLoss: income - expense,
        incomeByCat: incomeCat,
        expenseByCat: expenseCat,
        topParties: topParties,
        totalInvested: invested,
        totalRedeemed: redeemed,
        largestTransactions: largest,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Lightweight income+expense total for any arbitrary [month].
/// Used by the Reports screen to show month-over-month deltas.
final pnlForMonthProvider =
    FutureProvider.family<MonthlyPnL, DateTime>((ref, month) async {
  final mode = ref.watch(reportModeProvider);
  final repo = TransactionRepositoryImpl();
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
  final results = await Future.wait([
    repo.getTotalIncome(start, end, mode: mode),
    repo.getTotalExpense(start, end, mode: mode),
  ]);
  final income = results[0];
  final expense = results[1];
  return MonthlyPnL(
    totalIncome: income,
    totalExpense: expense,
    netProfitLoss: income - expense,
  );
});

/// Monthly income+expense totals grouped by payment method for [month].
final paymentMethodSplitProvider = FutureProvider.family<
    Map<String, ({double income, double expense})>, DateTime>((ref, month) async {
  final mode = ref.watch(reportModeProvider);
  final repo = TransactionRepositoryImpl();
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
  return repo.getByPaymentMethod(start, end, mode: mode);
});

/// Year-to-date summary from Jan 1 of [month]'s year through end of [month].
final ytdSummaryProvider =
    FutureProvider.family<MonthlyPnL, DateTime>((ref, month) async {
  final mode = ref.watch(reportModeProvider);
  final repo = TransactionRepositoryImpl();
  final start = DateTime(month.year, 1, 1);
  final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
  final results = await Future.wait([
    repo.getTotalIncome(start, end, mode: mode),
    repo.getTotalExpense(start, end, mode: mode),
  ]);
  final income = results[0];
  final expense = results[1];
  return MonthlyPnL(
    totalIncome: income,
    totalExpense: expense,
    netProfitLoss: income - expense,
  );
});

/// Monthly totals for the trend chart (last 6 months).
final monthlyTotalsProvider =
    StateNotifierProvider<MonthlyTotalsNotifier, AsyncValue<List<MonthlyTotal>>>(
  (ref) {
    final mode = ref.watch(reportModeProvider);
    return MonthlyTotalsNotifier(TransactionRepositoryImpl(), mode);
  },
);

class MonthlyTotalsNotifier
    extends StateNotifier<AsyncValue<List<MonthlyTotal>>> {
  final TransactionRepository _repo;
  final String? _mode;

  MonthlyTotalsNotifier(this._repo, this._mode) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final totals = await _repo.getMonthlyTotals(months: 6, mode: _mode);
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
    final mode = ref.watch(reportModeProvider);
    return DailyTotalsNotifier(TransactionRepositoryImpl(), month, mode);
  },
);

class DailyTotalsNotifier extends StateNotifier<AsyncValue<List<DailyTotal>>> {
  final TransactionRepository _repo;
  final DateTime _month;
  final String? _mode;

  DailyTotalsNotifier(this._repo, this._month, this._mode)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final start = DateTime(_month.year, _month.month, 1);
      final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
      final totals = await _repo.getDailyTotals(start, end, mode: _mode);
      state = AsyncValue.data(totals);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
