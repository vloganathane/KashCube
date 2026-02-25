import 'dart:math' as math;

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

enum _LedgerFilter { all, outstanding, lent, borrowed, investments, cleared }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Ledger (Khata) screen.
///
/// Shows ALL parties you have a financial relationship with — not just
/// lent/borrowed but also regular income/expense counterparties.
/// Each party taps into a running-balance T-account khata view.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  _LedgerFilter _filter = _LedgerFilter.outstanding;

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(ledgerSummariesProvider);
    final lentAsync     = ref.watch(totalOutstandingLentProvider);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Outstanding summary ─────────────────────────────────────────
          _SummaryCard(lentAsync: lentAsync, borrowedAsync: borrowedAsync),

          // ── Filter chips ────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: _LedgerFilter.values.map((f) {
                final label = switch (f) {
                  _LedgerFilter.all         => 'All Parties',
                  _LedgerFilter.outstanding => 'Outstanding',
                  _LedgerFilter.lent        => 'Lent (Diya)',
                  _LedgerFilter.borrowed    => 'Borrowed (Liya)',
                  _LedgerFilter.investments => 'Investments',
                  _LedgerFilter.cleared     => 'Cleared',
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

          // ── Party list ──────────────────────────────────────────────────
          Expanded(
            child: summariesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) => _buildList(entries),
            ),
          ),
        ],
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
      _LedgerFilter.all         => all,
      _LedgerFilter.outstanding => all.where((e) => e.hasOutstanding).toList(),
      _LedgerFilter.lent        => all.where((e) => e.netLendingBalance > 0.01).toList(),
      _LedgerFilter.borrowed    => all.where((e) => e.netBorrowingBalance > 0.01).toList(),
      _LedgerFilter.investments => all.where((e) => e.netInvestment > 0.01).toList(),
      _LedgerFilter.cleared     => all.where((e) => e.isCleared).toList(),
    };
  }

  Widget _buildEmpty() {
    final message = switch (_filter) {
      _LedgerFilter.all         => 'No ledger entries yet',
      _LedgerFilter.outstanding => 'No outstanding balances',
      _LedgerFilter.lent        => "You haven't lent anything",
      _LedgerFilter.borrowed    => "You haven't borrowed anything",
      _LedgerFilter.investments => 'No investments tracked',
      _LedgerFilter.cleared     => 'No cleared entries',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tap + to record a transaction with a party.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
// Summary card  (outstanding amounts only)
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.lentAsync, required this.borrowedAsync});

  final AsyncValue<double> lentAsync;
  final AsyncValue<double> borrowedAsync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                label: 'To receive',
                value: lentAsync.valueOrNull,
                color: colors.income,
                icon: Icons.arrow_downward_rounded,
              ),
            ),
            Container(width: 1, height: 40, color: scheme.outlineVariant),
            Expanded(
              child: _SummaryItem(
                label: 'To pay',
                value: borrowedAsync.valueOrNull,
                color: colors.expense,
                icon: Icons.arrow_upward_rounded,
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
    required this.icon,
  });

  final String label;
  final double? value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value != null ? CurrencyFormatter.format(value!) : '—',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
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
    final isOwedByThem = net > 0.01;
    final isOwedByMe   = net < -0.01;

    final balanceColor = isOwedByThem
        ? colors.income
        : isOwedByMe
            ? colors.expense
            : scheme.onSurface.withValues(alpha: 0.4);

    final balanceLabel = isOwedByThem
        ? 'owes you'
        : isOwedByMe
            ? 'you owe'
            : entry.hasRegularActivity
                ? 'settled'
                : 'no balance';

    // Subtitle: show relationship types present
    final parts = <String>[];
    if (entry.totalIncome > 0) parts.add('income');
    if (entry.totalExpense > 0) parts.add('expense');
    if (entry.netInvestment > 0.01) parts.add('investment');
    final subtitleExtra = parts.isNotEmpty ? ' · ${parts.join(', ')}' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => KhataDetailScreen(partyName: entry.partyName),
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

              // Party name + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.partyName,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${entry.lastTransactionDate != null ? DateFormatter.format(entry.lastTransactionDate!) : ''}$subtitleExtra',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entry.hasOutstanding)
                    Text(
                      CurrencyFormatter.format(net.abs()),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
              Icon(Icons.chevron_right,
                  color: scheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Khata detail screen  (T-account running balance view)
// ---------------------------------------------------------------------------

class KhataDetailScreen extends ConsumerWidget {
  const KhataDetailScreen({super.key, required this.partyName});

  final String partyName;

  /// Balance delta from MY perspective.
  /// Positive → I'm ahead (they owe me more / I received).
  /// Negative → I owe more / I paid out.
  static double _delta(Transaction tx) => switch (tx.type) {
    TransactionType.lent         =>  tx.amount,
    TransactionType.receivedBack => -tx.amount,
    TransactionType.borrowed     => -tx.amount,
    TransactionType.paidBack     =>  tx.amount,
    TransactionType.income       =>  tx.amount,
    TransactionType.expense      => -tx.amount,
    TransactionType.invested     => -tx.amount,
    TransactionType.redeemed     =>  tx.amount,
    _                            =>  0,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(partyTransactionsProvider(partyName));
    final colors    = Theme.of(context).extension<KashCubeColors>()!;
    final scheme    = Theme.of(context).colorScheme;

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
              ref.read(partyTransactionsProvider(partyName).notifier).load();
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

          // Build running balance list (oldest-first from repo).
          double running = 0;
          final entries = txns.map((tx) {
            running += _delta(tx);
            return (tx, running);
          }).toList();

          final finalColor = running > 0.01
              ? colors.income
              : running < -0.01
                  ? colors.expense
                  : scheme.onSurface.withValues(alpha: 0.5);
          final finalLabel = running > 0.01
              ? 'owes you'
              : running < -0.01
                  ? 'you owe'
                  : 'settled ✓';

          return Column(
            children: [
              // ── Balance header ──────────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(AppSpacing.base),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: finalColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: finalColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Net Balance',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                        Text(
                          CurrencyFormatter.format(running.abs()),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: finalColor,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: finalColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        finalLabel,
                        style: TextStyle(
                          color: finalColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Column headers ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Entry',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Amount',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Balance',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Divider(height: 1, indent: AppSpacing.base, endIndent: AppSpacing.base),

              // ── T-account timeline ──────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.base,
                    right: AppSpacing.base,
                    bottom: 32,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  itemBuilder: (context, i) {
                    final (tx, balance) = entries[i];
                    return _KhataRow(
                      transaction: tx,
                      runningBalance: balance,
                      delta: _delta(tx),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Khata row  (single T-account line with running balance)
// ---------------------------------------------------------------------------

class _KhataRow extends StatelessWidget {
  const _KhataRow({
    required this.transaction,
    required this.runningBalance,
    required this.delta,
  });

  final Transaction transaction;
  final double runningBalance;
  final double delta;

  static String _typeLabel(TransactionType t) => switch (t) {
    TransactionType.lent         => 'Lent',
    TransactionType.borrowed     => 'Borrowed',
    TransactionType.receivedBack => 'Received back',
    TransactionType.paidBack     => 'Paid back',
    TransactionType.income       => 'Income',
    TransactionType.expense      => 'Expense',
    TransactionType.invested     => 'Invested',
    TransactionType.redeemed     => 'Redeemed',
    _                            => t.label,
  };

  static IconData _typeIcon(TransactionType t) => switch (t) {
    TransactionType.lent         => Icons.arrow_outward,
    TransactionType.borrowed     => Icons.call_received,
    TransactionType.receivedBack => Icons.call_received,
    TransactionType.paidBack     => Icons.arrow_outward,
    TransactionType.income       => Icons.south_rounded,
    TransactionType.expense      => Icons.north_rounded,
    TransactionType.invested     => Icons.trending_up,
    TransactionType.redeemed     => Icons.redeem,
    _                            => Icons.swap_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final scheme = Theme.of(context).colorScheme;

    final deltaColor  = delta > 0 ? colors.income : colors.expense;
    final balColor    = runningBalance > 0.01
        ? colors.income
        : runningBalance < -0.01
            ? colors.expense
            : scheme.onSurface.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(transaction.type), size: 16, color: deltaColor),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Label + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(transaction.type),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${DateFormatter.format(transaction.date)}'
                  '${transaction.notes != null && transaction.notes!.isNotEmpty ? ' · ${transaction.notes}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Amount
          SizedBox(
            width: 80,
            child: Text(
              '${delta > 0 ? '+' : '−'}${CurrencyFormatter.format(transaction.amount)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: deltaColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
          ),

          // Running balance
          SizedBox(
            width: 80,
            child: Text(
              CurrencyFormatter.format(math.max(runningBalance, -runningBalance)),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: balColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
