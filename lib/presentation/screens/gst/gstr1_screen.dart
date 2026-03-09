import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/gstr1_pdf_service.dart';
import '../../../data/services/gstr1_service.dart';
import '../../providers/business_provider.dart';
import 'gstr_period_picker.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _gstr1WorkbookProvider =
    StateProvider<AsyncValue<Gstr1Workbook>?>((ref) => null);

// ─── Screen ───────────────────────────────────────────────────────────────────

/// GSTR-1 Workbook Export screen (Phase E3).
///
/// Allows the user to:
///   1. Pick a period (month or quarter)
///   2. Generate a GSTR-1 workbook preview
///   3. Export CSV ZIP or PDF summary
class Gstr1Screen extends ConsumerStatefulWidget {
  const Gstr1Screen({super.key});

  @override
  ConsumerState<Gstr1Screen> createState() => _Gstr1ScreenState();
}

class _Gstr1ScreenState extends ConsumerState<Gstr1Screen>
    with SingleTickerProviderStateMixin {
  late GstrDateRange _range;
  TabController? _tabController;
  bool _generating = false;
  int? _selectedBusinessId;

  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = ref.read(activeBusinessProvider)?.id;
    // _tabController is always ready so the workbook view never crashes when
    // the StateProvider already holds data from a previous visit.
    _tabController = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    // Default to last completed month
    final lastMonth = DateTime(now.year, now.month - 1);
    _range = GstrDateRange(
      from: DateTime(lastMonth.year, lastMonth.month, 1),
      to: DateTime(lastMonth.year, lastMonth.month + 1, 0),
      returnPeriodLabel:
          '${lastMonth.month.toString().padLeft(2, '0')}${lastMonth.year}',
      displayLabel:
          DateFormat('MMMM yyyy').format(lastMonth),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final businesses = ref.read(businessesProvider).valueOrNull ?? [];
    final business =
        businesses.where((b) => b.id == _selectedBusinessId).firstOrNull;
    if (business == null) {
      _showError('No active business. Please configure a business first.');
      return;
    }

    setState(() => _generating = true);
    ref.read(_gstr1WorkbookProvider.notifier).state =
        const AsyncValue.loading();

    try {
      final service = ref.read(gstr1ServiceProvider);
      final workbook = await service.generateWorkbook(
        businessId: business.id!,
        from: _range.from,
        to: _range.to,
      );
      // Reset tab controller to the first tab for the new workbook.
      _tabController!.animateTo(0);
      ref.read(_gstr1WorkbookProvider.notifier).state =
          AsyncValue.data(workbook);
    } catch (e, st) {
      ref.read(_gstr1WorkbookProvider.notifier).state =
          AsyncValue.error(e, st);
    } finally {
      setState(() => _generating = false);
    }
  }

  Future<void> _exportCsvZip(Gstr1Workbook wb) async {
    final service = ref.read(gstr1ServiceProvider);
    try {
      final xFile = await service.exportCsvZip(wb);
      await Share.shareXFiles([xFile],
          text: 'GSTR-1 Workbook ${wb.returnPeriodLabel}');
    } catch (e) {
      _showError('CSV export failed: $e');
    }
  }

  Future<void> _exportPdf(Gstr1Workbook wb) async {
    try {
      final file = await Gstr1PdfService.instance.generate(wb);
      await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: 'GSTR-1 Summary ${wb.returnPeriodLabel}');
    } catch (e) {
      _showError('PDF export failed: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final workbookAsync = ref.watch(_gstr1WorkbookProvider);
    final allBusinesses = ref.watch(businessesProvider).valueOrNull ?? [];
    final business =
        allBusinesses.where((b) => b.id == _selectedBusinessId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GSTR-1 Workbook'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // ── Business selector ─────────────────────────────────────────
          if (allBusinesses.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedBusinessId,
              decoration: const InputDecoration(
                labelText: 'Business',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business_outlined),
              ),
              items: allBusinesses.map((biz) {
                return DropdownMenuItem(
                  value: biz.id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(biz.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (biz.gstNo != null)
                        Text(
                          'GST: ${biz.gstNo}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedBusinessId = value);
                ref.read(_gstr1WorkbookProvider.notifier).state = null;
              },
            ),
            const SizedBox(height: AppSpacing.base),
          ],
          if (business?.gstNo == null || (business?.gstNo?.isEmpty ?? true))
            _NoGstinWarning(hasGstin: false),

          // ── Period picker ────────────────────────────────────────────────
          GstrPeriodPicker(
            onChanged: (range) {
              setState(() => _range = range);
              // Clear previous workbook on period change
              ref.read(_gstr1WorkbookProvider.notifier).state = null;
            },
          ),
          const SizedBox(height: AppSpacing.base),

          // ── Generate button ──────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (business == null || _generating) ? null : _generate,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_circle_outline_rounded),
            label: Text(_generating ? 'Generating…' : 'Generate Preview'),
          ),
          const SizedBox(height: AppSpacing.base),

          // ── Result ───────────────────────────────────────────────────────
          if (workbookAsync != null)
            workbookAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Card(
                color: context.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text('Error: $e',
                      style: TextStyle(
                          color: context.colorScheme.onErrorContainer)),
                ),
              ),
              data: (wb) => _WorkbookPreview(
                workbook: wb,
                tabController: _tabController!,
                onExportCsv: () => _exportCsvZip(wb),
                onExportPdf: () => _exportPdf(wb),
                amtFmt: _amtFmt,
              ),
            ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

// ─── No GSTIN warning ─────────────────────────────────────────────────────────

class _NoGstinWarning extends StatelessWidget {
  const _NoGstinWarning({required this.hasGstin});
  final bool hasGstin;

  @override
  Widget build(BuildContext context) {
    if (hasGstin) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: Card(
        color: context.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: context.colorScheme.error, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Business GSTIN not set. Go to Business Settings to add your GSTIN before generating GSTR-1.',
                  style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Workbook preview ─────────────────────────────────────────────────────────

class _WorkbookPreview extends StatelessWidget {
  const _WorkbookPreview({
    required this.workbook,
    required this.tabController,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.amtFmt,
  });

  final Gstr1Workbook workbook;
  final TabController tabController;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Summary cards row ──────────────────────────────────────────────
        _SummaryGrid(workbook: workbook, amtFmt: amtFmt),
        const SizedBox(height: AppSpacing.base),

        // ── Tax liability strip ────────────────────────────────────────────
        _TaxLiabilityStrip(workbook: workbook, amtFmt: amtFmt),
        const SizedBox(height: AppSpacing.base),

        // ── Export buttons ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExportCsv,
                icon: const Icon(Icons.folder_zip_outlined),
                label: const Text('Export CSV (ZIP)'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF Summary'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),

        // ── Table tabs ──────────────────────────────────────────────────────
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              TabBar(
                controller: tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'T4 B2B'),
                  Tab(text: 'T5 B2C Large'),
                  Tab(text: 'T7 B2C Small'),
                  Tab(text: 'T9 CDN'),
                  Tab(text: 'T12 HSN'),
                  Tab(text: 'T13 Docs'),
                ],
              ),
              SizedBox(
                height: 340,
                child: TabBarView(
                  controller: tabController,
                  children: [
                    _T4View(rows: workbook.tableB2b, amtFmt: amtFmt),
                    _T5View(rows: workbook.tableB2cLarge, amtFmt: amtFmt),
                    _T7View(rows: workbook.tableB2cSmall, amtFmt: amtFmt),
                    _T9View(rows: workbook.tableCdn, amtFmt: amtFmt),
                    _T12View(rows: workbook.tableHsn, amtFmt: amtFmt),
                    _T13View(rows: workbook.tableDocSummary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Summary grid ─────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.workbook, required this.amtFmt});

  final Gstr1Workbook workbook;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryItem('T4 B2B', '${workbook.totalB2bInvoices} inv',
          '₹${amtFmt.format(workbook.tableB2b.fold(0.0, (s, r) => s + r.taxableValue))}',
          Icons.receipt_long_outlined),
      _SummaryItem('T5 B2C Large', '${workbook.tableB2cLarge.length} rows',
          '₹${amtFmt.format(workbook.tableB2cLarge.fold(0.0, (s, r) => s + r.taxableValue))}',
          Icons.north_east_rounded),
      _SummaryItem('T7 B2C Small', '${workbook.tableB2cSmall.length} rows',
          '₹${amtFmt.format(workbook.tableB2cSmall.fold(0.0, (s, r) => s + r.taxableValue))}',
          Icons.people_outline_rounded),
      _SummaryItem('T9 CDN', '${workbook.tableCdn.length} notes',
          '₹${amtFmt.format(workbook.tableCdn.fold(0.0, (s, r) => s + r.taxableValue))}',
          Icons.undo_rounded),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.6,
      children: items.map((i) => _SummaryTile(item: i)).toList(),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.count, this.value, this.icon);
  final String label;
  final String count;
  final String value;
  final IconData icon;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.item});
  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(item.icon,
                color: context.colorScheme.primary, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.label,
                      style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant)),
                  Text(item.count,
                      style: context.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(item.value,
                      style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tax liability strip ──────────────────────────────────────────────────────

class _TaxLiabilityStrip extends StatelessWidget {
  const _TaxLiabilityStrip(
      {required this.workbook, required this.amtFmt});

  final Gstr1Workbook workbook;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            taxCell('Taxable',
                '₹${amtFmt.format(workbook.totalTaxableValue)}', context),
            _vDivider(context),
            taxCell(
                'CGST', '₹${amtFmt.format(workbook.totalCgst)}', context),
            _vDivider(context),
            taxCell(
                'SGST', '₹${amtFmt.format(workbook.totalSgst)}', context),
            _vDivider(context),
            taxCell(
                'IGST', '₹${amtFmt.format(workbook.totalIgst)}', context),
            _vDivider(context),
            taxCell(
              'Total Tax',
              '₹${amtFmt.format(workbook.totalTaxLiability)}',
              context,
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  static Widget taxCell(String label, String value, BuildContext context,
      {bool highlight = false}) =>
      Column(
        children: [
          Text(label,
              style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onPrimaryContainer
                      .withValues(alpha: 0.7))),
          Text(value,
              style: context.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: highlight
                    ? context.colorScheme.primary
                    : context.colorScheme.onPrimaryContainer,
              )),
        ],
      );

  static Widget _vDivider(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: context.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
      );
}

// ─── Table views ─────────────────────────────────────────────────────────────

class _T4View extends StatelessWidget {
  const _T4View({required this.rows, required this.amtFmt});
  final List<Gstr1B2bRow> rows;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['GSTIN', 'Invoice No', 'Date', 'Rate%', 'Taxable', 'CGST', 'SGST', 'IGST'],
      rows: rows.map((r) => [
            r.receiverGstin,
            r.invoiceNo,
            r.invoiceDate,
            r.rate.toStringAsFixed(0),
            '₹${amtFmt.format(r.taxableValue)}',
            '₹${amtFmt.format(r.cgst)}',
            '₹${amtFmt.format(r.sgst)}',
            '₹${amtFmt.format(r.igst)}',
          ]).toList(),
    );
  }
}

class _T5View extends StatelessWidget {
  const _T5View({required this.rows, required this.amtFmt});
  final List<Gstr1B2cLargeRow> rows;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['POS', 'Rate%', 'Taxable', 'IGST'],
      rows: rows.map((r) => [
            r.placeOfSupply,
            r.rate.toStringAsFixed(0),
            '₹${amtFmt.format(r.taxableValue)}',
            '₹${amtFmt.format(r.igst)}',
          ]).toList(),
    );
  }
}

class _T7View extends StatelessWidget {
  const _T7View({required this.rows, required this.amtFmt});
  final List<Gstr1B2cSmallRow> rows;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['Type', 'POS', 'Rate%', 'Taxable', 'CGST', 'SGST', 'IGST'],
      rows: rows.map((r) => [
            r.type,
            r.placeOfSupply,
            r.rate.toStringAsFixed(0),
            '₹${amtFmt.format(r.taxableValue)}',
            '₹${amtFmt.format(r.cgst)}',
            '₹${amtFmt.format(r.sgst)}',
            '₹${amtFmt.format(r.igst)}',
          ]).toList(),
    );
  }
}

class _T9View extends StatelessWidget {
  const _T9View({required this.rows, required this.amtFmt});
  final List<Gstr1CdnRow> rows;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['GSTIN', 'Note No', 'Date', 'Type', 'Orig Invoice', 'Rate%', 'Taxable'],
      rows: rows.map((r) => [
            r.receiverGstin,
            r.noteNo,
            r.noteDate,
            r.noteType == 'C' ? 'Credit' : 'Debit',
            r.originalInvoiceNo,
            r.rate.toStringAsFixed(0),
            '₹${amtFmt.format(r.taxableValue)}',
          ]).toList(),
    );
  }
}

class _T12View extends StatelessWidget {
  const _T12View({required this.rows, required this.amtFmt});
  final List<Gstr1HsnRow> rows;
  final NumberFormat amtFmt;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['HSN/SAC', 'Description', 'UQC', 'Qty', 'Taxable', 'CGST+SGST', 'IGST'],
      rows: rows.map((r) => [
            r.hsnCode,
            r.description,
            r.uqc,
            r.totalQty.toStringAsFixed(2),
            '₹${amtFmt.format(r.taxableValue)}',
            '₹${amtFmt.format(r.cgst + r.sgst)}',
            '₹${amtFmt.format(r.igst)}',
          ]).toList(),
    );
  }
}

class _T13View extends StatelessWidget {
  const _T13View({required this.rows});
  final List<Gstr1DocSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyTable();
    return _ScrollableTable(
      headers: const ['Nature of Document', 'From', 'To', 'Total', 'Cancelled'],
      rows: rows.map((r) => [
            r.natureOfDocument,
            r.seriesFrom,
            r.seriesTo,
            '${r.totalSubmitted}',
            '${r.cancelled}',
          ]).toList(),
    );
  }
}

// ─── Generic scrollable table ─────────────────────────────────────────────────

class _ScrollableTable extends StatelessWidget {
  const _ScrollableTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 36,
          columnSpacing: AppSpacing.md,
          headingTextStyle: context.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colorScheme.primary),
          dataTextStyle: const TextStyle(fontSize: 11),
          columns:
              headers.map((h) => DataColumn(label: Text(h))).toList(),
          rows: rows
              .map(
                (r) => DataRow(
                  cells: r.map((c) => DataCell(Text(c))).toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _EmptyTable extends StatelessWidget {
  const _EmptyTable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_rows_outlined,
              size: 36, color: context.colorScheme.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          Text('No data for this table',
              style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
