import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/quote.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/speed_dial_fab.dart';
import 'invoice_detail_screen.dart';
import 'quote_builder_screen.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessEnabled = ref.watch(businessModeProvider);
    if (!businessEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoices')),
        body: _DisabledView(
          onEnable: () => ref.read(businessModeProvider.notifier).setEnabled(true),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices & Quotes'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Invoices'),
            Tab(text: 'Quotes'),
          ],
        ),
      ),
      floatingActionButton: const SpeedDialFab(showAllOptions: false),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _InvoicesTab(),
          _QuotesTab(),
        ],
      ),
    );
  }
}

// ── Invoices Tab ─────────────────────────────────────────────────────────────

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(invoiceFilterProvider);
    final invoicesAsync = ref.watch(filteredInvoicesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(invoicesProvider.notifier).load();
      },
      child: Column(
        children: [
          _StatusFilterBar(
            selected: filter,
            onSelected: (s) =>
                ref.read(invoiceFilterProvider.notifier).state = s,
          ),
          Expanded(
            child: invoicesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => list.isEmpty
                  ? _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      label: 'No invoices yet',
                      sub: 'Create a quote and convert it to an invoice',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.base,
                        right: AppSpacing.base,
                        top: AppSpacing.base,
                        bottom: 80,
                      ),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) => _InvoiceTile(invoice: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});
  final InvoiceStatus? selected;
  final ValueChanged<InvoiceStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    final statuses = [null, ...InvoiceStatus.values];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        itemCount: statuses.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final s = statuses[i];
          final label = s?.label ?? 'All';
          return FilterChip(
            label: Text(label),
            selected: selected == s,
            onSelected: (_) => onSelected(s),
          );
        },
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(invoice.status, context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Draft invoices are editable, others are view-only
          if (invoice.status == InvoiceStatus.draft) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuoteBuilderScreen(
                  invoiceId: invoice.id!,
                  docType: DocumentType.invoice,
                ),
              ),
            ).then((_) => ref.invalidate(invoicesProvider));
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
              ),
            ).then((_) => ref.invalidate(invoicesProvider));
          }
        },
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_outlined,
                        color: statusColor, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Invoice no + customer
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.invoiceNo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoice.customerName,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Amount
                  Text(
                    CurrencyFormatter.format(invoice.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13,
                      color: cs.onSurface.withValues(alpha: 0.45)),
                  const SizedBox(width: 4),
                  Text(
                    DateFormatter.format(invoice.issueDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  if (invoice.dueDate != null) ...[
                    Text(
                      '  ·  Due ${DateFormatter.format(invoice.dueDate!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: invoice.isOverdue
                            ? const Color(0xFFC62828)
                            : cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                  const Spacer(),
                  _StatusChip(status: invoice.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(InvoiceStatus status, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      InvoiceStatus.paid => const Color(0xFF2E7D32),
      InvoiceStatus.overdue => const Color(0xFFC62828),
      InvoiceStatus.sent => cs.primary,
      InvoiceStatus.partiallyPaid => const Color(0xFFE65100),
      InvoiceStatus.draft => cs.outline,
    };
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Invoice?'),
        content: Text('Delete ${invoice.invoiceNo}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(invoicesProvider.notifier).remove(invoice.id!);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InvoiceStatus.paid => const Color(0xFF2E7D32),
      InvoiceStatus.overdue => const Color(0xFFC62828),
      InvoiceStatus.sent => Theme.of(context).colorScheme.primary,
      InvoiceStatus.partiallyPaid => const Color(0xFFE65100),
      InvoiceStatus.draft => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Quotes Tab ────────────────────────────────────────────────────────────────

class _QuotesTab extends ConsumerWidget {
  const _QuotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(quotesProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(quotesProvider.notifier).load();
      },
      child: quotesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? _EmptyState(
                icon: Icons.description_outlined,
                label: 'No quotes yet',
                sub: 'Tap + to create your first quote',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(
                  left: AppSpacing.base,
                  right: AppSpacing.base,
                  top: AppSpacing.base,
                  bottom: 80,
                ),
                itemCount: list.length,
                itemBuilder: (ctx, i) => _QuoteTile(quote: list[i]),
              ),
      ),
    );
  }
}

class _QuoteTile extends ConsumerWidget {
  const _QuoteTile({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = switch (quote.status) {
      QuoteStatus.accepted => const Color(0xFF2E7D32),
      QuoteStatus.rejected => const Color(0xFFC62828),
      QuoteStatus.sent => cs.primary,
      QuoteStatus.draft => cs.outline,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteBuilderScreen(quoteId: quote.id),
          ),
        ).then((_) => ref.invalidate(quotesProvider)),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined,
                        color: statusColor, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.quoteNo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          quote.customerName,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    CurrencyFormatter.format(quote.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  if (quote.validUntil != null) ...[
                    Icon(Icons.calendar_today_outlined,
                        size: 13,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                    const SizedBox(width: 4),
                    Text(
                      'Valid till ${DateFormatter.format(quote.validUntil!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      quote.status.label,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Quote?'),
        content: Text('Delete ${quote.quoteNo}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(quotesProvider.notifier).remove(quote.id!);
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.label, required this.sub});
  final IconData icon;
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text(label,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(sub,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DisabledView extends StatelessWidget {
  const _DisabledView({required this.onEnable});
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text('Business Mode is off',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enable Business Mode in Settings to create invoices and quotes.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: onEnable,
              child: const Text('Enable Business Mode'),
            ),
          ],
        ),
      ),
    );
  }
}
