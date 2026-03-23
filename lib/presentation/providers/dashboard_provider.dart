import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../data/models/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'account_provider.dart';
import 'settings_provider.dart';
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
/// Either backed by a named [Account] from the repository (Option B) or by the
/// legacy per-[PaymentMethod] settings keys (Option A fallback).
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

  /// Named account label. When non-null, used instead of [method.label].
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

// "Bank" payment rails — all draw from savings/current accounts.
const _kBankRails = [
  PaymentMethod.upi,
  PaymentMethod.debitCard,
  PaymentMethod.netBanking,
  PaymentMethod.cheque,
];

/// Provider for per-account balances.
///
/// **Option B** (preferred): reads named accounts from [AccountRepository].
/// Each account type group maps to the appropriate [PaymentMethod] rails.
///
/// **Fallback** (Option A / legacy): if no accounts exist in the repo yet,
/// reads `opening_balance_*` from the settings table, preserving data for
/// users who set them before the named-account system was introduced.
final accountBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  final acctRepo   = ref.watch(accountRepositoryProvider);
  final txnRepo    = ref.watch(transactionRepositoryProvider);
  final settings   = ref.watch(settingsRepositoryProvider);

  final accounts      = await acctRepo.getAll(activeOnly: true);
  final netsByMethod  = await txnRepo.getAllTimeByPaymentMethod();

  ({double income, double expense}) netFor(PaymentMethod m) =>
      netsByMethod[m.dbValue] ?? (income: 0.0, expense: 0.0);

  // Partition accounts by role.
  final bankAccts = accounts.where((a) =>
      a.accountType == AccountType.savings ||
      a.accountType == AccountType.current).toList();
  final walletAccts = accounts.where((a) =>
      a.accountType == AccountType.upiWallet ||
      a.accountType == AccountType.paymentWallet).toList();
  final ccAccts = accounts.where((a) =>
      a.accountType == AccountType.creditCard).toList();
  final cashAccts = accounts.where((a) =>
      a.accountType == AccountType.cash).toList();

  final balances = <AccountBalance>[];

  // ── Bank accounts (savings + current) ─────────────────────────────────
  if (bankAccts.isNotEmpty) {
    final opening =
        bankAccts.fold<double>(0, (s, a) => s + (a.currentBalance ?? 0));
    double income = 0, expense = 0;
    for (final rail in _kBankRails) {
      final n = netFor(rail);
      income += n.income;
      expense += n.expense;
    }
    balances.add(AccountBalance(
      method: PaymentMethod.upi,
      openingBalance: opening,
      allTimeIncome: income,
      allTimeExpense: expense,
      accountName:
          bankAccts.length == 1 ? bankAccts.first.accountName : 'Bank Accounts',
      accountId: bankAccts.length == 1 ? bankAccts.first.id : null,
    ));
  } else {
    // Legacy fallback: individual rail settings keys.
    for (final m in _kBankRails) {
      final opening = double.tryParse(
              await settings.get('opening_balance_${m.dbValue}') ?? '') ??
          0.0;
      final net = netFor(m);
      if (opening != 0 || net.income != 0 || net.expense != 0) {
        balances.add(AccountBalance(
          method: m,
          openingBalance: opening,
          allTimeIncome: net.income,
          allTimeExpense: net.expense,
        ));
      }
    }
  }

  // ── Wallet accounts ────────────────────────────────────────────────────
  if (walletAccts.isNotEmpty) {
    final opening =
        walletAccts.fold<double>(0, (s, a) => s + (a.currentBalance ?? 0));
    final net = netFor(PaymentMethod.wallet);
    balances.add(AccountBalance(
      method: PaymentMethod.wallet,
      openingBalance: opening,
      allTimeIncome: net.income,
      allTimeExpense: net.expense,
      accountName: walletAccts.length == 1 ? walletAccts.first.accountName : null,
      accountId: walletAccts.length == 1 ? walletAccts.first.id : null,
    ));
  } else {
    final opening = double.tryParse(
            await settings.get('opening_balance_wallet') ?? '') ??
        0.0;
    final net = netFor(PaymentMethod.wallet);
    if (opening != 0 || net.income != 0 || net.expense != 0) {
      balances.add(AccountBalance(
        method: PaymentMethod.wallet,
        openingBalance: opening,
        allTimeIncome: net.income,
        allTimeExpense: net.expense,
      ));
    }
  }

  // ── Credit card accounts ───────────────────────────────────────────────
  if (ccAccts.isNotEmpty) {
    final outstanding =
        ccAccts.fold<double>(0, (s, a) => s + (a.currentBalance ?? 0));
    final limit = ccAccts.fold<double>(0, (s, a) => s + (a.creditLimit ?? 0));
    final net = netFor(PaymentMethod.creditCard);
    balances.add(AccountBalance(
      method: PaymentMethod.creditCard,
      openingBalance: outstanding,
      allTimeIncome: net.income,
      allTimeExpense: net.expense,
      creditLimit: limit,
      accountName: ccAccts.length == 1 ? ccAccts.first.accountName : null,
      accountId: ccAccts.length == 1 ? ccAccts.first.id : null,
    ));
  } else {
    final outstanding = double.tryParse(
            await settings.get('opening_balance_creditCard') ?? '') ??
        0.0;
    final limit = double.tryParse(
            await settings.get('opening_balance_creditCard_limit') ?? '') ??
        0.0;
    final net = netFor(PaymentMethod.creditCard);
    if (outstanding != 0 || net.income != 0 || net.expense != 0 || limit != 0) {
      balances.add(AccountBalance(
        method: PaymentMethod.creditCard,
        openingBalance: outstanding,
        allTimeIncome: net.income,
        allTimeExpense: net.expense,
        creditLimit: limit,
      ));
    }
  }

  // ── Cash accounts ──────────────────────────────────────────────────────
  if (cashAccts.isNotEmpty) {
    final opening =
        cashAccts.fold<double>(0, (s, a) => s + (a.currentBalance ?? 0));
    final net = netFor(PaymentMethod.cash);
    balances.add(AccountBalance(
      method: PaymentMethod.cash,
      openingBalance: opening,
      allTimeIncome: net.income,
      allTimeExpense: net.expense,
    ));
  } else {
    final opening = double.tryParse(
            await settings.get('opening_balance_cash') ?? '') ??
        0.0;
    final net = netFor(PaymentMethod.cash);
    if (opening != 0 || net.income != 0 || net.expense != 0) {
      balances.add(AccountBalance(
        method: PaymentMethod.cash,
        openingBalance: opening,
        allTimeIncome: net.income,
        allTimeExpense: net.expense,
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
