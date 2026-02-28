import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/transaction.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../providers/booking_provider.dart';
import '../../providers/transaction_provider.dart';
import '../bookings/booking_detail_screen.dart';
import '../ledger/ledger_screen.dart';
import '../transactions/transaction_detail_screen.dart';

/// Global search across transactions and ledger entries.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search transactions, ledger, parties...',
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: AppSpacing.iconSm),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: _query.length < 2
          ? _buildHint(context)
          : _SearchResults(query: _query),
    );
  }

  Widget _buildHint(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Type at least 2 characters to search',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays combined search results from transactions and ledger entries.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final ledgerAsync = ref.watch(ledgerSummariesProvider);
    final bookingsAsync = ref.watch(bookingsProvider);

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (transactions) {
        final q = query.toLowerCase();

        // Filter transactions
        final matchedTxns = transactions.where((t) {
          final party = t.partyName?.toLowerCase() ?? '';
          final category = t.category.toLowerCase();
          final notes = t.notes?.toLowerCase() ?? '';
          final amount = CurrencyFormatter.format(t.amount).toLowerCase();
          return party.contains(q) ||
              category.contains(q) ||
              notes.contains(q) ||
              amount.contains(q);
        }).toList();

        // Filter ledger entries by party name
        final ledgerEntries = ledgerAsync.valueOrNull ?? <LedgerPartyEntry>[];
        final matchedLedger = ledgerEntries.where((e) {
          return e.partyName.toLowerCase().contains(q);
        }).toList();

        // Filter bookings by customer, service, or ref
        final bookings = bookingsAsync.valueOrNull ?? <Booking>[];
        final matchedBookings = bookings.where((b) {
          final customer = b.customerName.toLowerCase();
          final service = b.serviceName.toLowerCase();
          final ref = b.bookingRef?.toLowerCase() ?? '';
          final notes = b.notes?.toLowerCase() ?? '';
          return customer.contains(q) ||
              service.contains(q) ||
              ref.contains(q) ||
              notes.contains(q);
        }).toList();

        final totalResults =
            matchedTxns.length + matchedLedger.length + matchedBookings.length;

        if (totalResults == 0) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: context.colorScheme.outlineVariant,
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'No results for "$query"',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // Transactions section
            if (matchedTxns.isNotEmpty) ...[
              _SectionHeader(
                title: 'Transactions',
                count: matchedTxns.length,
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...matchedTxns.take(20).map((txn) => _TransactionTile(txn: txn)),
              if (matchedTxns.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '+ ${matchedTxns.length - 20} more transactions',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: AppSpacing.base),
            ],

            // Ledger section
            if (matchedLedger.isNotEmpty) ...[
              _SectionHeader(
                title: 'Ledger',
                count: matchedLedger.length,
                icon: Icons.book,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...matchedLedger.take(20).map((e) => _LedgerTile(entry: e)),
              if (matchedLedger.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '+ ${matchedLedger.length - 20} more entries',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],

            // Bookings section
            if (matchedBookings.isNotEmpty) ...[
              if (matchedTxns.isNotEmpty || matchedLedger.isNotEmpty)
                const SizedBox(height: AppSpacing.base),
              _SectionHeader(
                title: 'Bookings',
                count: matchedBookings.length,
                icon: Icons.calendar_month_outlined,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...matchedBookings
                  .take(20)
                  .map((b) => _BookingResultTile(booking: b)),
              if (matchedBookings.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '+ ${matchedBookings.length - 20} more bookings',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: context.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
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
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn});

  final Transaction txn;

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
        child: Icon(
          CategoryHelper.getIcon(txn.category),
          color: context.colorScheme.onPrimaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: Text(
        txn.partyName ?? txn.category,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${DateFormatter.format(txn.date)} · ${txn.category}',
        style: context.textTheme.bodySmall,
      ),
      trailing: Text(
        '$prefix${CurrencyFormatter.format(txn.amount)}',
        style: context.textTheme.titleSmall?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFamily: 'RobotoMono',
        ),
      ),
      onTap: () {
        if (txn.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transactionId: txn.id!),
            ),
          );
        }
      },
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final LedgerPartyEntry entry;

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
          style: TextStyle(
            color: context.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        entry.partyName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isPositive ? 'Owes you' : 'You owe',
        style: context.textTheme.bodySmall,
      ),
      trailing: Text(
        CurrencyFormatter.format(net.abs()),
        style: context.textTheme.titleSmall?.copyWith(
          color: balanceColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LedgerScreen(),
          ),
        );
      },
    );
  }
}

class _BookingResultTile extends StatelessWidget {
  const _BookingResultTile({required this.booking});

  final Booking booking;

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
        child: Icon(
          Icons.calendar_month_outlined,
          color: context.colorScheme.onPrimaryContainer,
          size: AppSpacing.iconMd,
        ),
      ),
      title: Text(
        booking.customerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${booking.serviceName} · ${DateFormatter.format(booking.startDatetime)}'
        '${booking.bookingRef != null ? ' · ${booking.bookingRef}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall,
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          booking.status.label,
          style: context.textTheme.labelSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: () {
        if (booking.id != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: booking.id!),
            ),
          );
        }
      },
    );
  }
}
