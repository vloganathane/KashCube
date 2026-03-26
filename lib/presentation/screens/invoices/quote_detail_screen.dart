import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/invoice.dart';
import '../../../data/models/quote.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/activity_log_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/upgrade_prompt_sheet.dart';
import '../settings/upgrade_screen.dart';
import 'invoice_detail_screen.dart';
import 'quote_builder_screen.dart';

class QuoteDetailScreen extends ConsumerWidget {
  const QuoteDetailScreen({super.key, required this.quoteId});

  final int quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoteAsync = ref.watch(quoteByIdProvider(quoteId));

    return quoteAsync.when(
      data: (quote) {
        if (quote == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Quote not found')),
          );
        }
        return _QuoteDetailView(quote: quote);
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── Detail View ───────────────────────────────────────────────────────────────

class _QuoteDetailView extends ConsumerStatefulWidget {
  const _QuoteDetailView({required this.quote});
  final Quote quote;

  @override
  ConsumerState<_QuoteDetailView> createState() => _QuoteDetailViewState();
}

class _QuoteDetailViewState extends ConsumerState<_QuoteDetailView> {
  bool _loading = false;

  Quote get quote => widget.quote;

  bool get _canEdit =>
      quote.status == QuoteStatus.draft || quote.status == QuoteStatus.sent;

  bool get _canSend => quote.status == QuoteStatus.draft;

  bool get _canConvert {
    // Only allow conversion from the sent state.
    if (quote.status != QuoteStatus.sent) return false;
    // If an invoice has already been created from this quote, don't show again.
    if (quote.id != null) {
      final linked = ref.watch(invoiceByQuoteIdProvider(quote.id!));
      if (linked != null) return false;
    }
    return true;
  }

  bool get _canReject => quote.status == QuoteStatus.sent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(quote.quoteNo),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Preview PDF',
            onPressed: _loading ? null : _previewPdf,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share PDF',
            onPressed: _loading ? null : _sharePdf,
          ),
          PopupMenuButton<_Action>(
            onSelected: _handleMenu,
            itemBuilder: (_) => [
              if (_canEdit)
                const PopupMenuItem(
                  value: _Action.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (_canReject)
                const PopupMenuItem(
                  value: _Action.reject,
                  child: ListTile(
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Mark as Rejected'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (quote.status == QuoteStatus.draft)
                const PopupMenuItem(
                  value: _Action.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outlined),
                    title: Text('Delete'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HeaderCard(quote: quote),
          const SizedBox(height: AppSpacing.base),
          _LineItemsCard(quote: quote),
          const SizedBox(height: AppSpacing.base),
          _TotalsCard(quote: quote),
          if (quote.notes != null && quote.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _NotesCard(notes: quote.notes!),
          ],
          if (quote.id != null) ...[
            const SizedBox(height: AppSpacing.base),
            _LinkedInvoiceCard(quoteId: quote.id!),
          ],
          if (quote.id != null) ...[
            const SizedBox(height: AppSpacing.base),
            _ActivityCard(quoteId: quote.id!),
          ],
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget? _buildBottomBar() {
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.base,
      AppSpacing.sm,
      AppSpacing.base,
      AppSpacing.xl,
    );
    if (_canSend) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
                onPressed: _loading ? null : _edit,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.send_outlined),
                label: const Text('Send'),
                onPressed: _loading ? null : _sharePdf,
              ),
            ),
          ],
        ),
      );
    }
    if (quote.status == QuoteStatus.sent) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            if (_canConvert) ...
              [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Convert to Invoice'),
                    onPressed: _loading ? null : _convertToInvoice,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Rejected'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onPressed: _loading ? null : _markRejected,
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  void _handleMenu(_Action action) {
    switch (action) {
      case _Action.edit:
        _edit();
      case _Action.reject:
        _markRejected();
      case _Action.delete:
        _delete();
    }
  }

  void _edit() {
    final notifier = ref.read(quotesProvider.notifier);
    Navigator.of(context)
        .pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuoteBuilderScreen(quoteId: quote.id),
      ),
    )
        .then((_) {
      notifier.load();
    });
  }

  Future<void> _previewPdf() async {
    setState(() => _loading = true);
    try {
      final business = ref.read(activeBusinessProvider);
      final party = quote.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(quote.customerPartyId!)
          : null;
      final tc = await ref.read(settingsRepositoryProvider).get(SettingsKeys.quoteTerms);
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        quote,
        business: business,
        customerParty: party,
        termsAndConditions: tc ?? SettingsKeys.defaultQuoteTerms,
      );
      if (!mounted) return;
      if (!kIsWeb) await OpenFile.open(pdfFile.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sharePdf() async {
    // Gate: free-tier users see the upgrade prompt first.
    final tier = ref.read(subscriptionTierProvider);
    bool showWatermark = false;
    if (tier.isFree) {
      final action = await showUpgradePromptSheet(context, featureName: 'quote');
      if (!mounted) return;
      if (action == UpgradePromptAction.upgrade) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradeScreen()));
        return;
      } else if (action == UpgradePromptAction.shareWithWatermark) {
        showWatermark = true;
      } else {
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final business = ref.read(activeBusinessProvider);
      final party = quote.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(quote.customerPartyId!)
          : null;
      final tc = await ref.read(settingsRepositoryProvider).get(SettingsKeys.quoteTerms);
      final pdfFile = await InvoicePdfService.instance.generateQuotePdf(
        quote,
        business: business,
        customerParty: party,
        termsAndConditions: tc ?? SettingsKeys.defaultQuoteTerms,
        showFreeWatermark: showWatermark,
        showUpiQr: tier.isStarter,
      );
      if (!mounted) return;
      final due = quote.validUntil;
      final message = 'Hi ${quote.customerName},\n\n'
          'Quote ${quote.quoteNo} for ${CurrencyFormatter.format(quote.total)}'
          '${due != null ? '\nValid till ${DateFormatter.formatFull(due)}' : ''}'
          '\n\n— ${business?.name ?? 'My Business'}';
      await Share.shareXFiles(
        [pdfFile],
        subject: 'Quote ${quote.quoteNo}',
        text: message,
      );
      // Promote draft → sent after a successful share.
      if (quote.status == QuoteStatus.draft && quote.id != null) {
        await ref.read(quotesProvider.notifier).markSent(quote.id!);
        if (mounted) ref.invalidate(activityLogProvider(('quote', quote.id!)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _convertToInvoice() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Invoice?'),
        content: Text(
            'Create a new invoice from ${quote.quoteNo}? The quote will be marked as accepted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final invoice =
          await ref.read(quotesProvider.notifier).convertToInvoice(quote.id!);
      if (!mounted) return;
      if (invoice == null || invoice.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversion failed: could not create invoice')),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversion failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRejected() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      builder: (_) => const _RejectionReasonSheet(),
    );
    // null means the user dismissed without confirming.
    if (reason == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(quotesProvider.notifier).markRejected(
            quote.id!,
            reason: reason.isEmpty ? null : reason,
          );
      if (mounted) ref.invalidate(activityLogProvider(('quote', quote.id!)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Delete Quote?'),
        content: Text('Delete ${quote.quoteNo}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(quotesProvider.notifier).remove(quote.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

enum _Action { edit, reject, delete }

// ── Activity Card ─────────────────────────────────────────────────────────────

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard({required this.quoteId});
  final int quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(activityLogProvider(('quote', quoteId)));

    return logsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (logs) {
        if (logs.isEmpty) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_outlined,
                        size: 18, color: cs.outline),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Activity',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ...logs.map((log) => _ActivityRow(log: log)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.log});
  final dynamic log; // ActivityLog

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isStatusChange =
        log.type.dbValue == 'status_change';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              isStatusChange
                  ? Icons.swap_horiz_outlined
                  : Icons.chat_bubble_outline,
              size: 15,
              color: isStatusChange ? cs.primary : cs.outline,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message as String,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormatter.formatDateTime(log.createdAt as DateTime),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.outline,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rejection Reason Sheet ────────────────────────────────────────────────────

class _RejectionReasonSheet extends StatefulWidget {
  const _RejectionReasonSheet();

  @override
  State<_RejectionReasonSheet> createState() => _RejectionReasonSheetState();
}

class _RejectionReasonSheetState extends State<_RejectionReasonSheet> {
  static const _presets = [
    'Price too high',
    'Went with a competitor',
    'Project cancelled',
    'Budget constraints',
    'Timeline doesn\'t work',
    'Scope changed',
  ];

  String? _selected;
  final _controller = TextEditingController();
  bool get _isOther => _selected == 'Other';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reason for rejection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  ..._presets.map(
                    (r) => ChoiceChip(
                      label: Text(r),
                      selected: _selected == r,
                      onSelected: (_) => setState(() {
                        _selected = r;
                        _controller.clear();
                      }),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _isOther,
                    onSelected: (_) => setState(() => _selected = 'Other'),
                  ),
                ],
              ),
              if (_isOther) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Enter reason…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.error,
                      ),
                      // Allow confirm with no reason (skip reason = empty string sentinel).
                      onPressed: () {
                        final reason = _isOther
                            ? _controller.text.trim()
                            : (_selected ?? '');
                        Navigator.pop(context, reason);
                      },
                      child: const Text('Mark Rejected'),
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

// ── Header Card ───────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = switch (quote.status) {
      QuoteStatus.accepted => const Color(0xFF2E7D32),
      QuoteStatus.rejected => const Color(0xFFC62828),
      QuoteStatus.sent => cs.primary,
      QuoteStatus.draft => cs.outline,
      QuoteStatus.pendingNumber => cs.outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    quote.customerName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    quote.status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(label: 'Quote #', value: quote.quoteNo),
            _InfoRow(
              label: 'Created',
              value: DateFormatter.formatFull(quote.createdAt),
            ),
            if (quote.validUntil != null)
              _InfoRow(
                label: 'Valid until',
                value: DateFormatter.formatFull(quote.validUntil!),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Line Items Card ───────────────────────────────────────────────────────────

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text('Item',
                      style: TextStyle(
                          fontSize: 12, color: cs.outline)),
                ),
                SizedBox(
                  width: 50,
                  child: Text('Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: cs.outline)),
                ),
                SizedBox(
                  width: 80,
                  child: Text('Total',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12, color: cs.outline)),
                ),
              ],
            ),
            const Divider(),
            ...quote.items.map((item) => Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (item.description != null &&
                                item.description!.isNotEmpty)
                              Text(
                                item.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text(
                          item.qty % 1 == 0
                              ? item.qty.toInt().toString()
                              : item.qty.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          CurrencyFormatter.format(item.lineTotal),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ── Totals Card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _TotalsRow(label: 'Subtotal',
                value: CurrencyFormatter.format(quote.subtotal)),
            if (quote.discountPct > 0)
              _TotalsRow(
                  label: 'Discount (${quote.discountPct.toStringAsFixed(0)}%)',
                  value: '-${CurrencyFormatter.format(quote.subtotal * quote.discountPct / 100)}'),
            if (quote.taxTotal > 0)
              _TotalsRow(
                  label: 'Tax',
                  value: CurrencyFormatter.format(quote.taxTotal)),
            if (quote.freightAmt > 0)
              _TotalsRow(
                  label: 'Freight',
                  value: CurrencyFormatter.format(quote.freightAmt)),
            if (quote.insuranceAmt > 0)
              _TotalsRow(
                  label: 'Insurance',
                  value: CurrencyFormatter.format(quote.insuranceAmt)),
            if (quote.packingAmt > 0)
              _TotalsRow(
                  label: 'Packing',
                  value: CurrencyFormatter.format(quote.packingAmt)),
            const Divider(),
            _TotalsRow(
              label: 'Total',
              value: CurrencyFormatter.format(quote.total),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)
                : null,
          ),
          Text(
            value,
            style: bold
                ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)
                : null,
          ),
        ],
      ),
    );
  }
}

// ── Notes Card ────────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(notes),
          ],
        ),
      ),
    );
  }
}

// ── Linked Invoice Card ───────────────────────────────────────────────────────

class _LinkedInvoiceCard extends ConsumerWidget {
  const _LinkedInvoiceCard({required this.quoteId});
  final int quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(invoiceByQuoteIdProvider(quoteId));
    if (invoice == null) return const SizedBox.shrink();

    final statusColor = switch (invoice.status) {
      InvoiceStatus.paid => const Color(0xFF2E7D32),
      InvoiceStatus.overdue => const Color(0xFFC62828),
      InvoiceStatus.sent => Theme.of(context).colorScheme.primary,
      InvoiceStatus.partiallyPaid => const Color(0xFFE65100),
      InvoiceStatus.cancelled => Theme.of(context).colorScheme.outline,
      InvoiceStatus.draft => Theme.of(context).colorScheme.outline,
      InvoiceStatus.pendingNumber => Theme.of(context).colorScheme.outline,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Converted Invoice',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.invoiceNo,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  invoice.status.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
