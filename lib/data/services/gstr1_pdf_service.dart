// ---------------------------------------------------------------------------
// Gstr1PdfService — Phase E2
// ---------------------------------------------------------------------------
// Generates a one-page GSTR-1 workbook summary PDF for the CA / accountant.
// Layout mirrors the spec table in GSTR1_WORKBOOK_SPEC.md.
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'gstr1_service.dart';

class Gstr1PdfService {
  Gstr1PdfService._();
  static final instance = Gstr1PdfService._();

  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a one-pager summary PDF for [workbook] and returns the [File].
  Future<File> generate(Gstr1Workbook workbook) async {
    final bytes = await _buildPdf(workbook);
    final dir = await getTemporaryDirectory();
    final fileName =
        'GSTR1_${workbook.returnPeriodLabel}_${workbook.businessGstin}_Summary.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── PDF builder ──────────────────────────────────────────────────────────

  Future<List<int>> _buildPdf(Gstr1Workbook wb) async {
    final doc = pw.Document();

    // ── Typography ────────────────────────────────────────────────────────
    const white70 = PdfColor(1, 1, 1, 0.7);
    const base = pw.TextStyle(fontSize: 9);
    final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final titleStyle =
        pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold);
    final sub = const pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
    final small = const pw.TextStyle(fontSize: 8, color: PdfColors.grey600);

    // ── Colours ───────────────────────────────────────────────────────────
    const primary = PdfColor.fromInt(0xFF1B5E20);
    const headerBg = PdfColor.fromInt(0xFFE8F5E9);
    const rowAlt = PdfColor.fromInt(0xFFF5F5F5);
    const totalBg = PdfColor.fromInt(0xFF2E7D32);
    const amtColor = PdfColor.fromInt(0xFF1A237E);

    // ── Period label (e.g. "032026" → "March 2026") ───────────────────────
    final periodLabel = _periodLabel(wb.returnPeriodLabel);

    // ── Distinct HSN count ────────────────────────────────────────────────
    final hsnCount = wb.tableHsn.map((r) => r.hsnCode).toSet().length;

    // ── Count cancelled docs from T13 ────────────────────────────────────
    final cancelledCount =
        wb.tableDocSummary.fold<int>(0, (s, r) => s + r.cancelled);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Header block ────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: primary,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'GSTR-1 WORKBOOK SUMMARY',
                        style: titleStyle.copyWith(color: PdfColors.white),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(wb.businessName,
                          style: base.copyWith(color: PdfColors.white)),
                      pw.Text('GSTIN: ${wb.businessGstin}',
                          style: base.copyWith(color: white70)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Return Period: $periodLabel',
                        style: bold.copyWith(color: PdfColors.white),
                      ),
                      pw.Text(
                        '(${wb.returnPeriodLabel})',
                        style: small.copyWith(color: white70),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Generated: ${_dateFmt.format(DateTime.now())}',
                        style: small.copyWith(color: white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // ── Period range ─────────────────────────────────────────────
            pw.Text(
              'Period: ${_dateFmt.format(wb.from)}  –  ${_dateFmt.format(wb.to)}',
              style: sub,
            ),
            pw.SizedBox(height: 10),

            // ── Table summary ─────────────────────────────────────────────
            pw.Text('TABLE-WISE SUMMARY',
                style: bold.copyWith(color: primary)),
            pw.SizedBox(height: 4),
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FixedColumnWidth(52),
                2: const pw.FixedColumnWidth(80),
                3: const pw.FixedColumnWidth(52),
                4: const pw.FixedColumnWidth(52),
                5: const pw.FixedColumnWidth(52),
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerBg),
                  children: [
                    _th('Table / Description', bold),
                    _th('Invoices', bold),
                    _th('Taxable Value', bold),
                    _th('CGST', bold),
                    _th('SGST', bold),
                    _th('IGST', bold),
                  ],
                ),
                // T4
                _summaryRow(
                  label: 'T4 — B2B (Registered Buyers)',
                  count: wb.totalB2bInvoices,
                  taxable: wb.tableB2b.fold(0, (s, r) => s + r.taxableValue),
                  cgst: wb.tableB2b.fold(0, (s, r) => s + r.cgst),
                  sgst: wb.tableB2b.fold(0, (s, r) => s + r.sgst),
                  igst: wb.tableB2b.fold(0, (s, r) => s + r.igst),
                  odd: false,
                  base: base,
                ),
                // T5
                _summaryRow(
                  label: 'T5 — B2C Large (Inter-state > ₹2.5L)',
                  count: wb.tableB2cLarge.length,
                  taxable:
                      wb.tableB2cLarge.fold(0, (s, r) => s + r.taxableValue),
                  cgst: 0,
                  sgst: 0,
                  igst: wb.tableB2cLarge.fold(0, (s, r) => s + r.igst),
                  odd: true,
                  base: base,
                ),
                // T7
                _summaryRow(
                  label: 'T7 — B2C Small (Other)',
                  count: wb.tableB2cSmall.length,
                  taxable:
                      wb.tableB2cSmall.fold(0, (s, r) => s + r.taxableValue),
                  cgst: wb.tableB2cSmall.fold(0, (s, r) => s + r.cgst),
                  sgst: wb.tableB2cSmall.fold(0, (s, r) => s + r.sgst),
                  igst: wb.tableB2cSmall.fold(0, (s, r) => s + r.igst),
                  odd: false,
                  base: base,
                ),
                // T9
                _summaryRow(
                  label: 'T9 — Credit / Debit Notes',
                  count: wb.tableCdn.length,
                  taxable: wb.tableCdn.fold(0, (s, r) => s + r.taxableValue),
                  cgst: wb.tableCdn.fold(0, (s, r) => s + r.cgst),
                  sgst: wb.tableCdn.fold(0, (s, r) => s + r.sgst),
                  igst: wb.tableCdn.fold(0, (s, r) => s + r.igst),
                  odd: true,
                  base: base,
                ),
                // T12
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
                  children: [
                    _td('T12 — HSN/SAC Summary', base),
                    _tdR('$hsnCount HSN codes', base),
                    _tdR('—', base),
                    _tdR('—', base),
                    _tdR('—', base),
                    _tdR('—', base),
                  ],
                ),
                // T13
                pw.TableRow(
                  children: [
                    _td('T13 — Document Summary', base),
                    _tdR(
                        '${wb.tableDocSummary.fold<int>(0, (s, r) => s + r.totalSubmitted)} docs',
                        base),
                    _tdR('—', base),
                    _tdR('—', base),
                    _tdR('—', base),
                    _tdR(cancelledCount > 0 ? '$cancelledCount ❌' : '—', base),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // ── Tax liability totals ──────────────────────────────────────
            pw.Text('TAX LIABILITY SUMMARY', style: bold.copyWith(color: primary)),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColors.grey300, width: 0.4),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _taxBlock(
                      'Total Taxable Value',
                      '₹${_amtFmt.format(wb.totalTaxableValue)}',
                      bold,
                      amtColor),
                  _divider(),
                  _taxBlock(
                      'CGST', '₹${_amtFmt.format(wb.totalCgst)}', bold, amtColor),
                  _divider(),
                  _taxBlock(
                      'SGST', '₹${_amtFmt.format(wb.totalSgst)}', bold, amtColor),
                  _divider(),
                  _taxBlock(
                      'IGST', '₹${_amtFmt.format(wb.totalIgst)}', bold, amtColor),
                  _divider(),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: const pw.BoxDecoration(
                      color: totalBg,
                      borderRadius:
                          pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: _taxBlock(
                        'TOTAL TAX LIABILITY',
                        '₹${_amtFmt.format(wb.totalTaxLiability)}',
                        bold.copyWith(fontSize: 10),
                        PdfColors.white),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // ── HSN quick view ────────────────────────────────────────────
            if (wb.tableHsn.isNotEmpty) ...[
              pw.Text('HSN / SAC CODE SUMMARY (T12)',
                  style: bold.copyWith(color: primary)),
              pw.SizedBox(height: 4),
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(72),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FixedColumnWidth(36),
                  3: const pw.FixedColumnWidth(52),
                  4: const pw.FixedColumnWidth(52),
                  5: const pw.FixedColumnWidth(52),
                  6: const pw.FixedColumnWidth(52),
                },
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.4),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: headerBg),
                    children: [
                      _th('HSN/SAC', bold),
                      _th('Description', bold),
                      _th('UQC', bold),
                      _th('Qty', bold),
                      _th('Taxable', bold),
                      _th('Tax (IGST)', bold),
                      _th('Tax (CGST+SGST)', bold),
                    ],
                  ),
                  for (int i = 0; i < wb.tableHsn.length; i++)
                    pw.TableRow(
                      decoration: i.isOdd
                          ? const pw.BoxDecoration(color: rowAlt)
                          : null,
                      children: [
                        _td(wb.tableHsn[i].hsnCode, base),
                        _td(wb.tableHsn[i].description, base),
                        _td(wb.tableHsn[i].uqc, base),
                        _tdR(wb.tableHsn[i].totalQty.toStringAsFixed(2), base),
                        _tdR(
                            '₹${_amtFmt.format(wb.tableHsn[i].taxableValue)}',
                            base),
                        _tdR(
                            '₹${_amtFmt.format(wb.tableHsn[i].igst)}', base),
                        _tdR(
                            '₹${_amtFmt.format(wb.tableHsn[i].cgst + wb.tableHsn[i].sgst)}',
                            base),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
            ],

            // ── Footer ────────────────────────────────────────────────────
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400, thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated by KashCube — all data stored locally on your device.',
                  style: small,
                ),
                pw.Text(
                  'GSTR-1 Return Period: ${wb.returnPeriodLabel}',
                  style: small,
                ),
              ],
            ),
          ],
        );
      },
    ));

    return doc.save();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static pw.TableRow _summaryRow({
    required String label,
    required int count,
    required double taxable,
    required double cgst,
    required double sgst,
    required double igst,
    required bool odd,
    required pw.TextStyle base,
  }) {
    return pw.TableRow(
      decoration: odd
          ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5))
          : null,
      children: [
        _td(label, base),
        _tdR(count > 0 ? '$count' : '—', base),
        _tdR(taxable > 0 ? '₹${NumberFormat('#,##,##0.00', 'en_IN').format(taxable)}' : '—', base),
        _tdR(cgst > 0 ? '₹${NumberFormat('#,##,##0.00', 'en_IN').format(cgst)}' : '—', base),
        _tdR(sgst > 0 ? '₹${NumberFormat('#,##,##0.00', 'en_IN').format(sgst)}' : '—', base),
        _tdR(igst > 0 ? '₹${NumberFormat('#,##,##0.00', 'en_IN').format(igst)}' : '—', base),
      ],
    );
  }

  static pw.Widget _th(String t, pw.TextStyle s) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: s),
      );

  static pw.Widget _td(String t, pw.TextStyle s) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: s),
      );

  static pw.Widget _tdR(String t, pw.TextStyle s) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(t, style: s),
        ),
      );

  static pw.Widget _taxBlock(
          String label, String value, pw.TextStyle style, PdfColor valueColor) =>
      pw.Column(
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7,
                  color: const PdfColor(1, 1, 1, 0.7))),
          pw.SizedBox(height: 2),
          pw.Text(value, style: style.copyWith(color: valueColor)),
        ],
      );

  static pw.Widget _divider() => pw.Container(
        width: 0.5,
        height: 32,
        color: PdfColors.grey400,
      );

  /// "032026" → "March 2026"
  static String _periodLabel(String code) {
    try {
      final mm = int.parse(code.substring(0, 2));
      final yyyy = int.parse(code.substring(2));
      final dt = DateTime(yyyy, mm);
      return DateFormat('MMMM yyyy').format(dt);
    } catch (_) {
      return code;
    }
  }
}
