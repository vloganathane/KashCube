// ---------------------------------------------------------------------------
// Party360Screen — unified party screen (merged from PartyDetailScreen)
// ---------------------------------------------------------------------------
// Tabs:
//   Overview   — net outstanding, summary chips, contact actions, urgency flags
//   Activity   — all activity types with filter chips + lifecycle tags
//   Documents  — invoices/quotes/DCs/bookings + reminder nudge + reminder history
//   Deals      — BusinessFlowChain list (Q→I→T revenue leakage tracker)
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/contacts_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/lifecycle_classifier.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/credit.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/lifecycle_info.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/party.dart';
import '../../../data/models/party_financial_summary.dart';
import '../../../data/models/party_reminder.dart';
import '../../../data/models/quote.dart';
import '../../../data/models/scheduled_payment.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/party_statement_pdf_service.dart';
import '../../providers/booking_provider.dart';
import '../../providers/business_flow_provider.dart';
import '../../providers/credit_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/party_financial_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/party_reminder_provider.dart';
import '../../providers/scheduled_payment_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/staff_provider.dart';
import '../staff/staff_screen.dart';
import '../../widgets/flow_chain_tile.dart';
import '../../widgets/lifecycle_tag.dart';
import '../../widgets/party_form_sheet.dart';
import '../../widgets/vcard_qr_dialog.dart';
import '../bookings/booking_detail_screen.dart';
import '../invoices/delivery_challan_detail_screen.dart';
import '../invoices/invoice_detail_screen.dart';
import '../invoices/invoices_screen.dart';
import '../invoices/quote_detail_screen.dart';
import '../ledger/credits_screen.dart';
import '../loans/loans_screen.dart';
import '../transactions/add_edit_transaction_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _monthAbbr(int m) {
  const abbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return abbr[m];
}

String _shortDate(DateTime dt) => '${dt.day} ${_monthAbbr(dt.month)}';

String _fullDate(DateTime dt) =>
    '${dt.day} ${_monthAbbr(dt.month)} ${dt.year}';

String _fmtRelative(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'Today';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (d.year == yesterday.year &&
      d.month == yesterday.month &&
      d.day == yesterday.day) {
    return 'Yesterday';
  }
  return d.year == now.year ? _shortDate(d) : _fullDate(d);
}

String _compactAmt(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) {
    final s = v.toStringAsFixed(0);
    return s.length > 3
        ? '₹${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}'
        : '₹$s';
  }
  return '₹${v.toStringAsFixed(0)}';
}

// ---------------------------------------------------------------------------
// Unified history item model
// ---------------------------------------------------------------------------

sealed class PartyHistoryItem {
  DateTime get date;
}

class TransactionHistoryItem extends PartyHistoryItem {
  TransactionHistoryItem(this.transaction);
  final Transaction transaction;
  @override
  DateTime get date => transaction.date;
}

class InvoiceHistoryItem extends PartyHistoryItem {
  InvoiceHistoryItem(this.invoice);
  final Invoice invoice;
  @override
  DateTime get date => invoice.issueDate;
}

class QuoteHistoryItem extends PartyHistoryItem {
  QuoteHistoryItem(this.quote);
  final Quote quote;
  @override
  DateTime get date => quote.createdAt;
}

class DeliveryChallanHistoryItem extends PartyHistoryItem {
  DeliveryChallanHistoryItem(this.challan);
  final DeliveryChallan challan;
  @override
  DateTime get date => challan.challanDate;
}

class ScheduledPaymentHistoryItem extends PartyHistoryItem {
  ScheduledPaymentHistoryItem(this.payment);
  final ScheduledPayment payment;
  @override
  DateTime get date => payment.nextDate;
}

class BookingHistoryItem extends PartyHistoryItem {
  BookingHistoryItem(this.booking);
  final Booking booking;
  @override
  DateTime get date => booking.startDatetime;
}

class ReminderHistoryItem extends PartyHistoryItem {
  ReminderHistoryItem(this.reminder);
  final PartyReminder reminder;
  @override
  DateTime get date => reminder.sentAt;
}

class CreditHistoryItem extends PartyHistoryItem {
  CreditHistoryItem(this.credit);
  final Credit credit;
  @override
  DateTime get date => credit.creditDate;
}

// ---------------------------------------------------------------------------
// Filter enums
// ---------------------------------------------------------------------------

enum _ActivityFilter {
  all, transactions, invoices, quotes, dc, bookings, reminders, credits;

  String get label => switch (this) {
        all => 'All',
        transactions => 'Transactions',
        invoices => 'Invoices',
        quotes => 'Quotes',
        dc => 'DC',
        bookings => 'Bookings',
        reminders => 'Reminders',
        credits => 'Credits',
      };
}

enum _DocsFilter {
  all, invoices, quotes, dc, bookings;

  String get label => switch (this) {
        all => 'All',
        invoices => 'Invoices',
        quotes => 'Quotes',
        dc => 'DC',
        bookings => 'Bookings',
      };
}

// ---------------------------------------------------------------------------
// Provider — full history for a party (by name)
// ---------------------------------------------------------------------------

final partyHistoryProvider =
    FutureProvider.family<List<PartyHistoryItem>, String>((ref, partyName) async {
  final txnRepo = ref.read(transactionRepositoryProvider);
  final invoiceRepo = ref.read(invoiceRepositoryProvider);
  final quoteRepo = ref.read(quoteRepositoryProvider);
  final challanRepo = ref.read(deliveryChallanRepositoryProvider);
  final scheduledRepo = ref.read(scheduledPaymentRepositoryProvider);
  final bookingRepo = ref.read(bookingRepositoryProvider);
  final reminderRepo = ref.read(partyReminderRepositoryProvider);
  final creditRepo = ref.read(creditRepositoryProvider);

  final partiesAsync = ref.read(partiesProvider);
  final parties = partiesAsync.valueOrNull ?? [];
  final party = parties.cast<Party?>().firstWhere(
    (p) => p?.name == partyName,
    orElse: () => null,
  );

  final results = await Future.wait([
    txnRepo.getTransactionsByParty(partyName),
    invoiceRepo.getByCustomer(partyName),
    quoteRepo.getByCustomer(partyName),
    challanRepo.getByCustomer(partyName),
    scheduledRepo.getByParty(partyName),
    party?.id != null
        ? bookingRepo.getByCustomer(party!.id!)
        : Future.value(<Booking>[]),
    reminderRepo.getByParty(partyName),
    creditRepo.getByPartyName(partyName),
  ]);

  final items = <PartyHistoryItem>[
    ...(results[0] as List<Transaction>).map(TransactionHistoryItem.new),
    ...(results[1] as List<Invoice>).map(InvoiceHistoryItem.new),
    ...(results[2] as List<Quote>).map(QuoteHistoryItem.new),
    ...(results[3] as List<DeliveryChallan>).map(DeliveryChallanHistoryItem.new),
    ...(results[4] as List<ScheduledPayment>).map(ScheduledPaymentHistoryItem.new),
    ...(results[5] as List<Booking>).map(BookingHistoryItem.new),
    ...(results[6] as List<PartyReminder>).map(ReminderHistoryItem.new),
    ...(results[7] as List<Credit>).map(CreditHistoryItem.new),
  ];
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class Party360Screen extends ConsumerStatefulWidget {
  const Party360Screen({
    super.key,
    required this.party,
    this.initialTab = 0,
  });

  final Party party;

  /// 0 = Overview (default) · 1 = Activity · 2 = Documents · 3 = Deals
  final int initialTab;

  @override
  ConsumerState<Party360Screen> createState() => _Party360ScreenState();
}

class _Party360ScreenState extends ConsumerState<Party360Screen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Export consolidated party statement PDF ─────────────────────────────

  Future<void> _exportStatement(int partyId) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Generating statement…'), duration: Duration(seconds: 10)),
    );
    try {
      final results = await Future.wait([
        ref.read(invoiceRepositoryProvider).getByPartyId(partyId),
        ref.read(creditRepositoryProvider).getByCustomerId(partyId),
        ref.read(loanRepositoryProvider).getByLenderId(partyId),
      ]);
      final file = await PartyStatementPdfService.instance.generate(
        party: widget.party,
        invoices: results[0] as List<Invoice>,
        credits: results[1] as List<Credit>,
        loans: results[2] as List<Loan>,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Statement — ${widget.party.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
        existing: widget.party,
        onSave: (updated) => ref.read(partiesProvider.notifier).update(updated),
      ),
    );
  }

  void _showReminderSheet() {
    final historyValue = ref.read(partyHistoryProvider(widget.party.name));
    final unpaid = historyValue.valueOrNull
            ?.whereType<InvoiceHistoryItem>()
            .map((h) => h.invoice)
            .where((i) => i.status != InvoiceStatus.paid)
            .toList() ??
        [];
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SendReminderSheet(
        party: widget.party,
        unpaidInvoices: unpaid,
        onReminderSent: (txnId) =>
            ref.read(partiesProvider.notifier).markReminderSent(txnId),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final partyId = widget.party.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          if (partyId != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export Statement',
              onPressed: () => _exportStatement(partyId),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_outlined),
            tooltip: 'Share QR',
            onPressed: () => showVCardQrDialog(
              context,
              vcard: vCardFromParty(widget.party),
              displayName: widget.party.name,
              subtitle: PhoneUtils.formatDisplay(widget.party.phoneNumber,
                      dialCode: widget.party.dialCode ?? '91') ??
                  widget.party.email,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: _showEditSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Activity'),
            Tab(text: 'Documents'),
            Tab(text: 'Deals'),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        party: widget.party,
        onSendReminder: _showReminderSheet,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(party: widget.party),
          _ActivityTab(partyName: widget.party.name),
          _DocumentsTab(
            partyName: widget.party.name,
            party: widget.party,
            onSendReminder: _showReminderSheet,
          ),
          partyId != null
              ? _DealsTab(partyId: partyId)
              : const Center(child: Text('Save the party first to track deals.')),
        ],
      ),
    );
  }
}

// ===========================================================================
// Overview tab
// ===========================================================================

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partyId = party.id;
    if (partyId == null) {
      return const Center(child: Text('Party not saved yet.'));
    }

    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final summaryAsync = ref.watch(partyFinancialSummaryProvider(partyId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (summary) => ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _NetOutstandingCard(summary: summary, colors: colors),
          const SizedBox(height: AppSpacing.base),
          _SummaryChipRow(summary: summary),
          const SizedBox(height: AppSpacing.base),
          _ContactCard(party: party),
          const SizedBox(height: AppSpacing.sm),
          if (party.partyType == PartyType.staff)
            _PayrollCard(party: party),
          if (party.partyType == PartyType.staff)
            const SizedBox(height: AppSpacing.sm),
          if (summary.hasOverdueItem)
            _UrgencyBanner(
              label: 'Overdue items — tap Activity to view',
              color: colors.expense,
            ),
          if (summary.earliestDueDate != null &&
              !summary.hasOverdueItem &&
              summary.earliestDueDate!
                  .isBefore(DateTime.now().add(const Duration(days: 7))))
            _UrgencyBanner(
              label: 'Payment due ${_shortDate(summary.earliestDueDate!)}',
              color: colors.credit,
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Activity tab
// ===========================================================================

class _ActivityTab extends ConsumerStatefulWidget {
  const _ActivityTab({required this.partyName});

  final String partyName;

  @override
  ConsumerState<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<_ActivityTab> {
  _ActivityFilter _filter = _ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final historyAsync = ref.watch(partyHistoryProvider(widget.partyName));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final filtered = _applyFilter(items);
        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
          children: [
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: AppSpacing.sm),
              child: Row(
                children: _ActivityFilter.values.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Center(
                  child: Text(
                    _filter == _ActivityFilter.all
                        ? 'No activity with ${widget.partyName} yet.'
                        : 'No ${_filter.label.toLowerCase()} with ${widget.partyName} yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              ...filtered.map((item) => _ActivityItemTile(item: item, colors: colors, partyName: widget.partyName)),
          ],
        );
      },
    );
  }

  List<PartyHistoryItem> _applyFilter(List<PartyHistoryItem> items) =>
      switch (_filter) {
        _ActivityFilter.all => items,
        _ActivityFilter.transactions =>
          items.whereType<TransactionHistoryItem>().toList(),
        _ActivityFilter.invoices =>
          items.whereType<InvoiceHistoryItem>().toList(),
        _ActivityFilter.quotes =>
          items.whereType<QuoteHistoryItem>().toList(),
        _ActivityFilter.dc =>
          items.whereType<DeliveryChallanHistoryItem>().toList(),
        _ActivityFilter.bookings =>
          items.whereType<BookingHistoryItem>().toList(),
        _ActivityFilter.reminders =>
          items.whereType<ReminderHistoryItem>().toList(),
        _ActivityFilter.credits =>
          items.whereType<CreditHistoryItem>().toList(),
      };
}

class _ActivityItemTile extends StatelessWidget {
  const _ActivityItemTile({
    required this.item,
    required this.colors,
    required this.partyName,
  });

  final PartyHistoryItem item;
  final KashCubeColors colors;
  final String partyName;

  static LifecycleInfo? _lifecycle(PartyHistoryItem item) => switch (item) {
        InvoiceHistoryItem i => LifecycleClassifier.forInvoice(i.invoice),
        CreditHistoryItem c => LifecycleClassifier.forCredit(c.credit),
        ScheduledPaymentHistoryItem s => LifecycleClassifier.forBill(s.payment),
        BookingHistoryItem b => LifecycleClassifier.forBooking(b.booking),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final info = _lifecycle(item);
    final isStale = info?.isStale() ?? false;

    Widget tile = switch (item) {
      TransactionHistoryItem h => _TransactionTile(txn: h.transaction, colors: colors),
      InvoiceHistoryItem h => _InvoiceTile(
          invoice: h.invoice,
          colors: colors,
          lifecycleInfo: info,
          onTap: h.invoice.id != null
              ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => InvoiceDetailScreen(invoiceId: h.invoice.id!),
                  ))
              : null,
        ),
      QuoteHistoryItem h => _QuoteTile(
          quote: h.quote,
          colors: colors,
          onTap: h.quote.id != null
              ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => QuoteDetailScreen(quoteId: h.quote.id!),
                  ))
              : null,
        ),
      DeliveryChallanHistoryItem h => _ChallanTile(
          challan: h.challan,
          colors: colors,
          onTap: h.challan.id != null
              ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DeliveryChallanDetailScreen(
                        challanId: h.challan.id!),
                  ))
              : null,
        ),
      ScheduledPaymentHistoryItem h =>
        _ScheduledPaymentTile(payment: h.payment, colors: colors),
      BookingHistoryItem h => _BookingTile(
          booking: h.booking,
          colors: colors,
          lifecycleInfo: info,
          onTap: h.booking.id != null
              ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => BookingDetailScreen(bookingId: h.booking.id!),
                  ))
              : null,
        ),
      ReminderHistoryItem h => _ReminderHistoryTile(reminder: h.reminder),
      CreditHistoryItem h => _CreditHistoryTile(credit: h.credit, colors: colors),
    };

    if (isStale) {
      tile = DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFFFA000), width: 3)),
        ),
        child: tile,
      );
    }
    return tile;
  }
}

// ===========================================================================
// Documents tab
// ===========================================================================

class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({
    required this.partyName,
    required this.party,
    required this.onSendReminder,
  });

  final String partyName;
  final Party party;
  final VoidCallback onSendReminder;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  _DocsFilter _filter = _DocsFilter.all;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final historyAsync = ref.watch(partyHistoryProvider(widget.partyName));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final invoices =
            items.whereType<InvoiceHistoryItem>().map((h) => h.invoice).toList();
        final quotes =
            items.whereType<QuoteHistoryItem>().map((h) => h.quote).toList();
        final challans = items
            .whereType<DeliveryChallanHistoryItem>()
            .map((h) => h.challan)
            .toList();
        final bookings =
            items.whereType<BookingHistoryItem>().map((h) => h.booking).toList();
        final reminders = items
            .whereType<ReminderHistoryItem>()
            .map((h) => h.reminder)
            .toList();
        final credits =
            items.whereType<CreditHistoryItem>().map((h) => h.credit).toList();

        final unpaidInvoices = invoices
            .where((i) =>
                i.status != InvoiceStatus.draft &&
                i.status != InvoiceStatus.paid)
            .toList();
        final outstandingCredits = credits
            .where((c) => c.direction == CreditDirection.given && !c.isCleared)
            .toList();
        final creditsPendingTotal =
            outstandingCredits.fold(0.0, (s, c) => s + c.pendingAmount);
        final lastReminder = reminders.isEmpty ? null : reminders.first;
        final daysSinceLast = lastReminder == null
            ? null
            : DateTime.now().difference(lastReminder.sentAt).inDays;
        final showNudge = (unpaidInvoices.isNotEmpty || creditsPendingTotal > 0) &&
            (lastReminder == null || daysSinceLast! >= 7);

        final filteredDocs = _applyDocFilter(
            _filter, invoices, quotes, challans, bookings);

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
          children: [
            if (invoices.isNotEmpty)
              _OutstandingBalanceCard(invoices: invoices, colors: colors)
            else if (credits.isNotEmpty)
              _CreditBalanceCard(credits: credits, colors: colors),
            if (showNudge)
              _ReminderNudgeCard(
                unpaidCount: unpaidInvoices.length,
                creditsPendingTotal: creditsPendingTotal,
                totalOutstanding:
                    unpaidInvoices.fold(0.0, (s, i) => s + i.balanceDue) +
                        creditsPendingTotal,
                daysSinceLast: daysSinceLast,
                onSendTap: widget.onSendReminder,
              ),
            const Divider(height: 1),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: AppSpacing.sm),
              child: Row(
                children: _DocsFilter.values.map((f) {
                  final count = switch (f) {
                    _DocsFilter.all =>
                      invoices.length + quotes.length + challans.length + bookings.length,
                    _DocsFilter.invoices => invoices.length,
                    _DocsFilter.quotes => quotes.length,
                    _DocsFilter.dc => challans.length,
                    _DocsFilter.bookings => bookings.length,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text('${f.label}${count > 0 ? ' ($count)' : ''}'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            if (filteredDocs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Center(
                  child: Text(
                    'No ${_filter == _DocsFilter.all ? 'documents' : _filter.label.toLowerCase()} '
                    'for ${widget.partyName} yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              ...filteredDocs.map((item) => _buildDocTile(context, item, colors)),
            // Reminder history
            const Divider(
              height: AppSpacing.xl,
              indent: AppSpacing.base,
              endIndent: AppSpacing.base,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    reminders.isEmpty
                        ? 'Reminders Sent'
                        : 'Reminders Sent (${reminders.length})',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base, AppSpacing.xs, AppSpacing.base, AppSpacing.md),
                child: Text(
                  'No reminders sent yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              )
            else
              ...reminders.map((r) => _ReminderHistoryTile(reminder: r)),
          ],
        );
      },
    );
  }

  List<PartyHistoryItem> _applyDocFilter(
    _DocsFilter filter,
    List<Invoice> invoices,
    List<Quote> quotes,
    List<DeliveryChallan> challans,
    List<Booking> bookings,
  ) =>
      switch (filter) {
        _DocsFilter.all => [
            ...invoices.map<PartyHistoryItem>(InvoiceHistoryItem.new),
            ...quotes.map<PartyHistoryItem>(QuoteHistoryItem.new),
            ...challans.map<PartyHistoryItem>(DeliveryChallanHistoryItem.new),
            ...bookings.map<PartyHistoryItem>(BookingHistoryItem.new),
          ]..sort((a, b) => b.date.compareTo(a.date)),
        _DocsFilter.invoices =>
          invoices.map<PartyHistoryItem>(InvoiceHistoryItem.new).toList(),
        _DocsFilter.quotes =>
          quotes.map<PartyHistoryItem>(QuoteHistoryItem.new).toList(),
        _DocsFilter.dc =>
          challans.map<PartyHistoryItem>(DeliveryChallanHistoryItem.new).toList(),
        _DocsFilter.bookings =>
          bookings.map<PartyHistoryItem>(BookingHistoryItem.new).toList(),
      };

  Widget _buildDocTile(
      BuildContext context, PartyHistoryItem item, KashCubeColors colors) =>
      switch (item) {
        InvoiceHistoryItem h => _InvoiceTile(
            invoice: h.invoice,
            colors: colors,
            onTap: h.invoice.id != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) =>
                          InvoiceDetailScreen(invoiceId: h.invoice.id!),
                    ))
                : null,
          ),
        QuoteHistoryItem h => _QuoteTile(
            quote: h.quote,
            colors: colors,
            onTap: h.quote.id != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => QuoteDetailScreen(quoteId: h.quote.id!),
                    ))
                : null,
          ),
        DeliveryChallanHistoryItem h => _ChallanTile(
            challan: h.challan,
            colors: colors,
            onTap: h.challan.id != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DeliveryChallanDetailScreen(
                          challanId: h.challan.id!),
                    ))
                : null,
          ),
        BookingHistoryItem h => _BookingTile(
            booking: h.booking,
            colors: colors,
            onTap: h.booking.id != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) =>
                          BookingDetailScreen(bookingId: h.booking.id!),
                    ))
                : null,
          ),
        _ => const SizedBox.shrink(),
      };
}

// ===========================================================================
// Deals tab
// ===========================================================================

class _DealsTab extends ConsumerWidget {
  const _DealsTab({required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chainsAsync = ref.watch(businessFlowChainsProvider(partyId));

    return chainsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load deals: $e')),
      data: (chains) {
        if (chains.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 56, color: context.colorScheme.outline),
                const SizedBox(height: AppSpacing.base),
                Text('No deal chains yet',
                    style: context.textTheme.titleMedium
                        ?.copyWith(color: context.colorScheme.outline)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Create a quote, challan, or invoice to track deal flow.',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colorScheme.outline),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: chains.length,
          itemBuilder: (_, i) => FlowChainTile(
            chain: chains[i],
            onTap: chains[i].invoice != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => InvoiceDetailScreen(
                          invoiceId: chains[i].invoice!.id!),
                    ))
                : null,
          ),
        );
      },
    );
  }
}

// ===========================================================================
// Bottom action bar
// ===========================================================================

class _BottomBar extends ConsumerStatefulWidget {
  const _BottomBar({required this.party, required this.onSendReminder});

  final Party party;
  final VoidCallback onSendReminder;

  @override
  ConsumerState<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends ConsumerState<_BottomBar> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.notifications_outlined, size: 18),
                label: const Text('Send Reminder'),
                onPressed: widget.onSendReminder,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record Payment'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditTransactionScreen(
                        initialPartyName: widget.party.name),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMoreMenu(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('New Invoice'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvoicesScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('New Due (Udhar)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreditsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Overview widgets
// ===========================================================================

class _NetOutstandingCard extends StatelessWidget {
  const _NetOutstandingCard({required this.summary, required this.colors});

  final PartyFinancialSummary summary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isPositive = summary.netOutstanding >= 0;
    final labelColor = isPositive ? colors.income : colors.expense;
    final bgColor = isPositive
        ? colors.income.withAlpha(20)
        : colors.expense.withAlpha(20);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: labelColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPositive ? 'TO COLLECT' : 'TO PAY',
            style: context.textTheme.labelSmall?.copyWith(
              color: labelColor,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(summary.netOutstanding.abs()),
            style: context.textTheme.displaySmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (summary.hasOverdueItem) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.warning_amber, size: 14, color: colors.expense),
                const SizedBox(width: 4),
                Text('Has overdue items',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: colors.expense)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChipRow extends StatelessWidget {
  const _SummaryChipRow({required this.summary});

  final PartyFinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _SummaryChip(
            label: 'Invoices',
            count: summary.openInvoices,
            amount: summary.invoicesPending,
            icon: Icons.receipt_long_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoicesScreen()),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SummaryChip(
            label: 'Dues',
            count: summary.openDues,
            amount: summary.duesPending,
            icon: Icons.handshake_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreditsScreen()),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SummaryChip(
            label: 'Loans',
            count: summary.activeLoans,
            amount: summary.loansPending,
            icon: Icons.account_balance_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoansScreen()),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SummaryChip(
            label: 'Bookings',
            count: summary.activeBookings,
            amount: summary.bookingsPending,
            icon: Icons.calendar_month_outlined,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.amount,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final double amount;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && onTap != null;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: context.colorScheme.primary),
                const SizedBox(width: 4),
                Text(label,
                    style: context.textTheme.labelSmall
                        ?.copyWith(color: context.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              count > 0 ? CurrencyFormatter.formatCompact(amount) : '—',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: count > 0
                    ? context.colorScheme.primary
                    : context.colorScheme.outline,
              ),
            ),
            if (count > 0)
              Text('$count item${count > 1 ? 's' : ''}',
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: context.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

// ── Payroll card (shown when party type == staff) ─────────────────────────────

class _PayrollCard extends ConsumerWidget {
  const _PayrollCard({required this.party});
  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffProvider);

    return staffAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, st) => const SizedBox.shrink(),
      data: (staffList) {
        final staff = staffList
            .where((s) => s.partyId == party.id)
            .firstOrNull;
        if (staff == null) return const SizedBox.shrink();

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: context.colorScheme.primaryContainer,
              child: Icon(Icons.payments_outlined,
                  color: context.colorScheme.primary, size: 20),
            ),
            title: Text(
              '${CurrencyFormatter.format(staff.baseSalary)} / ${staff.salaryType.name}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              staff.designation != null
                  ? '${staff.designation}${staff.department != null ? ' · ${staff.department}' : ''}'
                  : staff.department ?? 'Staff',
              style: context.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const StaffScreen(),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Contact card ──────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    final hasContact = party.phoneNumber != null || party.email != null;
    final details = <MapEntry<IconData, String>>[
      if (party.phoneNumber != null)
        MapEntry(Icons.phone_outlined,
            '+${party.dialCode ?? '91'} ${party.phoneNumber!}'),
      if (party.email != null) MapEntry(Icons.email_outlined, party.email!),
      if (party.gstin != null)
        MapEntry(Icons.badge_outlined, 'GSTIN: ${party.gstin!}'),
      if (party.city != null)
        MapEntry(Icons.location_on_outlined,
            [party.city, party.state].whereType<String>().join(', ')),
    ];

    if (details.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...details.map((e) => Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(e.key,
                          size: 16,
                          color: context.colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text(e.value,
                              style: context.textTheme.bodySmall)),
                    ],
                  ),
                )),
            if (hasContact) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  if (party.phoneNumber != null) ...[
                    _ContactChip(
                      icon: Icons.phone_outlined,
                      label: 'Call',
                      onTap: () {
                        final uri = PhoneUtils.telUri(party.phoneNumber!,
                            dialCode: party.dialCode ?? '91');
                        if (uri != null) {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    _ContactChip(
                      icon: Icons.chat_outlined,
                      label: 'WhatsApp',
                      onTap: () {
                        final uri = PhoneUtils.waUri(party.phoneNumber!,
                            dialCode: party.dialCode ?? '91', message: 'Hi,');
                        if (uri != null) {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    _ContactChip(
                      icon: Icons.message_outlined,
                      label: 'SMS',
                      onTap: () {
                        final uri = PhoneUtils.smsUri(party.phoneNumber!,
                            dialCode: party.dialCode ?? '91', body: 'Hi,');
                        if (uri != null) {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                  if (party.email != null)
                    _ContactChip(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      onTap: () => launchUrl(
                        Uri.parse('mailto:${party.email}'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  _ContactChip(
                    icon: Icons.contact_page_outlined,
                    label: 'Save Contact',
                    onTap: () => _saveToContacts(context),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveToContacts(BuildContext context) async {
    try {
      final granted = await requestContactsRuntimePermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Contacts permission denied. Enable it in Settings to save contacts.',
              ),
            ),
          );
        }
        return;
      }
      
      final contact = Contact()
        ..name = Name(last: party.name)
        ..phones = [if (party.phoneNumber != null) Phone(party.phoneNumber!)]
        ..emails = [if (party.email != null) Email(party.email!)];
      await FlutterContacts.openExternalInsert(contact);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open contacts app.')),
        );
      }
    }
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );
}

class _UrgencyBanner extends StatelessWidget {
  const _UrgencyBanner({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: context.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Documents widgets
// ===========================================================================

class _OutstandingBalanceCard extends StatelessWidget {
  const _OutstandingBalanceCard(
      {required this.invoices, required this.colors});

  final List<Invoice> invoices;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final totalInvoiced = invoices.fold(0.0, (s, i) => s + i.total);
    final totalPaid = invoices.fold(0.0, (s, i) => s + i.paidAmount);
    final outstanding = invoices
        .where((i) => i.status != InvoiceStatus.paid)
        .fold(0.0, (s, i) => s + i.balanceDue);
    final overdue = invoices
        .where((i) =>
            i.status != InvoiceStatus.paid &&
            i.dueDate != null &&
            i.dueDate!.isBefore(now))
        .fold(0.0, (s, i) => s + i.balanceDue);

    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outstanding Balance',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _BalanceStat(
                label: 'Invoiced',
                value: _compactAmt(totalInvoiced),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              _BalanceStat(
                  label: 'Paid',
                  value: _compactAmt(totalPaid),
                  color: colors.income),
              _BalanceStat(
                label: 'Balance',
                value: _compactAmt(outstanding),
                color: outstanding > 0 ? colors.expense : colors.income,
              ),
              if (overdue > 0)
                _BalanceStat(
                    label: 'Overdue',
                    value: _compactAmt(overdue),
                    color: colors.overdue),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditBalanceCard extends StatelessWidget {
  const _CreditBalanceCard({required this.credits, required this.colors});

  final List<Credit> credits;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    if (credits.isEmpty) return const SizedBox.shrink();
    final given = credits.where((c) => c.direction == CreditDirection.given);
    final received =
        credits.where((c) => c.direction == CreditDirection.received);
    final totalGiven = given.fold(0.0, (s, c) => s + c.pendingAmount);
    final totalReceived = received.fold(0.0, (s, c) => s + c.pendingAmount);
    final net = totalGiven - totalReceived;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Credit Balance',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (totalGiven > 0)
                _BalanceStat(
                    label: 'You Lent',
                    value: _compactAmt(totalGiven),
                    color: colors.credit),
              if (totalReceived > 0)
                _BalanceStat(
                    label: 'You Owe',
                    value: _compactAmt(totalReceived),
                    color: colors.expense),
              _BalanceStat(
                label: 'Net',
                value: (net >= 0 ? '+' : '') + _compactAmt(net.abs()),
                color: net > 0
                    ? colors.credit
                    : net < 0
                        ? colors.expense
                        : colors.income,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  const _BalanceStat(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

class _ReminderNudgeCard extends StatelessWidget {
  const _ReminderNudgeCard({
    required this.unpaidCount,
    required this.creditsPendingTotal,
    required this.totalOutstanding,
    required this.daysSinceLast,
    required this.onSendTap,
  });

  final int unpaidCount;
  final double creditsPendingTotal;
  final double totalOutstanding;
  final int? daysSinceLast;
  final VoidCallback onSendTap;

  String _buildTitle() {
    if (unpaidCount > 0 && creditsPendingTotal > 0) {
      return '$unpaidCount invoice${unpaidCount == 1 ? '' : 's'} + dues pending · ${_compactAmt(totalOutstanding)}';
    } else if (unpaidCount > 0) {
      return '$unpaidCount unpaid invoice${unpaidCount == 1 ? '' : 's'} · ${_compactAmt(totalOutstanding)}';
    } else {
      return 'Credit balance · ${_compactAmt(creditsPendingTotal)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lastLine = daysSinceLast == null
        ? 'No reminder sent yet'
        : 'Last reminder $daysSinceLast day${daysSinceLast == 1 ? '' : 's'} ago';

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.30),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: cs.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_buildTitle(),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onErrorContainer)),
                Text(lastLine,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onErrorContainer.withValues(alpha: 0.7))),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: onSendTap,
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.send_outlined, size: 14),
            label: const Text('Remind', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// History tile widgets
// ===========================================================================

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn, required this.colors});

  final Transaction txn;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final amountColor = txn.isIncome ? colors.income : colors.expense;
    final prefix = txn.isIncome ? '+' : '-';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child: Icon(_typeIcon(txn.type), size: 16, color: amountColor),
      ),
      title: Text(txn.category,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(_fullDate(txn.date),
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Text('$prefix${_compactAmt(txn.amount)}',
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13, color: amountColor)),
    );
  }

  IconData _typeIcon(TransactionType type) => switch (type) {
        TransactionType.income => Icons.arrow_downward,
        TransactionType.expense => Icons.arrow_upward,
        TransactionType.lent => Icons.call_made,
        TransactionType.borrowed => Icons.call_received,
        TransactionType.receivedBack => Icons.undo,
        TransactionType.paidBack => Icons.redo,
        TransactionType.transfer => Icons.swap_horiz,
        TransactionType.invested => Icons.trending_up,
        TransactionType.redeemed => Icons.trending_down,
      };
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.colors,
    this.lifecycleInfo,
    this.onTap,
  });

  final Invoice invoice;
  final KashCubeColors colors;
  final LifecycleInfo? lifecycleInfo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => colors.income,
      InvoiceStatus.partiallyPaid => Colors.orange,
      InvoiceStatus.overdue => colors.overdue,
      _ => colors.expense,
    };

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(Icons.receipt_long_outlined, size: 16, color: statusColor),
      ),
      title: Text(invoice.invoiceNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_fullDate(invoice.issueDate)} • ${invoice.status.label}',
              style: Theme.of(context).textTheme.labelSmall),
          if (lifecycleInfo != null) ...[
            const SizedBox(height: 2),
            LifecycleTag(info: lifecycleInfo!),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('₹${_raw(invoice.total)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: statusColor)),
          if (invoice.status == InvoiceStatus.partiallyPaid)
            Text('₹${_raw(invoice.paidAmount)} paid',
                style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile(
      {required this.quote, required this.colors, this.onTap});

  final Quote quote;
  final KashCubeColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (quote.status) {
      QuoteStatus.accepted => colors.income,
      QuoteStatus.rejected => colors.expense,
      _ => const Color(0xFF00838F),
    };

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(Icons.request_quote_outlined, size: 16, color: statusColor),
      ),
      title: Text(quote.quoteNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('${_fullDate(quote.createdAt)} • ${quote.status.label}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Text('₹${_raw(quote.total)}',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: statusColor)),
    );
  }
}

class _ChallanTile extends StatelessWidget {
  const _ChallanTile(
      {required this.challan, required this.colors, this.onTap});

  final DeliveryChallan challan;
  final KashCubeColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (challan.status) {
      ChallanStatus.dispatched => const Color(0xFF0D47A1),
      ChallanStatus.returned => colors.credit,
      ChallanStatus.converted => colors.income,
      ChallanStatus.draft => Theme.of(context).colorScheme.outline,
      ChallanStatus.pendingNumber => Theme.of(context).colorScheme.outline,
    };

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child:
            Icon(Icons.local_shipping_outlined, size: 16, color: statusColor),
      ),
      title: Text(challan.challanNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('${_fullDate(challan.challanDate)} • ${challan.status.label}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Text(
        '${challan.items.length} item${challan.items.length == 1 ? '' : 's'}',
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor),
      ),
    );
  }
}

class _ScheduledPaymentTile extends StatelessWidget {
  const _ScheduledPaymentTile(
      {required this.payment, required this.colors});

  final ScheduledPayment payment;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isIncome = payment.type == 'income';
    final amountColor = isIncome ? colors.income : colors.expense;
    final frequencyLabel = payment.frequency?.label ?? 'One-time';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child:
            Icon(Icons.event_repeat_outlined, size: 16, color: amountColor),
      ),
      title: Text(payment.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
          '${_fullDate(payment.nextDate)} • $frequencyLabel',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('₹${_raw(payment.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: amountColor)),
          if (payment.isOverdue)
            Icon(Icons.warning_outlined, size: 12, color: colors.overdue),
        ],
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({
    required this.booking,
    required this.colors,
    this.lifecycleInfo,
    this.onTap,
  });

  final Booking booking;
  final KashCubeColors colors;
  final LifecycleInfo? lifecycleInfo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status) {
      BookingStatus.pending => Colors.orange,
      BookingStatus.confirmed => Colors.green,
      BookingStatus.completed => Colors.grey,
      BookingStatus.cancelled => Colors.grey,
      BookingStatus.noShow => Colors.red,
    };
    final statusLabel = switch (booking.status) {
      BookingStatus.pending => 'Pending',
      BookingStatus.confirmed => 'Confirmed',
      BookingStatus.completed => 'Completed',
      BookingStatus.cancelled => 'Cancelled',
      BookingStatus.noShow => 'No-show',
    };

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child:
            Icon(Icons.calendar_month_outlined, size: 16, color: statusColor),
      ),
      title: Text(booking.serviceName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_fullDate(booking.startDatetime)} • $statusLabel',
              style: Theme.of(context).textTheme.labelSmall),
          if (lifecycleInfo != null) ...[
            const SizedBox(height: 2),
            LifecycleTag(info: lifecycleInfo!),
          ],
        ],
      ),
      trailing: Text('₹${_raw(booking.totalAmount)}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class _CreditHistoryTile extends StatelessWidget {
  const _CreditHistoryTile({required this.credit, required this.colors});

  final Credit credit;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isGiven = credit.direction == CreditDirection.given;
    final directionColor = isGiven ? colors.credit : colors.expense;
    final displayAmount =
        credit.pendingAmount > 0 ? credit.pendingAmount : credit.totalAmount;
    final statusLabel = credit.isCleared
        ? 'Cleared'
        : credit.isOverdue
            ? 'Overdue'
            : 'Pending';
    final statusColor = credit.isCleared
        ? colors.income
        : credit.isOverdue
            ? colors.overdue
            : colors.credit;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: directionColor.withValues(alpha: 0.12),
        child: Icon(
            isGiven ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 16,
            color: directionColor),
      ),
      title: Text(isGiven ? 'Lent to party' : 'Borrowed from party',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(_fmtRelative(credit.creditDate),
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${isGiven ? '' : '-'}${_compactAmt(displayAmount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: directionColor)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ReminderHistoryTile extends StatelessWidget {
  const _ReminderHistoryTile({required this.reminder});

  final PartyReminder reminder;

  @override
  Widget build(BuildContext context) {
    final channelIcon = switch (reminder.channel) {
      ReminderChannel.whatsapp => Icons.chat_outlined,
      ReminderChannel.sms => Icons.message_outlined,
      ReminderChannel.email => Icons.email_outlined,
    };
    final channelColor = switch (reminder.channel) {
      ReminderChannel.whatsapp => const Color(0xFF25D366),
      ReminderChannel.sms => const Color(0xFF1976D2),
      ReminderChannel.email => const Color(0xFFD32F2F),
    };

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: channelColor.withValues(alpha: 0.12),
        child: Icon(channelIcon, size: 16, color: channelColor),
      ),
      title: Text('${reminder.channel.label} Reminder',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reminder.invoiceCount > 0)
            Text(
              '${reminder.invoiceCount} invoice${reminder.invoiceCount == 1 ? '' : 's'}'
              '${reminder.totalOutstanding != null ? ' · ${_compactAmt(reminder.totalOutstanding!)}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          Text(
            reminder.message.split('\n').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_fmtRelative(reminder.sentAt),
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline)),
          Text(reminder.channel.label,
              style: TextStyle(fontSize: 10, color: channelColor)),
        ],
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _raw(double v) {
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) {
    final s = v.toStringAsFixed(0);
    return s.length > 3
        ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}'
        : s;
  }
  return v.toStringAsFixed(0);
}

// ===========================================================================
// Send Reminder bottom sheet
// ===========================================================================

class _SendReminderSheet extends ConsumerStatefulWidget {
  const _SendReminderSheet({
    required this.party,
    required this.unpaidInvoices,
    required this.onReminderSent,
  });

  final Party party;
  final List<Invoice> unpaidInvoices;
  final void Function(int txnId) onReminderSent;

  @override
  ConsumerState<_SendReminderSheet> createState() => _SendReminderSheetState();
}

class _SendReminderSheetState extends ConsumerState<_SendReminderSheet> {
  late TextEditingController _msgController;

  @override
  void initState() {
    super.initState();
    _msgController = TextEditingController(text: _buildDefaultMessage());
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  String _buildDefaultMessage() {
    final name = widget.party.name;
    final invoices = widget.unpaidInvoices;
    if (invoices.isEmpty) {
      return 'Hi $name, this is a friendly reminder regarding the outstanding '
          'amount. Please let me know when you can settle. Thank you!';
    }
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('Hi $name, here is a summary of your outstanding invoices:');
    buf.writeln();
    for (final inv in invoices) {
      final isOverdue = inv.dueDate != null &&
          inv.dueDate!.isBefore(now) &&
          inv.status != InvoiceStatus.paid;
      buf.write('• ${inv.invoiceNo} — ${_compactAmt(inv.balanceDue)}');
      if (inv.dueDate != null) {
        buf.write(' (Due: ${_fullDate(inv.dueDate!)})');
      }
      if (isOverdue) buf.write(' ⚠️ OVERDUE');
      if (inv.status == InvoiceStatus.partiallyPaid) {
        buf.write(
            ' [${_compactAmt(inv.paidAmount)} paid, ${_compactAmt(inv.balanceDue)} due]');
      }
      buf.writeln();
    }
    final total = invoices.fold(0.0, (s, i) => s + i.balanceDue);
    buf
      ..writeln()
      ..writeln('Total Outstanding: ${_compactAmt(total)}')
      ..writeln()
      ..write('Kindly settle at your earliest convenience. Thank you!');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final phone = widget.party.phoneNumber;
    final dialCode = widget.party.dialCode ?? '91';
    final email = widget.party.email;
    final now = DateTime.now();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.unpaidInvoices.isEmpty ? 0.55 : 0.80,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.xl),
          children: [
            Row(
              children: [
                Text('Send Reminder',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.unpaidInvoices.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${widget.unpaidInvoices.length} unpaid '
                          'invoice${widget.unpaidInvoices.length == 1 ? '' : 's'}',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...widget.unpaidInvoices.map((inv) {
                      final isOverdue = inv.dueDate != null &&
                          inv.dueDate!.isBefore(now) &&
                          inv.status != InvoiceStatus.paid;
                      final statusColor = isOverdue
                          ? colors.overdue
                          : inv.status == InvoiceStatus.partiallyPaid
                              ? Colors.orange
                              : colors.expense;
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(inv.invoiceNo,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  if (inv.dueDate != null)
                                    Text(
                                      'Due: ${_fullDate(inv.dueDate!)}${isOverdue ? '  ⚠️ OVERDUE' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: isOverdue
                                                  ? colors.overdue
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .outline),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_compactAmt(inv.balanceDue),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor)),
                                if (inv.status ==
                                    InvoiceStatus.partiallyPaid)
                                  Text(
                                    '${_compactAmt(inv.paidAmount)} paid',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Outstanding',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          _compactAmt(widget.unpaidInvoices
                              .fold(0.0, (s, i) => s + i.balanceDue)),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: colors.expense),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _msgController,
              maxLines: null,
              minLines: 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Message',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  tooltip: 'Reset to default',
                  onPressed: () => setState(
                      () => _msgController.text = _buildDefaultMessage()),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Send via:',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (phone != null) ...[
                  _ChannelButton(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _send(
                      'https://wa.me/$dialCode$phone?text='
                      '${Uri.encodeComponent(_msgController.text)}',
                      phone,
                      'whatsapp',
                    ),
                  ),
                  _ChannelButton(
                    icon: Icons.message_outlined,
                    label: 'SMS',
                    color: const Color(0xFF1976D2),
                    onTap: () => _send(
                      'sms:+$dialCode$phone?body='
                      '${Uri.encodeComponent(_msgController.text)}',
                      phone,
                      'sms',
                    ),
                  ),
                ],
                if (email != null)
                  _ChannelButton(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    color: const Color(0xFFD32F2F),
                    onTap: () => _send(
                      'mailto:$email?subject=Payment+Reminder&body='
                      '${Uri.encodeComponent(_msgController.text)}',
                      null,
                      'email',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Opening your messaging app. The message is pre-filled.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(String url, String? phone, String channel) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open app for this action.')),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    final reminder = PartyReminder(
      partyName: widget.party.name,
      channel: ReminderChannel.fromString(channel),
      message: _msgController.text,
      invoiceRefs: widget.unpaidInvoices.map((i) => i.invoiceNo).join(','),
      invoiceCount: widget.unpaidInvoices.length,
      totalOutstanding:
          widget.unpaidInvoices.fold<double>(0.0, (s, i) => s + i.balanceDue),
      sentAt: DateTime.now(),
    );
    await ref.read(partyReminderRepositoryProvider).insert(reminder);
    ref.invalidate(partyHistoryProvider(widget.party.name));

    final txns = await ref
        .read(transactionRepositoryProvider)
        .getTransactionsByParty(widget.party.name);
    for (final t in txns) {
      if (t.isLending && t.id != null) widget.onReminderSent(t.id!);
    }
    if (mounted) Navigator.pop(context);
  }
}

class _ChannelButton extends StatelessWidget {
  const _ChannelButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: color),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
