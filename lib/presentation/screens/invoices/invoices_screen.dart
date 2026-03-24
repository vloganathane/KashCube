import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/tutorial_mixin.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/quote.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tutorial_flow_provider.dart';
import '../search/search_screen.dart';
import '../../widgets/speed_dial_fab.dart';
import 'invoice_detail_screen.dart';
import 'quote_detail_screen.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen>
    with SingleTickerProviderStateMixin, TutorialMixin<InvoicesScreen> {
  // Keys for tutorial spotlights
  final _fabKey        = GlobalKey();
  final _searchKey     = GlobalKey();
  final _filterKey     = GlobalKey();
  final _newestCardKey = GlobalKey();

  late final TabController _tabController;

  @override
  String get tutorialKey => SettingsKeys.tutorialInvoicesDone;

  @override
  String get tutorialTitle => 'Invoices & Quotes';

  @override
  String get tutorialDescription =>
      'Create professional invoices for your business. '
      'Learn how to add customers, line items, and generate invoices.';

  @override
  @override
  List<TargetFocus> buildTargets() => [
        TargetFocus(
          identify: 'invoice_fab',
          keyTarget: _fabKey,
          shape: ShapeLightFocus.Circle,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Create invoices & quotes',
                message:
                    'Tap + to create a new invoice or quote\n'
                    '\u2014 add customers, items, and track payments.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'invoice_search',
          keyTarget: _searchKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Search invoices',
                message: 'Quickly find invoices by number, customer, or amount.',
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'invoice_filter',
          keyTarget: _filterKey,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Filter by date',
                message: 'View invoices from a specific period.',
              ),
            ),
          ],
        ),
      ];

  @override
  List<TutorialMenuItem> get tutorialMenuItems => [
        TutorialMenuItem(label: 'Orientation tour', onTap: replayTutorial),
        TutorialMenuItem(
          label: 'How to create an invoice',
          onTap: _replayInvoiceFlow,
        ),
      ];

  void _replayInvoiceFlow() {
    ref.read(settingsRepositoryProvider)
        .set(SettingsKeys.tutorialInvoiceFlowDone, 'false');
    ref.read(tutorialFlowProvider.notifier).abandon();
    ref.read(tutorialFlowProvider.notifier)
        .advance(TutorialFlowStep.newInvoiceFab);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    maybeShowTutorial();
    _maybeStartFlow();
  }

  Future<void> _maybeStartFlow() async {
    final settings = ref.read(settingsRepositoryProvider);
    if (await settings.get(SettingsKeys.tutorialInvoiceFlowDone) != 'true') {
      if (!mounted) return;
      ref.read(tutorialFlowProvider.notifier).abandon();
      ref.read(tutorialFlowProvider.notifier)
          .advance(TutorialFlowStep.newInvoiceFab);
    }
  }

  void _showFabFlowMark() {
    // Capture refs before showing tutorial to avoid "ref after dispose" errors
    final flowNotifier = ref.read(tutorialFlowProvider.notifier);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'flow_invoice_fab',
          keyTarget: _fabKey,
          shape: ShapeLightFocus.Circle,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Let\'s create your first invoice',
                message: 'Tap the + button to get started.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'SKIP',
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      alignSkip: Alignment.topRight,
      paddingFocus: 2,
      pulseEnable: true,
      onFinish: () {},  // user taps FAB overlay — FAB onPressed handles the advance
      onSkip: () {
        Future(() {
          flowNotifier.abandon();
          settingsRepo.set(SettingsKeys.tutorialInvoiceFlowDone, 'true');
        });
        return true;
      },
    ).show(context: context);
  }

  void _showResultMark() {
    // Capture refs before showing tutorial to avoid "ref after dispose" errors
    final flowNotifier = ref.read(tutorialFlowProvider.notifier);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'flow_invoice_result',
          keyTarget: _newestCardKey,
          shape: ShapeLightFocus.RRect,
          radius: 12,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: tutorialContentCard(
                title: 'Invoice created!',
                message:
                    'Tap to view details, share PDF, or mark as paid.\n'
                    'Swipe to delete.',
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: 'GOT IT',
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
      alignSkip: Alignment.topRight,
      paddingFocus: 4,
      pulseEnable: false,
      onFinish: () {
        Future(() {
          flowNotifier.finish();
          settingsRepo.set(SettingsKeys.tutorialInvoiceFlowDone, 'true');
        });
      },
      onSkip: () {
        Future(() {
          flowNotifier.finish();
          settingsRepo.set(SettingsKeys.tutorialInvoiceFlowDone, 'true');
        });
        return true;
      },
    ).show(context: context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for tutorial flow steps
    ref.listen<TutorialFlowStep>(tutorialFlowProvider, (_, step) {
      if (step == TutorialFlowStep.newInvoiceFab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFabFlowMark();
        });
      }
      if (step == TutorialFlowStep.newInvoiceResult) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _newestCardKey.currentContext == null) return;
          _showResultMark();
        });
      }
    });

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
        actions: [
          buildTutorialAppBarAction(),
          IconButton(
            key: _searchKey,
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen(initialFilter: SearchFilter.invoices)),
            ),
          ),
          IconButton(
            key: _filterKey,
            icon: const Icon(Icons.tune),
            onPressed: _showFilterDialog,
            tooltip: 'Filter by date',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Invoices'),
            Tab(text: 'Quotes'),
          ],
        ),
      ),
      floatingActionButton: SpeedDialFab(key: _fabKey, showAllOptions: false),
      body: TabBarView(
        controller: _tabController,
        children: [
          _InvoicesTab(newestCardKey: _newestCardKey),
          const _QuotesTab(),
        ],
      ),
    );
  }
}

// ── Invoices Tab ─────────────────────────────────────────────────────────────

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab({this.newestCardKey});

  final GlobalKey? newestCardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(invoiceFilterProvider);
    final typeFilter = ref.watch(invoiceTypeFilterProvider);
    final invoicesAsync = ref.watch(filteredInvoicesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(invoicesProvider.notifier).load();
      },
      child: Column(
        children: [
          _StatusFilterBar(
            selected: filter,
            selectedType: typeFilter,
            onSelected: (s) {
              ref.read(invoiceFilterProvider.notifier).state = s;
            },
            onTypeSelected: (t) {
              ref.read(invoiceTypeFilterProvider.notifier).state = t;
            },
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
                      itemBuilder: (ctx, i) => _InvoiceTile(
                        key: i == 0 ? newestCardKey : null,
                        invoice: list[i],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selected,
    required this.selectedType,
    required this.onSelected,
    required this.onTypeSelected,
  });
  final InvoiceStatus? selected;
  final InvoiceType? selectedType;
  final ValueChanged<InvoiceStatus?> onSelected;
  final ValueChanged<InvoiceType?> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final statuses = [null, ...InvoiceStatus.values];
    // CN / DN as separate chips after the status row
    const typeChips = [
      (label: 'Credit Notes', type: InvoiceType.creditNote),
      (label: 'Debit Notes',  type: InvoiceType.debitNote),
    ];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        children: [
          // Status chips
          ...statuses.map((s) {
            final label = s?.label ?? 'All';
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text(label),
                selected: selected == s && selectedType == null,
                onSelected: (_) {
                  onSelected(s);
                  onTypeSelected(null); // clear type filter
                },
              ),
            );
          }),
          // Divider
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Center(
              child: Container(
                width: 1,
                height: 24,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          // Type chips: Credit Notes, Debit Notes
          ...typeChips.map((tc) => Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label: Text(tc.label),
              selected: selectedType == tc.type,
              onSelected: (_) {
                onTypeSelected(
                  selectedType == tc.type ? null : tc.type,
                );
                onSelected(null); // clear status filter
              },
            ),
          )),
        ],
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(invoice.status, context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
          ),
        ).then((_) => ref.invalidate(invoicesProvider)),
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                invoice.invoiceNo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (invoice.invoiceType == InvoiceType.creditNote ||
                                invoice.invoiceType == InvoiceType.debitNote) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (invoice.invoiceType ==
                                              InvoiceType.creditNote
                                          ? Theme.of(context).colorScheme.error
                                          : Colors.orange)
                                      .withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  invoice.invoiceType == InvoiceType.creditNote
                                      ? 'CN'
                                      : 'DN',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: invoice.invoiceType ==
                                            InvoiceType.creditNote
                                        ? Theme.of(context).colorScheme.error
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ],
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
      InvoiceStatus.cancelled => cs.outline,
      InvoiceStatus.draft => cs.outline,
      InvoiceStatus.pendingNumber => cs.outline,
    };
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
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
      InvoiceStatus.cancelled => Theme.of(context).colorScheme.outline,
      InvoiceStatus.draft => Theme.of(context).colorScheme.outline,
      InvoiceStatus.pendingNumber => Theme.of(context).colorScheme.outline,
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
    final quotesAsync = ref.watch(filteredQuotesProvider);
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
      QuoteStatus.pendingNumber => cs.outline,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteDetailScreen(quoteId: quote.id!),
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
      useRootNavigator: false,
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

// ── Filter Bottom Sheet ──────────────────────────────────────────────────────

class _FilterBottomSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange = ref.watch(invoiceDateRangeProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Filter by Date',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              if (dateRange != null)
                TextButton(
                  onPressed: () {
                    ref.read(invoiceDateRangeProvider.notifier).state = null;
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),

          // Quick filters
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Today'),
            onTap: () {
              final today = DateTime.now();
              ref.read(invoiceDateRangeProvider.notifier).state = DateTimeRange(
                start: DateTime(today.year, today.month, today.day),
                end: DateTime(today.year, today.month, today.day, 23, 59, 59),
              );
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_week),
            title: const Text('This Week'),
            onTap: () {
              final now = DateTime.now();
              final weekStart = now.subtract(Duration(days: now.weekday - 1));
              final weekEnd = weekStart.add(const Duration(days: 6));
              ref.read(invoiceDateRangeProvider.notifier).state = DateTimeRange(
                start: DateTime(weekStart.year, weekStart.month, weekStart.day),
                end: DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59),
              );
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('This Month'),
            onTap: () {
              final now = DateTime.now();
              final monthStart = DateTime(now.year, now.month, 1);
              final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
              ref.read(invoiceDateRangeProvider.notifier).state = DateTimeRange(
                start: monthStart,
                end: monthEnd,
              );
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Custom Range'),
            trailing: dateRange != null
                ? Text(
                    '${DateFormatter.format(dateRange.start)} - ${DateFormatter.format(dateRange.end)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: dateRange,
              );
              if (picked != null) {
                ref.read(invoiceDateRangeProvider.notifier).state = picked;
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),

          // Bottom padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
