import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_tables.dart';
import '../../data/services/sync_event_bus.dart';
import 'account_provider.dart';
import 'bill_schedule_provider.dart';
import 'booking_provider.dart';
import 'budget_provider.dart';
import 'business_provider.dart';
import 'category_provider.dart';
import 'credit_provider.dart';
import 'dashboard_provider.dart';
import 'delivery_challan_provider.dart';
import 'document_template_provider.dart';
import 'inventory_provider.dart';
import 'settings_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'party_provider.dart';
import 'party_reminder_provider.dart';
import 'purchase_bill_provider.dart';
import 'recurring_provider.dart';
import 'scheduled_payment_provider.dart';
import 'staff_provider.dart';
import 'transaction_provider.dart';

final syncEventStreamProvider = StreamProvider<String>(
  (_) => SyncEventBus.instance.stream,
);

/// Table-to-providers mapping.
/// Adding a new syncable table = one new entry here — no switch needed.
/// Multiple tables can share the same list (child tables → parent providers).
/// Tables absent from this map fall back to [_broadRefresh].
final _tableInvalidators = <String, List<ProviderOrFamily>>{
  AppTables.transactions: [
    transactionsProvider,
    recentTransactionsProvider,
    ledgerSummariesProvider,
    dashboardSummaryProvider,
    todayCashflowProvider,
    accountBalancesProvider,
    totalBalanceProvider,
    allTimeInvestmentProvider,
  ],
  AppTables.credits: [
    activeCreditsProvider,
    creditPartySummariesProvider,
    totalCreditsPendingGivenProvider,
    totalCreditsPendingReceivedProvider,
  ],
  AppTables.creditPayments: [
    activeCreditsProvider,
    creditPartySummariesProvider,
    totalCreditsPendingGivenProvider,
    totalCreditsPendingReceivedProvider,
  ],
  AppTables.loans: [
    activeLoansProvider,
    totalPendingLoanProvider,
    totalPendingLentProvider,
    totalPendingBorrowedProvider,
    clearedLoansProvider,
    overdueLoansProvider,
    partySummariesProvider,
  ],
  AppTables.loanPayments: [
    activeLoansProvider,
    totalPendingLoanProvider,
    totalPendingLentProvider,
    totalPendingBorrowedProvider,
    clearedLoansProvider,
    overdueLoansProvider,
  ],
  AppTables.parties: [partiesProvider],
  AppTables.partyAddresses: [partiesProvider],
  AppTables.partyReminders: [partyRemindersProvider, recentRemindersProvider],
  AppTables.accounts: [
    accountsProvider,
    accountBalancesProvider,
    totalBalanceProvider,
  ],
  AppTables.categories: [customCategoriesProvider],
  AppTables.budgets: [currentMonthBudgetsProvider],
  AppTables.invoices: [invoicesProvider],
  AppTables.invoiceItems: [invoicesProvider],
  AppTables.quotes: [quotesProvider],
  AppTables.quoteItems: [quotesProvider],
  AppTables.businesses: [businessesProvider],
  AppTables.purchaseBills: [purchaseBillsProvider],
  AppTables.purchaseBillItems: [purchaseBillsProvider],
  AppTables.itemCatalog: [catalogProvider],
  AppTables.itemStock: [inventoryProvider],
  AppTables.stockMovements: [inventoryProvider],
  AppTables.scheduledPayments: [
    scheduledPaymentsProvider,
    totalMonthlyScheduledExpenseProvider,
  ],
  AppTables.settings: [
    themeModeProvider,
    businessModeProvider,
    businessNameProvider,
    notificationSettingsProvider,
    smsAutoDetectEnabledProvider,
    defaultAccountIdProvider,
  ],
  AppTables.documentTemplates: [documentTemplatesProvider],
  AppTables.deliveryChallans: [challansProvider],
  AppTables.deliveryChallanItems: [challansProvider],
  AppTables.bookings: [bookingsProvider],
  AppTables.bookingItems: [bookingsProvider],
  AppTables.staff: [staffProvider],
  AppTables.salaryPayments: [staffProvider],
  AppTables.recurringTransactions: [
    recurringTransactionsProvider,
    recurringMonthlySummaryProvider,
  ],
  AppTables.bills: [
    scheduledBillsProvider,
    overdueBillsProvider,
    upcomingBillsProvider,
    totalMonthlyBillsProvider,
  ],
};

/// Broad refresh applied when a table is not in [_tableInvalidators].
/// Covers all major data domains so UI stays consistent after sync discovers
/// a new table that hasn't been mapped above yet.
final _broadRefresh = <ProviderOrFamily>[
  transactionsProvider,
  activeCreditsProvider,
  activeLoansProvider,
  partiesProvider,
  accountsProvider,
  dashboardSummaryProvider,
  invoicesProvider,
  quotesProvider,
  purchaseBillsProvider,
  catalogProvider,
];

/// Installs app-wide auto-refresh wiring from DB sync events to Riverpod state.
///
/// This ensures rows merged from WebSocket/P2P (which bypass UI notifiers)
/// still refresh visible screens without manual pull-to-refresh.
final syncAutoRefreshInstallerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<String>>(syncEventStreamProvider, (_, next) {
    final table = next.valueOrNull;
    if (table == null) return;
    final targets = _tableInvalidators[table] ?? _broadRefresh;
    for (final provider in targets) {
      ref.invalidate(provider);
    }
  });
});
