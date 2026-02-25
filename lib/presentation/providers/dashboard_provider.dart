import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Summary data for the home dashboard.
class DashboardSummary {
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final double totalInvestment;
  final Map<String, double> categorySummary;

  // Mode breakdown — nullable so hot-reload with stale objects doesn't crash
  final double? personalIncome;
  final double? personalExpense;
  final double? businessIncome;
  final double? businessExpense;

  const DashboardSummary({
    this.totalIncome = 0,
    this.totalExpense = 0,
    this.balance = 0,
    this.totalInvestment = 0,
    this.categorySummary = const {},
    this.personalIncome,
    this.personalExpense,
    this.businessIncome,
    this.businessExpense,
  });

  double get personalPnl => (personalIncome ?? 0) - (personalExpense ?? 0);
  double get businessPnl => (businessIncome ?? 0) - (businessExpense ?? 0);

  /// True when any business-mode transaction exists this month.
  bool get hasBusinessActivity =>
      (businessIncome ?? 0) > 0 || (businessExpense ?? 0) > 0;
}

/// Provider for this month's dashboard summary.
final dashboardSummaryProvider =
    StateNotifierProvider<DashboardNotifier, AsyncValue<DashboardSummary>>(
  (ref) => DashboardNotifier(TransactionRepositoryImpl()),
);

/// Computes dashboard summary from transaction data.
class DashboardNotifier extends StateNotifier<AsyncValue<DashboardSummary>> {
  final TransactionRepository _transactionRepo;

  DashboardNotifier(this._transactionRepo) : super(const AsyncValue.loading()) {
    loadSummary();
  }

  Future<void> loadSummary() async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final income = await _transactionRepo.getTotalIncome(monthStart, monthEnd);
      final expense = await _transactionRepo.getTotalExpense(monthStart, monthEnd);
      final impl = _transactionRepo as TransactionRepositoryImpl;
      final invested = await impl.getTotalInvested(monthStart, monthEnd);
      final redeemed = await impl.getTotalRedeemed(monthStart, monthEnd);
      final categorySummary = await _transactionRepo.getCategorySummary(monthStart, monthEnd);

      // Mode breakdown (run in parallel)
      final results = await Future.wait([
        _transactionRepo.getTotalIncome(monthStart, monthEnd, mode: 'personal'),
        _transactionRepo.getTotalExpense(monthStart, monthEnd, mode: 'personal'),
        _transactionRepo.getTotalIncome(monthStart, monthEnd, mode: 'business'),
        _transactionRepo.getTotalExpense(monthStart, monthEnd, mode: 'business'),
      ]);

      state = AsyncValue.data(DashboardSummary(
        totalIncome: income,
        totalExpense: expense,
        balance: income - expense,
        totalInvestment: invested - redeemed,
        categorySummary: categorySummary,
        personalIncome: results[0],
        personalExpense: results[1],
        businessIncome: results[2],
        businessExpense: results[3],
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
