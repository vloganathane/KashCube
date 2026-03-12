import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../data/services/fiscal_year_service.dart';
import 'context_provider.dart';
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
    final contextId = ref.watch(activeContextProvider);
    return MonthlyPnLNotifier(TransactionRepositoryImpl(contextId: contextId), month, mode);
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
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
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
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
  return repo.getByPaymentMethod(start, end, mode: mode);
});

/// Transactions for a specific [category] within [month].
/// Key is a record (String category, int year, int month).
final categoryTransactionsProvider = FutureProvider.family<
    List<Transaction>, ({String category, int year, int month})>((ref, key) async {
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
  final start = DateTime(key.year, key.month, 1);
  final end = DateTime(key.year, key.month + 1, 0, 23, 59, 59);
  return repo.getByCategoryInRange(key.category, start, end);
});

/// Year-to-date summary from Jan 1 of [month]'s year through end of [month].
final ytdSummaryProvider =
    FutureProvider.family<MonthlyPnL, DateTime>((ref, month) async {
  final mode = ref.watch(reportModeProvider);
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
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
    final contextId = ref.watch(activeContextProvider);
    return MonthlyTotalsNotifier(TransactionRepositoryImpl(contextId: contextId), mode);
  },
);

/// Monthly totals for the trend chart with a configurable count (6 or 12).
final monthlyTotalsForCountProvider =
    FutureProvider.family<List<MonthlyTotal>, int>((ref, count) async {
  final mode = ref.watch(reportModeProvider);
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
  return repo.getMonthlyTotals(months: count, mode: mode);
});

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
    final contextId = ref.watch(activeContextProvider);
    return DailyTotalsNotifier(TransactionRepositoryImpl(contextId: contextId), month, mode);
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

// ── Fiscal Year Period Filter ────────────────────────────────────────────────────

/// Active period mode for the Reports screen.
/// 'this_fy'  — full current fiscal year (default)
/// 'last_fy'  — full previous fiscal year
/// 'month'    — individual calendar month (legacy monthly view)
final reportPeriodModeProvider = StateProvider<String>((ref) => 'this_fy');

/// Resolved (start, end) date range for the active report period.
final reportActiveDateRangeProvider =
    FutureProvider<({DateTime start, DateTime end})>((ref) async {
  final periodMode = ref.watch(reportPeriodModeProvider);
  final month = ref.watch(reportMonthProvider);
  switch (periodMode) {
    case 'this_fy':
      final fy = await FiscalYearService.instance.currentFiscalYear;
      return (
        start: fy.start,
        end: DateTime(fy.end.year, fy.end.month, fy.end.day, 23, 59, 59),
      );
    case 'last_fy':
      final currentFy = await FiscalYearService.instance.currentFiscalYear;
      final lastFyEnd = currentFy.start.subtract(const Duration(days: 1));
      final lastFy =
          await FiscalYearService.instance.getFiscalYearFor(lastFyEnd);
      return (
        start: lastFy.start,
        end: DateTime(
            lastFy.end.year, lastFy.end.month, lastFy.end.day, 23, 59, 59),
      );
    default: // 'month'
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
      return (start: start, end: end);
  }
});

/// Display label for the active report period.
/// Examples: "FY 2025–26", "FY 2024–25", "March 2026".
final reportPeriodLabelProvider = FutureProvider<String>((ref) async {
  final periodMode = ref.watch(reportPeriodModeProvider);
  final month = ref.watch(reportMonthProvider);
  switch (periodMode) {
    case 'this_fy':
      return FiscalYearService.instance.currentFYLabel;
    case 'last_fy':
      final currentFy = await FiscalYearService.instance.currentFiscalYear;
      final lastFyEnd = currentFy.start.subtract(const Duration(days: 1));
      final lastFy =
          await FiscalYearService.instance.getFiscalYearFor(lastFyEnd);
      return FiscalYearService.instance.getFYLabel(lastFy);
    default:
      return DateFormat('MMMM yyyy').format(month);
  }
});

/// P&L summary for the full active period (FY or month).
/// Uses the same [MonthlyPnL] model regardless of period length.
final fyPnLProvider = FutureProvider<MonthlyPnL>((ref) async {
  final range = await ref.watch(reportActiveDateRangeProvider.future);
  final mode = ref.watch(reportModeProvider);
  final contextId = ref.watch(activeContextProvider);
  final repo = TransactionRepositoryImpl(contextId: contextId);
  final results = await Future.wait([
    repo.getTotalIncome(range.start, range.end, mode: mode),
    repo.getTotalExpense(range.start, range.end, mode: mode),
    repo.getIncomeByCategorySummary(range.start, range.end, mode: mode),
    repo.getExpenseByCategorySummary(range.start, range.end, mode: mode),
    repo.getTopParties(range.start, range.end, mode: mode),
    repo.getTopByAmount(range.start, range.end, limit: 5),
  ]);
  final income = results[0] as double;
  final expense = results[1] as double;
  return MonthlyPnL(
    totalIncome: income,
    totalExpense: expense,
    netProfitLoss: income - expense,
    incomeByCat: results[2] as Map<String, double>,
    expenseByCat: results[3] as Map<String, double>,
    topParties: results[4] as List<PartyTotal>,
    largestTransactions: results[5] as List<Transaction>,
  );
});
