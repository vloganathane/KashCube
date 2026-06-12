// ---------------------------------------------------------------------------
// PartyStatementPdfService — P3.3
// ---------------------------------------------------------------------------
// Generates a consolidated party statement PDF covering:
//   • Invoices (open and paid)
//   • Credits / Dues (given and received)
//   • Loans (lent and borrowed)
//
// Output: a local File in the temp directory.
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/credit.dart';
import '../models/invoice.dart';
import '../models/loan.dart';
import '../models/party.dart';

// ---------------------------------------------------------------------------
// Data row (internal)
// ---------------------------------------------------------------------------

enum _TxType { invoice, creditGiven, creditReceived, loanLent, loanBorrowed }

class _StatementRow {
  const _StatementRow({
    required this.date,
    required this.type,
    required this.ref,
    required this.description,
    this.debit = 0, // amount party owes us  (Dr)
    this.credit = 0, // amount we owe party   (Cr)
    this.isPaid = false,
  });

  final DateTime date;
  final _TxType type;
  final String ref;
  final String description;
  final double debit;
  final double credit;
  final bool isPaid;

  String get typeLabel => switch (type) {
    _TxType.invoice => 'Invoice',
    _TxType.creditGiven => 'Due (Given)',
    _TxType.creditReceived => 'Due (Rcvd)',
    _TxType.loanLent => 'Loan (Lent)',
    _TxType.loanBorrowed => 'Loan (Borrowed)',
  };
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class PartyStatementPdfService {
  PartyStatementPdfService._();
  static final instance = PartyStatementPdfService._();

  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  // ── Public API ──────────────────────────────────────────────────────────

  /// Generates a statement PDF for [party] covering [invoices], [credits],
  /// and [loans]. Returns a local [File] in the temp directory.
  Future<File> generate({
    required Party party,
    required List<Invoice> invoices,
    required List<Credit> credits,
    required List<Loan> loans,
  }) async {
    final rows = _buildRows(
      party: party,
      invoices: invoices,
      credits: credits,
      loans: loans,
    );

    final bytes = await _buildPdf(party: party, rows: rows);
    final dir = await getTemporaryDirectory();
    final safe = party.name.replaceAll(RegExp(r'[^\w]'), '_');
    final file = File(
      '${dir.path}/Statement_${safe}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── Row builder ─────────────────────────────────────────────────────────

  List<_StatementRow> _buildRows({
    required Party party,
    required List<Invoice> invoices,
    required List<Credit> credits,
    required List<Loan> loans,
  }) {
    final rows = <_StatementRow>[];

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.draft) continue;
      rows.add(
        _StatementRow(
          date: inv.issueDate,
          type: _TxType.invoice,
          ref: inv.invoiceNo,
          description: 'Invoice ${inv.invoiceNo}',
          debit: inv.total,
          credit: inv.paidAmount > 0 ? inv.paidAmount : 0,
          isPaid: inv.status == InvoiceStatus.paid,
        ),
      );
    }

    for (final c in credits) {
      final isGiven = c.direction == CreditDirection.given;
      rows.add(
        _StatementRow(
          date: c.creditDate,
          type: isGiven ? _TxType.creditGiven : _TxType.creditReceived,
          ref: 'C${c.id ?? ''}',
          description: isGiven
              ? 'Due given to ${c.customerName}'
              : 'Due received from ${c.customerName}',
          debit: isGiven ? c.totalAmount : 0,
          credit: isGiven ? 0 : c.totalAmount,
          isPaid: c.isCleared,
        ),
      );
    }

    for (final l in loans) {
      final isLent = l.isLent;
      rows.add(
        _StatementRow(
          date: l.loanDate,
          type: isLent ? _TxType.loanLent : _TxType.loanBorrowed,
          ref: 'L${l.id ?? ''}',
          description: isLent
              ? 'Loan lent to ${l.lenderName}'
              : 'Loan from ${l.lenderName}',
          debit: isLent ? l.principalAmount : 0,
          credit: isLent ? 0 : l.principalAmount,
          isPaid: l.isCleared,
        ),
      );
    }

    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  // ── PDF builder ─────────────────────────────────────────────────────────

  Future<List<int>> _buildPdf({
    required Party party,
    required List<_StatementRow> rows,
  }) async {
    final doc = pw.Document();

    // ── Fonts (use Helvetica built-in — no asset needed) ──────────────────
    final base = const pw.TextStyle(fontSize: 9);
    final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final small = const pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
    final title = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final sub = const pw.TextStyle(fontSize: 10, color: PdfColors.grey600);

    // ── Colours ────────────────────────────────────────────────────────────
    const primary = PdfColor.fromInt(0xFF1B5E20); // dark green
    const headerCol = PdfColor.fromInt(0xFFE8F5E9); // light green bg
    const debitCol = PdfColor.fromInt(0xFF2E7D32); // income green
    const creditCol = PdfColor.fromInt(0xFFC62828); // expense red

    // ── Running balance ───────────────────────────────────────────────────
    double balance = 0;
    final rowsWithBalance = rows.map((r) {
      balance += r.debit - r.credit;
      return (r, balance);
    }).toList();

    final totalDebit = rows.fold<double>(0, (s, r) => s + r.debit);
    final totalCredit = rows.fold<double>(0, (s, r) => s + r.credit);
    final net = totalDebit - totalCredit;

    // ── Page ──────────────────────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PARTY STATEMENT',
                      style: title.copyWith(color: primary),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      party.name,
                      style: sub.merge(const pw.TextStyle(fontSize: 12)),
                    ),
                    if (party.phoneNumber != null)
                      pw.Text('+91 ${party.phoneNumber}', style: small),
                    if (party.address != null)
                      pw.Text(party.address!, style: small),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated: ${_dateFmt.format(DateTime.now())}',
                      style: small,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        color: net >= 0 ? debitCol : creditCol,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Text(
                        net >= 0
                            ? 'Net Receivable: ₹${_amtFmt.format(net)}'
                            : 'Net Payable: ₹${_amtFmt.format(-net)}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: primary, thickness: 1.5),
          ],
        ),
        build: (ctx) {
          if (rows.isEmpty) {
            return [
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(32),
                  child: pw.Text(
                    'No transactions found for this party.',
                    style: small,
                  ),
                ),
              ),
            ];
          }

          return [
            pw.Table(
              columnWidths: {
                0: const pw.FixedColumnWidth(60), // Date
                1: const pw.FixedColumnWidth(72), // Type
                2: const pw.FlexColumnWidth(2), // Description
                3: const pw.FixedColumnWidth(60), // Dr
                4: const pw.FixedColumnWidth(60), // Cr
                5: const pw.FixedColumnWidth(68), // Balance
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerCol),
                  children: [
                    _th('Date', style: bold),
                    _th('Type', style: bold),
                    _th('Description', style: bold),
                    _th('Dr (Rcvbl)', style: bold.copyWith(color: debitCol)),
                    _th('Cr (Paybl)', style: bold.copyWith(color: creditCol)),
                    _th('Balance', style: bold),
                  ],
                ),
                // Data rows
                for (final (row, bal) in rowsWithBalance) ...[
                  pw.TableRow(
                    decoration: row.isPaid
                        ? const pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFFF9FBE7),
                          )
                        : null,
                    children: [
                      _td(_dateFmt.format(row.date), style: base),
                      _td(
                        row.typeLabel,
                        style: base.copyWith(color: PdfColors.grey700),
                      ),
                      _td(
                        row.description + (row.isPaid ? '  ✓' : ''),
                        style: base,
                      ),
                      _td(
                        row.debit > 0 ? '₹${_amtFmt.format(row.debit)}' : '',
                        style: base.copyWith(color: debitCol),
                        align: pw.Alignment.centerRight,
                      ),
                      _td(
                        row.credit > 0 ? '₹${_amtFmt.format(row.credit)}' : '',
                        style: base.copyWith(color: creditCol),
                        align: pw.Alignment.centerRight,
                      ),
                      _td(
                        '₹${_amtFmt.format(bal.abs())}',
                        style: bold.copyWith(
                          color: bal >= 0 ? debitCol : creditCol,
                        ),
                        align: pw.Alignment.centerRight,
                      ),
                    ],
                  ),
                ],
                // Totals row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: headerCol),
                  children: [
                    _th('', style: bold),
                    _th('TOTAL', style: bold),
                    _th('', style: bold),
                    _th(
                      '₹${_amtFmt.format(totalDebit)}',
                      style: bold.copyWith(color: debitCol),
                    ),
                    _th(
                      '₹${_amtFmt.format(totalCredit)}',
                      style: bold.copyWith(color: creditCol),
                    ),
                    _th(
                      '₹${_amtFmt.format(net.abs())} ${net >= 0 ? "Dr" : "Cr"}',
                      style: bold.copyWith(
                        color: net >= 0 ? debitCol : creditCol,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '✓ = settled  |  Dr = receivable (party owes you)  |  Cr = payable (you owe party)',
              style: small,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated by KashCube — all data stored locally on your device.',
              style: small,
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  // ── Table cell helpers ───────────────────────────────────────────────────

  static pw.Widget _th(
    String text, {
    pw.TextStyle? style,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Align(
      alignment: align,
      child: pw.Text(text, style: style),
    ),
  );

  static pw.Widget _td(
    String text, {
    pw.TextStyle? style,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Align(
      alignment: align,
      child: pw.Text(text, style: style),
    ),
  );
}
