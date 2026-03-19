import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/sync_event_bus.dart';
import 'account_provider.dart';
import 'booking_provider.dart';
import 'budget_provider.dart';
import 'business_provider.dart';
import 'category_provider.dart';
import 'credit_provider.dart';
import 'dashboard_provider.dart';
import 'delivery_challan_provider.dart';
import 'document_template_provider.dart';
import 'inventory_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'party_provider.dart';
import 'party_reminder_provider.dart';
import 'purchase_bill_provider.dart';
import 'scheduled_payment_provider.dart';
import 'staff_provider.dart';
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
      case 'credit_payments':
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
      case 'party_addresses':
        ref.invalidate(partiesProvider);
        break;
      case 'party_reminders':
        ref.invalidate(partyRemindersProvider);
        break;
      case 'accounts':
        ref.invalidate(accountsProvider);
        ref.invalidate(accountBalancesProvider);
        ref.invalidate(totalBalanceProvider);
        break;
      case 'categories':
        ref.invalidate(customCategoriesProvider);
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
      case 'purchase_bill_items':
        ref.invalidate(purchaseBillsProvider);
        break;
      case 'item_catalog':
        ref.invalidate(catalogProvider);
        break;
      case 'item_stock':
      case 'stock_movements':
        ref.invalidate(inventoryProvider);
        break;
      case 'scheduled_payments':
        ref.invalidate(scheduledPaymentsProvider);
        ref.invalidate(totalMonthlyScheduledExpenseProvider);
        break;
      case 'document_templates':
        ref.invalidate(documentTemplatesProvider);
        break;
      case 'delivery_challans':
      case 'delivery_challan_items':
        ref.invalidate(challansProvider);
        break;
      case 'bookings':
        ref.invalidate(bookingsProvider);
        break;
      case 'staff':
      case 'salary_payments':
        ref.invalidate(staffProvider);
        break;
      default:
        // Unknown table synced — dynamic discovery added a new table.
        // Broad refresh covers all major data domains so UI stays consistent.
        ref.invalidate(transactionsProvider);
        ref.invalidate(activeCreditsProvider);
        ref.invalidate(activeLoansProvider);
        ref.invalidate(partiesProvider);
        ref.invalidate(accountsProvider);
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(invoicesProvider);
        ref.invalidate(quotesProvider);
        ref.invalidate(purchaseBillsProvider);
        ref.invalidate(catalogProvider);
        break;
    }
  });
});
