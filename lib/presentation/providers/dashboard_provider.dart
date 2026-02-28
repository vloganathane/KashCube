import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transaction.dart';
import '../../data/repositories/settings_repository_impl.dart';
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

// ---------------------------------------------------------------------------
// Today's cashflow
// ---------------------------------------------------------------------------

/// A lightweight record of today's total income and expense.
typedef TodayCashflow = ({double income, double expense});

/// Provider for today's cashflow (income + expense totals for today only).
final todayCashflowProvider = FutureProvider<TodayCashflow>((ref) async {
  final repo = TransactionRepositoryImpl();
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final dayEnd   = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final results = await Future.wait([
    repo.getTotalIncome(dayStart, dayEnd),
    repo.getTotalExpense(dayStart, dayEnd),
  ]);
  return (income: results[0], expense: results[1]);
});

// ---------------------------------------------------------------------------
// Account-based balance (Model C)
// ---------------------------------------------------------------------------

/// Per-payment-method running balance.
class AccountBalance {
  const AccountBalance({
    required this.method,
    required this.openingBalance,
    required this.allTimeIncome,
    required this.allTimeExpense,
  });

  final PaymentMethod method;
  final double openingBalance;
  final double allTimeIncome;
  final double allTimeExpense;

  /// opening + all-time inflows − outflows.
  double get runningBalance => openingBalance + allTimeIncome - allTimeExpense;

  /// True when this account has any activity or a non-zero opening balance.
  bool get hasActivity =>
      openingBalance != 0 || allTimeIncome != 0 || allTimeExpense != 0;
}

/// Provider for per-payment-method account balances.
/// Reads opening balances from the settings table and combines with all-time
/// transaction data grouped by [payment_method].
final accountBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  final repo = TransactionRepositoryImpl();
  final settings = SettingsRepositoryImpl();

  final netsByMethod = await repo.getAllTimeByPaymentMethod();

  final balances = <AccountBalance>[];
  for (final method in PaymentMethod.values) {
    final openingStr =
        await settings.get('opening_balance_${method.dbValue}');
    final opening = double.tryParse(openingStr ?? '') ?? 0.0;
    final net = netsByMethod[method.dbValue] ??
        (income: 0.0, expense: 0.0);
    balances.add(AccountBalance(
      method: method,
      openingBalance: opening,
      allTimeIncome: net.income,
      allTimeExpense: net.expense,
    ));
  }
  return balances;
});

/// Total balance = sum of all account running balances.
final totalBalanceProvider = FutureProvider<double>((ref) async {
  final accounts = await ref.watch(accountBalancesProvider.future);
  return accounts.fold<double>(0.0, (sum, a) => sum + a.runningBalance);
});

/// Invalidates both balance providers (call after saving opening balances).
void invalidateBalanceProviders(Ref ref) {
  ref.invalidate(accountBalancesProvider);
  ref.invalidate(totalBalanceProvider);
}

// ---------------------------------------------------------------------------
// All-time investments
// ---------------------------------------------------------------------------

/// All-time invested (still deployed) and redeemed (returned) totals.
/// Net invested = invested − redeemed = capital still in market/FD/etc.
final allTimeInvestmentProvider =
    FutureProvider<({double invested, double redeemed, double net})>((ref) async {
  final repo = TransactionRepositoryImpl();
  final data = await repo.getAllTimeInvestments();
  return (
    invested: data.invested,
    redeemed: data.redeemed,
    net: data.invested - data.redeemed,
  );
});
