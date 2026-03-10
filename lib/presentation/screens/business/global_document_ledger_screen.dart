import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/party.dart';
import '../../../data/models/quote.dart';
import '../../providers/booking_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../parties/party_360_screen.dart';
import '../search/search_screen.dart';

// ---------------------------------------------------------------------------
// Sort and filter enums
// ---------------------------------------------------------------------------

enum _LedgerSort {
  recent,
  highestBalance,
  alphabetical;

  String get label => switch (this) {
        recent => 'Recent',
        highestBalance => 'Highest Balance',
        alphabetical => 'A–Z',
      };
}

enum _LedgerFilter {
  all,
  hasBalance;

  String get label => switch (this) {
        all => 'All',
        hasBalance => 'Has Balance',
      };
}

// ---------------------------------------------------------------------------
// Party summary data class
// ---------------------------------------------------------------------------

class _PartySummary {
  _PartySummary({
    required this.party,
    required this.invoices,
    required this.quotes,
    required this.challans,
    required this.bookings,
  });

  final Party party;
  final List<Invoice> invoices;
  final List<Quote> quotes;
  final List<DeliveryChallan> challans;
  final List<Booking> bookings;

  int get docCount =>
      invoices.length + quotes.length + challans.length + bookings.length;

  double get outstanding => invoices
      .where((i) => i.status != InvoiceStatus.paid)
      .fold(0.0, (s, i) => s + i.balanceDue);

  double get overdue {
    final now = DateTime.now();
    return invoices
        .where((i) =>
            i.status != InvoiceStatus.paid &&
            i.dueDate != null &&
            i.dueDate!.isBefore(now))
        .fold(0.0, (s, i) => s + i.balanceDue);
  }

  DateTime? get mostRecentDate {
    final dates = <DateTime>[
      ...invoices.map((i) => i.issueDate),
      ...quotes.map((q) => q.createdAt),
      ...challans.map((c) => c.challanDate),
      ...bookings.map((b) => b.startDatetime),
    ];
    if (dates.isEmpty) return null;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GlobalDocumentLedgerScreen extends ConsumerStatefulWidget {
  const GlobalDocumentLedgerScreen({super.key});

  @override
  ConsumerState<GlobalDocumentLedgerScreen> createState() =>
      _GlobalDocumentLedgerScreenState();
}

class _GlobalDocumentLedgerScreenState
    extends ConsumerState<GlobalDocumentLedgerScreen> {
  _LedgerSort _sort = _LedgerSort.recent;
  _LedgerFilter _filter = _LedgerFilter.all;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;

    final partiesAsync = ref.watch(partiesProvider);
    final invoicesAsync = ref.watch(invoicesProvider);
    final quotesAsync = ref.watch(quotesProvider);
    final challansAsync = ref.watch(challansProvider);
    final bookingsAsync = ref.watch(bookingsProvider);

    final isLoading = partiesAsync.isLoading ||
        invoicesAsync.isLoading ||
        quotesAsync.isLoading ||
        challansAsync.isLoading ||
        bookingsAsync.isLoading;

    final parties = partiesAsync.valueOrNull ?? <Party>[];
    final invoices = invoicesAsync.valueOrNull ?? <Invoice>[];
    final quotes = quotesAsync.valueOrNull ?? <Quote>[];
    final challans = challansAsync.valueOrNull ?? <DeliveryChallan>[];
    final bookings = bookingsAsync.valueOrNull ?? <Booking>[];

    // Group documents by customerName → party
    final summaries = _buildSummaries(
      parties: parties,
      invoices: invoices,
      quotes: quotes,
      challans: challans,
      bookings: bookings,
    );

    // Apply filter
    final filtered = switch (_filter) {
      _LedgerFilter.all => summaries,
      _LedgerFilter.hasBalance =>
        summaries.where((s) => s.outstanding > 0).toList(),
    };

    // Apply sort
    final sorted = List<_PartySummary>.from(filtered);
    switch (_sort) {
      case _LedgerSort.recent:
        sorted.sort((a, b) {
          final da = a.mostRecentDate;
          final db = b.mostRecentDate;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case _LedgerSort.highestBalance:
        sorted.sort((a, b) => b.outstanding.compareTo(a.outstanding));
      case _LedgerSort.alphabetical:
        sorted.sort((a, b) => a.party.name.compareTo(b.party.name));
    }

    // Header stats
    final totalOutstanding =
        sorted.fold(0.0, (s, p) => s + p.outstanding);
    final partiesWithBalance =
        sorted.where((p) => p.outstanding > 0).length;
    final openInvoices = invoices
        .where((i) =>
            i.status == InvoiceStatus.sent ||
            i.status == InvoiceStatus.overdue ||
            i.status == InvoiceStatus.partiallyPaid)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Document Ledger'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search parties',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SearchScreen(initialFilter: SearchFilter.parties),
              ),
            ),
          ),
          PopupMenuButton<_LedgerSort>(
            icon: const Icon(Icons.sort_outlined),
            tooltip: 'Sort',
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => _LedgerSort.values
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          if (_sort == s)
                            const Icon(Icons.check, size: 16)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: AppSpacing.sm),
                          Text(s.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Header summary ─────────────────────────────────────────
                _HeaderSummary(
                  partyCount: sorted.length,
                  openInvoices: openInvoices,
                  totalOutstanding: totalOutstanding,
                  partiesWithBalance: partiesWithBalance,
                  colors: colors,
                ),

                // ── Filter chips ───────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm),
                  child: Row(
                    children: _LedgerFilter.values.map((f) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(right: AppSpacing.sm),
                        child: FilterChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) =>
                              setState(() => _filter = f),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const Divider(height: 1),

                // ── Party list ─────────────────────────────────────────────
                Expanded(
                  child: sorted.isEmpty
                      ? Center(
                          child: Text(
                            _filter == _LedgerFilter.hasBalance
                                ? 'No parties with outstanding balance.'
                                : 'No parties with documents yet.',
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(
                              bottom: AppSpacing.xxxl),
                          itemCount: sorted.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) => _PartySummaryTile(
                            summary: sorted[i],
                            colors: colors,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  List<_PartySummary> _buildSummaries({
    required List<Party> parties,
    required List<Invoice> invoices,
    required List<Quote> quotes,
    required List<DeliveryChallan> challans,
    required List<Booking> bookings,
  }) {
    // Build a name → party map for quick lookup
    final partyMap = <String, Party>{
      for (final p in parties) p.name: p,
    };

    // Collect all unique customer names that appear in any document
    final allNames = <String>{
      ...invoices.map((i) => i.customerName),
      ...quotes.map((q) => q.customerName),
      ...challans.map((c) => c.customerName),
      ...bookings.map((b) => b.customerName),
    };

    final results = <_PartySummary>[];
    for (final name in allNames) {
      final party = partyMap[name];
      if (party == null) continue; // skip orphaned doc names

      results.add(_PartySummary(
        party: party,
        invoices: invoices.where((i) => i.customerName == name).toList(),
        quotes: quotes.where((q) => q.customerName == name).toList(),
        challans: challans.where((c) => c.customerName == name).toList(),
        bookings: bookings.where((b) => b.customerName == name).toList(),
      ));
    }
    return results;
  }
}

// ---------------------------------------------------------------------------
// Header Summary
// ---------------------------------------------------------------------------

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({
    required this.partyCount,
    required this.openInvoices,
    required this.totalOutstanding,
    required this.partiesWithBalance,
    required this.colors,
  });

  final int partyCount;
  final int openInvoices;
  final double totalOutstanding;
  final int partiesWithBalance;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          _HeaderStat(
            label: 'Parties',
            value: '$partyCount',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          _HeaderStat(
            label: 'Open invoices',
            value: '$openInvoices',
            color: colors.expense,
          ),
          _HeaderStat(
            label: 'Outstanding',
            value: _fmt(totalOutstanding),
            color: totalOutstanding > 0 ? colors.overdue : colors.income,
          ),
          _HeaderStat(
            label: 'With balance',
            value: '$partiesWithBalance',
            color: partiesWithBalance > 0 ? colors.credit : colors.income,
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

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
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
                      color:
                          Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Party Summary Tile
// ---------------------------------------------------------------------------

class _PartySummaryTile extends StatelessWidget {
  const _PartySummaryTile({
    required this.summary,
    required this.colors,
  });

  final _PartySummary summary;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final party = summary.party;
    final outstanding = summary.outstanding;
    final overdue = summary.overdue;
    final hasBalance = outstanding > 0;
    final balanceColor = overdue > 0
        ? colors.overdue
        : hasBalance
            ? colors.expense
            : colors.income;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context)
            .colorScheme
            .primaryContainer,
        child: Text(
          party.name.isNotEmpty ? party.name[0].toUpperCase() : '?',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
      ),
      title: Text(party.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: _DocCountRow(summary: summary),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasBalance)
            Text(
              _fmt(outstanding),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: balanceColor),
            )
          else
            Text('All settled',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.income)),
          if (overdue > 0)
            Text(
              '${_fmt(overdue)} overdue',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.overdue),
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              Party360Screen(party: party, initialTab: 2),
        ),
      ),
    );
  }

  String _fmt(double v) {
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

class _DocCountRow extends StatelessWidget {
  const _DocCountRow({required this.summary});

  final _PartySummary summary;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (summary.invoices.isNotEmpty) {
      parts.add(
          '${summary.invoices.length} Invoice${summary.invoices.length == 1 ? '' : 's'}');
    }
    if (summary.quotes.isNotEmpty) {
      parts.add(
          '${summary.quotes.length} Quote${summary.quotes.length == 1 ? '' : 's'}');
    }
    if (summary.challans.isNotEmpty) {
      parts.add('${summary.challans.length} DC');
    }
    if (summary.bookings.isNotEmpty) {
      parts.add(
          '${summary.bookings.length} Booking${summary.bookings.length == 1 ? '' : 's'}');
    }
    return Text(
      parts.isEmpty ? 'No documents' : parts.join(' · '),
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
