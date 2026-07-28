import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_config.dart';
import '../../core/utils/date_formatter.dart';
import 'pdf_cache_manager.dart';
import 'pdf_document_data.dart';

/// Unified PDF renderer.
///
/// Accepts a [PdfDocumentData] + [DocumentTemplate] and produces a saved
/// [File]. All rendering is pure Dart/`pdf`—no HTML, no network, no
/// cloud dependencies. 100% local.
///
/// Usage:
/// ```dart
/// final file = await PdfLayoutEngine.instance.generate(data, DocumentTemplate.modern, 'Invoice_001.pdf');
/// ```
class PdfLayoutEngine {
  PdfLayoutEngine._();
  static final instance = PdfLayoutEngine._();

  // ── Shared colour tokens ──────────────────────────────────────────────────

  static const PdfColor _dark = PdfColor.fromInt(0xFF212121);
  static const PdfColor _muted = PdfColor.fromInt(0xFF757575);
  static const PdfColor _divider = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor _rowAlt = PdfColor.fromInt(0xFFF5F5F5);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generate PDF bytes without saving to disk. Used for thumbnail previews.
  ///
  /// Safe to call from a background isolate — pure Dart, no platform channels.
  Future<Uint8List> generateBytes(
    PdfDocumentData data,
    DocumentTemplate template,
  ) async {
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs.',
      decimalDigits: template.amountDecimalDigits,
    );
    final pdf = pw.Document();
    if (template.id == 'industrial') {
      pdf.addPage(
        pw.Page(
          pageFormat: template.pageFormat,
          theme: _themeFor(template),
          margin: pw.EdgeInsets.all(template.pageMargin),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: _buildIndustrialContent(data, template),
          ),
        ),
      );
    } else {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: template.pageFormat,
          theme: _themeFor(template),
          margin: template.isThermal
              ? pw.EdgeInsets.all(4 * PdfPageFormat.mm)
              : pw.EdgeInsets.all(template.pageMargin),
          build: (ctx) => template.isThermal
              ? _buildThermalContent(data, fmt)
              : _buildContent(data, template, fmt),
        ),
      );
    }
    return pdf.save();
  }

  /// Generate a PDF and save it to the temp cache, returning the [File].
  Future<File> generate(
    PdfDocumentData data,
    DocumentTemplate template,
    String filename,
  ) async {
    // Build a formatter appropriate for this template
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs.',
      decimalDigits: template.amountDecimalDigits,
    );

    final pdf = pw.Document();
    if (template.id == 'industrial') {
      pdf.addPage(
        pw.Page(
          pageFormat: template.pageFormat,
          theme: _themeFor(template),
          margin: pw.EdgeInsets.all(template.pageMargin),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: _buildIndustrialContent(data, template),
          ),
        ),
      );
    } else {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: template.pageFormat,
          theme: _themeFor(template),
          margin: template.isThermal
              ? pw.EdgeInsets.all(4 * PdfPageFormat.mm)
              : pw.EdgeInsets.all(template.pageMargin),
          build: (ctx) => template.isThermal
              ? _buildThermalContent(data, fmt)
              : _buildContent(data, template, fmt),
        ),
      );
    }

    final path = await PdfCacheManager.instance.tempPath(filename);
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Cross-platform PDF generation that returns an [XFile] suitable for
  /// sharing via [share_plus] on both Android and web.
  ///
  /// On web: bytes are kept in memory (no disk write — `dart:io` unavailable).
  /// On native: same as [generate] but wrapped in [XFile].
  Future<XFile> generateXFile(
    PdfDocumentData data,
    DocumentTemplate template,
    String filename,
  ) async {
    final bytes = await generateBytes(data, template);
    if (kIsWeb) {
      return XFile.fromData(bytes, name: filename, mimeType: 'application/pdf');
    }
    final path = await PdfCacheManager.instance.tempPath(filename);
    await File(path).writeAsBytes(bytes);
    return XFile(path, mimeType: 'application/pdf');
  }

  // ── Document assembly ─────────────────────────────────────────────────────

  pw.ThemeData _themeFor(DocumentTemplate template) {
    switch (template.fontFamily) {
      case PdfFontFamily.times:
        return pw.ThemeData.withFont(
          base: pw.Font.times(),
          bold: pw.Font.timesBold(),
          italic: pw.Font.timesItalic(),
          boldItalic: pw.Font.timesBoldItalic(),
        );
      case PdfFontFamily.courier:
        return pw.ThemeData.withFont(
          base: pw.Font.courier(),
          bold: pw.Font.courierBold(),
          italic: pw.Font.courierOblique(),
          boldItalic: pw.Font.courierBoldOblique(),
        );
      case PdfFontFamily.helvetica:
        return pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
        );
    }
  }

  List<pw.Widget> _buildContent(
    PdfDocumentData data,
    DocumentTemplate template,
    NumberFormat fmt,
  ) {
    if (template.id == 'industrial') {
      return _buildIndustrialContent(data, template);
    }

    final sections = <pw.Widget>[];
    for (final section in template.config.sectionOrder) {
      if (!template.config.shows(section)) continue;
      final widget = switch (section) {
        'header' => _buildHeaderAndTitle(data, template),
        'parties' => _buildParties(data, template),
        'items' => _buildLineItemsTable(data, template, fmt),
        'gst' when data.totals.hasGst => _buildGstSummaryTable(data, fmt),
        'totals' => _buildTotals(data, template, fmt),
        'transport' when data.transport != null && !data.transport!.isEmpty =>
          _buildTransport(data.transport!),
        'footer' => _buildFooter(data, template),
        _ => null,
      };
      if (widget == null) continue;
      if (sections.isNotEmpty) {
        sections.add(pw.SizedBox(height: template.sectionSpacing));
      }
      sections.add(widget);
    }
    return sections;
  }

  // ── Industrial grid layout ───────────────────────────────────────────────

  List<pw.Widget> _buildIndustrialContent(
    PdfDocumentData data,
    DocumentTemplate template,
  ) {
    final seller = data.seller;
    final buyer = data.buyer;
    final delivery = data.shipTo;
    final plainMoney = NumberFormat('#,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd-MM-yyyy');
    final items = data.lineItems;
    const minRows = 18;
    const maxRows = 20;
    final visibleItems = items.take(maxRows).toList();
    final rowCount = visibleItems.length > minRows
        ? visibleItems.length
        : minRows;
    final hasOverflowItems = items.length > maxRows;

    final totalCgst = data.totals.gstRows.fold<double>(0, (s, r) => s + r.cgst);
    final totalSgst = data.totals.gstRows.fold<double>(0, (s, r) => s + r.sgst);
    final totalIgst = data.totals.gstRows.fold<double>(0, (s, r) => s + r.igst);

    String fmtQty(double value) => value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    String lineMoney(double value) => plainMoney.format(value.abs());

    final topBand = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            data.typeLabel.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.Text(
            '(ORIGINAL FOR RECIPIENT)',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    final headerBody = pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 170,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(color: PdfColors.black, width: 0.8),
              ),
            ),
            child: pw.Table(
              border: const pw.TableBorder(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                horizontalInside: pw.BorderSide(
                  color: PdfColors.black,
                  width: 0.8,
                ),
                verticalInside: pw.BorderSide(
                  color: PdfColors.black,
                  width: 0.8,
                ),
              ),
              children: [
                pw.TableRow(
                  children: [
                    _industrialInfoCell('Invoice No:'),
                    _industrialInfoCell(data.docNumber, bold: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _industrialInfoCell('Date:'),
                    _industrialInfoCell(
                      dateFmt.format(data.issueDate),
                      bold: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (template.showLogo && seller.logoImage != null)
                    pw.Container(
                      width: seller.logoIsWide ? 74 : 44,
                      height: 30,
                      margin: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Image(
                        seller.logoImage!,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  pw.Text(
                    seller.name.toUpperCase(),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (seller.address != null && seller.address!.isNotEmpty)
                    pw.Text(
                      seller.address!,
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (seller.gstin != null && seller.gstin!.isNotEmpty)
                    pw.Text(
                      'GSTIN: ${seller.gstin}',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (seller.panNo != null && seller.panNo!.isNotEmpty)
                    pw.Text(
                      'PAN: ${seller.panNo}',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (seller.tinNo != null && seller.tinNo!.isNotEmpty)
                    pw.Text(
                      'TIN: ${seller.tinNo}',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final toAndDetails = pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            color: PdfColors.black,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'To.',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  'Delivery Address',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 73,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.black, width: 0.8),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        buyer.name.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (buyer.address != null && buyer.address!.isNotEmpty)
                        pw.Text(
                          buyer.address!,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      if (buyer.state != null && buyer.state!.isNotEmpty)
                        pw.Text(
                          '${buyer.state}, India.',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              pw.Expanded(
                flex: 27,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (delivery != null) ...[
                        pw.Text(
                          delivery.name.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (delivery.address != null &&
                            delivery.address!.isNotEmpty)
                          pw.Text(
                            delivery.address!,
                            style: const pw.TextStyle(fontSize: 8.2),
                          ),
                        if (delivery.state != null &&
                            delivery.state!.isNotEmpty)
                          pw.Text(
                            '${delivery.state}, India.',
                            style: pw.TextStyle(
                              fontSize: 8.2,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                      ] else
                        pw.Text(
                          'Same as billing address',
                          style: pw.TextStyle(
                            fontSize: 8.2,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final itemTable = pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(6),
        1: pw.FlexColumnWidth(10),
        2: pw.FlexColumnWidth(46),
        3: pw.FlexColumnWidth(11),
        4: pw.FlexColumnWidth(13),
        5: pw.FlexColumnWidth(14),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.black),
          children: [
            _industrialHeadCell('SL. No.'),
            _industrialHeadCell('HSN Code'),
            _industrialHeadCell('Product Name / Description'),
            _industrialHeadCell('Qty.'),
            _industrialHeadCell('Unit Price'),
            _industrialHeadCell('Total'),
          ],
        ),
        for (var i = 0; i < rowCount; i++)
          pw.TableRow(
            children: [
              _industrialBodyCell(
                i < visibleItems.length ? '${i + 1}' : '',
                align: pw.TextAlign.center,
              ),
              _industrialBodyCell(
                i < visibleItems.length ? (visibleItems[i].hsnCode ?? '') : '',
              ),
              _industrialBodyCell(
                i < visibleItems.length ? visibleItems[i].name : '',
              ),
              _industrialBodyCell(
                i < visibleItems.length ? fmtQty(visibleItems[i].qty) : '',
                align: pw.TextAlign.center,
              ),
              _industrialBodyCell(
                i < visibleItems.length
                    ? lineMoney(visibleItems[i].unitPrice)
                    : '',
                align: pw.TextAlign.center,
              ),
              _industrialBodyCell(
                i < visibleItems.length
                    ? lineMoney(visibleItems[i].lineTotal)
                    : '',
                align: pw.TextAlign.center,
                bold: i < visibleItems.length,
              ),
            ],
          ),
      ],
    );

    final bottomBlock = pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 62,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(color: PdfColors.black, width: 0.8),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _industrialLeftLine('Party GST No', buyer.gstin ?? ''),
                  _industrialLeftLine('Ref. Dc', data.referenceDocNo ?? ''),
                  _industrialLeftLine(
                    'Ref. Dc Date',
                    data.referenceDocDate ?? '',
                  ),
                  _industrialLeftLine('P.O. No.', data.poNumber ?? ''),
                  _industrialLeftLine(
                    'Date',
                    data.dueDate != null ? dateFmt.format(data.dueDate!) : '',
                  ),
                  _industrialLeftLine('Vehicle No.', data.vehicleNo ?? ''),
                  pw.Container(
                    width: double.infinity,
                    color: PdfColors.black,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: pw.Text(
                      'OUR BANK DETAILS',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  _industrialLeftLine('Bank Name', data.bankName ?? ''),
                  _industrialLeftLine('A/C No', data.bankAccountNo ?? ''),
                  _industrialLeftLine(
                    'A/C Name',
                    data.bankAccountName ?? seller.name,
                  ),
                  _industrialLeftLine('IFSC code', data.bankIfsc ?? ''),
                  _industrialLeftLine('Branch', data.bankBranch ?? ''),
                ],
              ),
            ),
          ),
          pw.Expanded(
            flex: 38,
            child: pw.Column(
              children: [
                _industrialRightTotal(
                  'Sub Total',
                  lineMoney(data.totals.subtotal),
                  bold: true,
                ),
                _industrialRightTotal('SGST', lineMoney(totalSgst)),
                _industrialRightTotal('CGST', lineMoney(totalCgst)),
                if (totalIgst > 0)
                  _industrialRightTotal('IGST', lineMoney(totalIgst)),
                _industrialRightTotal(
                  'Round off / Freight',
                  lineMoney(
                    data.totals.freight +
                        data.totals.insurance +
                        data.totals.packing,
                  ),
                ),
                _industrialRightTotal(
                  'Grand Total',
                  lineMoney(data.totals.grandTotal),
                  bold: true,
                ),
                pw.SizedBox(
                  height: 58,
                  child: pw.Center(
                    child: pw.Text(
                      'For ${seller.name}',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final footer = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.black, width: 0.8),
          right: pw.BorderSide(color: PdfColors.black, width: 0.8),
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _phoneList(seller) != null ? 'Ph. ${_phoneList(seller)}' : '',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(seller.email ?? '', style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );

    return [
      topBand,
      headerBody,
      toAndDetails,
      itemTable,
      if (hasOverflowItems)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, left: 2),
          child: pw.Text(
            'Showing first $maxRows items (${items.length - maxRows} more not shown in this style).',
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
      bottomBlock,
      footer,
    ];
  }

  pw.Widget _industrialInfoCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _industrialHeadCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 8.5,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _industrialBodyCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
  }) {
    return pw.Container(
      height: 16,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8.4,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _industrialLeftLine(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 92,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
          ),
        ],
      ),
    );
  }

  pw.Widget _industrialRightTotal(
    String label,
    String value, {
    bool bold = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ── Header + document title ───────────────────────────────────────────────

  // ── Thermal receipt layout ────────────────────────────────────────────────

  /// Compact single-column layout for 58 mm and 80 mm thermal printers.
  ///
  /// Design principles:
  /// • Monochrome only — no colour fills or accents.
  /// • Compact 8–10 pt type; no logo.
  /// • Dashed text dividers (fits any roll width).
  /// • Items split into name row + amount row for readability on narrow paper.
  List<pw.Widget> _buildThermalContent(PdfDocumentData data, NumberFormat fmt) {
    const ts8 = pw.TextStyle(fontSize: 8);
    final ts8b = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final ts9b = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final ts10b = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
    const dash = '- - - - - - - - - - - - - - - - - - - - - - -';
    final seller = data.seller;
    final totals = data.totals;

    // helpers
    pw.Widget divider() => pw.Center(
      child: pw.Text(dash, style: ts8.copyWith(color: _muted)),
    );

    pw.Widget kv(
      String label,
      String value, {
      bool bold = false,
      double fontSize = 8,
    }) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: bold ? ts8b.copyWith(fontSize: fontSize) : ts8),
        pw.Text(value, style: bold ? ts8b.copyWith(fontSize: fontSize) : ts8),
      ],
    );

    final totalCgst = totals.gstRows.fold<double>(0.0, (s, r) => s + r.cgst);
    final totalSgst = totals.gstRows.fold<double>(0.0, (s, r) => s + r.sgst);
    final totalIgst = totals.gstRows.fold<double>(0.0, (s, r) => s + r.igst);

    final dateFmt = DateFormat('dd MMM yyyy');

    return [
      // business block
      pw.Center(
        child: pw.Text(
          seller.name.toUpperCase(),
          style: ts10b,
          textAlign: pw.TextAlign.center,
        ),
      ),
      if (seller.address != null && seller.address!.isNotEmpty)
        pw.Center(
          child: pw.Text(
            seller.address!,
            style: ts8,
            textAlign: pw.TextAlign.center,
          ),
        ),
      if (_phoneList(seller) != null)
        pw.Center(child: pw.Text('Ph: ${_phoneList(seller)}', style: ts8)),
      if (seller.gstin != null && seller.gstin!.isNotEmpty)
        pw.Center(child: pw.Text('GSTIN: ${seller.gstin}', style: ts8)),
      pw.SizedBox(height: 4),
      divider(),
      pw.SizedBox(height: 2),

      // document meta
      pw.Center(
        child: pw.Text(
          data.typeLabel,
          style: ts9b,
          textAlign: pw.TextAlign.center,
        ),
      ),
      kv('#:', data.docNumber),
      kv('Date:', dateFmt.format(data.issueDate)),
      if (data.buyer.name.isNotEmpty) kv('To:', data.buyer.name),
      pw.SizedBox(height: 2),
      divider(),
      pw.SizedBox(height: 2),

      // line items
      for (final item in data.lineItems) ...<pw.Widget>[
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Text(item.name, style: ts8b)),
            pw.Text(fmt.format(item.lineTotal), style: ts8b),
          ],
        ),
        pw.Text(
          '  ${item.qty} ${item.unit ?? 'pcs'} × ${fmt.format(item.unitPrice)}',
          style: ts8,
        ),
        if (item.description != null && item.description!.isNotEmpty)
          pw.Text('  ${item.description}', style: ts8),
        pw.SizedBox(height: 2),
      ],

      divider(),
      pw.SizedBox(height: 2),

      // totals
      kv('Subtotal:', fmt.format(totals.subtotal)),
      if (totals.freight > 0) kv('Freight:', fmt.format(totals.freight)),
      if (totals.packing > 0) kv('Packing:', fmt.format(totals.packing)),
      if (totals.insurance > 0) kv('Insurance:', fmt.format(totals.insurance)),
      if (totals.hasGst) ...<pw.Widget>[
        if (totalCgst > 0) kv('CGST:', fmt.format(totalCgst)),
        if (totalSgst > 0) kv('SGST:', fmt.format(totalSgst)),
        if (totalIgst > 0) kv('IGST:', fmt.format(totalIgst)),
      ],
      divider(),
      kv('TOTAL', fmt.format(totals.grandTotal), bold: true, fontSize: 9),
      if (totals.hasPayment) ...<pw.Widget>[
        kv('Paid:', fmt.format(totals.paidAmount)),
        kv('Balance:', fmt.format(totals.balanceDue), bold: true),
      ],
      divider(),
      pw.SizedBox(height: 4),

      // footer
      if (data.footerNote.isNotEmpty)
        pw.Center(
          child: pw.Text(
            data.footerNote,
            style: ts8,
            textAlign: pw.TextAlign.center,
          ),
        ),
      if (data.termsAndConditions != null &&
          data.termsAndConditions!.isNotEmpty) ...<pw.Widget>[
        pw.SizedBox(height: 2),
        divider(),
        pw.Text(data.termsAndConditions!, style: ts8),
      ],
    ];
  }

  // ── Header + document title ───────────────────────────────────────────────

  pw.Widget _buildHeaderAndTitle(PdfDocumentData data, DocumentTemplate t) {
    final seller = data.seller;
    final logo = t.showLogo ? seller.logoImage : null;
    final isBanner = t.headerStyle == PdfHeaderStyle.banner;
    final fg = isBanner ? PdfColors.white : _dark;
    final fgMuted = isBanner ? PdfColors.white : _muted;

    // Business info column ──────────────────────────────────────────────────
    final details = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          seller.name.isNotEmpty ? seller.name : 'Your Business',
          style: pw.TextStyle(
            fontSize: t.config.businessFontSize,
            fontWeight: t.config.businessBold
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
            color: fg,
          ),
        ),
        if (t.config.showGstin &&
            seller.gstin != null &&
            seller.gstin!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'GSTIN: ${seller.gstin}',
            style: pw.TextStyle(fontSize: t.bodyFontSize, color: fgMuted),
          ),
        ],
        if (t.config.showAddresses && _addressLine(seller) != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            _addressLine(seller)!,
            style: pw.TextStyle(fontSize: t.bodyFontSize, color: fgMuted),
          ),
        ],
        if (_contactLine(seller) != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            _contactLine(seller)!,
            style: pw.TextStyle(fontSize: t.bodyFontSize, color: fgMuted),
          ),
        ],
      ],
    );
    final logoWidget = logo == null
        ? null
        : pw.Container(
            width: data.seller.logoIsWide
                ? t.config.logoSize * 2.4
                : t.config.logoSize,
            height: t.config.logoSize,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          );
    final businessCol = _buildBusinessLogoLayout(
      details: details,
      logo: logoWidget,
      position: t.config.logoPosition,
    );

    // Document meta column ─────────────────────────────────────────────────
    final docMetaCol = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          data.typeLabel,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: fg,
          ),
        ),
        pw.SizedBox(height: 4),
        if (t.config.showDocumentNumber)
          pw.Text(
            '#${data.docNumber}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (t.config.showDates)
          pw.Text(
            'Date: ${DateFormatter.formatFull(data.issueDate)}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (t.config.showDates && data.dueDate != null)
          pw.Text(
            'Due: ${DateFormatter.formatFull(data.dueDate!)}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (t.config.showDates && data.validUntil != null)
          pw.Text(
            'Valid Until: ${DateFormatter.formatFull(data.validUntil!)}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (data.purpose != null && data.purpose!.isNotEmpty)
          pw.Text(
            'Purpose: ${data.purpose}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (data.ewbNo != null && data.ewbNo!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'EWB No: ${data.ewbNo}',
            style: pw.TextStyle(
              fontSize: 9,
              color: fg,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
        pw.SizedBox(height: 4),
        _statusBadge(data.statusLabel, data.statusColor, onDark: isBanner),
      ],
    );

    if (isBanner) {
      // Banner: single coloured container with business on left, doc meta right
      final headerChildren = <pw.Widget>[
        pw.Expanded(child: businessCol),
        pw.SizedBox(width: 16),
        docMetaCol,
      ];
      return _wrapCopyLabel(
        data,
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: t.accentColor,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: t.headerAlignment == PdfHeaderAlignment.left
                ? headerChildren
                : headerChildren.reversed.toList(),
          ),
        ),
      );
    } else {
      // Minimal: business block → thin accent line → doc title row
      return _wrapCopyLabel(
        data,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            businessCol,
            pw.SizedBox(height: 12),
            if (t.config.dividerThickness > 0)
              pw.Container(
                height: t.config.dividerThickness,
                color: t.accentColor,
              ),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: _alignedHeaderChildren(t, [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDocumentTitle(data.typeLabel, t),
                    if (data.subTypeLabel != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        data.subTypeLabel!,
                        style: pw.TextStyle(fontSize: 10, color: _muted),
                      ),
                    ],
                    if (t.config.showDocumentNumber) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(
                        data.docNumber,
                        style: pw.TextStyle(fontSize: 14, color: _muted),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (t.config.showDates)
                      pw.Text(
                        'Date: ${DateFormatter.formatFull(data.issueDate)}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    if (t.config.showDates && data.dueDate != null)
                      pw.Text(
                        'Due: ${DateFormatter.formatFull(data.dueDate!)}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    if (t.config.showDates && data.validUntil != null)
                      pw.Text(
                        'Valid Until: ${DateFormatter.formatFull(data.validUntil!)}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    pw.SizedBox(height: 4),
                    _statusBadge(
                      data.statusLabel,
                      data.statusColor,
                      onDark: false,
                    ),
                  ],
                ),
              ]),
            ),
          ],
        ),
      );
    }
  }

  List<pw.Widget> _alignedHeaderChildren(
    DocumentTemplate template,
    List<pw.Widget> children,
  ) {
    return template.headerAlignment == PdfHeaderAlignment.left
        ? children
        : children.reversed.toList();
  }

  pw.Widget _buildBusinessLogoLayout({
    required pw.Widget details,
    required pw.Widget? logo,
    required String position,
  }) {
    if (logo == null) return details;
    switch (position) {
      case 'besideRight':
      case 'right':
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(child: details),
            pw.SizedBox(width: 12),
            logo,
          ],
        );
      case 'aboveCenter':
      case 'center':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [logo, pw.SizedBox(height: 8), details],
        );
      case 'aboveRight':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [logo, pw.SizedBox(height: 8), details],
        );
      case 'belowLeft':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [details, pw.SizedBox(height: 8), logo],
        );
      case 'aboveLeft':
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [logo, pw.SizedBox(height: 8), details],
        );
      case 'besideLeft':
      case 'left':
      default:
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            logo,
            pw.SizedBox(width: 12),
            pw.Expanded(child: details),
          ],
        );
    }
  }

  pw.Widget _wrapCopyLabel(PdfDocumentData data, pw.Widget child) {
    if (data.copyLabel == null || data.copyLabel!.isEmpty) {
      return child;
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(right: 4),
            child: pw.Text(
              data.copyLabel!,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        child,
      ],
    );
  }

  pw.Widget _buildDocumentTitle(String label, DocumentTemplate template) {
    final text = pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: template.titleFontSize,
        fontWeight: pw.FontWeight.bold,
        color: _dark,
        decoration: template.config.titleStyle == 'underline'
            ? pw.TextDecoration.underline
            : null,
      ),
    );
    if (template.config.titleStyle != 'boxed') return text;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: template.accentColor),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: text,
    );
  }

  pw.Widget _statusBadge(String label, PdfColor color, {bool onDark = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: pw.BoxDecoration(
        color: onDark
            ? PdfColor.fromInt(0x33000000) // semi-transparent dark overlay
            : PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: onDark ? PdfColors.white : color,
        ),
      ),
    );
  }

  String? _addressLine(PdfPartyInfo p) {
    final parts = [p.address].where((e) => e != null && e.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _contactLine(PdfPartyInfo p) {
    final phonePart = _phoneList(p);
    final parts = [
      if (phonePart != null && phonePart.isNotEmpty) 'Ph: $phonePart',
      p.email,
    ].where((e) => e != null && e.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String? _phoneList(PdfPartyInfo p) {
    final values = <String>{};
    if (p.phones != null) {
      for (final value in p.phones!) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) values.add(trimmed);
      }
    }
    final primary = p.phone?.trim();
    if (primary != null && primary.isNotEmpty) values.add(primary);
    if (values.isEmpty) return null;
    return values.join(', ');
  }

  // ── Parties section ───────────────────────────────────────────────────────

  pw.Widget _buildParties(PdfDocumentData data, DocumentTemplate t) {
    final isDC = data.type == PdfDocumentType.deliveryChallan;

    if (isDC) {
      // DC: two bordered boxes side by side — From / To
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _partyBox(
              'From',
              _partyLines(data.seller, t, includeEmail: false),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _partyBox(
              'To',
              _partyLines(data.buyer, t, includeEmail: false),
            ),
          ),
        ],
      );
    }

    // Invoice / Quote: left = buyer block, right = GST metadata
    final billToLabel = data.type == PdfDocumentType.invoice
        ? 'BILL TO'
        : 'QUOTE FOR';

    // Build the buyer/billTo column (plain text style)
    pw.Widget buyerBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          billToLabel,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _muted,
          ),
        ),
        pw.SizedBox(height: 8),
        ..._partyLines(data.buyer, t, includeEmail: true).asMap().entries.map(
          (e) => pw.Text(
            e.value,
            style: pw.TextStyle(
              fontSize: e.key == 0 ? 14 : 10,
              fontWeight: e.key == 0
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: e.key == 0 ? _dark : _muted,
            ),
          ),
        ),
      ],
    );

    // When a ship-to address exists, render BILL TO and SHIP TO side by side
    // inside bordered boxes, matching the GST standard invoice layout.
    pw.Widget leftSection;
    if (data.shipTo != null) {
      leftSection = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _partyBox(
              billToLabel,
              _partyLines(data.buyer, t, includeEmail: false),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _partyBox(
              'SHIP TO',
              _partyLines(data.shipTo!, t, includeEmail: false),
            ),
          ),
        ],
      );
    } else {
      leftSection = buyerBlock;
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(child: leftSection),
        pw.SizedBox(width: 16),
        _metaBox(data, t),
      ],
    );
  }

  List<String> _partyLines(
    PdfPartyInfo p,
    DocumentTemplate template, {
    required bool includeEmail,
  }) {
    return [
      p.name,
      if (template.config.showGstin && p.gstin != null && p.gstin!.isNotEmpty)
        'GSTIN: ${p.gstin}',
      if (template.config.showAddresses &&
          p.address != null &&
          p.address!.isNotEmpty)
        p.address!,
      if ((p.phones != null && p.phones!.isNotEmpty) ||
          (p.phone != null && p.phone!.isNotEmpty))
        'Ph: ${(p.phones != null && p.phones!.isNotEmpty) ? p.phones!.join(', ') : p.phone}',
      if (includeEmail && p.email != null && p.email!.isNotEmpty) p.email!,
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
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              color: _muted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          ...lines.map(
            (l) => pw.Text(
              l,
              style: const pw.TextStyle(fontSize: 9, color: _dark),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _metaBox(PdfDocumentData data, DocumentTemplate template) {
    return pw.Container(
      width: 200,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (data.placeOfSupply != null && data.placeOfSupply!.isNotEmpty) ...[
            _metaRow('Place of Supply', data.placeOfSupply!),
            pw.SizedBox(height: 4),
          ],
          _metaRow(
            'Supply Type',
            data.totals.isInterState
                ? 'Inter-State (IGST)'
                : 'Intra-State (CGST+SGST)',
          ),
          pw.SizedBox(height: 4),
          _metaRow('Reverse Charge', data.reverseCharge ? 'Yes' : 'No'),
          if (template.config.showNotes &&
              data.notes != null &&
              data.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 4),
            pw.Text(
              'NOTES',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _muted,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(data.notes!, style: const pw.TextStyle(fontSize: 9)),
          ],
        ],
      ),
    );
  }

  pw.Widget _metaRow(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
            ),
          ),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ── Line items table ──────────────────────────────────────────────────────

  pw.Widget _buildLineItemsTable(
    PdfDocumentData data,
    DocumentTemplate t,
    NumberFormat fmt,
  ) {
    final items = data.lineItems;
    final isDC = data.type == PdfDocumentType.deliveryChallan;
    final hasTax = !isDC && items.any((i) => i.taxPct > 0);
    final hasDiscount = !isDC && items.any((i) => i.discountPct > 0);
    final hasHsn = items.any((i) => i.hsnCode != null && i.hsnCode!.isNotEmpty);
    final hasUnit = items.any((i) => i.unit != null && i.unit!.isNotEmpty);
    var columns = t.config.columns.where((column) {
      if (!column.visible) return false;
      if (column.id == 'hsn') return hasHsn;
      if (column.id == 'unit') return hasUnit;
      if (column.id == 'tax') return hasTax;
      if (column.id == 'discount') return hasDiscount;
      return true;
    }).toList();
    if (columns.isEmpty) {
      columns = PdfTemplateConfig.defaultColumns
          .where((column) => column.id == 'item' || column.id == 'amount')
          .toList();
    }

    final isBanner = t.headerStyle == PdfHeaderStyle.banner;
    final headerBg = isBanner ? t.accentColor : PdfColors.grey200;
    final headerFg = isBanner ? PdfColors.white : _dark;

    // Build header row
    final headers = _buildHeaderCells(
      columns: columns,
      bg: headerBg,
      fg: headerFg,
      template: t,
    );

    // Build data rows
    final dataRows = items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      return pw.TableRow(
        decoration: pw.BoxDecoration(
          color: idx.isEven ? PdfColors.white : _rowAlt,
        ),
        children: _buildItemCells(
          item,
          idx: idx,
          columns: columns,
          fmt: fmt,
          template: t,
        ),
      );
    }).toList();

    final colCount = headers.children.length;
    final columnWidths = <int, pw.TableColumnWidth>{};
    for (var index = 0; index < colCount; index++) {
      columnWidths[index] = pw.FlexColumnWidth(columns[index].widthPct);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _divider, width: 0.5),
      columnWidths: columnWidths,
      children: [headers, ...dataRows],
    );
  }

  pw.TableRow _buildHeaderCells({
    required List<PdfTemplateColumn> columns,
    required PdfColor bg,
    required PdfColor fg,
    required DocumentTemplate template,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: columns
          .map(
            (column) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              child: pw.Text(
                column.label,
                textAlign: _textAlign(column.alignment),
                style: pw.TextStyle(
                  fontSize: template.bodyFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: fg,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  List<pw.Widget> _buildItemCells(
    PdfLineItem item, {
    required int idx,
    required List<PdfTemplateColumn> columns,
    required NumberFormat fmt,
    required DocumentTemplate template,
  }) {
    String fmtQty(double q) =>
        q == q.truncateToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
    String fmtRate(double r) => fmt.format(r.abs());

    return columns.map((column) {
      if (column.id == 'item') {
        return _cellWidget(
          _itemNameWidget(item.name, item.description, template),
          verticalPadding: template.config.rowVerticalPadding,
        );
      }
      final value = switch (column.id) {
        'index' => '${idx + 1}',
        'hsn' => item.hsnCode ?? '',
        'qty' => fmtQty(item.qty),
        'unit' => item.unit ?? '',
        'rate' => fmtRate(item.unitPrice),
        'tax' => item.taxPct > 0 ? '${item.taxPct.toStringAsFixed(1)}%' : '—',
        'discount' =>
          item.discountPct > 0
              ? '${item.discountPct.toStringAsFixed(1)}%'
              : '—',
        'amount' => fmt.format(item.lineTotal.abs()),
        _ => '',
      };
      return _cell(
        value,
        bold: column.id == 'amount',
        fontSize: template.bodyFontSize,
        textAlign: _textAlign(column.alignment),
        verticalPadding: template.config.rowVerticalPadding,
      );
    }).toList();
  }

  pw.TextAlign _textAlign(PdfTextAlign alignment) {
    return switch (alignment) {
      PdfTextAlign.left => pw.TextAlign.left,
      PdfTextAlign.center => pw.TextAlign.center,
      PdfTextAlign.right => pw.TextAlign.right,
    };
  }

  pw.Widget _cell(
    String text, {
    bool bold = false,
    double fontSize = 9,
    pw.TextAlign? textAlign,
    double verticalPadding = 4,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 4,
        vertical: verticalPadding,
      ),
      child: pw.Text(
        text,
        textAlign: textAlign,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: _dark,
          fontWeight: bold ? pw.FontWeight.bold : null,
        ),
      ),
    );
  }

  pw.Widget _cellWidget(pw.Widget child, {double verticalPadding = 4}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: 4,
        vertical: verticalPadding,
      ),
      child: child,
    );
  }

  pw.Widget _itemNameWidget(
    String name,
    String? description,
    DocumentTemplate template,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          name,
          style: pw.TextStyle(fontSize: template.bodyFontSize, color: _dark),
        ),
        if (description != null && description.isNotEmpty)
          pw.Text(
            description,
            style: pw.TextStyle(
              fontSize: template.bodyFontSize - 1,
              color: _muted,
            ),
          ),
      ],
    );
  }

  // ── GST summary table ─────────────────────────────────────────────────────

  pw.Widget _buildGstSummaryTable(PdfDocumentData data, NumberFormat fmt) {
    final rows = data.totals.gstRows;
    if (rows.isEmpty) return pw.SizedBox.shrink();

    final isInterState = rows.first.isInterState;
    final totTaxable = rows.fold<double>(0, (s, r) => s + r.taxableAmount);
    final totCgst = rows.fold<double>(0, (s, r) => s + r.cgst);
    final totSgst = rows.fold<double>(0, (s, r) => s + r.sgst);
    final totIgst = rows.fold<double>(0, (s, r) => s + r.igst);
    final totGst = rows.fold<double>(0, (s, r) => s + r.total);

    String fmtRate(double rate) => rate == rate.truncateToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(1);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'GST Summary',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _muted,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: _divider, width: 0.5),
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _cell('HSN/SAC', bold: true),
                _cell('Taxable Amt', bold: true),
                _cell('Rate', bold: true),
                if (!isInterState) _cell('CGST', bold: true),
                if (!isInterState) _cell('SGST', bold: true),
                if (isInterState) _cell('IGST', bold: true),
                _cell('Total Tax', bold: true),
              ],
            ),
            // Detail rows
            ...rows.map(
              (r) => pw.TableRow(
                children: [
                  _cell(r.codeLabel),
                  _cell(fmt.format(r.taxableAmount.abs())),
                  _cell('${fmtRate(r.gstPct)}%'),
                  if (!isInterState) _cell(fmt.format(r.cgst.abs())),
                  if (!isInterState) _cell(fmt.format(r.sgst.abs())),
                  if (isInterState) _cell(fmt.format(r.igst.abs())),
                  _cell(fmt.format(r.total.abs()), bold: true),
                ],
              ),
            ),
            // Totals row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _cell('Total', bold: true),
                _cell(fmt.format(totTaxable.abs()), bold: true),
                _cell(''),
                if (!isInterState) _cell(fmt.format(totCgst.abs()), bold: true),
                if (!isInterState) _cell(fmt.format(totSgst.abs()), bold: true),
                if (isInterState) _cell(fmt.format(totIgst.abs()), bold: true),
                _cell(fmt.format(totGst.abs()), bold: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── Totals block ──────────────────────────────────────────────────────────

  pw.Widget _buildTotals(
    PdfDocumentData data,
    DocumentTemplate template,
    NumberFormat fmt,
  ) {
    final totals = data.totals;
    final config = template.config;
    final isDC = data.type == PdfDocumentType.deliveryChallan;
    final alignment = config.totalsAlignment == 'left'
        ? pw.Alignment.centerLeft
        : pw.Alignment.centerRight;

    String fmtRate(double rate) => rate == rate.truncateToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(1);

    // Delivery Challan: compact single-row total (ex-tax, no GST section).
    if (isDC) {
      return pw.Align(
        alignment: alignment,
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
                fmt.format(totals.grandTotal.abs()),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _dark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Invoice / Quote: full breakdown with GST lines and optional paid/balance.
    return pw.Align(
      alignment: alignment,
      child: pw.Container(
        width: 280,
        child: pw.Column(
          children: [
            if (config.showSubtotal) ...[
              _totalsRow('Subtotal', totals.subtotal, fmt, template: template),
              pw.Divider(color: _divider),
            ],
            if (config.showTaxBreakdown && totals.gstRows.isEmpty)
              _totalsRow(
                totals.isInterState ? 'IGST' : 'CGST + SGST',
                0,
                fmt,
                template: template,
                isSmall: true,
              )
            else if (config.showTaxBreakdown)
              for (final r in totals.gstRows) ...[
                if (totals.isInterState)
                  _totalsRow(
                    'IGST @${fmtRate(r.gstPct)}%',
                    r.igst,
                    fmt,
                    template: template,
                    isSmall: true,
                  )
                else ...[
                  _totalsRow(
                    'CGST @${fmtRate(r.gstPct / 2)}%',
                    r.cgst,
                    fmt,
                    template: template,
                    isSmall: true,
                  ),
                  _totalsRow(
                    'SGST @${fmtRate(r.gstPct / 2)}%',
                    r.sgst,
                    fmt,
                    template: template,
                    isSmall: true,
                  ),
                ],
              ],
            pw.Divider(color: _muted),
            if (totals.freight > 0)
              _totalsRow(
                'Freight',
                totals.freight,
                fmt,
                template: template,
                isSmall: true,
              ),
            if (totals.insurance > 0)
              _totalsRow(
                'Insurance',
                totals.insurance,
                fmt,
                template: template,
                isSmall: true,
              ),
            if (totals.packing > 0)
              _totalsRow(
                'Packing & Forwarding',
                totals.packing,
                fmt,
                template: template,
                isSmall: true,
              ),
            _totalsRow(
              'Total',
              totals.grandTotal,
              fmt,
              template: template,
              isBold: true,
              isLarge: true,
            ),
            if (totals.hasPayment &&
                (config.showPaid || config.showBalance)) ...[
              pw.SizedBox(height: 8),
              if (config.showPaid)
                _totalsRow(
                  'Paid',
                  totals.paidAmount,
                  fmt,
                  template: template,
                  color: PdfColors.green700,
                ),
              if (config.showBalance)
                _totalsRow(
                  'Balance Due',
                  totals.balanceDue,
                  fmt,
                  template: template,
                  isBold: true,
                  color: PdfColor.fromHex(config.balanceColorHex),
                ),
            ],
            if (config.showAmountInWords) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'Amount in words: ${_amountInWords(totals.grandTotal)}',
                style: pw.TextStyle(
                  fontSize: template.bodyFontSize,
                  color: _muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _totalsRow(
    String label,
    double amount,
    NumberFormat fmt, {
    required DocumentTemplate template,
    bool isBold = false,
    bool isSmall = false,
    bool isLarge = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isLarge
                  ? template.config.totalsFontSize + 2
                  : template.config.totalsFontSize,
              fontWeight: isBold || template.config.totalsBold
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: color ?? (isSmall ? _muted : _dark),
            ),
          ),
          pw.Text(
            fmt.format(amount.abs()),
            style: pw.TextStyle(
              fontSize: isLarge
                  ? template.config.totalsFontSize + 4
                  : template.config.totalsFontSize,
              fontWeight: isBold || template.config.totalsBold
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: color ?? _dark,
            ),
          ),
        ],
      ),
    );
  }

  String _amountInWords(double amount) {
    final value = amount.round();
    if (value == 0) return 'Zero rupees only';
    return '${_numberInWords(value)} rupees only';
  }

  String _numberInWords(int value) {
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    if (value < 20) return ones[value];
    if (value < 100) {
      return '${tens[value ~/ 10]} ${ones[value % 10]}'.trim();
    }
    if (value < 1000) {
      return '${ones[value ~/ 100]} Hundred ${_numberInWords(value % 100)}'
          .trim();
    }
    if (value < 100000) {
      return '${_numberInWords(value ~/ 1000)} Thousand '
              '${_numberInWords(value % 1000)}'
          .trim();
    }
    if (value < 10000000) {
      return '${_numberInWords(value ~/ 100000)} Lakh '
              '${_numberInWords(value % 100000)}'
          .trim();
    }
    return '${_numberInWords(value ~/ 10000000)} Crore '
            '${_numberInWords(value % 10000000)}'
        .trim();
  }

  // ── Transport details (DC only) ───────────────────────────────────────────

  pw.Widget _buildTransport(PdfTransportInfo t) {
    final entries = <String, String>{};
    if (t.transporterName != null && t.transporterName!.isNotEmpty) {
      entries['Transporter'] = t.transporterName!;
    }
    if (t.vehicleNo != null && t.vehicleNo!.isNotEmpty) {
      entries['Vehicle No.'] = t.vehicleNo!;
    }
    if (t.transportMode != null && t.transportMode!.isNotEmpty) {
      entries['Mode'] = _modeLabel(t.transportMode!);
    }
    if (t.distanceKm != null) {
      entries['Distance'] = '${t.distanceKm} km';
    }
    if (t.dispatchDate != null) {
      entries['Dispatch Date'] = DateFormatter.formatFull(t.dispatchDate!);
    }

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
              color: _muted,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            children: entries.entries
                .map(
                  (e) => pw.Container(
                    width: 140,
                    margin: const pw.EdgeInsets.only(bottom: 4, right: 8),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '${e.key}: ',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: _muted,
                            ),
                          ),
                          pw.TextSpan(
                            text: e.value,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: _dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
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

  // ── Footer ────────────────────────────────────────────────────────────────

  pw.Widget _buildFooter(PdfDocumentData data, DocumentTemplate template) {
    final isDC = data.type == PdfDocumentType.deliveryChallan;
    final config = template.config;
    final footerMessage = config.footerMessage.isEmpty
        ? data.footerNote
        : config.footerMessage;
    final showQr =
        (config.paymentDisplay == 'qr' || config.paymentDisplay == 'both') &&
        data.upiQrBytes != null;
    final showPaymentText =
        (config.paymentDisplay == 'text' || config.paymentDisplay == 'both') &&
        config.paymentText.isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // DC: declaration + signatory box
        if (isDC && config.showSignature) ...[
          pw.Row(
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
                          color: _muted,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'We declare that this invoice is true and correct and '
                        'the goods are being dispatched as per the details '
                        'mentioned above.',
                        style: const pw.TextStyle(fontSize: 8, color: _muted),
                      ),
                      if (data.notes != null && data.notes!.isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Notes: ${data.notes}',
                          style: const pw.TextStyle(fontSize: 8, color: _dark),
                        ),
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
                      'For ${data.seller.name}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _dark,
                      ),
                    ),
                    pw.SizedBox(height: 32),
                    pw.Container(height: 1, color: _dark),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      config.signatureLabel,
                      style: const pw.TextStyle(fontSize: 7, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
        ],

        // Footer note (thank you / validity sentence)
        if (footerMessage.isNotEmpty)
          pw.Text(
            footerMessage,
            style: pw.TextStyle(fontSize: config.footerFontSize + 4),
          ),

        // Terms & conditions
        if (config.showTerms &&
            data.termsAndConditions != null &&
            data.termsAndConditions!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Divider(color: _divider),
          pw.SizedBox(height: 8),
          pw.Text(
            'TERMS & CONDITIONS',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            data.termsAndConditions!,
            style: const pw.TextStyle(fontSize: 8, color: _dark),
          ),
        ],

        // Signatory box for Invoice & Quote (DC already has one inline above)
        if (!isDC && config.showSignature) ...[
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: showQr || showPaymentText
                ? pw.MainAxisAlignment.spaceBetween
                : config.signatureAlignment == 'left'
                ? pw.MainAxisAlignment.start
                : pw.MainAxisAlignment.end,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (showQr || showPaymentText)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (showQr)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _divider, width: 0.5),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Image(
                          pw.MemoryImage(data.upiQrBytes!),
                          width: 72,
                          height: 72,
                        ),
                      ),
                    if (showQr) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Scan to pay via UPI',
                        style: pw.TextStyle(fontSize: 7, color: _muted),
                      ),
                    ],
                    if (showPaymentText) ...[
                      if (showQr) pw.SizedBox(height: 4),
                      pw.Container(
                        width: 180,
                        child: pw.Text(
                          config.paymentText,
                          style: pw.TextStyle(
                            fontSize: config.footerFontSize,
                            color: _muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              pw.Container(
                width: 180,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _divider),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'For ${data.seller.name}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _dark,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 32),
                    pw.Container(height: 1, color: _dark),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      config.signatureLabel,
                      style: const pw.TextStyle(fontSize: 7, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (!isDC && !config.showSignature && (showQr || showPaymentText)) ...[
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (showQr)
                  pw.Image(
                    pw.MemoryImage(data.upiQrBytes!),
                    width: 72,
                    height: 72,
                  ),
                if (showQr) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Scan to pay via UPI',
                    style: pw.TextStyle(fontSize: 7, color: _muted),
                  ),
                ],
                if (showPaymentText) ...[
                  if (showQr) pw.SizedBox(height: 4),
                  pw.Text(
                    config.paymentText,
                    style: pw.TextStyle(
                      fontSize: config.footerFontSize,
                      color: _muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (data.showFreeWatermark) ...[
          pw.SizedBox(height: 10),
          _buildFreeWatermarkBanner(),
        ],
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (config.showGeneratedDate)
              pw.Text(
                'Generated on ${DateFormatter.formatFull(DateTime.now())}',
                style: pw.TextStyle(
                  fontSize: config.footerFontSize,
                  color: _muted,
                ),
              ),
            pw.UrlLink(
              destination: AppConfig.baseUrl,
              child: pw.Text(
                'Powered by Kash Cube · ${Uri.parse(AppConfig.baseUrl).host}',
                style: pw.TextStyle(
                  fontSize: config.footerFontSize,
                  color: PdfColor.fromHex('#2E7D32'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Legacy full-page copy note block retained for possible future reuse.
  // ignore: unused_element
  pw.Widget _buildCopyInfoBox(PdfCopyInfo copyInfo) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NUMBER OF COPIES REQUIRED',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${copyInfo.heading}: Prepared in ${_copyCountLabel(copyInfo.copyCount)} (${copyInfo.copyCount} copies)',
            style: const pw.TextStyle(fontSize: 8, color: _dark),
          ),
          pw.SizedBox(height: 4),
          ...copyInfo.copyLines.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(top: 1),
              child: pw.Text(
                '- $line',
                style: const pw.TextStyle(fontSize: 8, color: _dark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _copyCountLabel(int count) {
    switch (count) {
      case 2:
        return 'duplicate';
      case 3:
        return 'triplicate';
      case 4:
        return 'quadruplicate';
      default:
        return '$count-copies';
    }
  }

  /// Amber-tinted banner shown on documents generated by Free-tier users.
  pw.Widget _buildFreeWatermarkBanner() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFF8E1'),
        border: pw.Border.all(color: PdfColor.fromHex('#FFC107'), width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'Created with KashCube Free  ·  Remove watermark: upgrade to Starter at kashcube.app',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#E65100'),
            ),
          ),
        ],
      ),
    );
  }
}
