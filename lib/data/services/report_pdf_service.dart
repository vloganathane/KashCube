import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/repositories/transaction_repository.dart' show PartyTotal;
import '../../presentation/providers/report_provider.dart' show MonthlyPnL;

/// Generates a P&L summary PDF report.
///
/// 100% local — no network calls.
class ReportPdfService {
  ReportPdfService._();
  static final instance = ReportPdfService._();

  // ── Palette ─────────────────────────────────────────────────────────────────
  static const _accent = PdfColor.fromInt(0xFF1B5E20);
  static const _incomeColor = PdfColor.fromInt(0xFF2E7D32);
  static const _expenseColor = PdfColor.fromInt(0xFFC62828);
  static const _muted = PdfColor.fromInt(0xFF757575);
  static const _dark = PdfColor.fromInt(0xFF212121);
  static const _surface = PdfColor.fromInt(0xFFF5F5F5);
  static const _divider = PdfColor.fromInt(0xFFE0E0E0);

  static final _fmt = NumberFormat('#,##,##0.00', 'en_IN');
  static String _rupee(double v) => '₹${_fmt.format(v)}';
  static String _pct(double share) => '${(share * 100).toStringAsFixed(1)}%';

  // ── Public API ────────────────────────────────────────────────────────────--

  /// Generates a P&L summary PDF for [pnl] over [periodLabel] and returns the [File].
  Future<File> generate(MonthlyPnL pnl, String periodLabel) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        build: (ctx) => [
          _buildHeader(periodLabel),
          pw.SizedBox(height: 18),
          _buildSummaryRow(pnl),
          pw.SizedBox(height: 20),
          if (pnl.incomeByCat.isNotEmpty) ...[
            _buildCategoryTable(
                'Income Breakdown', pnl.incomeByCat, _incomeColor, pnl.totalIncome),
            pw.SizedBox(height: 16),
          ],
          if (pnl.expenseByCat.isNotEmpty) ...[
            _buildCategoryTable(
                'Expense Breakdown', pnl.expenseByCat, _expenseColor, pnl.totalExpense),
            pw.SizedBox(height: 16),
          ],
          if (pnl.topParties.isNotEmpty) ...[
            _buildTopParties(pnl.topParties),
            pw.SizedBox(height: 16),
          ],
          _buildFooter(),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final safe = periodLabel.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_');
    final file = File('${dir.path}/KashCube_PnL_$safe.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // ── Sections ─────────────────────────────────────────────────────────────--

  pw.Widget _buildHeader(String periodLabel) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Profit & Loss Report',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  periodLabel,
                  style: pw.TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: _accent,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'KashCube',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 2, color: _accent),
      ],
    );
  }

  pw.Widget _buildSummaryRow(MonthlyPnL pnl) {
    final isProfit = pnl.netProfitLoss >= 0;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
            child: _summaryCard('Total Income', pnl.totalIncome, _incomeColor)),
        pw.SizedBox(width: 10),
        pw.Expanded(
            child: _summaryCard('Total Expenses', pnl.totalExpense, _expenseColor)),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _summaryCard(
            isProfit ? 'Net Profit' : 'Net Loss',
            pnl.netProfitLoss.abs(),
            isProfit ? _incomeColor : _expenseColor,
            prefix: isProfit ? '+' : '−',
          ),
        ),
      ],
    );
  }

  pw.Widget _summaryCard(String label, double amount, PdfColor color,
      {String prefix = ''}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              color: _muted,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '$prefix${_rupee(amount)}',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCategoryTable(
    String title,
    Map<String, double> data,
    PdfColor accentColor,
    double total,
  ) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: _dark),
        ),
        pw.SizedBox(height: 5),
        pw.Table(
          border: pw.TableBorder.all(color: _divider, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _surface),
              children: [
                _cell('Category', header: true),
                _cell('Amount', header: true, align: pw.TextAlign.right),
                _cell('Share', header: true, align: pw.TextAlign.right),
              ],
            ),
            ...sorted.map((e) => pw.TableRow(
                  children: [
                    _cell(e.key),
                    _cell(_rupee(e.value), align: pw.TextAlign.right),
                    _cell(
                      total > 0 ? _pct(e.value / total) : '—',
                      align: pw.TextAlign.right,
                    ),
                  ],
                )),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _surface),
              children: [
                _cell('Total', bold: true),
                _cell(_rupee(total),
                    bold: true,
                    align: pw.TextAlign.right,
                    color: accentColor),
                _cell('100%', bold: true, align: pw.TextAlign.right),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildTopParties(List<PartyTotal> parties) {
    final top5 = parties.take(5).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Top Parties',
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: _dark),
        ),
        pw.SizedBox(height: 5),
        pw.Table(
          border: pw.TableBorder.all(color: _divider, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _surface),
              children: [
                _cell('Party', header: true),
                _cell('Total', header: true, align: pw.TextAlign.right),
              ],
            ),
            ...top5.map((p) => pw.TableRow(
                  children: [
                    _cell(p.partyName),
                    _cell(_rupee(p.totalAmount), align: pw.TextAlign.right),
                  ],
                )),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.SizedBox(height: 16),
        pw.Container(height: 1, color: _divider),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated on ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.Text(
              'Powered by KashCube · Your data, your device.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  pw.Widget _cell(
    String text, {
    bool header = false,
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: (header || bold) ? pw.FontWeight.bold : null,
          color: color ?? (header ? _muted : _dark),
        ),
      ),
    );
  }
}
