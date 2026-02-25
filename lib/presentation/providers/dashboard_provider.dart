import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Summary data for the home dashboard.
class DashboardSummary {
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final double totalPendingCredit;
  final double totalInvestment;
  final Map<String, double> categorySummary;

  const DashboardSummary({
    this.totalIncome = 0,
    this.totalExpense = 0,
    this.balance = 0,
    this.totalPendingCredit = 0,
    this.totalInvestment = 0,
    this.categorySummary = const {},
  });
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
      final invested = await _transactionRepo.getTotalExpense(
        monthStart, monthEnd, mode: 'investment',
      );
      final investmentReturns = await _transactionRepo.getTotalIncome(
        monthStart, monthEnd, mode: 'investment',
      );
      final categorySummary = await _transactionRepo.getCategorySummary(monthStart, monthEnd);

      state = AsyncValue.data(DashboardSummary(
        totalIncome: income,
        totalExpense: expense,
        balance: income - expense,
        totalInvestment: invested + investmentReturns,
        categorySummary: categorySummary,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
