import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/date_formatter.dart';
import '../models/business.dart';
import '../models/delivery_challan.dart';
import '../models/party.dart';
import 'pdf_cache_manager.dart';

/// Generates a Delivery Challan PDF as per GST Rule 55.
/// 100% local — no network calls, no cloud storage.
class DeliveryChallanPdfService {
  DeliveryChallanPdfService._();
  static final instance = DeliveryChallanPdfService._();

  static final _indianFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs.',
    decimalDigits: 2,
  );

  String _fmt(double amount) => _indianFormat.format(amount.abs());

  static const PdfColor _dark = PdfColor.fromInt(0xFF212121);
  static const PdfColor _muted = PdfColor.fromInt(0xFF757575);
  static const PdfColor _divider = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor _headerBg = PdfColor.fromInt(0xFF1B5E20);
  static const PdfColor _headerFg = PdfColors.white;
  static const PdfColor _rowAlt = PdfColor.fromInt(0xFFF5F5F5);

  Future<pw.MemoryImage?> _loadLogo(Business business) async {
    if (business.logoPath == null || business.logoPath!.isEmpty) return null;
    try {
      final file = File(business.logoPath!);
      if (await file.exists()) return pw.MemoryImage(await file.readAsBytes());
    } catch (_) {}
    return null;
  }

  /// Generates the PDF and returns the saved [File].
  Future<File> generateChallanPdf(
    DeliveryChallan challan, {
    Business? business,
    Party? customerParty,
  }) async {
    final pdf = pw.Document();
    final logo = business != null ? await _loadLogo(business) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          _buildHeader(challan, business: business, logo: logo),
          pw.SizedBox(height: 20),
          _buildParties(challan, business: business, customer: customerParty),
          pw.SizedBox(height: 20),
          _buildItemsTable(challan),
          pw.SizedBox(height: 16),
          _buildTotals(challan),
          if (_hasTransport(challan)) ...[
            pw.SizedBox(height: 16),
            _buildTransport(challan),
          ],
          pw.SizedBox(height: 24),
          _buildDeclaration(challan, business: business),
        ],
      ),
    );

    return _savePdf(pdf, 'DC_${challan.challanNo.replaceAll('/', '-')}.pdf');
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  pw.Widget _buildHeader(
    DeliveryChallan challan, {
    Business? business,
    pw.MemoryImage? logo,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _headerBg,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 56,
              height: 56,
              child: pw.Image(logo),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  business?.name ?? 'Your Business',
                  style: pw.TextStyle(
                    color: _headerFg,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (business?.gstin != null && business!.gstin!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'GSTIN: ${business.gstin}',
                    style: pw.TextStyle(color: _headerFg, fontSize: 9),
                  ),
                ],
                if (business?.address != null &&
                    business!.address.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    business.address,
                    style: pw.TextStyle(color: _headerFg, fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'DELIVERY CHALLAN',
                style: pw.TextStyle(
                  color: _headerFg,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'No: ${challan.challanNo}',
                style: pw.TextStyle(color: _headerFg, fontSize: 9),
              ),
              pw.Text(
                'Date: ${DateFormatter.formatDisplay(challan.challanDate)}',
                style: pw.TextStyle(color: _headerFg, fontSize: 9),
              ),
              pw.Text(
                'Purpose: ${challan.purpose.label}',
                style: pw.TextStyle(color: _headerFg, fontSize: 9),
              ),
              if (challan.ewbNo != null && challan.ewbNo!.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'EWB No: ${challan.ewbNo}',
                  style: pw.TextStyle(
                    color: _headerFg,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── From / To ───────────────────────────────────────────────────────────────

  pw.Widget _buildParties(
    DeliveryChallan challan, {
    Business? business,
    Party? customer,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _partyBox('From', _buildFromLines(business))),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _partyBox('To', _buildToLines(challan, customer))),
      ],
    );
  }

  List<String> _buildFromLines(Business? b) {
    if (b == null) return ['Your Business'];
    return [
      b.name,
      if (b.gstin != null && b.gstin!.isNotEmpty) 'GSTIN: ${b.gstin}',
      if (b.address.isNotEmpty) b.address,
      if (b.phone != null && b.phone!.isNotEmpty) 'Ph: ${b.phone}',
    ];
  }

  List<String> _buildToLines(DeliveryChallan c, Party? p) {
    return [
      c.customerName,
      if (c.customerGstin != null && c.customerGstin!.isNotEmpty)
        'GSTIN: ${c.customerGstin}',
      if (p != null && p.address != null && p.address!.isNotEmpty) p.address!,
      if (p?.phone != null && p!.phone!.isNotEmpty) 'Ph: ${p.phone}',
      if (c.placeOfSupply != null && c.placeOfSupply!.isNotEmpty)
        'Place of Supply: ${c.placeOfSupply}',
    ];
  }

  pw.Widget _partyBox(String title, List<String> lines) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 9,
                  color: _muted,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          ...lines.map((l) => pw.Text(l,
              style: const pw.TextStyle(fontSize: 9, color: _dark))),
        ],
      ),
    );
  }

  // ── Items table ──────────────────────────────────────────────────────────────

  pw.Widget _buildItemsTable(DeliveryChallan challan) {
    const headers = ['#', 'Item / Description', 'HSN', 'Qty', 'Unit', 'Rate', 'Amount'];
    const colWidths = [
      pw.FlexColumnWidth(0.5),
      pw.FlexColumnWidth(4),
      pw.FlexColumnWidth(1.2),
      pw.FlexColumnWidth(1),
      pw.FlexColumnWidth(1),
      pw.FlexColumnWidth(1.5),
      pw.FlexColumnWidth(1.5),
    ];

    final rows = <pw.TableRow>[
      // Header row
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: headers
            .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: _headerFg,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ))
            .toList(),
      ),
      // Data rows
      ...challan.items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        return pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : _rowAlt,
          ),
          children: [
            _cell('${i + 1}'),
            _cell(
              item.description != null && item.description!.isNotEmpty
                  ? '${item.itemName}\n${item.description}'
                  : item.itemName,
            ),
            _cell(item.hsnCode ?? ''),
            _cell(_fmtQty(item.qty)),
            _cell(item.unit),
            _cell(_fmt(item.unitPrice)),
            _cell(_fmt(item.lineTotal)),
          ],
        );
      }),
    ];

    return pw.Table(
      columnWidths: {
        for (var i = 0; i < colWidths.length; i++) i: colWidths[i]
      },
      border: pw.TableBorder.all(color: _divider, width: 0.5),
      children: rows,
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          color: _dark,
          fontWeight: bold ? pw.FontWeight.bold : null,
        ),
      ),
    );
  }

  String _fmtQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toStringAsFixed(0);
    return qty.toStringAsFixed(2);
  }

  // ── Totals ───────────────────────────────────────────────────────────────────

  pw.Widget _buildTotals(DeliveryChallan challan) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _rowAlt,
          border: pw.Border.all(color: _divider),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Total Value (Ex-tax)',
              style: const pw.TextStyle(fontSize: 10, color: _dark),
            ),
            pw.Text(
              _fmt(challan.subtotal),
              style: pw.TextStyle(
                fontSize: 10,
                color: _dark,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Transport details ────────────────────────────────────────────────────────

  bool _hasTransport(DeliveryChallan c) {
    return (c.vehicleNo != null && c.vehicleNo!.isNotEmpty) ||
        (c.transporterName != null && c.transporterName!.isNotEmpty) ||
        c.distanceKm != null;
  }

  pw.Widget _buildTransport(DeliveryChallan c) {
    final items = <String, String>{};
    if (c.transporterName != null && c.transporterName!.isNotEmpty)
      items['Transporter'] = c.transporterName!;
    if (c.vehicleNo != null && c.vehicleNo!.isNotEmpty)
      items['Vehicle No.'] = c.vehicleNo!;
    if (c.transportMode != null && c.transportMode!.isNotEmpty)
      items['Mode'] = _modeLabel(c.transportMode!);
    if (c.distanceKm != null)
      items['Distance'] = '${c.distanceKm} km';
    if (c.dispatchDate != null)
      items['Dispatch Date'] = DateFormatter.formatDisplay(c.dispatchDate!);

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Transport Details',
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _muted),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            children: items.entries
                .map((e) => pw.Container(
                      width: 140,
                      margin: const pw.EdgeInsets.only(bottom: 4, right: 8),
                      child: pw.RichText(
                        text: pw.TextSpan(children: [
                          pw.TextSpan(
                            text: '${e.key}: ',
                            style: const pw.TextStyle(
                                fontSize: 9, color: _muted),
                          ),
                          pw.TextSpan(
                            text: e.value,
                            style: const pw.TextStyle(
                                fontSize: 9, color: _dark),
                          ),
                        ]),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case '1':
        return 'Road';
      case '2':
        return 'Rail';
      case '3':
        return 'Air';
      case '4':
        return 'Ship';
      default:
        return mode;
    }
  }

  // ── Declaration ──────────────────────────────────────────────────────────────

  pw.Widget _buildDeclaration(DeliveryChallan challan, {Business? business}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _divider),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Declaration',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _muted),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'We declare that this invoice is true and correct and the goods '
                  'are being dispatched as per the details mentioned above.',
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
                if (challan.notes != null && challan.notes!.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text('Notes: ${challan.notes}',
                      style: const pw.TextStyle(fontSize: 8, color: _dark)),
                ],
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          width: 160,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _divider),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'For ${business?.name ?? ''}',
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark),
              ),
              pw.SizedBox(height: 32),
              pw.Container(
                height: 1,
                color: _dark,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Authorised Signatory',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── IO ───────────────────────────────────────────────────────────────────────

  Future<File> _savePdf(pw.Document pdf, String filename) async {
    final path = await PdfCacheManager.instance.tempPath(filename);
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
