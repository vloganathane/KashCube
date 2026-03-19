import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/sync_event_bus.dart';
import 'account_provider.dart';
import 'budget_provider.dart';
import 'business_provider.dart';
import 'credit_provider.dart';
import 'dashboard_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'party_provider.dart';
import 'purchase_bill_provider.dart';
import 'scheduled_payment_provider.dart';
import 'transaction_provider.dart';

final syncEventStreamProvider = StreamProvider<String>(
  (_) => SyncEventBus.instance.stream,
);

/// Installs app-wide auto-refresh wiring from DB sync events to Riverpod state.
///
/// This ensures rows merged from WebSocket/P2P (which bypass UI notifiers)
/// still refresh visible screens without manual pull-to-refresh.
final syncAutoRefreshInstallerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<String>>(syncEventStreamProvider, (_, next) {
    final table = next.valueOrNull;
    if (table == null) return;

    switch (table) {
      case 'transactions':
        ref.invalidate(transactionsProvider);
        ref.invalidate(recentTransactionsProvider);
        ref.invalidate(ledgerSummariesProvider);
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(todayCashflowProvider);
        ref.invalidate(accountBalancesProvider);
        ref.invalidate(totalBalanceProvider);
        ref.invalidate(allTimeInvestmentProvider);
        break;
      case 'credits':
        ref.invalidate(activeCreditsProvider);
        ref.invalidate(creditPartySummariesProvider);
        ref.invalidate(totalCreditsPendingGivenProvider);
        ref.invalidate(totalCreditsPendingReceivedProvider);
        break;
      case 'loans':
        ref.invalidate(activeLoansProvider);
        ref.invalidate(totalPendingLoanProvider);
        ref.invalidate(totalPendingLentProvider);
        ref.invalidate(totalPendingBorrowedProvider);
        ref.invalidate(clearedLoansProvider);
        ref.invalidate(overdueLoansProvider);
        ref.invalidate(partySummariesProvider);
        break;
      case 'parties':
        ref.invalidate(partiesProvider);
        break;
      case 'accounts':
        ref.invalidate(accountsProvider);
        ref.invalidate(accountBalancesProvider);
        ref.invalidate(totalBalanceProvider);
        break;
      case 'budgets':
        ref.invalidate(currentMonthBudgetsProvider);
        break;
      case 'invoices':
        ref.invalidate(invoicesProvider);
        break;
      case 'quotes':
        ref.invalidate(quotesProvider);
        break;
      case 'businesses':
        ref.invalidate(businessesProvider);
        break;
      case 'purchase_bills':
        ref.invalidate(purchaseBillsProvider);
        break;
      case 'item_catalog':
        ref.invalidate(catalogProvider);
        break;
      case 'scheduled_payments':
        ref.invalidate(scheduledPaymentsProvider);
        ref.invalidate(totalMonthlyScheduledExpenseProvider);
        break;
      default:
        break;
    }
  });
});
