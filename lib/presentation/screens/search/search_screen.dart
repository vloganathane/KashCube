import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/party.dart';
import '../../../data/models/purchase_bill.dart';
import '../../../data/models/quote.dart';
import '../../../data/models/recurring_transaction.dart';
import '../../../data/models/transaction.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../providers/bill_schedule_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/purchase_bill_provider.dart';
import '../../providers/recurring_provider.dart';
import '../../providers/transaction_provider.dart';
import '../bookings/booking_detail_screen.dart';
import '../gst/purchase_bill_detail_screen.dart';
import '../invoices/delivery_challan_detail_screen.dart';
import '../invoices/invoice_detail_screen.dart';
import '../ledger/ledger_screen.dart';
import '../loans/loans_screen.dart';
import '../parties/party_360_screen.dart';
import '../bills/bills_and_payments_screen.dart';
import '../invoices/quote_detail_screen.dart';
import '../transactions/transaction_detail_screen.dart';

// ---------------------------------------------------------------------------
// Recent searches — session-level in-memory store
// ---------------------------------------------------------------------------

/// Holds the last 5 unique search queries for the current session.
final recentSearchesProvider = StateProvider<List<String>>((_) => const []);

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

/// Scope filter for the global search screen.
/// Pass [initialFilter] to [SearchScreen] to pre-select a scope based on
/// which screen the user opened search from.
enum SearchFilter {
  all,
  transactions,
  invoices,
  quotes,
  credits,
  bills,
  purchaseBills,
  bookings,
  parties,
  loans,
  challans,
  recurring,
}

extension SearchFilterExt on SearchFilter {
  String get label => switch (this) {
        SearchFilter.all => 'All',
        SearchFilter.transactions => 'Transactions',
        SearchFilter.invoices => 'Invoices',
        SearchFilter.quotes => 'Quotes',
        SearchFilter.credits => 'Credits',
        SearchFilter.bills => 'Bills',
        SearchFilter.purchaseBills => 'Purchase Bills',
        SearchFilter.bookings => 'Bookings',
        SearchFilter.parties => 'Parties',
        SearchFilter.loans => 'Loans',
        SearchFilter.challans => 'Challans',
        SearchFilter.recurring => 'Recurring',
      };

  IconData get icon => switch (this) {
        SearchFilter.all => Icons.apps,
        SearchFilter.transactions => Icons.receipt_long_outlined,
        SearchFilter.invoices => Icons.description_outlined,
        SearchFilter.quotes => Icons.request_quote_outlined,
        SearchFilter.credits => Icons.book_outlined,
        SearchFilter.bills => Icons.calendar_today_outlined,
        SearchFilter.purchaseBills => Icons.inventory_2_outlined,
        SearchFilter.bookings => Icons.calendar_month_outlined,
        SearchFilter.parties => Icons.people_outline,
        SearchFilter.loans => Icons.account_balance_wallet_outlined,
        SearchFilter.challans => Icons.local_shipping_outlined,
        SearchFilter.recurring => Icons.repeat_outlined,
      };
}

/// Unified global search across transactions, invoices, credits, bills,
/// bookings, and parties. Accessible from every main screen.
///
/// Pass [initialFilter] to pre-select a scope filter so search starts
/// focused on the entity type relevant to the calling screen.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialFilter = SearchFilter.all});

  final SearchFilter initialFilter;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  late SearchFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmit(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return;
    final list = ref.read(recentSearchesProvider);
    final updated = [
      trimmed,
      ...list.where((r) => r != trimmed),
    ].take(5).toList();
    ref.read(recentSearchesProvider.notifier).state = updated;
  }

  String get _hintText => switch (_filter) {
        SearchFilter.all => 'Search everything…',
        SearchFilter.transactions => 'Search transactions…',
        SearchFilter.invoices => 'Search invoices…',
        SearchFilter.quotes => 'Search quotes…',
        SearchFilter.credits => 'Search dues…',
        SearchFilter.bills => 'Search bills…',
        SearchFilter.purchaseBills => 'Search purchase bills…',
        SearchFilter.bookings => 'Search bookings…',
        SearchFilter.parties => 'Search by name or phone…',
        SearchFilter.loans => 'Search loans…',
        SearchFilter.challans => 'Search challans…',
        SearchFilter.recurring => 'Search recurring transactions…',
      };

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentSearchesProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: _hintText,
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: AppSpacing.iconSm),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: _onSubmit,
        ),
      ),
      body: Column(
        children: [
          _FilterBar(
            selected: _filter,
            initialFilter: widget.initialFilter,
            onChanged: (f) => setState(() => _filter = f),
          ),
          const Divider(height: 1),
          Expanded(
            child: _query.length < 2
                ? _HintState(
                    recents: recents,
                    onRecentTap: (q) {
                      _controller.text = q;
                      setState(() => _query = q);
                    },
                  )
                : _SearchResults(query: _query, filter: _filter),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chips bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.initialFilter,
    required this.onChanged,
  });

  final SearchFilter selected;
  final SearchFilter initialFilter;
  final ValueChanged<SearchFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: SearchFilter.values
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: FilterChip(
                  avatar: Icon(
                    f.icon,
                    size: 14,
                    // Highlight the context-scoped filter differently
                    color: f == initialFilter && f != SearchFilter.all
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  label: Text(f.label),
                  selected: selected == f,
                  onSelected: (_) => onChanged(f),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint / recent searches
// ---------------------------------------------------------------------------

class _HintState extends StatelessWidget {
  const _HintState({required this.recents, required this.onRecentTap});

  final List<String> recents;
  final ValueChanged<String> onRecentTap;

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: context.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Type at least 2 characters to search',
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colorScheme.outline),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent',
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colorScheme.outline),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: recents
                .map(
                  (q) => ActionChip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(q),
                    onPressed: () => onRecentTap(q),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results widget
// ---------------------------------------------------------------------------

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.filter});

  final String query;
  final SearchFilter filter;

  bool _show(SearchFilter f) => filter == SearchFilter.all || filter == f;

  bool _matchTxn(Transaction t, String q) =>
      (t.partyName?.toLowerCase().contains(q) ?? false) ||
      t.category.toLowerCase().contains(q) ||
      (t.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(t.amount).contains(q);

  bool _matchInvoice(Invoice inv, String q) =>
      inv.customerName.toLowerCase().contains(q) ||
      inv.invoiceNo.toLowerCase().contains(q) ||
      inv.status.label.toLowerCase().contains(q) ||
      (inv.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(inv.total).contains(q);

  bool _matchQuote(Quote qt, String q) =>
      qt.customerName.toLowerCase().contains(q) ||
      qt.quoteNo.toLowerCase().contains(q) ||
      qt.status.label.toLowerCase().contains(q) ||
      (qt.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(qt.total).contains(q);

  bool _matchPurchaseBill(PurchaseBill b, String q) =>
      b.vendorName.toLowerCase().contains(q) ||
      b.billNo.toLowerCase().contains(q) ||
      (b.vendorGstin?.toLowerCase().contains(q) ?? false) ||
      (b.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(b.total).contains(q);

  bool _matchBill(Bill b, String q) =>
      b.name.toLowerCase().contains(q) ||
      b.category.toLowerCase().contains(q) ||
      (b.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(b.amount).contains(q);

  bool _matchBooking(Booking b, String q) =>
      b.customerName.toLowerCase().contains(q) ||
      b.serviceName.toLowerCase().contains(q) ||
      (b.bookingRef?.toLowerCase().contains(q) ?? false) ||
      (b.notes?.toLowerCase().contains(q) ?? false);

  bool _matchParty(Party p, String q) =>
      p.name.toLowerCase().contains(q) ||
      (p.phoneNumber?.toLowerCase().contains(q) ?? false) ||
      (p.email?.toLowerCase().contains(q) ?? false) ||
      p.partyType.label.toLowerCase().contains(q);

  bool _matchLoan(Loan l, String q) =>
      l.lenderName.toLowerCase().contains(q) ||
      (l.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(l.principalAmount).contains(q) ||
      l.direction.name.toLowerCase().contains(q);

  bool _matchChallan(DeliveryChallan c, String q) =>
      c.customerName.toLowerCase().contains(q) ||
      c.challanNo.toLowerCase().contains(q) ||
      (c.notes?.toLowerCase().contains(q) ?? false) ||
      (c.vehicleNo?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(c.subtotal).contains(q);

  bool _matchRecurring(RecurringTransaction r, String q) =>
      r.category.toLowerCase().contains(q) ||
      (r.partyName?.toLowerCase().contains(q) ?? false) ||
      (r.notes?.toLowerCase().contains(q) ?? false) ||
      CurrencyFormatter.format(r.amount).contains(q);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.toLowerCase();

    final txns = _show(SearchFilter.transactions)
        ? (ref.watch(transactionsProvider).valueOrNull ?? <Transaction>[])
            .where((t) => _matchTxn(t, q))
            .toList()
        : <Transaction>[];

    final invoices = _show(SearchFilter.invoices)
        ? (ref.watch(invoicesProvider).valueOrNull ?? <Invoice>[])
            .where((inv) => _matchInvoice(inv, q))
            .toList()
        : <Invoice>[];

    final quotes = _show(SearchFilter.quotes)
        ? (ref.watch(quotesProvider).valueOrNull ?? <Quote>[])
            .where((qt) => _matchQuote(qt, q))
            .toList()
        : <Quote>[];

    final credits = _show(SearchFilter.credits)
        ? (ref.watch(ledgerSummariesProvider).valueOrNull ?? <LedgerPartyEntry>[])
            .where((e) => e.partyName.toLowerCase().contains(q))
            .toList()
        : <LedgerPartyEntry>[];

    final bills = _show(SearchFilter.bills)
        ? (ref.watch(scheduledBillsProvider).valueOrNull ?? <Bill>[])
            .where((b) => _matchBill(b, q))
            .toList()
        : <Bill>[];

    final purchaseBills = _show(SearchFilter.purchaseBills)
        ? (ref.watch(purchaseBillsProvider).valueOrNull ?? <PurchaseBill>[])
            .where((b) => _matchPurchaseBill(b, q))
            .toList()
        : <PurchaseBill>[];

    final bookings = _show(SearchFilter.bookings)
        ? (ref.watch(bookingsProvider).valueOrNull ?? <Booking>[])
            .where((b) => _matchBooking(b, q))
            .toList()
        : <Booking>[];

    final parties = _show(SearchFilter.parties)
        ? (ref.watch(partiesProvider).valueOrNull ?? <Party>[])
            .where((p) => _matchParty(p, q))
            .toList()
        : <Party>[];

    final loans = _show(SearchFilter.loans)
        ? (ref.watch(activeLoansProvider).valueOrNull ?? <Loan>[])
            .where((l) => _matchLoan(l, q))
            .toList()
        : <Loan>[];

    final challans = _show(SearchFilter.challans)
        ? (ref.watch(challansProvider).valueOrNull ?? <DeliveryChallan>[])
            .where((c) => _matchChallan(c, q))
            .toList()
        : <DeliveryChallan>[];

    final recurring = _show(SearchFilter.recurring)
        ? (ref.watch(recurringTransactionsProvider).valueOrNull ?? <RecurringTransaction>[])
            .where((r) => _matchRecurring(r, q))
            .toList()
        : <RecurringTransaction>[];

    final total = txns.length + invoices.length + quotes.length + credits.length +
        bills.length + purchaseBills.length + bookings.length + parties.length +
        loans.length + challans.length + recurring.length;

    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: context.colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text(
              'No results for "$query"',
              style: context.textTheme.titleMedium
                  ?.copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      children: [
        if (txns.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Transactions', count: txns.length, icon: Icons.receipt_long),
          ...txns.take(10).map((t) => _TxnTile(txn: t, query: query)),
          if (txns.length > 10) _MoreRow(count: txns.length - 10, label: 'transactions'),
        ],
        if (invoices.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Invoices', count: invoices.length, icon: Icons.description_outlined),
          ...invoices.take(10).map((inv) => _InvoiceTile(invoice: inv, query: query)),
          if (invoices.length > 10) _MoreRow(count: invoices.length - 10, label: 'invoices'),
        ],
        if (quotes.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Quotes', count: quotes.length, icon: Icons.request_quote_outlined),
          ...quotes.take(10).map((qt) => _QuoteTile(quote: qt, query: query)),
          if (quotes.length > 10) _MoreRow(count: quotes.length - 10, label: 'quotes'),
        ],
        if (credits.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Credits', count: credits.length, icon: Icons.book),
          ...credits.take(10).map((e) => _CreditTile(entry: e, query: query)),
          if (credits.length > 10) _MoreRow(count: credits.length - 10, label: 'credits'),
        ],
        if (bills.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Bills', count: bills.length, icon: Icons.calendar_today_outlined),
          ...bills.take(10).map((b) => _BillTile(bill: b, query: query)),
          if (bills.length > 10) _MoreRow(count: bills.length - 10, label: 'bills'),
        ],
        if (purchaseBills.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Purchase Bills', count: purchaseBills.length, icon: Icons.inventory_2_outlined),
          ...purchaseBills.take(10).map((b) => _PurchaseBillTile(bill: b, query: query)),
          if (purchaseBills.length > 10) _MoreRow(count: purchaseBills.length - 10, label: 'purchase bills'),
        ],
        if (bookings.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Bookings', count: bookings.length, icon: Icons.calendar_month_outlined),
          ...bookings.take(10).map((b) => _BookingTile(booking: b, query: query)),
          if (bookings.length > 10) _MoreRow(count: bookings.length - 10, label: 'bookings'),
        ],
        if (parties.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Parties', count: parties.length, icon: Icons.people_outline),
          ...parties.take(10).map((p) => _PartyTile(party: p, query: query)),
          if (parties.length > 10) _MoreRow(count: parties.length - 10, label: 'parties'),
        ],
        if (loans.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Loans', count: loans.length, icon: Icons.account_balance_wallet_outlined),
          ...loans.take(10).map((l) => _LoanTile(loan: l, query: query)),
          if (loans.length > 10) _MoreRow(count: loans.length - 10, label: 'loans'),
        ],
        if (challans.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Challans', count: challans.length, icon: Icons.local_shipping_outlined),
          ...challans.take(10).map((c) => _ChallanTile(challan: c, query: query)),
          if (challans.length > 10) _MoreRow(count: challans.length - 10, label: 'challans'),
        ],
        if (recurring.isNotEmpty) ...[const SizedBox(height: AppSpacing.base),
          _SectionHeader(title: 'Recurring', count: recurring.length, icon: Icons.repeat_outlined),
          ...recurring.take(10).map((r) => _RecurringTile(item: r, query: query)),
          if (recurring.length > 10) _MoreRow(count: recurring.length - 10, label: 'recurring'),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared layout widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.icon});

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: context.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: context.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              '$count',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.count, required this.label});
  final int count;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          '+ $count more $label',
          style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.outline),
          textAlign: TextAlign.center,
        ),
      );
}

// ---------------------------------------------------------------------------
// Highlighted text — bolds matching substring
// ---------------------------------------------------------------------------

class _Highlight extends StatelessWidget {
  const _Highlight({required this.text, required this.query});
  final String text;
  final String query;
  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final idx = lower.indexOf(lowerQ);
    if (idx < 0 || lowerQ.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, idx)),
        TextSpan(
          text: text.substring(idx, idx + lowerQ.length),
          style: TextStyle(fontWeight: FontWeight.bold, color: context.colorScheme.primary),
        ),
        TextSpan(text: text.substring(idx + lowerQ.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// Result tiles
// ---------------------------------------------------------------------------

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn, required this.query});
  final Transaction txn;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isIncome = txn.isIncome;
    final amountColor = isIncome ? colors.income : colors.expense;
    final prefix = isIncome ? '+' : '-';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(CategoryHelper.getIcon(txn.category),
            color: context.colorScheme.onPrimaryContainer, size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: txn.partyName ?? txn.category, query: query),
      subtitle: Text('${DateFormatter.format(txn.date)} · ${txn.category}',
          style: context.textTheme.bodySmall),
      trailing: Text('$prefix${CurrencyFormatter.format(txn.amount)}',
          style: context.textTheme.titleSmall?.copyWith(
              color: amountColor, fontWeight: FontWeight.w600, fontFamily: 'RobotoMono')),
      onTap: () {
        if (txn.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: txn.id!)),
          );
        }
      },
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.query});
  final Invoice invoice;
  final String query;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => Colors.green,
      InvoiceStatus.overdue => context.colorScheme.error,
      InvoiceStatus.sent => Colors.orange,
      InvoiceStatus.partiallyPaid => Colors.blue,
      InvoiceStatus.cancelled => context.colorScheme.outline,
      InvoiceStatus.draft => context.colorScheme.outline,
      InvoiceStatus.pendingNumber => context.colorScheme.outline,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.secondaryContainer,
        child: Icon(Icons.description_outlined,
            color: context.colorScheme.onSecondaryContainer, size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: invoice.customerName, query: query),
      subtitle: Text('${invoice.invoiceNo} · ${DateFormatter.format(invoice.issueDate)}',
          style: context.textTheme.bodySmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(CurrencyFormatter.format(invoice.total),
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600, fontFamily: 'RobotoMono')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(invoice.status.label,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      onTap: () {
        if (invoice.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!)),
          );
        }
      },
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.query});
  final Bill bill;
  final String query;

  @override
  Widget build(BuildContext context) {
    final isOverdue = !bill.isPaidThisPeriod && bill.nextDueDate.isBefore(DateTime.now());
    final statusColor = isOverdue
        ? context.colorScheme.error
        : bill.isPaidThisPeriod ? Colors.green : Colors.orange;
    final statusLabel = isOverdue ? 'Overdue' : bill.isPaidThisPeriod ? 'Paid' : 'Upcoming';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.tertiaryContainer,
        child: Icon(Icons.receipt_outlined,
            color: context.colorScheme.onTertiaryContainer, size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: bill.name, query: query),
      subtitle: Text('${bill.category} · Due ${bill.dueDay}${_ord(bill.dueDay)}',
          style: context.textTheme.bodySmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(CurrencyFormatter.format(bill.amount),
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600, fontFamily: 'RobotoMono')),
          Text(statusLabel,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
        ],
      ),
      onTap: () => Navigator.of(context).pop(),
    );
  }

  String _ord(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.entry, required this.query});
  final LedgerPartyEntry entry;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final net = entry.netBalance;
    final isPositive = net > 0.01;
    final balanceColor = isPositive ? colors.income : colors.expense;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Text(
          entry.partyName.isNotEmpty ? entry.partyName[0].toUpperCase() : '?',
          style: TextStyle(color: context.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
        ),
      ),
      title: _Highlight(text: entry.partyName, query: query),
      subtitle: Text(isPositive ? 'Owes you' : 'You owe', style: context.textTheme.bodySmall),
      trailing: Text(CurrencyFormatter.format(net.abs()),
          style: context.textTheme.titleSmall
              ?.copyWith(color: balanceColor, fontWeight: FontWeight.w600)),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LedgerScreen())),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, required this.query});
  final Booking booking;
  final String query;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status) {
      BookingStatus.confirmed => Colors.green,
      BookingStatus.pending => Colors.orange,
      BookingStatus.completed => context.colorScheme.primary,
      BookingStatus.cancelled => context.colorScheme.outline,
      BookingStatus.noShow => context.colorScheme.error,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(Icons.calendar_month_outlined,
            color: context.colorScheme.onPrimaryContainer, size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: booking.customerName, query: query),
      subtitle: Text(
        '${booking.serviceName} · ${DateFormatter.format(booking.startDatetime)}'
        '${booking.bookingRef != null ? ' · ${booking.bookingRef}' : ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.bodySmall,
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(booking.status.label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
      ),
      onTap: () {
        if (booking.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: booking.id!)),
          );
        }
      },
    );
  }
}

class _PurchaseBillTile extends StatelessWidget {
  const _PurchaseBillTile({required this.bill, required this.query});
  final PurchaseBill bill;
  final String query;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (bill.status) {
      PurchaseBillStatus.paid => Colors.green,
      PurchaseBillStatus.partiallyPaid => Colors.orange,
      PurchaseBillStatus.unpaid => context.colorScheme.error,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.secondaryContainer,
        child: Icon(Icons.inventory_2_outlined,
            color: context.colorScheme.onSecondaryContainer,
            size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: bill.vendorName, query: query),
      subtitle: Text(
        '${bill.billNo} · ${DateFormatter.format(bill.billDate)}'
        '${bill.vendorGstin != null ? ' · ${bill.vendorGstin}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(bill.total),
            style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600, fontFamily: 'RobotoMono'),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              bill.status.label,
              style: context.textTheme.labelSmall?.copyWith(
                  color: statusColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      onTap: () {
        if (bill.id != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PurchaseBillDetailScreen(billId: bill.id!),
          ));
        }
      },
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.party, required this.query});
  final Party party;
  final String query;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      party.partyType.label,
      if (party.phoneNumber != null && party.phoneNumber!.isNotEmpty) party.phoneNumber!,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Text(
          party.name.isNotEmpty ? party.name[0].toUpperCase() : '?',
          style: TextStyle(color: context.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
        ),
      ),
      title: _Highlight(text: party.name, query: query),
      subtitle: Text(subtitle, style: context.textTheme.bodySmall),
      trailing: party.totalTransactions > 0
          ? Text('${party.totalTransactions} txns',
              style: context.textTheme.labelSmall?.copyWith(color: context.colorScheme.outline))
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => Party360Screen(party: party)),
      ),
    );
  }
}

class _LoanTile extends StatelessWidget {
  const _LoanTile({required this.loan, required this.query});
  final Loan loan;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isBorrowed = loan.direction == LoanDirection.borrowed;
    final amountColor = isBorrowed ? colors.expense : colors.income;
    final dirLabel = isBorrowed ? 'Borrowed' : 'Lent';
    final statusColor = loan.isOverdue
        ? context.colorScheme.error
        : loan.isCleared
            ? Colors.green
            : Colors.orange;
    final statusLabel = loan.isOverdue
        ? 'Overdue'
        : loan.isCleared
            ? 'Cleared'
            : 'Active';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.primaryContainer,
        child: Icon(
          Icons.account_balance_wallet_outlined,
          color: context.colorScheme.onPrimaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: _Highlight(text: loan.lenderName, query: query),
      subtitle: Text(
        '$dirLabel · ${DateFormatter.format(loan.loanDate)}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(loan.pendingAmount),
            style: context.textTheme.titleSmall?.copyWith(
                color: amountColor, fontWeight: FontWeight.w600, fontFamily: 'RobotoMono'),
          ),
          Text(
            statusLabel,
            style: context.textTheme.labelSmall
                ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoansScreen()),
      ),
    );
  }
}

class _ChallanTile extends StatelessWidget {
  const _ChallanTile({required this.challan, required this.query});
  final DeliveryChallan challan;
  final String query;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (challan.status) {
      ChallanStatus.draft => context.colorScheme.outline,
      ChallanStatus.dispatched => Colors.orange,
      ChallanStatus.returned => context.colorScheme.primary,
      ChallanStatus.converted => Colors.blue,
      ChallanStatus.pendingNumber => context.colorScheme.outline,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.secondaryContainer,
        child: Icon(
          Icons.local_shipping_outlined,
          color: context.colorScheme.onSecondaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: _Highlight(text: challan.customerName, query: query),
      subtitle: Text(
        '${challan.challanNo} · ${DateFormatter.format(challan.challanDate)}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(challan.subtotal),
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, fontFamily: 'RobotoMono'),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              challan.status.name,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      onTap: () {
        if (challan.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => DeliveryChallanDetailScreen(challanId: challan.id!)),
          );
        }
      },
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({required this.item, required this.query});
  final RecurringTransaction item;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.kashColors;
    final isExpense = item.type == 'expense';
    final amountColor = isExpense ? colors.expense : colors.income;
    final prefix = isExpense ? '-' : '+';
    final freqLabel = item.frequency.name;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.tertiaryContainer,
        child: Icon(
          Icons.repeat_outlined,
          color: context.colorScheme.onTertiaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: _Highlight(text: item.partyName ?? item.category, query: query),
      subtitle: Text(
        '${item.category} · $freqLabel · Next ${DateFormatter.format(item.nextDate)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall,
      ),
      trailing: Text(
        '$prefix${CurrencyFormatter.format(item.amount)}',
        style: context.textTheme.titleSmall?.copyWith(
            color: amountColor, fontWeight: FontWeight.w600, fontFamily: 'RobotoMono'),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BillsAndPaymentsScreen()),
      ),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote, required this.query});
  final Quote quote;
  final String query;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (quote.status) {
      QuoteStatus.accepted => Colors.green,
      QuoteStatus.rejected => context.colorScheme.error,
      QuoteStatus.sent     => Colors.orange,
      QuoteStatus.draft    => context.colorScheme.outline,
      QuoteStatus.pendingNumber => context.colorScheme.outline,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CircleAvatar(
        backgroundColor: context.colorScheme.tertiaryContainer,
        child: Icon(Icons.request_quote_outlined,
            color: context.colorScheme.onTertiaryContainer,
            size: AppSpacing.iconMd),
      ),
      title: _Highlight(text: quote.customerName, query: query),
      subtitle: Text(
        '${quote.quoteNo} · ${DateFormatter.format(quote.createdAt)}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            CurrencyFormatter.format(quote.total),
            style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600, fontFamily: 'RobotoMono'),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              quote.status.label,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      onTap: () {
        if (quote.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => QuoteDetailScreen(quoteId: quote.id!)),
          );
        }
      },
    );
  }
}
