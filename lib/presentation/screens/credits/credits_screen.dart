import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/credit_record.dart';
import '../../providers/credit_provider.dart';
import 'add_edit_credit_screen.dart';
import 'credit_detail_screen.dart';
import 'customer_profile_screen.dart';

/// Filter tabs for the credits screen.
enum CreditFilter { all, pending, overdue, cleared, customers }

/// Screen showing credit/udhar records with collections dashboard.
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  CreditFilter _filter = CreditFilter.pending;
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search credits...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Credits (Udhar)'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_credits',
        onPressed: () => _navigateToAddCredit(),
        icon: const Icon(Icons.add),
        label: const Text('Give Credit'),
      ),
      body: Column(
        children: [
          // Summary cards
          _buildSummaryCards(),

          // Filter tabs
          _buildFilterTabs(),

          // Content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final totalPendingAsync = ref.watch(totalPendingCreditProvider);
    final totalOverdueAsync = ref.watch(totalOverdueCreditProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              title: 'Total Pending',
              value: totalPendingAsync,
              color: context.kashColors.credit,
              icon: Icons.account_balance_wallet_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryCard(
              title: 'Overdue',
              value: totalOverdueAsync,
              color: context.kashColors.overdue,
              icon: Icons.warning_amber_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: CreditFilter.values.map((f) {
          final isSelected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label: Text(_filterLabel(f)),
              selected: isSelected,
              onSelected: (_) => setState(() => _filter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _filterLabel(CreditFilter f) {
    switch (f) {
      case CreditFilter.all:
        return 'All';
      case CreditFilter.pending:
        return 'Pending';
      case CreditFilter.overdue:
        return 'Overdue';
      case CreditFilter.cleared:
        return 'Cleared';
      case CreditFilter.customers:
        return 'Customers';
    }
  }

  Widget _buildContent() {
    if (_filter == CreditFilter.customers) {
      return _buildCustomersList();
    }
    return _buildCreditsList();
  }

  Widget _buildCreditsList() {
    final creditsAsync = ref.watch(pendingCreditsProvider);

    // For 'all' we need a different data source
    if (_filter == CreditFilter.all || _filter == CreditFilter.cleared) {
      return _buildFilteredCreditsList();
    }

    return creditsAsync.when(
      data: (credits) {
        var filtered = _applyFilter(credits);
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filtered = filtered
              .where((c) =>
                  c.customerName.toLowerCase().contains(q) ||
                  (c.notes?.toLowerCase().contains(q) ?? false))
              .toList();
        }

        if (filtered.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: filtered.length,
          itemBuilder: (context, index) =>
              _CreditListTile(credit: filtered[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildFilteredCreditsList() {
    final AsyncValue<List<CreditRecord>> dataAsync;
    if (_filter == CreditFilter.cleared) {
      dataAsync = ref.watch(clearedCreditsProvider);
    } else {
      // 'all' — combine from repo
      dataAsync = ref.watch(pendingCreditsProvider);
    }

    return dataAsync.when(
      data: (credits) {
        var filtered = credits;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filtered = filtered
              .where((c) =>
                  c.customerName.toLowerCase().contains(q) ||
                  (c.notes?.toLowerCase().contains(q) ?? false))
              .toList();
        }

        if (filtered.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: filtered.length,
          itemBuilder: (context, index) =>
              _CreditListTile(credit: filtered[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  List<CreditRecord> _applyFilter(List<CreditRecord> credits) {
    switch (_filter) {
      case CreditFilter.overdue:
        return credits.where((c) => c.computedOverdue).toList();
      case CreditFilter.pending:
      case CreditFilter.all:
      case CreditFilter.cleared:
      case CreditFilter.customers:
        return credits;
    }
  }

  Widget _buildCustomersList() {
    final summariesAsync = ref.watch(customerSummariesProvider);

    return summariesAsync.when(
      data: (summaries) {
        var filtered = summaries;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filtered = filtered
              .where((s) => s.customerName.toLowerCase().contains(q))
              .toList();
        }

        if (filtered.isEmpty) {
          return _buildEmptyState(message: 'No customers found');
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final summary = filtered[index];
            final hasOverdue = summary.overdueCount > 0;

            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: hasOverdue
                      ? context.kashColors.overdueBackground
                      : context.kashColors.creditBackground,
                  child: Text(
                    summary.customerName[0].toUpperCase(),
                    style: TextStyle(
                      color: hasOverdue
                          ? context.kashColors.overdue
                          : context.kashColors.credit,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(summary.customerName),
                subtitle: Text(
                  '${summary.pendingCount} pending'
                  '${summary.overdueCount > 0 ? ' · ${summary.overdueCount} overdue' : ''}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: hasOverdue ? context.kashColors.overdue : null,
                  ),
                ),
                trailing: Text(
                  CurrencyFormatter.format(summary.totalPending),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'RobotoMono',
                    color: context.kashColors.credit,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CustomerProfileScreen(
                        customerName: summary.customerName,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildEmptyState({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            message ?? 'No credits found',
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search'
                : 'Tap + to give credit to a customer',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToAddCredit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddEditCreditScreen()),
    );
    if (result == true) {
      ref.invalidate(totalPendingCreditProvider);
      ref.invalidate(totalOverdueCreditProvider);
      ref.invalidate(customerSummariesProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Summary card widget
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final AsyncValue<double> value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            value.when(
              data: (total) => Text(
                CurrencyFormatter.format(total),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                    ),
              ),
              loading: () => const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => const Text('--'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Credit list tile widget
// ---------------------------------------------------------------------------

class _CreditListTile extends ConsumerWidget {
  const _CreditListTile({required this.credit});

  final CreditRecord credit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOverdue = credit.computedOverdue;
    final colors = context.kashColors;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreditDetailScreen(creditId: credit.id!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor:
                    isOverdue ? colors.overdueBackground : colors.creditBackground,
                child: Text(
                  credit.customerName[0].toUpperCase(),
                  style: TextStyle(
                    color: isOverdue ? colors.overdue : colors.credit,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            credit.customerName,
                            style: context.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (credit.isReceived) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.income.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Received',
                              style:
                                  context.textTheme.labelSmall?.copyWith(
                                color: colors.income,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          DateFormatter.format(credit.creditDate),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (credit.dueDate != null) ...[
                          Text(
                            ' · Due ${DateFormatter.format(credit.dueDate!)}',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isOverdue
                                  ? colors.overdue
                                  : context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Payment progress bar
                    if (credit.paidAmount > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: credit.repaymentProgress,
                          minHeight: 3,
                          backgroundColor:
                              context.colorScheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(colors.income),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(credit.pendingAmount),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'RobotoMono',
                      color: isOverdue ? colors.overdue : colors.credit,
                    ),
                  ),
                  if (isOverdue)
                    Text(
                      'OVERDUE',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.overdue,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (credit.isCleared)
                    Text(
                      'CLEARED',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: colors.income,
                        fontWeight: FontWeight.bold,
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
