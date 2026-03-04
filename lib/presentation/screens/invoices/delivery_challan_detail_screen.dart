import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/delivery_challan.dart';
import '../../../data/models/business.dart';
import '../../../data/models/ewb_transport_details.dart';
import '../../../data/models/invoice.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/delivery_challan_pdf_service.dart';
import '../../../data/services/eway_bill_service.dart';
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
              if (challan.status == ChallanStatus.draft ||
                  challan.status == ChallanStatus.dispatched)
                const PopupMenuItem(
                  value: _MenuAction.ewayBill,
                  child: ListTile(
                    leading: Icon(Icons.receipt_outlined),
                    title: Text('e-Way Bill'),
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
      case _MenuAction.ewayBill:
        _showEwayBillSheet();
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
          .generateChallanPdf(challan, business: business, customerParty: customerParty, termsAndConditions: terms ?? SettingsKeys.defaultChallanTerms);
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
          .generateChallanPdf(challan, business: business, customerParty: customerParty, termsAndConditions: terms ?? SettingsKeys.defaultChallanTerms);
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

  void _showEwayBillSheet() {
    final business = ref.read(activeBusinessProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DcEwayBillSheet(
        challan: challan,
        business: business,
        onExported: (updated) =>
            ref.read(challansProvider.notifier).edit(updated),
      ),
    );
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

enum _MenuAction { edit, ewayBill, delete }

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

// ── DC e-Way Bill Sheet ───────────────────────────────────────────────────────

class _DcEwayBillSheet extends StatefulWidget {
  const _DcEwayBillSheet({
    required this.challan,
    this.business,
    this.onExported,
  });

  final DeliveryChallan challan;
  final Business? business; // active business profile
  /// Called with the updated [DeliveryChallan] (transport fields filled) after
  /// a successful export so the caller can persist the changes.
  final void Function(DeliveryChallan updated)? onExported;

  @override
  State<_DcEwayBillSheet> createState() => _DcEwayBillSheetState();
}

class _DcEwayBillSheetState extends State<_DcEwayBillSheet> {
  final _formKey = GlobalKey<FormState>();

  String _mode = '1'; // Road default
  final _vehicleCtrl = TextEditingController();
  final _transporterNameCtrl = TextEditingController();
  final _transporterGstinCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _docNoCtrl = TextEditingController();
  final _docDateCtrl = TextEditingController();

  List<Map<String, dynamic>> _frequentTransporters = [];
  bool _exporting = false;

  static const _modes = [
    ('1', 'Road'),
    ('2', 'Rail'),
    ('3', 'Air'),
    ('4', 'Ship'),
  ];

  static const _vehicleRegex = r'^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$';

  @override
  void initState() {
    super.initState();
    // Pre-fill from challan if transport was previously filled.
    if (widget.challan.transportMode != null) {
      _mode = widget.challan.transportMode!;
    }
    if (widget.challan.vehicleNo != null) {
      _vehicleCtrl.text = widget.challan.vehicleNo!;
    }
    if (widget.challan.transporterName != null) {
      _transporterNameCtrl.text = widget.challan.transporterName!;
    }
    if (widget.challan.distanceKm != null) {
      _distanceCtrl.text = widget.challan.distanceKm.toString();
    }
    _loadFrequentTransporters();
  }

  Future<void> _loadFrequentTransporters() async {
    final rows = await DatabaseHelper.instance.getTransporters();
    if (mounted) setState(() => _frequentTransporters = rows);
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _transporterNameCtrl.dispose();
    _transporterGstinCtrl.dispose();
    _distanceCtrl.dispose();
    _docNoCtrl.dispose();
    _docDateCtrl.dispose();
    super.dispose();
  }

  int? get _validityDays {
    final km = int.tryParse(_distanceCtrl.text.trim());
    if (km == null || km <= 0) return null;
    return km < 100 ? 1 : (km / 100).floor();
  }

  Future<void> _export() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _exporting = true);

    final transport = EwbTransportDetails(
      mode: _mode,
      vehicleNo:
          _vehicleCtrl.text.trim().isEmpty ? null : _vehicleCtrl.text.trim(),
      transporterName: _transporterNameCtrl.text.trim().isEmpty
          ? null
          : _transporterNameCtrl.text.trim(),
      transporterGstin: _transporterGstinCtrl.text.trim().isEmpty
          ? null
          : _transporterGstinCtrl.text.trim(),
      distanceKm: int.tryParse(_distanceCtrl.text.trim()),
      transDocNo:
          _docNoCtrl.text.trim().isEmpty ? null : _docNoCtrl.text.trim(),
      transDocDate:
          _docDateCtrl.text.trim().isEmpty ? null : _docDateCtrl.text.trim(),
    );

    try {
      await EwayBillService.instance.exportAndShareForChallan(
        widget.challan,
        business: widget.business,
        transport: transport,
      );

      // ── Save transport fields back to the challan ─────────────────────
      if (widget.challan.id != null) {
        final updated = widget.challan.copyWith(
          transportMode: transport.mode,
          vehicleNo: transport.vehicleNo,
          transporterName: transport.transporterName,
          distanceKm: transport.distanceKm,
        );
        widget.onExported?.call(updated);
      }

      // Persist frequent transporter.
      if (transport.transporterName != null) {
        await DatabaseHelper.instance.saveTransporter(
          name: transport.transporterName!,
          gstin: transport.transporterGstin,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'e-Way Bill JSON exported for ${widget.challan.challanNo}. '
              'Upload to ewaybillgst.gov.in to generate EWB number.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBelowThreshold =
        EwayBillService.instance.isBelowThresholdForChallan(widget.challan);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── handle ─────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('e-Way Bill', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Delivery Challan ${widget.challan.challanNo}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── threshold warning ──────────────────────────────────────
              if (isBelowThreshold) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: theme.colorScheme.secondary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Challan total is below ₹50,000. EWB is optional for this consignment.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── existing EWB badge ─────────────────────────────────────
              if (widget.challan.hasEwb) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'EWB No: ${widget.challan.ewbNo}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── transport mode ─────────────────────────────────────────
              Text('Transport Mode', style: theme.textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                segments: [
                  for (final (code, label) in _modes)
                    ButtonSegment(value: code, label: Text(label)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── vehicle number (road & ship only) ─────────────────────
              if (_mode == '1' || _mode == '4') ...[
                TextFormField(
                  controller: _vehicleCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number',
                    hintText: 'MH12AB1234',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) return null;
                    if (!RegExp(_vehicleRegex).hasMatch(val)) {
                      return 'Format: MH12AB1234 (state + RTO + alpha + serial)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── transporter name (autocomplete) ───────────────────────
              Autocomplete<String>(
                optionsBuilder: (v) {
                  if (v.text.isEmpty) return const [];
                  return _frequentTransporters
                      .map((r) => r['name'] as String)
                      .where((n) =>
                          n.toLowerCase().contains(v.text.toLowerCase()));
                },
                onSelected: (name) {
                  _transporterNameCtrl.text = name;
                  final match = _frequentTransporters
                      .firstWhere((r) => r['name'] == name,
                          orElse: () => {});
                  if (match['gstin'] != null) {
                    _transporterGstinCtrl.text = match['gstin'] as String;
                  }
                },
                fieldViewBuilder:
                    (context, ctrl, focusNode, onEditingComplete) {
                  ctrl.text = _transporterNameCtrl.text;
                  ctrl.addListener(
                      () => _transporterNameCtrl.text = ctrl.text);
                  return TextFormField(
                    controller: ctrl,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Transporter Name (optional)',
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // ── transporter GSTIN ──────────────────────────────────────
              TextFormField(
                controller: _transporterGstinCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Transporter GSTIN (optional)',
                  hintText: '22AAAAA0000A1Z5',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── distance + validity chip ───────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _distanceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Distance (km)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return null;
                        if (int.tryParse(val) == null) return 'Enter a number';
                        if (int.parse(val) <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                  if (_validityDays != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Chip(
                      avatar: const Icon(Icons.timer_outlined, size: 16),
                      label: Text(
                        'Valid $_validityDays day${_validityDays == 1 ? '' : 's'}',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── export button ─────────────────────────────────────────
              FilledButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: const Text('Export JSON'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
