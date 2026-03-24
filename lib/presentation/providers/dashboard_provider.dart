import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../data/models/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'account_provider.dart';
import 'transaction_provider.dart';

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
  (ref) => DashboardNotifier(ref.watch(transactionRepositoryProvider)),
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
      final invested = await _transactionRepo.getTotalInvested(monthStart, monthEnd);
      final redeemed = await _transactionRepo.getTotalRedeemed(monthStart, monthEnd);
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
  final repo = ref.watch(transactionRepositoryProvider);
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

/// Per-account running balance.
///
/// Each entry corresponds to either:
/// - A named [Account] from the repository (income/expense from linked tx), or
/// - An "unlinked" bucket for transactions that have no [account_id] set,
///   grouped by [PaymentMethod] for backward compatibility.
class AccountBalance {
  const AccountBalance({
    required this.method,
    required this.openingBalance,
    required this.allTimeIncome,
    required this.allTimeExpense,
    this.creditLimit = 0.0,
    this.accountName,
    this.accountId,
  });

  final PaymentMethod method;
  final double openingBalance;
  final double allTimeIncome;
  final double allTimeExpense;

  /// Total approved credit limit (credit card accounts only).
  final double creditLimit;

  /// Named account label. When non-null, shown instead of [method.label].
  final String? accountName;

  /// Linked [Account.id] if backed by a named account.
  final int? accountId;

  String get displayName => accountName ?? method.label;

  /// Bank/wallet/cash: opening + net tx. Credit card: opening outstanding + purchases.
  double get runningBalance => openingBalance + allTimeIncome - allTimeExpense;

  /// Available credit remaining (credit cards only).
  double get availableCredit =>
      creditLimit > 0 ? (creditLimit - openingBalance - allTimeExpense + allTimeIncome) : 0;

  bool get hasActivity =>
      openingBalance != 0 || allTimeIncome != 0 || allTimeExpense != 0 || creditLimit != 0;
}

/// Provider for per-account balances.
///
/// **Named accounts**: each active [Account] becomes one [AccountBalance]
/// entry. Income/expense are computed from transactions where
/// `account_id = account.id`.
///
/// **Unlinked transactions**: transactions without an `account_id` are grouped
/// by [PaymentMethod] and added as implicit balance buckets (opening balance
/// = 0). This preserves visibility of legacy data entered before account
/// linking was introduced.
///
/// Note: [Account.linkedBankAccountId] (debit card / UPI → parent savings
/// account) is stored but balance roll-up is Phase 2 — each account currently
/// tracks its own transactions independently.
final accountBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  final acctRepo = ref.watch(accountRepositoryProvider);
  final txnRepo  = ref.watch(transactionRepositoryProvider);

  final accounts          = await acctRepo.getAll(activeOnly: true);
  final netsByAccountId   = await txnRepo.getAllTimeByAccountId();
  final unlinkedByMethod  = await txnRepo.getAllTimeUnlinkedByPaymentMethod();

  final balances = <AccountBalance>[];

  // ── One entry per named account ────────────────────────────────────────
  for (final account in accounts) {
    final nets = netsByAccountId[account.id] ?? (income: 0.0, expense: 0.0);
    balances.add(AccountBalance(
      method: account.accountType.representativeMethod,
      openingBalance: account.openingBalance ?? 0.0,
      allTimeIncome: nets.income,
      allTimeExpense: nets.expense,
      creditLimit: account.creditLimit ?? 0.0,
      accountName: account.accountName,
      accountId: account.id,
    ));
  }

  // ── Unlinked transactions (no account_id), grouped by payment_method ───
  // These appear as implicit buckets so legacy data stays visible.
  for (final entry in unlinkedByMethod.entries) {
    final method = PaymentMethod.fromDb(entry.key);
    final nets = entry.value;
    if (nets.income != 0 || nets.expense != 0) {
      balances.add(AccountBalance(
        method: method,
        openingBalance: 0.0,
        allTimeIncome: nets.income,
        allTimeExpense: nets.expense,
        // Label: "Other (UPI)", "Other (Cash)", etc. — visually distinct from named accounts.
        accountName: 'Other (${method.label})',
      ));
    }
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
  final repo = ref.watch(transactionRepositoryProvider);
  final data = await repo.getAllTimeInvestments();
  return (
    invested: data.invested,
    redeemed: data.redeemed,
    net: data.invested - data.redeemed,
  );
});
