import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/transaction.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../providers/transaction_provider.dart';
import '../transactions/add_edit_transaction_screen.dart';

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _LedgerFilter { all, lent, borrowed, investments, cleared }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Ledger screen — shows party-level lent / borrowed / invested positions
/// grouped by person or institution, all sourced from the transactions table.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  _LedgerFilter _filter = _LedgerFilter.all;

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(ledgerSummariesProvider);
    final lentAsync = ref.watch(totalOutstandingLentProvider);
    final borrowedAsync = ref.watch(totalOutstandingBorrowedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(ledgerSummariesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Summary card ───────────────────────────────────────────────
          _SummaryCard(
            lentAsync: lentAsync,
            borrowedAsync: borrowedAsync,
          ),

          // ── Filter chips ───────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: _LedgerFilter.values.map((f) {
                final label = switch (f) {
                  _LedgerFilter.all => 'All',
                  _LedgerFilter.lent => 'Lent (Diya)',
                  _LedgerFilter.borrowed => 'Borrowed (Liya)',
                  _LedgerFilter.investments => 'Investments',
                  _LedgerFilter.cleared => 'Cleared',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Party list ─────────────────────────────────────────────────
          Expanded(
            child: summariesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) => _buildList(entries),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_ledger',
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AddEditTransactionScreen(
                initialType: TransactionType.lent,
              ),
            ),
          );
          if (mounted) {
            ref.read(ledgerSummariesProvider.notifier).refresh();
          }
        },
      ),
    );
  }

  Widget _buildList(List<LedgerPartyEntry> entries) {
    final filtered = _applyFilter(entries);
    if (filtered.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: () => ref.read(ledgerSummariesProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base,
          bottom: 96,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, i) => _PartyTile(entry: filtered[i]),
      ),
    );
  }

  List<LedgerPartyEntry> _applyFilter(List<LedgerPartyEntry> all) {
    return switch (_filter) {
      _LedgerFilter.all => all.where((e) => !e.isCleared).toList(),
      _LedgerFilter.lent => all
          .where((e) => e.netLendingBalance > 0.01)
          .toList(),
      _LedgerFilter.borrowed => all
          .where((e) => e.netBorrowingBalance > 0.01)
          .toList(),
      _LedgerFilter.investments => all
          .where((e) => e.netInvestment > 0.01)
          .toList(),
      _LedgerFilter.cleared => all.where((e) => e.isCleared).toList(),
    };
  }

  Widget _buildEmpty() {
    final message = switch (_filter) {
      _LedgerFilter.all => 'No active ledger entries',
      _LedgerFilter.lent => "You haven't lent anything",
      _LedgerFilter.borrowed => "You haven't borrowed anything",
      _LedgerFilter.investments => 'No investments tracked',
      _LedgerFilter.cleared => 'No cleared entries',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.book_outlined,
              size: 64,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap + to record a lent or borrowed transaction.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.lentAsync,
    required this.borrowedAsync,
  });

  final AsyncValue<double> lentAsync;
  final AsyncValue<double> borrowedAsync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: lentAsync.when(
                loading: () => const _SummaryItem(
                  label: 'Outstanding\n(to receive)',
                  value: '—',
                  color: Colors.transparent,
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (v) => _SummaryItem(
                  label: 'Outstanding\n(to receive)',
                  value: CurrencyFormatter.format(v),
                  color: colors.income,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: scheme.outlineVariant,
            ),
            Expanded(
              child: borrowedAsync.when(
                loading: () => const _SummaryItem(
                  label: 'Outstanding\n(to pay)',
                  value: '—',
                  color: Colors.transparent,
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (v) => _SummaryItem(
                  label: 'Outstanding\n(to pay)',
                  value: CurrencyFormatter.format(v),
                  color: colors.expense,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Party tile
// ---------------------------------------------------------------------------

class _PartyTile extends ConsumerWidget {
  const _PartyTile({required this.entry});

  final LedgerPartyEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final scheme = Theme.of(context).colorScheme;

    final net = entry.netBalance;
    final isPositive = net > 0.01;
    final isNegative = net < -0.01;
    final balanceColor = isPositive
        ? colors.income
        : isNegative
            ? colors.expense
            : scheme.onSurface.withValues(alpha: 0.5);

    final balanceLabel = isPositive
        ? 'owes you'
        : isNegative
            ? 'you owe'
            : 'settled';

    final hasInvestment = entry.netInvestment > 0.01;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _PartyDetailScreen(partyName: entry.partyName),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  entry.partyName.isNotEmpty
                      ? entry.partyName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Party name + last date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.partyName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasInvestment)
                          Container(
                            margin:
                                const EdgeInsets.only(left: AppSpacing.xs),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'INV',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (entry.lastTransactionDate != null)
                      Text(
                        DateFormatter.format(
                            entry.lastTransactionDate!),
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                      ),
                  ],
                ),
              ),

              // Net balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(net.abs()),
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: balanceColor,
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                  Text(
                    balanceLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: balanceColor.withValues(alpha: 0.8),
                        ),
                  ),
                ],
              ),

              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Party detail screen
// ---------------------------------------------------------------------------

class _PartyDetailScreen extends ConsumerWidget {
  const _PartyDetailScreen({required this.partyName});

  final String partyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(partyTransactionsProvider(partyName));
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(partyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add entry',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditTransactionScreen(
                    initialType: TransactionType.lent,
                    initialPartyName: partyName,
                  ),
                ),
              );
              ref
                  .read(partyTransactionsProvider(partyName).notifier)
                  .load();
              ref.read(ledgerSummariesProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: txnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txns) {
          if (txns.isEmpty) {
            return const Center(child: Text('No transactions found.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: txns.length,
            itemBuilder: (context, i) {
              final tx = txns[i];
              final isInflow =
                  tx.type == TransactionType.receivedBack ||
                      tx.type == TransactionType.redeemed;
              final typeLabel = switch (tx.type) {
                TransactionType.lent => 'Lent',
                TransactionType.borrowed => 'Borrowed',
                TransactionType.receivedBack => 'Received back',
                TransactionType.paidBack => 'Paid back',
                TransactionType.invested => 'Invested',
                TransactionType.redeemed => 'Redeemed',
                _ => tx.type.label,
              };
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isInflow
                      ? colors.incomeBackground
                      : colors.creditBackground,
                  child: Icon(
                    isInflow
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: isInflow ? colors.income : colors.credit,
                    size: 18,
                  ),
                ),
                title: Text(typeLabel),
                subtitle: Text(
                  '${DateFormatter.format(tx.date)}'
                  '${tx.notes != null && tx.notes!.isNotEmpty ? ' · ${tx.notes}' : ''}',
                ),
                trailing: Text(
                  CurrencyFormatter.format(tx.amount),
                  style: TextStyle(
                    color: isInflow ? colors.income : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
