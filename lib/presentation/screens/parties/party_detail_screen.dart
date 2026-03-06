import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/party.dart';
import '../../../data/models/quote.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/scheduled_payment.dart';
import '../../../data/models/booking.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/scheduled_payment_provider.dart';
import '../../providers/booking_provider.dart';
import '../../widgets/party_form_sheet.dart';
import '../../widgets/vcard_qr_dialog.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../../core/utils/phone_utils.dart';
import '../invoices/invoice_detail_screen.dart';
import '../invoices/quote_detail_screen.dart';
import '../invoices/delivery_challan_detail_screen.dart';
import '../bookings/booking_detail_screen.dart';

// ---------------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------------

String _monthAbbr(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return months[month - 1];
}

// ---------------------------------------------------------------------------
// Unified History Item — wraps different activity types
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

// ---------------------------------------------------------------------------
// Activity filter enum (Option A)
// ---------------------------------------------------------------------------

enum _ActivityFilter {
  all,
  transactions,
  invoices,
  quotes,
  dc,
  bookings;

  String get label => switch (this) {
        all => 'All',
        transactions => 'Transactions',
        invoices => 'Invoices',
        quotes => 'Quotes',
        dc => 'DC',
        bookings => 'Bookings',
      };
}

enum _DocsFilter {
  all,
  invoices,
  quotes,
  dc,
  bookings;

  String get label => switch (this) {
        all => 'All',
        invoices => 'Invoices',
        quotes => 'Quotes',
        dc => 'DC',
        bookings => 'Bookings',
      };
}

// ---------------------------------------------------------------------------
// FutureProvider — loads unified history for a given party name
// ---------------------------------------------------------------------------

final _partyHistoryFutureProvider =
    FutureProvider.family<List<PartyHistoryItem>, String>((ref, partyName) async {
  final txnRepo = ref.read(transactionRepositoryProvider);
  final invoiceRepo = ref.read(invoiceRepositoryProvider);
  final quoteRepo = ref.read(quoteRepositoryProvider);
  final challanRepo = ref.read(deliveryChallanRepositoryProvider);
  final scheduledRepo = ref.read(scheduledPaymentRepositoryProvider);
  final bookingRepo = ref.read(bookingRepositoryProvider);

  // Get party by name to get ID for bookings
  final partiesAsync = ref.read(partiesProvider);
  final parties = partiesAsync.valueOrNull ?? [];
  final party = parties.cast<Party?>().firstWhere(
    (p) => p?.name == partyName,
    orElse: () => null,
  );

  // Load all types in parallel
  final results = await Future.wait([
    txnRepo.getTransactionsByParty(partyName),
    invoiceRepo.getByCustomer(partyName),
    quoteRepo.getByCustomer(partyName),
    challanRepo.getByCustomer(partyName),
    scheduledRepo.getByParty(partyName),
    party?.id != null ? bookingRepo.getByCustomer(party!.id!) : Future.value(<Booking>[]),
  ]);

  final transactions = results[0] as List<Transaction>;
  final invoices = results[1] as List<Invoice>;
  final quotes = results[2] as List<Quote>;
  final challans = results[3] as List<DeliveryChallan>;
  final scheduled = results[4] as List<ScheduledPayment>;
  final bookings = results[5] as List<Booking>;

  // Wrap in unified type
  final List<PartyHistoryItem> items = [
    ...transactions.map((t) => TransactionHistoryItem(t)),
    ...invoices.map((i) => InvoiceHistoryItem(i)),
    ...quotes.map((q) => QuoteHistoryItem(q)),
    ...challans.map((c) => DeliveryChallanHistoryItem(c)),
    ...scheduled.map((s) => ScheduledPaymentHistoryItem(s)),
    ...bookings.map((b) => BookingHistoryItem(b)),
  ];

  // Sort by date descending (newest first)
  items.sort((a, b) => b.date.compareTo(a.date));

  return items;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PartyDetailScreen extends ConsumerStatefulWidget {
  const PartyDetailScreen({super.key, required this.party, this.initialTab = 0});

  final Party party;
  /// 0 = Activity (default), 1 = Documents
  final int initialTab;

  @override
  ConsumerState<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends ConsumerState<PartyDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  _ActivityFilter _activityFilter = _ActivityFilter.all;
  _DocsFilter _docsFilter = _DocsFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final historyAsync =
        ref.watch(_partyHistoryFutureProvider(widget.party.name));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Activity'),
            Tab(text: 'Documents'),
          ],
        ),
        actions: [
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
            onPressed: () => _showEditSheet(context),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildActivityTab(context, items, colors),
              _buildDocumentsTab(context, items, colors),
            ],
          );
        },
      ),
      floatingActionButton: widget.party.phoneNumber != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send Reminder'),
              onPressed: () => _showReminderSheet(context),
            )
          : null,
    );
  }

  // ── Activity tab (Option A) ────────────────────────────────────────────────
  Widget _buildActivityTab(
      BuildContext context, List<PartyHistoryItem> items, KashCubeColors colors) {
    final transactions = items.whereType<TransactionHistoryItem>()
        .map((h) => h.transaction)
        .toList();
    final txnCount = transactions.length;
    final txnTotal = transactions.fold<double>(0, (s, t) => s + t.amount);

    // Apply filter
    final filtered = switch (_activityFilter) {
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
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
      children: [
        _HeaderCard(party: widget.party, colors: colors),
        _SummaryRow(
          party: widget.party,
          colors: colors,
          transactionCount: txnCount,
          transactionTotal: txnTotal,
        ),
        if (widget.party.phoneNumber != null || widget.party.email != null)
          _ContactActions(party: widget.party),
        const Divider(height: 1),

        // ── Filter chips row (Option A) ───────────────────────────────
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
                  selected: _activityFilter == f,
                  onSelected: (_) => setState(() => _activityFilter = f),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),

        // ── Item list ─────────────────────────────────────────────────
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Center(
              child: Text(
                _activityFilter == _ActivityFilter.all
                    ? 'No activity with ${widget.party.name} yet.'
                    : 'No ${_activityFilter.label.toLowerCase()} with ${widget.party.name} yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          Column(
            children: filtered.map((item) => _buildHistoryTile(item, colors)).toList(),
          ),
      ],
    );
  }

  // ── Documents tab (Option B) ───────────────────────────────────────────────
  Widget _buildDocumentsTab(
      BuildContext context, List<PartyHistoryItem> items, KashCubeColors colors) {
    final invoices = items.whereType<InvoiceHistoryItem>().map((h) => h.invoice).toList();
    final quotes = items.whereType<QuoteHistoryItem>().map((h) => h.quote).toList();
    final challans =
        items.whereType<DeliveryChallanHistoryItem>().map((h) => h.challan).toList();
    final bookings = items.whereType<BookingHistoryItem>().map((h) => h.booking).toList();

    // Filtered items for documents tab
    final filteredDocs = switch (_docsFilter) {
      _DocsFilter.all => [
          ...invoices.map<PartyHistoryItem>(InvoiceHistoryItem.new),
          ...quotes.map<PartyHistoryItem>(QuoteHistoryItem.new),
          ...challans.map<PartyHistoryItem>(DeliveryChallanHistoryItem.new),
          ...bookings.map<PartyHistoryItem>(BookingHistoryItem.new),
        ]..sort((a, b) => b.date.compareTo(a.date)),
      _DocsFilter.invoices => invoices.map<PartyHistoryItem>(InvoiceHistoryItem.new).toList(),
      _DocsFilter.quotes => quotes.map<PartyHistoryItem>(QuoteHistoryItem.new).toList(),
      _DocsFilter.dc => challans.map<PartyHistoryItem>(DeliveryChallanHistoryItem.new).toList(),
      _DocsFilter.bookings => bookings.map<PartyHistoryItem>(BookingHistoryItem.new).toList(),
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
      children: [
        // ── Outstanding Balance card ───────────────────────────────────
        _OutstandingBalanceCard(invoices: invoices, colors: colors),

        const Divider(height: 1),

        // ── Filter chips ──────────────────────────────────────────────
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
                  selected: _docsFilter == f,
                  onSelected: (_) => setState(() => _docsFilter = f),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),

        // ── Document list ─────────────────────────────────────────────
        if (filteredDocs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Center(
              child: Text(
                'No ${_docsFilter == _DocsFilter.all ? 'documents' : _docsFilter.label.toLowerCase()} for ${widget.party.name} yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          Column(
            children: filteredDocs
                .map((item) => _buildHistoryTile(item, colors))
                .toList(),
          ),
      ],
    );
  }

  // ── Build a single tile based on type ─────────────────────────────────────
  Widget _buildHistoryTile(PartyHistoryItem item, KashCubeColors colors) {
    return switch (item) {
      TransactionHistoryItem() => _TransactionTile(
          txn: item.transaction,
          colors: colors,
        ),
      InvoiceHistoryItem() => _InvoiceTile(
          invoice: item.invoice,
          colors: colors,
          onTap: item.invoice.id != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          InvoiceDetailScreen(invoiceId: item.invoice.id!),
                    ),
                  )
              : null,
        ),
      QuoteHistoryItem() => _QuoteTile(
          quote: item.quote,
          colors: colors,
          onTap: item.quote.id != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          QuoteDetailScreen(quoteId: item.quote.id!),
                    ),
                  )
              : null,
        ),
      DeliveryChallanHistoryItem() => _ChallanTile(
          challan: item.challan,
          colors: colors,
          onTap: item.challan.id != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DeliveryChallanDetailScreen(challanId: item.challan.id!),
                    ),
                  )
              : null,
        ),
      ScheduledPaymentHistoryItem() => _ScheduledPaymentTile(
          payment: item.payment,
          colors: colors,
        ),
      BookingHistoryItem() => _BookingTile(
          booking: item.booking,
          colors: colors,
          onTap: item.booking.id != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BookingDetailScreen(bookingId: item.booking.id!),
                    ),
                  )
              : null,
        ),
    };
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
        existing: widget.party,
        onSave: (updated) =>
            ref.read(partiesProvider.notifier).update(updated),
      ),
    );
  }

  void _showReminderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SendReminderSheet(
        party: widget.party,
        onReminderSent: (transactionId) {
          ref
              .read(partiesProvider.notifier)
              .markReminderSent(transactionId);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outstanding Balance Card (Option B)
// ---------------------------------------------------------------------------

class _OutstandingBalanceCard extends StatelessWidget {
  const _OutstandingBalanceCard({
    required this.invoices,
    required this.colors,
  });

  final List<Invoice> invoices;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
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

    if (invoices.isEmpty) {
      return const SizedBox.shrink();
    }

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
                value: _fmt(totalInvoiced),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              _BalanceStat(
                label: 'Paid',
                value: _fmt(totalPaid),
                color: colors.income,
              ),
              _BalanceStat(
                label: 'Balance',
                value: _fmt(outstanding),
                color: outstanding > 0 ? colors.expense : colors.income,
              ),
              if (overdue > 0)
                _BalanceStat(
                  label: 'Overdue',
                  value: _fmt(overdue),
                  color: colors.overdue,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '₹${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return '₹$s';
    }
    return '₹${v.toStringAsFixed(0)}';
  }
}

class _BalanceStat extends StatelessWidget {
  const _BalanceStat({
    required this.label,
    required this.value,
    required this.color,
  });

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
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color)),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.party, required this.colors});

  final Party party;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(party.partyType, colors);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: typeColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: typeColor.withValues(alpha: 0.2),
            child: Text(
              party.name.isNotEmpty
                  ? party.name[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: typeColor),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(party.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                _InfoRow(
                  icon: Icons.label_outline,
                  text: party.partyType.label,
                  color: typeColor,
                ),
                if (party.phoneNumber != null)
                  _InfoRow(
                      icon: Icons.phone_outlined,
                      text: '+${party.dialCode ?? '91'} ${party.phoneNumber!}'),
                if (party.email != null)
                  _InfoRow(
                      icon: Icons.email_outlined, text: party.email!),
                if (party.gstin != null)
                  _InfoRow(
                      icon: Icons.receipt_long_outlined,
                      text: party.gstin!),
                if (party.formattedAddress != null)
                  _InfoRow(
                      icon: Icons.location_on_outlined,
                      text: party.formattedAddress!),
                if (party.notes != null)
                  _InfoRow(
                      icon: Icons.notes_outlined, text: party.notes!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(PartyType type, KashCubeColors colors) {
    switch (type) {
      case PartyType.personal:
        return colors.investment;
      case PartyType.customer:
        return colors.income;
      case PartyType.vendor:
        return colors.expense;
      case PartyType.lender:
        return colors.credit;
      case PartyType.borrower:
        return colors.overdue;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: effectiveColor)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary row
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.party,
    required this.colors,
    required this.transactionCount,
    required this.transactionTotal,
  });

  final Party party;
  final KashCubeColors colors;
  final int transactionCount;
  final double transactionTotal;

  @override
  Widget build(BuildContext context) {
    final netBalance =
        party.totalCreditGiven - party.totalCreditReceived;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _StatChip(
            label: 'Transactions',
            value: '$transactionCount',
            icon: Icons.receipt_outlined,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatChip(
            label: 'Total',
            value: _inr(transactionTotal),
            icon: Icons.currency_rupee,
          ),
          if (netBalance != 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _StatChip(
              label: netBalance > 0 ? 'You lent' : 'You owe',
              value: _inr(netBalance.abs()),
              icon: netBalance > 0
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              color: netBalance > 0 ? colors.credit : colors.overdue,
            ),
          ],
        ],
      ),
    );
  }

  String _inr(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '₹${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return '₹$s';
    }
    return '₹${v.toStringAsFixed(0)}';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: c)),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact action buttons
// ---------------------------------------------------------------------------

class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          if (party.phoneNumber != null) ...[
            _ActionButton(
              icon: Icons.phone_outlined,
              label: 'Call',
              onTap: () => _launch(
                  PhoneUtils.telUri(party.phoneNumber, dialCode: party.dialCode ?? '91').toString()),
            ),
            _ActionButton(
              icon: Icons.message_outlined,
              label: 'SMS',
              onTap: () => _launch(
                  PhoneUtils.smsUri(party.phoneNumber, dialCode: party.dialCode ?? '91', body: 'Hi,').toString()),
            ),
            _ActionButton(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              onTap: () => _launch(
                  PhoneUtils.waUri(party.phoneNumber, dialCode: party.dialCode ?? '91', message: 'Hi,').toString()),
            ),
          ],
          if (party.email != null)
            _ActionButton(
              icon: Icons.email_outlined,
              label: 'Email',
              onTap: () => _launch('mailto:${party.email}'),
            ),          _ActionButton(
            icon: Icons.contact_page_outlined,
            label: 'Save to Contacts',
            onTap: () => _saveToContacts(context),
          ),        ],
      ),
    );
  }

  void _launch(String url) {
    final uri = Uri.parse(url);
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _saveToContacts(BuildContext context) async {
    try {
      final contact = Contact()
        ..name = Name(last: party.name)
        ..phones = [
          if (party.phoneNumber != null) Phone(party.phoneNumber!)
        ]
        ..emails = [
          if (party.email != null) Email(party.email!)
        ];
      await FlutterContacts.openExternalInsert(contact);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open contacts app.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction tile (compact)
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn, required this.colors});

  final Transaction txn;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isIn = txn.isIncome;
    final amountColor = isIn ? colors.income : colors.expense;
    final prefix = isIn ? '+' : '-';
    final dateStr =
        '${txn.date.day} ${_monthAbbr(txn.date.month)} ${txn.date.year}';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child: Icon(
          _typeIcon(txn.type),
          size: 16,
          color: amountColor,
        ),
      ),
      title: Text(txn.category,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(dateStr,
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$prefix₹${_fmt(txn.amount)}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: amountColor),
          ),
          if (txn.reminderSentAt != null)
            Icon(Icons.notifications_active_outlined,
                size: 12,
                color: colors.credit),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  IconData _typeIcon(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.arrow_downward;
      case TransactionType.expense:
        return Icons.arrow_upward;
      case TransactionType.lent:
        return Icons.call_made;
      case TransactionType.borrowed:
        return Icons.call_received;
      case TransactionType.receivedBack:
        return Icons.undo;
      case TransactionType.paidBack:
        return Icons.redo;
      case TransactionType.transfer:
        return Icons.swap_horiz;
      case TransactionType.invested:
        return Icons.trending_up;
      case TransactionType.redeemed:
        return Icons.trending_down;
    }
  }

  String _monthAbbr(int m) {
    const abbr = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return abbr[m];
  }
}

// ---------------------------------------------------------------------------
// Invoice tile (compact)
// ---------------------------------------------------------------------------

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.colors, this.onTap});

  final Invoice invoice;
  final KashCubeColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => colors.income,
      InvoiceStatus.partiallyPaid => Colors.orange,
      InvoiceStatus.overdue => colors.overdue,
      _ => colors.expense,
    };
    final dateStr =
        '${invoice.issueDate.day} ${_monthAbbr(invoice.issueDate.month)} ${invoice.issueDate.year}';

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.receipt_long_outlined,
          size: 16,
          color: statusColor,
        ),
      ),
      title: Text(invoice.invoiceNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('$dateStr • ${invoice.status.label}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${_fmt(invoice.total)}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: statusColor),
          ),
          if (invoice.status == InvoiceStatus.partiallyPaid)
            Text(
              '₹${_fmt(invoice.paidAmount)} paid',
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  String _monthAbbr(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
}

// ---------------------------------------------------------------------------
// Quote tile (compact)
// ---------------------------------------------------------------------------

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote, required this.colors, this.onTap});

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
    final dateStr =
        '${quote.createdAt.day} ${_monthAbbr(quote.createdAt.month)} ${quote.createdAt.year}';

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.request_quote_outlined,
          size: 16,
          color: statusColor,
        ),
      ),
      title: Text(quote.quoteNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('$dateStr • ${quote.status.label}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Text(
        '₹${_fmt(quote.total)}',
        style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13, color: statusColor),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  String _monthAbbr(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
}

// ---------------------------------------------------------------------------
// Delivery Challan tile (compact)
// ---------------------------------------------------------------------------

class _ChallanTile extends StatelessWidget {
  const _ChallanTile({required this.challan, required this.colors, this.onTap});

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
    };
    final dateStr =
        '${challan.challanDate.day} ${_monthAbbr(challan.challanDate.month)} ${challan.challanDate.year}';
    final itemCount = challan.items.length;

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.local_shipping_outlined,
          size: 16,
          color: statusColor,
        ),
      ),
      title: Text(challan.challanNo,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('$dateStr • ${challan.status.label}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Text(
        '$itemCount item${itemCount == 1 ? '' : 's'}',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: statusColor),
      ),
    );
  }

  String _monthAbbr(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
}
// Scheduled Payment tile (compact)
// ---------------------------------------------------------------------------

class _ScheduledPaymentTile extends StatelessWidget {
  const _ScheduledPaymentTile({required this.payment, required this.colors});

  final ScheduledPayment payment;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isIncome = payment.type == 'income';
    final amountColor = isIncome ? colors.income : colors.expense;
    final dateStr =
        '${payment.nextDate.day} ${_monthAbbr(payment.nextDate.month)} ${payment.nextDate.year}';
    final frequencyLabel = payment.frequency?.label ?? 'One-time';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.event_repeat_outlined,
          size: 16,
          color: amountColor,
        ),
      ),
      title: Text(payment.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('$dateStr • $frequencyLabel',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${_fmt(payment.amount)}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: amountColor),
          ),
          if (payment.isOverdue)
            Icon(Icons.warning_outlined,
                size: 12, color: colors.overdue),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  String _monthAbbr(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
}

// ---------------------------------------------------------------------------
// Send Reminder bottom sheet
// ---------------------------------------------------------------------------

class _SendReminderSheet extends ConsumerStatefulWidget {
  const _SendReminderSheet(
      {required this.party, required this.onReminderSent});

  final Party party;
  final void Function(int transactionId) onReminderSent;

  @override
  ConsumerState<_SendReminderSheet> createState() =>
      _SendReminderSheetState();
}

class _SendReminderSheetState extends ConsumerState<_SendReminderSheet> {
  String _customMessage = '';

  @override
  void initState() {
    super.initState();
    final name = widget.party.name;
    _customMessage = 'Hi $name, this is a friendly reminder regarding '
        'the outstanding amount. Please let me know when you can settle. '
        'Thank you!';
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.party.phoneNumber;
    final email = widget.party.email;
    final encodedMsg = Uri.encodeComponent(_customMessage);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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

          // ── Message editor ────────────────────────────────────────────
          TextField(
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _customMessage = v),
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: _customMessage,
                selection: TextSelection.collapsed(
                    offset: _customMessage.length),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Send via:',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),

          // ── Channel buttons ───────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (phone != null) ...[
                _ReminderChannelButton(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _send(
                    'https://wa.me/91$phone?text=$encodedMsg',
                    phone,
                  ),
                ),
                _ReminderChannelButton(
                  icon: Icons.message_outlined,
                  label: 'SMS',
                  color: const Color(0xFF1976D2),
                  onTap: () => _send(
                    'sms:+91$phone?body=$encodedMsg',
                    phone,
                  ),
                ),
              ],
              if (email != null)
                _ReminderChannelButton(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  color: const Color(0xFFD32F2F),
                  onTap: () => _send(
                    'mailto:$email?subject=Payment+Reminder&body=$encodedMsg',
                    null,
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
                ?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String url, String? phone) async {
    final uri = Uri.parse(url);
    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open app for this action.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    // Mark reminder sent on all lending transactions with this party
    final txns = await ref
        .read(transactionRepositoryProvider)
        .getTransactionsByParty(widget.party.name);
    for (final t in txns) {
      if (t.isLending && t.id != null) {
        widget.onReminderSent(t.id!);
      }
    }
    if (mounted) Navigator.pop(context);
  }
}

class _ReminderChannelButton extends StatelessWidget {
  const _ReminderChannelButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ── Booking Tile ──────────────────────────────────────────────────────────────

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, required this.colors, this.onTap});

  final Booking booking;
  final KashCubeColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(booking.status);
    final dateStr =
        '${booking.startDatetime.day} ${_monthAbbr(booking.startDatetime.month)} ${booking.startDatetime.year}';

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(
          Icons.calendar_month_outlined,
          size: 16,
          color: statusColor,
        ),
      ),
      title: Text(booking.serviceName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('$dateStr • ${_statusLabel(booking.status)}',
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₹${_fmt(booking.totalAmount)}',
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
          if (booking.status == BookingStatus.noShow)
            Icon(Icons.person_off_outlined,
                size: 12,
                color: colors.overdue),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.confirmed:
        return Colors.green;
      case BookingStatus.completed:
        return Colors.grey;
      case BookingStatus.cancelled:
        return Colors.grey;
      case BookingStatus.noShow:
        return Colors.red;
    }
  }

  String _statusLabel(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.noShow:
        return 'No-show';
    }
  }
}
