import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/delivery_challan.dart';
import '../../providers/delivery_challan_provider.dart';
import '../search/search_screen.dart';
import 'delivery_challan_detail_screen.dart';
import 'quote_builder_screen.dart';

class DeliveryChallansScreen extends ConsumerStatefulWidget {
  const DeliveryChallansScreen({super.key});

  @override
  ConsumerState<DeliveryChallansScreen> createState() =>
      _DeliveryChallansScreenState();
}

class _DeliveryChallansScreenState
    extends ConsumerState<DeliveryChallansScreen> {
  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredChallansProvider);
    final activeFilter = ref.watch(challanStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Challans'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search challans',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SearchScreen(initialFilter: SearchFilter.challans),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _FilterChips(
            selected: activeFilter,
            onSelect: (status) =>
                ref.read(challanStatusFilterProvider.notifier).state = status,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'New Delivery Challan',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => const QuoteBuilderScreen(
                docType: DocumentType.deliveryChallan,
              ),
            ))
            .then((_) => ref.read(challansProvider.notifier).invalidate()),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(challansProvider.notifier).invalidate(),
        child: filteredAsync.when(
          data: (list) => list.isEmpty
              ? _EmptyState(filter: activeFilter)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.base,
                    AppSpacing.base,
                    92,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) =>
                      _ChallanCard(challan: list[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: TextStyle(color: context.colorScheme.error)),
          ),
        ),
      ),
    );
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final ChallanStatus? selected;
  final ValueChanged<ChallanStatus?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          const SizedBox(width: AppSpacing.sm),
          ...ChallanStatus.values.map((s) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: FilterChip(
                  label: Text(s.label),
                  selected: selected == s,
                  onSelected: (_) =>
                      onSelect(selected == s ? null : s),
                  avatar: Icon(_statusIcon(s), size: 14),
                ),
              )),
        ],
      ),
    );
  }

  IconData _statusIcon(ChallanStatus s) {
    switch (s) {
      case ChallanStatus.draft:
        return Icons.edit_outlined;
      case ChallanStatus.dispatched:
        return Icons.local_shipping_outlined;
      case ChallanStatus.returned:
        return Icons.assignment_return_outlined;
      case ChallanStatus.converted:
        return Icons.receipt_outlined;
      case ChallanStatus.pendingNumber:
        return Icons.pending_outlined;
    }
  }
}

// ── Challan card ──────────────────────────────────────────────────────────────

class _ChallanCard extends ConsumerWidget {
  const _ChallanCard({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DeliveryChallanDetailScreen(challanId: challan.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor(challan.status, context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_shipping_outlined,
                  color: _statusColor(challan.status, context),
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          challan.challanNo,
                          style: context.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _PurposeBadge(purpose: challan.purpose),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      challan.customerName,
                      style: context.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormatter.formatFull(challan.challanDate),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(challan.subtotal),
                    style: context.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusChip(status: challan.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ChallanStatus s, BuildContext context) {
    switch (s) {
      case ChallanStatus.draft:
        return context.colorScheme.outline;
      case ChallanStatus.dispatched:
        return Colors.blue.shade700;
      case ChallanStatus.returned:
        return Colors.orange.shade700;
      case ChallanStatus.converted:
        return Colors.green.shade700;
      case ChallanStatus.pendingNumber:
        return context.colorScheme.outline;
    }
  }
}

class _PurposeBadge extends StatelessWidget {
  const _PurposeBadge({required this.purpose});

  final ChallanPurpose purpose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        purpose.label,
        style: context.textTheme.labelSmall?.copyWith(
          color: context.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ChallanStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case ChallanStatus.draft:
        bg = context.colorScheme.surfaceContainerHighest;
        fg = context.colorScheme.onSurfaceVariant;
        break;
      case ChallanStatus.dispatched:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        break;
      case ChallanStatus.returned:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        break;
      case ChallanStatus.converted:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case ChallanStatus.pendingNumber:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: context.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.filter});

  final ChallanStatus? filter;

  @override
  Widget build(BuildContext context) {
    final msg = filter == null
        ? 'No delivery challans yet.\nTap + to create one.'
        : 'No ${filter!.label.toLowerCase()} challans.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 72,
            color: context.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyLarge?.copyWith(
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
