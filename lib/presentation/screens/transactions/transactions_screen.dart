import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/category_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/transaction.dart';
import '../../providers/transaction_provider.dart';
import 'transaction_detail_screen.dart';

/// Date range filter for the transactions list.
enum TransactionFilter {
  all('All'),
  today('Today'),
  thisWeek('This Week'),
  thisMonth('This Month');

  const TransactionFilter(this.label);
  final String label;
}

/// Screen showing the full list of transactions with search and filters.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionFilter _activeFilter = TransactionFilter.all;
  TransactionType? _typeFilter;
  String? _categoryFilter;
  PaymentMethod? _paymentMethodFilter;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasAdvancedFilters =>
      _typeFilter != null ||
      _categoryFilter != null ||
      _paymentMethodFilter != null;

  void _clearAdvancedFilters() {
    setState(() {
      _typeFilter = null;
      _categoryFilter = null;
      _paymentMethodFilter = null;
    });
  }

  List<Transaction> _applyFilter(List<Transaction> transactions) {
    var filtered = transactions;

    // Apply date filter
    final now = DateTime.now();
    switch (_activeFilter) {
      case TransactionFilter.all:
        break;
      case TransactionFilter.today:
        final todayStart = DateTime(now.year, now.month, now.day);
        filtered = filtered.where((t) => !t.date.isBefore(todayStart)).toList();
      case TransactionFilter.thisWeek:
        final weekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        filtered =
            filtered.where((t) => !t.date.isBefore(weekStart)).toList();
      case TransactionFilter.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        filtered =
            filtered.where((t) => !t.date.isBefore(monthStart)).toList();
    }

    // Apply type filter
    if (_typeFilter != null) {
      filtered = filtered.where((t) => t.type == _typeFilter).toList();
    }

    // Apply category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((t) => t.category == _categoryFilter).toList();
    }

    // Apply payment method filter
    if (_paymentMethodFilter != null) {
      filtered =
          filtered.where((t) => t.paymentMethod == _paymentMethodFilter).toList();
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        final party = t.partyName?.toLowerCase() ?? '';
        final category = t.category.toLowerCase();
        final notes = t.notes?.toLowerCase() ?? '';
        return party.contains(query) ||
            category.contains(query) ||
            notes.contains(query);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
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
        ],
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          final filtered = _applyFilter(transactions);

          return Column(
            children: [
              // Filter chips
              _FilterChips(
                active: _activeFilter,
                onChanged: (filter) =>
                    setState(() => _activeFilter = filter),
                totalCount: transactions.length,
                filteredCount: filtered.length,
              ),

              // Transaction list
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(transactions.isEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final txn = filtered[index];
                          final colors = context.kashColors;
                          final amountColor =
                              txn.isIncome ? colors.income : colors.expense;
                          final prefix = txn.isIncome ? '+' : '-';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  context.colorScheme.primaryContainer,
                              child: Icon(
                                CategoryHelper.getIcon(txn.category),
                                color:
                                    context.colorScheme.onPrimaryContainer,
                                size: AppSpacing.iconMd,
                              ),
                            ),
                            title: Text(
                              txn.partyName ?? txn.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${DateFormatter.format(txn.date)} · ${txn.paymentMethod.label}',
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
                                    builder: (_) =>
                                        TransactionDetailScreen(
                                      transactionId: txn.id!,
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AdvancedFilterSheet(
        typeFilter: _typeFilter,
        categoryFilter: _categoryFilter,
        paymentMethodFilter: _paymentMethodFilter,
        onApply: (type, category, method) {
          setState(() {
            _typeFilter = type;
            _categoryFilter = category;
            _paymentMethodFilter = method;
          });
        },
        onClear: _clearAdvancedFilters,
      ),
    );
  }

  Widget _buildEmptyState(bool noTransactions) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noTransactions
                ? Icons.receipt_long_outlined
                : Icons.search_off,
            size: 64,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            noTransactions ? 'No transactions yet' : 'No matching transactions',
            style: context.textTheme.titleMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            noTransactions
                ? 'Tap + to add your first transaction'
                : 'Try a different filter or search term',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal filter chips row.
class _FilterChips extends StatelessWidget {
  final TransactionFilter active;
  final ValueChanged<TransactionFilter> onChanged;
  final int totalCount;
  final int filteredCount;

  const _FilterChips({
    required this.active,
    required this.onChanged,
    required this.totalCount,
    required this.filteredCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TransactionFilter.values.map((filter) {
                  final isActive = filter == active;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(filter.label),
                      selected: isActive,
                      onSelected: (_) => onChanged(filter),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Count badge
          if (active != TransactionFilter.all)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                '$filteredCount',
                style: context.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet for advanced filtering by type, category, and payment method.
class _AdvancedFilterSheet extends StatefulWidget {
  const _AdvancedFilterSheet({
    required this.typeFilter,
    required this.categoryFilter,
    required this.paymentMethodFilter,
    required this.onApply,
    required this.onClear,
  });

  final TransactionType? typeFilter;
  final String? categoryFilter;
  final PaymentMethod? paymentMethodFilter;
  final void Function(TransactionType?, String?, PaymentMethod?) onApply;
  final VoidCallback onClear;

  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  late TransactionType? _type;
  late String? _category;
  late PaymentMethod? _method;

  static const _categories = [
    'Food & Dining',
    'Transportation',
    'Shopping',
    'Bills & Utilities',
    'Healthcare',
    'Entertainment',
    'Groceries',
    'Education',
    'Business Expense',
    'Salary',
    'Business Income',
    'Freelance',
    'Investment',
    'Refund',
    'Other Income',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.typeFilter;
    _category = widget.categoryFilter;
    _method = widget.paymentMethodFilter;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
            const SizedBox(height: AppSpacing.md),

            // Type filter
            Text('Type', style: context.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final type in [
                  TransactionType.income,
                  TransactionType.expense,
                ])
                  FilterChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (selected) {
                      setState(() => _type = selected ? type : null);
                    },
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Category filter
            Text('Category', style: context.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: _categories.map((cat) {
                return FilterChip(
                  label: Text(cat),
                  selected: _category == cat,
                  onSelected: (selected) {
                    setState(() => _category = selected ? cat : null);
                  },
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    CategoryHelper.getIcon(cat),
                    size: 14,
                    color: CategoryHelper.getColor(cat),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),

            // Payment method filter
            Text('Payment Method', style: context.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: PaymentMethod.values.map((m) {
                return FilterChip(
                  label: Text(m.label),
                  selected: _method == m,
                  onSelected: (selected) {
                    setState(() => _method = selected ? m : null);
                  },
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  widget.onApply(_type, _category, _method);
                  Navigator.pop(context);
                },
                child: const Text('Apply Filters'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
