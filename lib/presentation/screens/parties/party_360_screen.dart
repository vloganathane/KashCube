// ---------------------------------------------------------------------------
// Party360Screen — P2.1 + P2.2
// ---------------------------------------------------------------------------
// A unified financial overview for a single party. Answers:
//   "How much does this person owe me / I owe them, and what's the history?"
//
// Tabs:
//   Overview — header + summary chips + urgency flags
//   Activity — merged timeline (Invoices · Dues · Loans · Transactions)
//   Deals    — BusinessFlowChain list (implemented in P2.10)
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/lifecycle_classifier.dart';
import '../../../data/models/lifecycle_info.dart';
import '../../widgets/lifecycle_tag.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/credit.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/party.dart';
import '../../../data/models/party_financial_summary.dart';
import '../../../data/models/transaction.dart';
import '../../../data/services/party_statement_pdf_service.dart';
import '../../providers/booking_provider.dart';
import '../../providers/credit_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/party_financial_provider.dart';
import '../../providers/business_flow_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/flow_chain_tile.dart';
import '../../widgets/party_form_sheet.dart';
import '../invoices/invoice_detail_screen.dart';
import '../invoices/invoices_screen.dart';
import '../ledger/credits_screen.dart';
import '../loans/loans_screen.dart';
import '../transactions/add_edit_transaction_screen.dart';

// ---------------------------------------------------------------------------
// Local item model — unified activity timeline entry
// ---------------------------------------------------------------------------

sealed class _P360Item {
  DateTime get date;
  String get title;
  String get subtitle;
  double? get amount;
  bool get isInflow;
  IconData get icon;
}

class _InvoiceItem extends _P360Item {
  _InvoiceItem(this.invoice);
  final Invoice invoice;

  @override
  DateTime get date => invoice.issueDate;
  @override
  String get title => 'Invoice ${invoice.invoiceNo}';
  @override
  String get subtitle => invoice.status.label;
  @override
  double? get amount => invoice.balanceDue > 0 ? invoice.balanceDue : invoice.total;
  @override
  bool get isInflow => true;
  @override
  IconData get icon => Icons.receipt_long_outlined;
}

class _CreditItem extends _P360Item {
  _CreditItem(this.credit);
  final Credit credit;

  @override
  DateTime get date => credit.creditDate;
  @override
  String get title => credit.isGiven ? 'Due from party' : 'Due to party';
  @override
  String get subtitle =>
      credit.isCleared ? 'Cleared' : 'Pending${credit.dueDate != null ? " · Due ${_shortDate(credit.dueDate!)}" : ""}';
  @override
  double? get amount => credit.pendingAmount;
  @override
  bool get isInflow => credit.isGiven;
  @override
  IconData get icon => Icons.handshake_outlined;
}

class _LoanItem extends _P360Item {
  _LoanItem(this.loan);
  final Loan loan;

  @override
  DateTime get date => loan.loanDate;
  @override
  String get title => loan.isLent ? 'Loan lent' : 'Loan borrowed';
  @override
  String get subtitle =>
      loan.isCleared ? 'Cleared' : 'Pending${loan.nextEmiDate != null ? " · EMI ${_shortDate(loan.nextEmiDate!)}" : ""}';
  @override
  double? get amount => loan.pendingAmount;
  @override
  bool get isInflow => loan.isLent;
  @override
  IconData get icon => Icons.account_balance_outlined;
}

class _TransactionItem extends _P360Item {
  _TransactionItem(this.transaction);
  final Transaction transaction;

  @override
  DateTime get date => transaction.date;
  @override
  String get title => transaction.category;
  @override
  String get subtitle => transaction.notes ?? (transaction.isIncome ? 'Income' : 'Expense');
  @override
  double? get amount => transaction.amount;
  @override
  bool get isInflow => transaction.isIncome;
  @override
  IconData get icon =>
      transaction.isIncome ? Icons.arrow_downward : Icons.arrow_upward;
}

class _BookingItem extends _P360Item {
  _BookingItem(this.booking);
  final Booking booking;

  @override
  DateTime get date => booking.startDatetime;
  @override
  String get title => booking.serviceName;
  @override
  String get subtitle => booking.status.name;
  @override
  double? get amount =>
      (booking.totalAmount - booking.paidAmount).clamp(0, double.infinity) > 0
          ? booking.totalAmount - booking.paidAmount
          : booking.totalAmount;
  @override
  bool get isInflow => true;
  @override
  IconData get icon => Icons.calendar_month_outlined;
}

// ---------------------------------------------------------------------------
// Activity provider — loads merged timeline for a party (by id)
// ---------------------------------------------------------------------------

final _party360ActivityProvider =
    FutureProvider.family<List<_P360Item>, int>((ref, partyId) async {
  final invoiceRepo = ref.read(invoiceRepositoryProvider);
  final creditRepo = ref.read(creditRepositoryProvider);
  final loanRepo = ref.read(loanRepositoryProvider);
  final txnRepo = ref.read(transactionRepositoryProvider);
  final bookingRepo = ref.read(bookingRepositoryProvider);

  // We need party name for reminders — read from partyFinancialSummaryProvider
  // but since that may be loading we read repos directly here.
  // All ID-based methods (P1.2) are used except reminders which stays name-based.
  // Reminders are fetched via partyFinancialSummaryProvider which already resolved name.
  final results = await Future.wait([
    invoiceRepo.getByPartyId(partyId),         // 0
    creditRepo.getByCustomerId(partyId),        // 1
    loanRepo.getByLenderId(partyId),           // 2
    txnRepo.getByPartyId(partyId),             // 3
    bookingRepo.getByPartyId(partyId),         // 4
  ]);

  final invoices = results[0] as List<Invoice>;
  final credits = results[1] as List<Credit>;
  final loans = results[2] as List<Loan>;
  final transactions = results[3] as List<Transaction>;
  final bookings = results[4] as List<Booking>;

  final items = <_P360Item>[
    ...invoices.map(_InvoiceItem.new),
    ...credits.map(_CreditItem.new),
    ...loans.map(_LoanItem.new),
    ...transactions.map(_TransactionItem.new),
    ...bookings.map(_BookingItem.new),
  ];

  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _shortDate(DateTime dt) =>
    '${dt.day} ${const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month]}';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class Party360Screen extends ConsumerStatefulWidget {
  const Party360Screen({super.key, required this.party});

  final Party party;

  @override
  ConsumerState<Party360Screen> createState() => _Party360ScreenState();
}

class _Party360ScreenState extends ConsumerState<Party360Screen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Export a consolidated party statement PDF and share it.
  Future<void> _exportStatement(BuildContext context, int partyId) async {
    final party = widget.party;

    // Show loading snackbar
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating statement…'), duration: Duration(seconds: 10)),
    );

    try {
      // Fetch data in parallel
      final results = await Future.wait([
        ref.read(invoiceRepositoryProvider).getByPartyId(partyId),
        ref.read(creditRepositoryProvider).getByCustomerId(partyId),
        ref.read(loanRepositoryProvider).getByLenderId(partyId),
      ]);

      final invoices = results[0] as List<Invoice>;
      final credits  = results[1] as List<Credit>;
      final loans    = results[2] as List<Loan>;

      final file = await PartyStatementPdfService.instance.generate(
        party: party,
        invoices: invoices,
        credits: credits,
        loans: loans,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Statement — ${party.name}',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final partyId = widget.party.id;
    if (partyId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.party.name)),
        body: const Center(child: Text('Party not saved yet.')),
      );
    }

    final summaryAsync = ref.watch(partyFinancialSummaryProvider(partyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export Statement',
            onPressed: () => _exportStatement(context, partyId),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => PartyFormSheet(
              existing: widget.party,
              onSave: (_) {},
            ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Activity'),
            Tab(text: 'Deals'),
          ],
        ),
      ),
      bottomNavigationBar: _BottomActionBar(party: widget.party),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summary) => TabBarView(
          controller: _tabController,
          children: [
            _OverviewTab(party: widget.party, summary: summary),
            _ActivityTab(partyId: partyId),
            _DealsTab(partyId: partyId),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.party, required this.summary});

  final Party party;
  final PartyFinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        // ── Net outstanding card ────────────────────────────────────────────
        _NetOutstandingCard(summary: summary, colors: colors),
        const SizedBox(height: AppSpacing.base),

        // ── Module summary chips ────────────────────────────────────────────
        _SummaryChipRow(summary: summary),
        const SizedBox(height: AppSpacing.base),

        // ── Party contact info ──────────────────────────────────────────────
        _ContactCard(party: party),
        const SizedBox(height: AppSpacing.lg),

        // ── Urgency flags ───────────────────────────────────────────────────
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
            label:
                'Payment due ${_shortDate(summary.earliestDueDate!)}',
            color: colors.credit,
          ),
      ],
    );
  }
}

class _NetOutstandingCard extends StatelessWidget {
  const _NetOutstandingCard(
      {required this.summary, required this.colors});

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
                Text(
                  'Has overdue items',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: colors.expense),
                ),
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
                Icon(icon, size: 14,
                    color: context.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurface,
                  ),
                ),
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
              Text(
                '$count item${count > 1 ? 's' : ''}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    final details = <MapEntry<IconData, String>>[
      if (party.phoneNumber != null)
        MapEntry(Icons.phone_outlined, party.phoneNumber!),
      if (party.email != null)
        MapEntry(Icons.email_outlined, party.email!),
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
          children: details
              .map((e) => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Icon(e.key,
                            size: 16,
                            color: context.colorScheme.onSurfaceVariant),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            e.value,
                            style: context.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
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
              style:
                  context.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity tab
// ---------------------------------------------------------------------------

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(_party360ActivityProvider(partyId));

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load activity: $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Text('No activity recorded for this party yet.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, i) => _ActivityTile(item: items[i]),
        );
      },
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final _P360Item item;

  static LifecycleInfo? _computeLifecycle(_P360Item item) => switch (item) {
        _InvoiceItem i    => LifecycleClassifier.forInvoice(i.invoice),
        _CreditItem c     => LifecycleClassifier.forCredit(c.credit),
        _LoanItem l       => LifecycleClassifier.forLoan(l.loan),
        _BookingItem b    => LifecycleClassifier.forBooking(b.booking),
        _TransactionItem _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final amountColor = item.isInflow ? colors.income : colors.expense;
    final lifecycleInfo = _computeLifecycle(item);
    final isStale = lifecycleInfo?.isStale() ?? false;

    Widget tile = ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: context.colorScheme.surfaceContainerHighest,
        child: Icon(item.icon, size: 18,
            color: context.colorScheme.primary),
      ),
      title: Text(item.title,
          style: context.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_shortDate(item.date)} · ${item.subtitle}',
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colorScheme.outline),
          ),
          if (lifecycleInfo != null) ...[  
            const SizedBox(height: 2),
            LifecycleTag(info: lifecycleInfo),
          ],
        ],
      ),
      trailing: item.amount != null
          ? Text(
              CurrencyFormatter.format(item.amount!),
              style: context.textTheme.bodyMedium?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      onTap: () => _handleTap(context, item),
    );

    if (isStale) {
      tile = DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0xFFFFA000), width: 3),
          ),
        ),
        child: tile,
      );
    }

    return tile;
  }

  void _handleTap(BuildContext context, _P360Item item) {
    if (item is _InvoiceItem) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              InvoiceDetailScreen(invoiceId: item.invoice.id!),
        ),
      );
    }
    // Credits → CreditsScreen; Loans, Bookings, Transactions open detail screens
    // Additional tap handlers can be added per module
  }
}

// ---------------------------------------------------------------------------
// Deals tab — P2.10 wired to businessFlowChainsProvider
// ---------------------------------------------------------------------------

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
                Text(
                  'No deal chains yet',
                  style: context.textTheme.titleMedium
                      ?.copyWith(color: context.colorScheme.outline),
                ),
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
                ? () => Navigator.of(context).push(MaterialPageRoute(
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

// ---------------------------------------------------------------------------
// Bottom action bar
// ---------------------------------------------------------------------------

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.party});

  final Party party;

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
                onPressed: () => _showComingSoon(context, 'Send Reminder'),
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
                      initialPartyName: party.name,
                    ),
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
                _showComingSoon(context, 'New Invoice');
              },
            ),
            ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('New Due (Udhar)'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoon(context, 'New Due');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming soon')),
    );
  }
}
