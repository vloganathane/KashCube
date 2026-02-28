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
import '../parties/parties_screen.dart';
import '../transactions/add_edit_transaction_screen.dart';
import '../search/search_screen.dart';

// ---------------------------------------------------------------------------
// Mode / filter enums
// ---------------------------------------------------------------------------

enum _ModeTab { all, personal, business }
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

class _LedgerScreenState extends ConsumerState<LedgerScreen>
    with SingleTickerProviderStateMixin {
  _LedgerFilter _filter = _LedgerFilter.all;
  late final TabController _tabController;
  _ModeTab get _modeTab => _ModeTab.values[_tabController.index];
  
  // Search and filter state
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();
  
  // Advanced filters
  double? _minBalance;
  double? _maxBalance;
  int? _minTransactionCount;
  bool? _onlyOutstanding;

  bool get _hasAdvancedFilters =>
      _minBalance != null ||
      _maxBalance != null ||
      _minTransactionCount != null ||
      _onlyOutstanding != null;

  void _clearAdvancedFilters() {
    setState(() {
      _minBalance = null;
      _maxBalance = null;
      _minTransactionCount = null;
      _onlyOutstanding = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
    // Auto-refresh ledger data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ledgerSummariesProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(ledgerSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Filter parties…',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Global Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.filter_list),
            tooltip: _isSearching ? 'Clear filter' : 'Filter parties',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          Badge(
            isLabelVisible: _hasAdvancedFilters,
            child: IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Filters',
              onPressed: () => _showFilterSheet(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Manage Parties',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PartiesScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Personal'),
            Tab(text: 'Business'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    final modeFiltered = switch (_modeTab) {
      _ModeTab.all      => entries,
      _ModeTab.personal => entries.where((e) => e.personalCount > 0).toList(),
      _ModeTab.business => entries.where((e) => e.businessCount > 0).toList(),
    };
    final filtered = _applyFilter(modeFiltered);
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
    var filtered = switch (_filter) {
      _LedgerFilter.all         => all,
      _LedgerFilter.outstanding => all.where((e) => e.hasOutstanding).toList(),
      _LedgerFilter.lent        => all.where((e) => e.netLendingBalance > 0.01).toList(),
      _LedgerFilter.borrowed    => all.where((e) => e.netBorrowingBalance > 0.01).toList(),
      _LedgerFilter.investments => all.where((e) => e.netInvestment > 0.01).toList(),
      _LedgerFilter.cleared     => all.where((e) => e.isCleared).toList(),
    };

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        return e.partyName.toLowerCase().contains(query);
      }).toList();
    }

    // Apply advanced filters
    if (_minBalance != null) {
      filtered = filtered.where((e) {
        final balance = (e.netLendingBalance + e.netBorrowingBalance + e.netInvestment).abs();
        return balance >= _minBalance!;
      }).toList();
    }
    if (_maxBalance != null) {
      filtered = filtered.where((e) {
        final balance = (e.netLendingBalance + e.netBorrowingBalance + e.netInvestment).abs();
        return balance <= _maxBalance!;
      }).toList();
    }
    if (_minTransactionCount != null) {
      filtered = filtered.where((e) => e.transactionCount >= _minTransactionCount!).toList();
    }
    if (_onlyOutstanding == true) {
      filtered = filtered.where((e) => e.hasOutstanding).toList();
    }

    return filtered;
  }

  Widget _buildEmpty() {
    // Show search/filter specific message
    if (_searchQuery.isNotEmpty || _hasAdvancedFilters) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                'No matching parties',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Try a different search term or filter',
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

    final modeLabel = switch (_modeTab) {
      _ModeTab.all      => '',
      _ModeTab.personal => 'personal ',
      _ModeTab.business => 'business ',
    };
    final message = switch (_filter) {
      _LedgerFilter.all         => 'No ${modeLabel}ledger entries yet',
      _LedgerFilter.outstanding => 'No ${modeLabel}outstanding balances',
      _LedgerFilter.lent        => "You haven't lent anything ($modeLabel)",
      _LedgerFilter.borrowed    => "You haven't borrowed anything ($modeLabel)",
      _LedgerFilter.investments => 'No ${modeLabel}investments tracked',
      _LedgerFilter.cleared     => 'No ${modeLabel}cleared entries',
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

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LedgerAdvancedFilterSheet(
        minBalance: _minBalance,
        maxBalance: _maxBalance,
        minTransactionCount: _minTransactionCount,
        onlyOutstanding: _onlyOutstanding,
        onApply: (minBal, maxBal, minTxn, onlyOut) {
          setState(() {
            _minBalance = minBal;
            _maxBalance = maxBal;
            _minTransactionCount = minTxn;
            _onlyOutstanding = onlyOut;
          });
        },
        onClear: _clearAdvancedFilters,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced filter bottom sheet
// ---------------------------------------------------------------------------

class _LedgerAdvancedFilterSheet extends StatefulWidget {
  const _LedgerAdvancedFilterSheet({
    required this.minBalance,
    required this.maxBalance,
    required this.minTransactionCount,
    required this.onlyOutstanding,
    required this.onApply,
    required this.onClear,
  });

  final double? minBalance;
  final double? maxBalance;
  final int? minTransactionCount;
  final bool? onlyOutstanding;
  final void Function(double?, double?, int?, bool?) onApply;
  final VoidCallback onClear;

  @override
  State<_LedgerAdvancedFilterSheet> createState() =>
      _LedgerAdvancedFilterSheetState();
}

class _LedgerAdvancedFilterSheetState
    extends State<_LedgerAdvancedFilterSheet> {
  late double? _minBalance;
  late double? _maxBalance;
  late int? _minTransactionCount;
  late bool? _onlyOutstanding;

  final _minBalanceController = TextEditingController();
  final _maxBalanceController = TextEditingController();
  final _minTxnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minBalance = widget.minBalance;
    _maxBalance = widget.maxBalance;
    _minTransactionCount = widget.minTransactionCount;
    _onlyOutstanding = widget.onlyOutstanding;

    if (_minBalance != null) {
      _minBalanceController.text = _minBalance!.toStringAsFixed(0);
    }
    if (_maxBalance != null) {
      _maxBalanceController.text = _maxBalance!.toStringAsFixed(0);
    }
    if (_minTransactionCount != null) {
      _minTxnController.text = _minTransactionCount.toString();
    }
  }

  @override
  void dispose() {
    _minBalanceController.dispose();
    _maxBalanceController.dispose();
    _minTxnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Advanced Filters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () {
                  widget.onClear();
                  Navigator.pop(context);
                },
                child: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Balance range
          Text(
            'Balance Range',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min ₹',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _minBalance = double.tryParse(val);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: TextField(
                  controller: _maxBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max ₹',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _maxBalance = double.tryParse(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Min transaction count
          Text(
            'Minimum Transactions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _minTxnController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Min transaction count',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              _minTransactionCount = int.tryParse(val);
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Only outstanding
          CheckboxListTile(
            value: _onlyOutstanding ?? false,
            onChanged: (val) {
              setState(() {
                _onlyOutstanding = val;
              });
            },
            title: const Text('Only Outstanding Balances'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Apply button
          FilledButton(
            onPressed: () {
              widget.onApply(
                _minBalance,
                _maxBalance,
                _minTransactionCount,
                _onlyOutstanding,
              );
              Navigator.pop(context);
            },
            child: const Text('Apply Filters'),
          ),
        ],
      ),
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
            : scheme.onSurface.withValues(alpha: 0.45);

    final statusLabel = isOwedByThem
        ? 'owes you'
        : isOwedByMe
            ? 'you owe'
            : 'settled';

    // Determine dominant activity type for avatar color
    final hasLending = entry.netLendingBalance > 0.01 || entry.netBorrowingBalance > 0.01;
    final avatarBg = hasLending
        ? colors.credit.withValues(alpha: 0.2)
        : entry.totalIncome >= entry.totalExpense
            ? colors.income.withValues(alpha: 0.18)
            : colors.expense.withValues(alpha: 0.18);
    final avatarFg = hasLending
        ? colors.credit
        : entry.totalIncome >= entry.totalExpense
            ? colors.income
            : colors.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => KhataDetailScreen(partyName: entry.partyName),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: avatar + name + chevron ───────────────────────
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: avatarBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        entry.partyName.isNotEmpty
                            ? entry.partyName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: avatarFg,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.partyName,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entry.lastTransactionDate != null)
                          Text(
                            'Last: ${DateFormatter.format(entry.lastTransactionDate!)} · ${entry.transactionCount} txn${entry.transactionCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.45),
                                ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: scheme.onSurface.withValues(alpha: 0.3)),
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: AppSpacing.md),

              // ── Row 2: stat pills ────────────────────────────────────
              Row(
                children: [
                  if (entry.totalIncome > 0) ...[
                    _StatPill(
                      label: 'Received',
                      amount: entry.totalIncome,
                      color: colors.income,
                      icon: Icons.south_west_rounded,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (entry.totalExpense > 0) ...[
                    _StatPill(
                      label: 'Paid',
                      amount: entry.totalExpense,
                      color: colors.expense,
                      icon: Icons.north_east_rounded,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (entry.netLendingBalance > 0.01) ...[
                    _StatPill(
                      label: 'Lent',
                      amount: entry.netLendingBalance,
                      color: colors.credit,
                      icon: Icons.call_made_rounded,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (entry.netBorrowingBalance > 0.01) ...[
                    _StatPill(
                      label: 'Borrowed',
                      amount: entry.netBorrowingBalance,
                      color: colors.expense,
                      icon: Icons.call_received_rounded,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (entry.netInvestment > 0.01)
                    _StatPill(
                      label: 'Invested',
                      amount: entry.netInvestment,
                      color: scheme.primary,
                      icon: Icons.trending_up_rounded,
                    ),
                  // Mode tag
                  if (entry.isMixed) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _ModePill(label: 'Personal + Business'),
                  ] else if (entry.isBusinessOnly) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _ModePill(label: 'Business', color: scheme.primary),
                  ],
                  const Spacer(),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: balanceColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.hasOutstanding
                          ? '${CurrencyFormatter.format(net.abs())} $statusLabel'
                          : statusLabel,
                      style: TextStyle(
                        color: balanceColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500),
              ),
              Text(
                CurrencyFormatter.format(amount),
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode pill (Personal / Business / Personal + Business tag)
// ---------------------------------------------------------------------------

class _ModePill extends StatelessWidget {
  const _ModePill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: c,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
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
