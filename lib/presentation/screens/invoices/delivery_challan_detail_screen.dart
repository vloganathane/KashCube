import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/invoice.dart';
import '../../../data/services/delivery_challan_pdf_service.dart';
import '../../../data/services/fiscal_year_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/party_provider.dart';
import '../../providers/settings_provider.dart';
import '../invoices/invoice_detail_screen.dart';
import 'quote_builder_screen.dart';

/// Detail view for a single Delivery Challan with action buttons.
class DeliveryChallanDetailScreen extends ConsumerWidget {
  const DeliveryChallanDetailScreen({super.key, required this.challanId});

  final int challanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challanAsync =
        ref.watch(challanByIdProvider(challanId));

    return challanAsync.when(
      data: (challan) {
        if (challan == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Challan not found')),
          );
        }
        return _ChallanDetailView(challan: challan);
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

class _ChallanDetailView extends ConsumerStatefulWidget {
  const _ChallanDetailView({required this.challan});

  final DeliveryChallan challan;

  @override
  ConsumerState<_ChallanDetailView> createState() => _ChallanDetailViewState();
}

class _ChallanDetailViewState extends ConsumerState<_ChallanDetailView> {
  bool _loading = false;

  DeliveryChallan get challan => widget.challan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(challan.challanNo),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Preview PDF',
            onPressed: _loading ? null : _printPdf,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share PDF',
            onPressed: _loading ? null : _sharePdf,
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: _handleMenu,
            itemBuilder: (_) => [
              if (challan.status == ChallanStatus.draft)
                const PopupMenuItem(
                  value: _MenuAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (challan.status == ChallanStatus.draft)
                const PopupMenuItem(
                  value: _MenuAction.delete,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _StatusBanner(status: challan.status),
                const SizedBox(height: AppSpacing.base),
                _InfoCard(challan: challan),
                const SizedBox(height: AppSpacing.base),
                _ItemsCard(challan: challan),
                if (challan.vehicleNo != null ||
                    challan.transporterName != null ||
                    challan.distanceKm != null) ...[
                  const SizedBox(height: AppSpacing.base),
                  _TransportCard(challan: challan),
                ],
                if (challan.notes != null && challan.notes!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.base),
                  _NotesCard(notes: challan.notes!),
                ],
                const SizedBox(height: 120),
              ],
            ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    if (challan.status == ChallanStatus.converted) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View Invoice'),
            onPressed: challan.convertedInvoiceId != null
                ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => InvoiceDetailScreen(
                          invoiceId: challan.convertedInvoiceId!),
                    ))
                : null,
          ),
        ),
      );
    }

    if (challan.status == ChallanStatus.returned) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.base),
        child: Row(
          children: [
            if (challan.status == ChallanStatus.draft) ...[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Dispatch'),
                  onPressed: _loading ? null : _dispatch,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (challan.status == ChallanStatus.dispatched) ...[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Mark Returned'),
                  onPressed: _loading ? null : _markReturned,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Convert to Invoice'),
                onPressed: _loading ? null : _convertToInvoice,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuoteBuilderScreen(
        docType: DocumentType.deliveryChallan,
        challanId: challan.id,
      ),
    ));
    ref.read(challansProvider.notifier).invalidate();
  }

  Future<void> _dispatch() async {
    final now = DateTime.now();
    setState(() => _loading = true);
    try {
      await ref
          .read(challansProvider.notifier)
          .dispatch(challan.id!, dispatchDate: now);
    } catch (e) {
      _showError('Dispatch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markReturned() async {
    final confirm = await _confirm(
        'Mark as Returned', 'Goods have been returned to you?');
    if (!confirm) return;
    setState(() => _loading = true);
    try {
      await ref.read(challansProvider.notifier).markReturned(challan.id!);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _convertToInvoice() async {
    final confirm = await _confirm(
      'Convert to Invoice',
      'This will create a new invoice from this challan and mark it as converted.',
    );
    if (!confirm) return;

    setState(() => _loading = true);
    try {
      final invoiceNo =
          await FiscalYearService.instance.nextInvoiceNo();
      final Invoice invoice = await ref
          .read(deliveryChallanRepositoryProvider)
          .convertToInvoice(challan.id!, invoiceNo);
      ref.read(challansProvider.notifier).invalidate();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id!),
          ),
        );
      }
    } catch (e) {
      _showError('Conversion failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleMenu(_MenuAction action) {
    switch (action) {
      case _MenuAction.edit:
        _edit();
      case _MenuAction.delete:
        _delete();
    }
  }

  Future<void> _printPdf() async {
    setState(() => _loading = true);
    try {
      final business = challan.businessId != null
          ? await ref.read(businessRepositoryProvider).getById(challan.businessId!)
          : null;
      final customerParty = challan.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(challan.customerPartyId!)
          : null;
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.challanTerms);
      final file = await DeliveryChallanPdfService.instance
          .generateChallanPdf(challan, business: business, customerParty: customerParty, termsAndConditions: terms);
      // Open with system viewer
      // ignore: use_build_context_synchronously
      final result = await _openFile(file.path);
      if (!result && mounted) {
        _showError('Could not open PDF viewer');
      }
    } catch (e) {
      _showError('PDF generation failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _loading = true);
    try {
      final business = challan.businessId != null
          ? await ref.read(businessRepositoryProvider).getById(challan.businessId!)
          : null;
      final customerParty = challan.customerPartyId != null
          ? await ref.read(partyRepositoryProvider).getById(challan.customerPartyId!)
          : null;
      final terms = await ref.read(settingsRepositoryProvider).get(SettingsKeys.challanTerms);
      final file = await DeliveryChallanPdfService.instance
          .generateChallanPdf(challan, business: business, customerParty: customerParty, termsAndConditions: terms);
      await _shareFile(file.path, 'Delivery Challan ${challan.challanNo}');
    } catch (e) {
      _showError('Share failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await _confirm(
        'Delete Challan',
        'This action cannot be undone. Delete ${challan.challanNo}?');
    if (!confirm) return;
    await ref.read(challansProvider.notifier).remove(challan.id!);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Opens a file with the device's default viewer.
  Future<bool> _openFile(String path) async {
    try {
      final result = await OpenFile.open(path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  Future<void> _shareFile(String path, String subject) async {
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: subject,
      );
    } catch (_) {}
  }
}

enum _MenuAction { edit, delete }

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final ChallanStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case ChallanStatus.draft:
        bg = context.colorScheme.surfaceVariant;
        fg = context.colorScheme.onSurfaceVariant;
        icon = Icons.edit_note_outlined;
        label = 'Draft — not yet dispatched';
        break;
      case ChallanStatus.dispatched:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        icon = Icons.local_shipping_outlined;
        label = 'Goods Dispatched';
        break;
      case ChallanStatus.returned:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        icon = Icons.assignment_return_outlined;
        label = 'Goods Returned';
        break;
      case ChallanStatus.converted:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        icon = Icons.check_circle_outline;
        label = 'Converted to Invoice';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details',
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: AppSpacing.lg),
            _Row('Challan No.', challan.challanNo),
            _Row('Customer', challan.customerName),
            _Row('Date',
                DateFormatter.formatFull(challan.challanDate)),
            _Row('Purpose', challan.purpose.label),
            if (challan.customerGstin != null &&
                challan.customerGstin!.isNotEmpty)
              _Row('Customer GSTIN', challan.customerGstin!),
            if (challan.placeOfSupply != null &&
                challan.placeOfSupply!.isNotEmpty)
              _Row('Place of Supply', challan.placeOfSupply!),
            if (challan.dispatchDate != null)
              _Row('Dispatched On',
                  DateFormatter.formatFull(challan.dispatchDate!)),
            if (challan.expectedReturnDate != null)
              _Row('Expected Return',
                  DateFormatter.formatFull(challan.expectedReturnDate!)),
            if (challan.ewbNo != null && challan.ewbNo!.isNotEmpty)
              _Row('EWB No.', challan.ewbNo!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.outline)),
          ),
          Expanded(
              child: Text(value,
                  style: context.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Items',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text('${challan.items.length} item(s)',
                    style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.outline)),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            // Header
            Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _HeaderCell('Item')),
                Expanded(child: _HeaderCell('Qty', right: true)),
                Expanded(child: _HeaderCell('Rate', right: true)),
                Expanded(child: _HeaderCell('Amount', right: true)),
              ],
            ),
            const Divider(height: AppSpacing.sm),
            ...challan.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.itemName,
                                style: context.textTheme.bodyMedium),
                            if (item.description != null &&
                                item.description!.isNotEmpty)
                              Text(item.description!,
                                  style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colorScheme.outline)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${_fmtQty(item.qty)} ${item.unit}',
                          textAlign: TextAlign.right,
                          style: context.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          CurrencyFormatter.format(item.unitPrice),
                          textAlign: TextAlign.right,
                          style: context.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          CurrencyFormatter.format(item.lineTotal),
                          textAlign: TextAlign.right,
                          style: context.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Total: ',
                    style: context.textTheme.titleSmall),
                Text(
                  CurrencyFormatter.format(challan.subtotal),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toStringAsFixed(0);
    return qty.toStringAsFixed(2);
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.right = false});

  final String label;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: context.textTheme.labelSmall
          ?.copyWith(color: context.colorScheme.outline),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transport Details',
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: AppSpacing.lg),
            if (challan.transporterName != null &&
                challan.transporterName!.isNotEmpty)
              _Row('Transporter', challan.transporterName!),
            if (challan.vehicleNo != null && challan.vehicleNo!.isNotEmpty)
              _Row('Vehicle No.', challan.vehicleNo!),
            if (challan.transportMode != null &&
                challan.transportMode!.isNotEmpty)
              _Row('Mode', _modeLabel(challan.transportMode!)),
            if (challan.distanceKm != null)
              _Row('Distance', '${challan.distanceKm} km'),
          ],
        ),
      ),
    );
  }

  String _modeLabel(String m) {
    switch (m) {
      case '1': return 'Road';
      case '2': return 'Rail';
      case '3': return 'Air';
      case '4': return 'Ship';
      default: return m;
    }
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes',
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: AppSpacing.lg),
            Text(notes, style: context.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
