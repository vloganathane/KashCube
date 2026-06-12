// ---------------------------------------------------------------------------
// Gstr3bOffsetScreen — Phase G5
// ---------------------------------------------------------------------------
// GSTR-3B Consolidated Offset Summary screen.
// Computes outward tax liability + ITC and shows the cash amount to file.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/gstr3b_pdf_service.dart';
import '../../../data/services/gstr3b_service.dart';
import '../../../data/services/gstr3b_xls_service.dart';
import '../../providers/business_provider.dart';
import 'gstr_period_picker.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _gstr3bWorkbookProvider = StateProvider<AsyncValue<Gstr3bWorkbook>?>(
  (ref) => null,
);

// ─── Screen ───────────────────────────────────────────────────────────────────

class Gstr3bOffsetScreen extends ConsumerStatefulWidget {
  const Gstr3bOffsetScreen({super.key});

  @override
  ConsumerState<Gstr3bOffsetScreen> createState() => _Gstr3bOffsetScreenState();
}

class _Gstr3bOffsetScreenState extends ConsumerState<Gstr3bOffsetScreen> {
  late GstrDateRange _range;
  bool _generating = false;
  int? _selectedBusinessId;

  // Manual override fields — ITC reversal
  final _itcRevIgstCtrl = TextEditingController(text: '0');
  final _itcRevCgstCtrl = TextEditingController(text: '0');
  final _itcRevSgstCtrl = TextEditingController(text: '0');

  // Manual override fields — interest / late fees
  final _feeIgstCtrl = TextEditingController(text: '0');
  final _feeCgstCtrl = TextEditingController(text: '0');
  final _feeSgstCtrl = TextEditingController(text: '0');

  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = ref.read(activeBusinessProvider)?.id;
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1);
    _range = GstrDateRange(
      from: DateTime(last.year, last.month, 1),
      to: DateTime(last.year, last.month + 1, 0),
      returnPeriodLabel: '${last.month.toString().padLeft(2, '0')}${last.year}',
      displayLabel: DateFormat('MMMM yyyy').format(last),
    );
  }

  @override
  void dispose() {
    _itcRevIgstCtrl.dispose();
    _itcRevCgstCtrl.dispose();
    _itcRevSgstCtrl.dispose();
    _feeIgstCtrl.dispose();
    _feeCgstCtrl.dispose();
    _feeSgstCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    final businesses = ref.read(businessesProvider).valueOrNull ?? [];
    final business = businesses
        .where((b) => b.id == _selectedBusinessId)
        .firstOrNull;
    if (business == null) {
      _showError('No active business. Configure a business first.');
      return;
    }

    setState(() => _generating = true);
    ref.read(_gstr3bWorkbookProvider.notifier).state =
        const AsyncValue.loading();

    try {
      final service = ref.read(gstr3bServiceProvider);
      final workbook = await service.compute(
        businessId: business.id!,
        from: _range.from,
        to: _range.to,
        itcReversed: _parseManual(
          igst: _itcRevIgstCtrl.text,
          cgst: _itcRevCgstCtrl.text,
          sgst: _itcRevSgstCtrl.text,
        ),
        interestLateFee: _parseManual(
          igst: _feeIgstCtrl.text,
          cgst: _feeCgstCtrl.text,
          sgst: _feeSgstCtrl.text,
        ),
      );
      if (mounted) {
        ref.read(_gstr3bWorkbookProvider.notifier).state = AsyncValue.data(
          workbook,
        );
      }
    } catch (e, st) {
      if (mounted) {
        ref.read(_gstr3bWorkbookProvider.notifier).state = AsyncValue.error(
          e,
          st,
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportPdf(Gstr3bWorkbook wb) async {
    try {
      final file = await Gstr3bPdfService.instance.generate(wb);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], text: 'GSTR-3B Offset Summary — ${wb.period}');
    } catch (e) {
      _showError('PDF export failed: $e');
    }
  }

  Future<void> _exportXls(Gstr3bWorkbook wb) async {
    try {
      final file = await Gstr3bXlsService.instance.generate(wb);
      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ], text: 'GSTR-3B Offset Summary — ${wb.period}');
    } catch (e) {
      _showError('XLS export failed: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Gstr3bTaxAmounts _parseManual({
    required String igst,
    required String cgst,
    required String sgst,
  }) {
    return Gstr3bTaxAmounts(
      igst: double.tryParse(igst) ?? 0,
      cgst: double.tryParse(cgst) ?? 0,
      sgst: double.tryParse(sgst) ?? 0,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final workbookAsync = ref.watch(_gstr3bWorkbookProvider);
    final allBusinesses = ref.watch(businessesProvider).valueOrNull ?? [];
    final business = allBusinesses
        .where((b) => b.id == _selectedBusinessId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GSTR-3B Offset Summary'),
        actions: [
          if (workbookAsync?.hasValue == true) ...[
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Export XLS',
              onPressed: () => _exportXls(workbookAsync!.value!),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(workbookAsync!.value!),
            ),
          ],
        ],
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
                      Text(
                        biz.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (biz.gstNo != null)
                        Text(
                          'GST: ${biz.gstNo}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedBusinessId = value);
                ref.read(_gstr3bWorkbookProvider.notifier).state = null;
              },
            ),
            const SizedBox(height: AppSpacing.base),
          ],
          if (business?.gstNo == null || (business?.gstNo?.isEmpty ?? true))
            _NoGstinWarning(),

          const SizedBox(height: AppSpacing.base),

          // ── Period picker ────────────────────────────────────────────────
          GstrPeriodPicker(
            onChanged: (range) {
              setState(() => _range = range);
              ref.read(_gstr3bWorkbookProvider.notifier).state = null;
            },
          ),
          const SizedBox(height: AppSpacing.base),

          // ── Manual overrides ─────────────────────────────────────────────
          _ManualOverrideCard(
            title: 'ITC Reversal (Rules 42 / 43)',
            igstCtrl: _itcRevIgstCtrl,
            cgstCtrl: _itcRevCgstCtrl,
            sgstCtrl: _itcRevSgstCtrl,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ManualOverrideCard(
            title: 'Interest / Late Fees',
            igstCtrl: _feeIgstCtrl,
            cgstCtrl: _feeCgstCtrl,
            sgstCtrl: _feeSgstCtrl,
          ),
          const SizedBox(height: AppSpacing.base),

          // ── Generate button ──────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (business == null || _generating) ? null : _generate,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.calculate_outlined),
            label: Text(_generating ? 'Computing…' : 'Compute Offset'),
          ),
          const SizedBox(height: AppSpacing.base),

          // ── Result ───────────────────────────────────────────────────────
          if (workbookAsync != null)
            workbookAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Card(
                color: context.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    'Error: $e',
                    style: TextStyle(
                      color: context.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              data: (wb) => _WorkbookView(
                workbook: wb,
                amtFmt: _amtFmt,
                onExportPdf: () => _exportPdf(wb),
                onExportXls: () => _exportXls(wb),
              ),
            ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

// ─── Business info card ───────────────────────────────────────────────────────

class _NoGstinWarning extends StatelessWidget {
  const _NoGstinWarning();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      color: context.colorScheme.errorContainer,
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'GSTIN not configured. Please update business settings '
                'before filing GSTR-3B.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Manual override card ─────────────────────────────────────────────────────

class _ManualOverrideCard extends StatelessWidget {
  const _ManualOverrideCard({
    required this.title,
    required this.igstCtrl,
    required this.cgstCtrl,
    required this.sgstCtrl,
  });

  final String title;
  final TextEditingController igstCtrl;
  final TextEditingController cgstCtrl;
  final TextEditingController sgstCtrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _AmtField(label: 'IGST', controller: igstCtrl),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _AmtField(label: 'CGST', controller: cgstCtrl),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _AmtField(label: 'SGST', controller: sgstCtrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmtField extends StatelessWidget {
  const _AmtField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        prefixText: '₹',
      ),
    );
  }
}

// ─── Workbook view ────────────────────────────────────────────────────────────

class _WorkbookView extends StatelessWidget {
  const _WorkbookView({
    required this.workbook,
    required this.amtFmt,
    required this.onExportPdf,
    required this.onExportXls,
  });

  final Gstr3bWorkbook workbook;
  final NumberFormat amtFmt;
  final VoidCallback onExportPdf;
  final VoidCallback onExportXls;

  String _a(double v) => amtFmt.format(v);

  @override
  Widget build(BuildContext context) {
    final wb = workbook;
    final offset = wb.offsetData.compute();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Period info ──────────────────────────────────────────────────
        _SectionCard(
          title: 'Period: ${wb.period}',
          subtitle:
              '${_sDate(wb.from)} — ${_sDate(wb.to)}  |  ${wb.businessGstin}',
          icon: Icons.calendar_month_outlined,
          children: [],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Table 1: Outward supply ──────────────────────────────────────
        _ExpandableTable(
          title: 'Table 1 — Outward Supply Liability',
          icon: Icons.arrow_upward_rounded,
          headers: const ['Category', 'IGST', 'CGST', 'SGST'],
          rows: [
            [
              'Regular Supply',
              _a(wb.outwardRegular.igst),
              _a(wb.outwardRegular.cgst),
              _a(wb.outwardRegular.sgst),
            ],
            ['Zero-rated / Exports', _a(wb.outwardZeroRated.igst), '—', '—'],
            [
              'Nil-rated / Exempt',
              '—',
              _a(wb.outwardNilExempted.cgst),
              _a(wb.outwardNilExempted.sgst),
            ],
          ],
          totalRow: [
            'TOTAL',
            _a(wb.totalLiability.igst),
            _a(wb.totalLiability.cgst),
            _a(wb.totalLiability.sgst),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Table 2: RCM ────────────────────────────────────────────────
        _ExpandableTable(
          title: 'Table 2 — Inward Supply (RCM)',
          icon: Icons.arrow_downward_rounded,
          headers: const ['Category', 'IGST', 'CGST', 'SGST'],
          rows: [
            [
              'RCM — Registered',
              _a(wb.rcmLiability.igst),
              _a(wb.rcmLiability.cgst),
              _a(wb.rcmLiability.sgst),
            ],
            [
              'Interest / Late Fees',
              _a(wb.interestLateFee.igst),
              _a(wb.interestLateFee.cgst),
              _a(wb.interestLateFee.sgst),
            ],
          ],
          totalRow: [
            'TOTAL RCM',
            _a(wb.rcmLiability.igst + wb.interestLateFee.igst),
            _a(wb.rcmLiability.cgst + wb.interestLateFee.cgst),
            _a(wb.rcmLiability.sgst + wb.interestLateFee.sgst),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Table 3: ITC ─────────────────────────────────────────────────
        _ExpandableTable(
          title: 'Table 3 — Input Tax Credit',
          icon: Icons.account_balance_outlined,
          headers: const ['Category', 'IGST', 'CGST', 'SGST'],
          rows: [
            [
              'Eligible ITC',
              _a(wb.itcEligible.igst),
              _a(wb.itcEligible.cgst),
              _a(wb.itcEligible.sgst),
            ],
            [
              'Reversed (Rule 42/43)',
              _a(wb.itcReversed.igst),
              _a(wb.itcReversed.cgst),
              _a(wb.itcReversed.sgst),
            ],
            [
              'Blocked (Sec. 17(5))',
              _a(wb.itcBlocked.igst),
              _a(wb.itcBlocked.cgst),
              _a(wb.itcBlocked.sgst),
            ],
          ],
          totalRow: [
            'NET ITC',
            _a(wb.netItc.igst),
            _a(wb.netItc.cgst),
            _a(wb.netItc.sgst),
          ],
        ),
        const SizedBox(height: AppSpacing.base),

        // ── Offset result card ───────────────────────────────────────────
        _OffsetCard(offset: offset, amtFmt: amtFmt),
        const SizedBox(height: AppSpacing.base),

        // ── Export buttons ───────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExportXls,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export XLS'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _sDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.textTheme.titleSmall),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Expandable table ─────────────────────────────────────────────────────────

class _ExpandableTable extends StatefulWidget {
  const _ExpandableTable({
    required this.title,
    required this.icon,
    required this.headers,
    required this.rows,
    required this.totalRow,
  });

  final String title;
  final IconData icon;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> totalRow;

  @override
  State<_ExpandableTable> createState() => _ExpandableTableState();
}

class _ExpandableTableState extends State<_ExpandableTable> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final primary = context.colorScheme.primary;
    final surfaceVariant = context.colorScheme.surfaceContainerHighest;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
              bottom: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: context.textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: context.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Table(
                border: TableBorder.all(
                  color: context.colorScheme.outlineVariant,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const FlexColumnWidth(2.5),
                  for (int i = 1; i < widget.headers.length; i++)
                    i: const FlexColumnWidth(1.5),
                },
                children: [
                  // Header row
                  TableRow(
                    decoration: BoxDecoration(color: surfaceVariant),
                    children: widget.headers
                        .map(
                          (h) => _TableCell(
                            text: h,
                            isBold: true,
                            isRight: h != widget.headers[0],
                          ),
                        )
                        .toList(),
                  ),
                  // Data rows
                  for (final row in widget.rows)
                    TableRow(
                      children: [
                        _TableCell(text: row[0]),
                        for (int i = 1; i < row.length; i++)
                          _TableCell(text: row[i], isRight: true),
                      ],
                    ),
                  // Total row
                  TableRow(
                    decoration: BoxDecoration(
                      color: context.colorScheme.primaryContainer,
                    ),
                    children: [
                      _TableCell(text: widget.totalRow[0], isBold: true),
                      for (int i = 1; i < widget.totalRow.length; i++)
                        _TableCell(
                          text: widget.totalRow[i],
                          isBold: true,
                          isRight: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.text,
    this.isBold = false,
    this.isRight = false,
  });

  final String text;
  final bool isBold;
  final bool isRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        text,
        textAlign: isRight ? TextAlign.right : TextAlign.left,
        style: context.textTheme.bodySmall?.copyWith(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: isRight ? 'RobotoMono' : null,
        ),
      ),
    );
  }
}

// ─── Offset result card ───────────────────────────────────────────────────────

class _OffsetCard extends StatelessWidget {
  const _OffsetCard({required this.offset, required this.amtFmt});
  final OffsetResult offset;
  final NumberFormat amtFmt;

  String _a(double v) => amtFmt.format(v);

  @override
  Widget build(BuildContext context) {
    final isNoCash = offset.totalCash == 0;

    return Card(
      margin: EdgeInsets.zero,
      color: isNoCash
          ? context.colorScheme.secondaryContainer
          : context.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNoCash
                      ? Icons.check_circle_outline_rounded
                      : Icons.payments_outlined,
                  color: isNoCash
                      ? context.colorScheme.onSecondaryContainer
                      : context.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'ITC Offset Result',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: isNoCash
                        ? context.colorScheme.onSecondaryContainer
                        : context.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _OffsetRow(
              label: 'IGST — by Credit',
              value: '₹${_a(offset.igstByCredit)}',
            ),
            _OffsetRow(
              label: 'CGST — by Credit',
              value: '₹${_a(offset.cgstByCredit)}',
            ),
            _OffsetRow(
              label: 'SGST — by Credit',
              value: '₹${_a(offset.sgstByCredit)}',
            ),
            const Divider(height: AppSpacing.base),
            _OffsetRow(
              label: 'IGST — Cash Required',
              value: '₹${_a(offset.igstByCash)}',
              highlight: offset.igstByCash > 0,
            ),
            _OffsetRow(
              label: 'CGST — Cash Required',
              value: '₹${_a(offset.cgstByCash)}',
              highlight: offset.cgstByCash > 0,
            ),
            _OffsetRow(
              label: 'SGST — Cash Required',
              value: '₹${_a(offset.sgstByCash)}',
              highlight: offset.sgstByCash > 0,
            ),
            const Divider(height: AppSpacing.base),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL CASH TO PAY',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: isNoCash
                        ? context.colorScheme.onSecondaryContainer
                        : context.colorScheme.onErrorContainer,
                  ),
                ),
                Text(
                  '₹${_a(offset.totalCash)}',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isNoCash
                        ? context.colorScheme.onSecondaryContainer
                        : context.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            if (offset.igstCreditBalance > 0 ||
                offset.cgstCreditBalance > 0 ||
                offset.sgstCreditBalance > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Carry-forward credit — '
                'IGST: ₹${_a(offset.igstCreditBalance)}  '
                'CGST: ₹${_a(offset.cgstCreditBalance)}  '
                'SGST: ₹${_a(offset.sgstCreditBalance)}',
                style: context.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OffsetRow extends StatelessWidget {
  const _OffsetRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodySmall),
          Text(
            value,
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'RobotoMono',
            ),
          ),
        ],
      ),
    );
  }
}
