// ---------------------------------------------------------------------------
// Gstr3bPdfService — Phase G5
// ---------------------------------------------------------------------------
// Generates a CA-format GSTR-3B Offset Summary PDF (A4, one page).
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'gstr3b_service.dart';

class Gstr3bPdfService {
  Gstr3bPdfService._();
  static final instance = Gstr3bPdfService._();

  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a CA-format GSTR-3B Offset Summary and saves to temp dir.
  Future<File> generate(Gstr3bWorkbook wb) async {
    final bytes = await _buildPdf(wb);
    final dir = await getTemporaryDirectory();
    final safeGstin = wb.businessGstin.replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    final safePeriod = wb.period.replaceAll(' ', '_');
    final file = File('${dir.path}/GSTR3B_Offset_${safePeriod}_$safeGstin.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── PDF builder ──────────────────────────────────────────────────────────

  Future<List<int>> _buildPdf(Gstr3bWorkbook wb) async {
    final doc = pw.Document();

    final bold = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    final base = pw.TextStyle(fontSize: 8.5);
    final small = pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600);
    final headerBdrStyle = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
    );

    const primary = PdfColor.fromInt(0xFF1B5E20);
    const headerBg = PdfColor.fromInt(0xFFE8F5E9);
    const rowAlt = PdfColor.fromInt(0xFFF9FBF9);

    final offset = wb.offsetData;
    final result = offset.compute();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1B5E20),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'GSTR-3B CONSOLIDATED OFFSET SUMMARY',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        wb.businessName,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        'GSTIN: ${wb.businessGstin}',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Period: ${wb.period}',
                        style: bold.copyWith(color: PdfColors.white),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${_fmtDate(wb.from)} — ${_fmtDate(wb.to)}',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // ── Table 1: Outward Supply Liability ───────────────────────────
            _sectionLabel(
              'TABLE 1 — OUTWARD SUPPLY LIABILITY',
              headerBdrStyle,
              primary,
            ),
            pw.SizedBox(height: 3),
            pw.TableHelper.fromTextArray(
              headers: [
                'Category',
                'Taxable Value (₹)',
                'IGST (₹)',
                'CGST (₹)',
                'SGST (₹)',
              ],
              data: [
                [
                  'Regular Supply',
                  _a(wb.outwardRegular.taxableValue),
                  _a(wb.outwardRegular.igst),
                  _a(wb.outwardRegular.cgst),
                  _a(wb.outwardRegular.sgst),
                ],
                [
                  'Zero-rated / Exports',
                  _a(wb.outwardZeroRated.taxableValue),
                  _a(wb.outwardZeroRated.igst),
                  '—',
                  '—',
                ],
                [
                  'Nil-rated / Exempt',
                  _a(wb.outwardNilExempted.taxableValue),
                  '—',
                  _a(wb.outwardNilExempted.cgst),
                  _a(wb.outwardNilExempted.sgst),
                ],
                [
                  'TOTAL LIABILITY',
                  _a(wb.totalLiability.taxableValue),
                  _a(wb.totalLiability.igst),
                  _a(wb.totalLiability.cgst),
                  _a(wb.totalLiability.sgst),
                ],
                [
                  'Offset by ITC',
                  '',
                  _a(result.igstByCredit),
                  _a(result.cgstByCredit),
                  _a(result.sgstByCredit),
                ],
                [
                  'Balance by Cash',
                  '',
                  _a(result.igstByCash),
                  _a(result.cgstByCash),
                  _a(result.sgstByCash),
                ],
              ],
              headerStyle: bold.copyWith(fontSize: 7.5),
              cellStyle: base.copyWith(fontSize: 7.5),
              headerDecoration: pw.BoxDecoration(color: headerBg),
              oddRowDecoration: pw.BoxDecoration(color: rowAlt),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.4),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.4),
              },
            ),
            pw.SizedBox(height: 8),

            // ── Table 2: Inward Supply (RCM) ────────────────────────────────
            _sectionLabel(
              'TABLE 2 — INWARD SUPPLY (REVERSE CHARGE)',
              headerBdrStyle,
              primary,
            ),
            pw.SizedBox(height: 3),
            pw.TableHelper.fromTextArray(
              headers: [
                'Category',
                'Taxable Value (₹)',
                'IGST (₹)',
                'CGST (₹)',
                'SGST (₹)',
              ],
              data: [
                [
                  'RCM — Registered Suppliers',
                  _a(wb.rcmLiability.taxableValue),
                  _a(wb.rcmLiability.igst),
                  _a(wb.rcmLiability.cgst),
                  _a(wb.rcmLiability.sgst),
                ],
                ['Imports (manual)', '0.00', '0.00', '—', '—'],
                [
                  'Interest / Late Fees',
                  _a(wb.interestLateFee.taxableValue),
                  _a(wb.interestLateFee.igst),
                  _a(wb.interestLateFee.cgst),
                  _a(wb.interestLateFee.sgst),
                ],
                [
                  'TOTAL RCM',
                  _a(
                    wb.rcmLiability.taxableValue +
                        wb.interestLateFee.taxableValue,
                  ),
                  _a(wb.rcmLiability.igst + wb.interestLateFee.igst),
                  _a(wb.rcmLiability.cgst + wb.interestLateFee.cgst),
                  _a(wb.rcmLiability.sgst + wb.interestLateFee.sgst),
                ],
              ],
              headerStyle: bold.copyWith(fontSize: 7.5),
              cellStyle: base.copyWith(fontSize: 7.5),
              headerDecoration: pw.BoxDecoration(color: headerBg),
              oddRowDecoration: pw.BoxDecoration(color: rowAlt),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.4),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.4),
              },
            ),
            pw.SizedBox(height: 8),

            // ── Table 3: ITC Summary ─────────────────────────────────────────
            _sectionLabel(
              'TABLE 3 — INPUT TAX CREDIT SUMMARY',
              headerBdrStyle,
              primary,
            ),
            pw.SizedBox(height: 3),
            pw.TableHelper.fromTextArray(
              headers: [
                'ITC Category',
                'IGST (₹)',
                'CGST (₹)',
                'SGST (₹)',
                'Total (₹)',
              ],
              data: [
                [
                  'Eligible ITC (from purchase bills)',
                  _a(wb.itcEligible.igst),
                  _a(wb.itcEligible.cgst),
                  _a(wb.itcEligible.sgst),
                  _a(wb.itcEligible.totalTax),
                ],
                [
                  'ITC Reversed (Rules 42/43)',
                  _a(wb.itcReversed.igst),
                  _a(wb.itcReversed.cgst),
                  _a(wb.itcReversed.sgst),
                  _a(wb.itcReversed.totalTax),
                ],
                [
                  'Blocked ITC (Sec. 17(5))',
                  _a(wb.itcBlocked.igst),
                  _a(wb.itcBlocked.cgst),
                  _a(wb.itcBlocked.sgst),
                  _a(wb.itcBlocked.totalTax),
                ],
                [
                  'NET ITC AVAILABLE',
                  _a(wb.netItc.igst),
                  _a(wb.netItc.cgst),
                  _a(wb.netItc.sgst),
                  _a(wb.netItc.totalTax),
                ],
                [
                  'Credit Balance Carry-forward (IGST)',
                  _a(result.igstCreditBalance),
                  '—',
                  '—',
                  '',
                ],
                [
                  'Credit Balance Carry-forward (CGST)',
                  '—',
                  _a(result.cgstCreditBalance),
                  '—',
                  '',
                ],
                [
                  'Credit Balance Carry-forward (SGST)',
                  '—',
                  '—',
                  _a(result.sgstCreditBalance),
                  '',
                ],
              ],
              headerStyle: bold.copyWith(fontSize: 7.5),
              cellStyle: base.copyWith(fontSize: 7.5),
              headerDecoration: pw.BoxDecoration(color: headerBg),
              oddRowDecoration: pw.BoxDecoration(color: rowAlt),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.8),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.2),
              },
            ),
            pw.SizedBox(height: 10),

            // ── Cash Summary ─────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F5E9),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL CASH REQUIRED TO FILE GSTR-3B',
                    style: bold.copyWith(fontSize: 9, color: primary),
                  ),
                  pw.Text(
                    '₹${_a(result.totalCash)}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFFB71C1C),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),

            // ── Footer ───────────────────────────────────────────────────────
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 3),
            pw.Text(
              'Generated by KashCube  |  All data sourced from local device  |  '
              'Verify with GSTN portal before filing. '
              'IGST credit offsets IGST → CGST → SGST (Rules 88A).',
              style: small,
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  pw.Widget _sectionLabel(String text, pw.TextStyle labelStyle, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(text, style: labelStyle.copyWith(color: PdfColors.white)),
    );
  }

  String _a(double v) => _amtFmt.format(v);
  String _fmtDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);
}
