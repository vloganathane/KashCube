import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => _buildContent(data, template, fmt),
      ),
    );

    final path = await PdfCacheManager.instance.tempPath(filename);
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // ── Document assembly ─────────────────────────────────────────────────────

  List<pw.Widget> _buildContent(
    PdfDocumentData data,
    DocumentTemplate template,
    NumberFormat fmt,
  ) {
    // Banner style merges header + document title into one coloured block.
    // Minimal style keeps them separate.
    return [
      _buildHeaderAndTitle(data, template),
      pw.SizedBox(height: 20),
      _buildParties(data, template),
      pw.SizedBox(height: 20),
      _buildLineItemsTable(data, template, fmt),
      pw.SizedBox(height: 16),
      if (data.totals.hasGst) ...[
        _buildGstSummaryTable(data, fmt),
        pw.SizedBox(height: 8),
      ],
      _buildTotals(data, fmt),
      if (data.transport != null && !data.transport!.isEmpty) ...[
        pw.SizedBox(height: 16),
        _buildTransport(data.transport!),
      ],
      pw.SizedBox(height: 24),
      _buildFooter(data),
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
    final businessCol = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Container(width: 48, height: 48, child: pw.Image(logo)),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                seller.name.isNotEmpty ? seller.name : 'Your Business',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: fg,
                ),
              ),
              if (seller.gstin != null && seller.gstin!.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'GSTIN: ${seller.gstin}',
                  style: pw.TextStyle(fontSize: 9, color: fgMuted),
                ),
              ],
              if (_addressLine(seller) != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  _addressLine(seller)!,
                  style: pw.TextStyle(fontSize: 9, color: fgMuted),
                ),
              ],
              if (_contactLine(seller) != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  _contactLine(seller)!,
                  style: pw.TextStyle(fontSize: 9, color: fgMuted),
                ),
              ],
            ],
          ),
        ),
      ],
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
        pw.Text(
          '#${data.docNumber}',
          style: pw.TextStyle(fontSize: 9, color: fgMuted),
        ),
        pw.Text(
          'Date: ${DateFormatter.formatFull(data.issueDate)}',
          style: pw.TextStyle(fontSize: 9, color: fgMuted),
        ),
        if (data.dueDate != null)
          pw.Text(
            'Due: ${DateFormatter.formatFull(data.dueDate!)}',
            style: pw.TextStyle(fontSize: 9, color: fgMuted),
          ),
        if (data.validUntil != null)
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
        _statusBadge(data.statusLabel, data.statusColor,
            onDark: isBanner),
      ],
    );

    if (isBanner) {
      // Banner: single coloured container with business on left, doc meta right
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: t.accentColor,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: businessCol),
            pw.SizedBox(width: 16),
            docMetaCol,
          ],
        ),
      );
    } else {
      // Minimal: business block → thin accent line → doc title row
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          businessCol,
          pw.SizedBox(height: 12),
          pw.Container(height: 2, color: t.accentColor),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.typeLabel,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  if (data.subTypeLabel != null) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      data.subTypeLabel!,
                      style: pw.TextStyle(fontSize: 10, color: _muted),
                    ),
                  ],
                  pw.SizedBox(height: 6),
                  pw.Text(
                    data.docNumber,
                    style: pw.TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Date: ${DateFormatter.formatFull(data.issueDate)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  if (data.dueDate != null)
                    pw.Text(
                      'Due: ${DateFormatter.formatFull(data.dueDate!)}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  if (data.validUntil != null)
                    pw.Text(
                      'Valid Until: ${DateFormatter.formatFull(data.validUntil!)}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  pw.SizedBox(height: 4),
                  _statusBadge(data.statusLabel, data.statusColor,
                      onDark: false),
                ],
              ),
            ],
          ),
        ],
      );
    }
  }

  pw.Widget _statusBadge(String label, PdfColor color,
      {bool onDark = false}) {
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
    final parts = [p.phone, p.email]
        .where((e) => e != null && e.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' | ');
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
              child:
                  _partyBox('From', _partyLines(data.seller, includeEmail: false))),
          pw.SizedBox(width: 12),
          pw.Expanded(
              child:
                  _partyBox('To', _partyLines(data.buyer, includeEmail: false))),
        ],
      );
    }

    // Invoice / Quote: left = buyer block, right = GST metadata
    final billToLabel =
        data.type == PdfDocumentType.invoice ? 'BILL TO' : 'QUOTE FOR';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Column(
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
              ..._partyLines(data.buyer, includeEmail: true)
                  .asMap()
                  .entries
                  .map((e) => pw.Text(
                        e.value,
                        style: pw.TextStyle(
                          fontSize: e.key == 0 ? 14 : 10,
                          fontWeight: e.key == 0
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                          color: e.key == 0 ? _dark : _muted,
                        ),
                      )),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        _metaBox(data),
      ],
    );
  }

  List<String> _partyLines(PdfPartyInfo p,
      {required bool includeEmail}) {
    return [
      p.name,
      if (p.gstin != null && p.gstin!.isNotEmpty) 'GSTIN: ${p.gstin}',
      if (p.address != null && p.address!.isNotEmpty) p.address!,
      if (p.phone != null && p.phone!.isNotEmpty) 'Ph: ${p.phone}',
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
                fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          ...lines.map((l) =>
              pw.Text(l, style: const pw.TextStyle(fontSize: 9, color: _dark))),
        ],
      ),
    );
  }

  pw.Widget _metaBox(PdfDocumentData data) {
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
          if (data.placeOfSupply != null &&
              data.placeOfSupply!.isNotEmpty) ...[
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
          if (data.notes != null && data.notes!.isNotEmpty) ...[
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
                color: _muted),
          ),
          pw.TextSpan(
              text: value, style: const pw.TextStyle(fontSize: 9)),
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

    final isBanner = t.headerStyle == PdfHeaderStyle.banner;
    final headerBg = isBanner ? t.accentColor : PdfColors.grey200;
    final headerFg = isBanner ? PdfColors.white : _dark;

    // Build header row
    final headers = _buildHeaderCells(
      hasHsn: hasHsn,
      hasTax: hasTax,
      hasDiscount: hasDiscount,
      hasUnit: hasUnit,
      isDC: isDC,
      bg: headerBg,
      fg: headerFg,
    );

    // Build data rows
    final dataRows = items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      return pw.TableRow(
        decoration: pw.BoxDecoration(
            color: idx.isEven ? PdfColors.white : _rowAlt),
        children: _buildItemCells(
          item,
          idx: idx,
          hasHsn: hasHsn,
          hasTax: hasTax,
          hasDiscount: hasDiscount,
          hasUnit: hasUnit,
          isDC: isDC,
          fmt: fmt,
        ),
      );
    }).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: _divider, width: 0.5),
      children: [headers, ...dataRows],
    );
  }

  pw.TableRow _buildHeaderCells({
    required bool hasHsn,
    required bool hasTax,
    required bool hasDiscount,
    required bool hasUnit,
    required bool isDC,
    required PdfColor bg,
    required PdfColor fg,
  }) {
    final labels = <String>['#', 'Item / Description'];
    if (hasHsn) labels.add('HSN');
    labels.add('Qty');
    if (hasUnit) labels.add('Unit');
    labels.add('Rate');
    if (hasTax) labels.add('Tax %');
    if (hasDiscount) labels.add('Disc %');
    labels.add('Amount');

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: labels
          .map((h) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 6),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: fg,
                  ),
                ),
              ))
          .toList(),
    );
  }

  List<pw.Widget> _buildItemCells(
    PdfLineItem item, {
    required int idx,
    required bool hasHsn,
    required bool hasTax,
    required bool hasDiscount,
    required bool hasUnit,
    required bool isDC,
    required NumberFormat fmt,
  }) {
    String fmtQty(double q) =>
        q == q.truncateToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
    String fmtRate(double r) => fmt.format(r.abs());

    final cells = <pw.Widget>[
      _cell('${idx + 1}'),
      _cellWidget(_itemNameWidget(item.name, item.description)),
      if (hasHsn) _cell(item.hsnCode ?? ''),
      _cell(fmtQty(item.qty)),
      if (hasUnit) _cell(item.unit ?? ''),
      _cell(fmtRate(item.unitPrice)),
      if (hasTax)
        _cell(item.taxPct > 0 ? '${item.taxPct.toStringAsFixed(1)}%' : '—'),
      if (hasDiscount)
        _cell(
            item.discountPct > 0
                ? '${item.discountPct.toStringAsFixed(1)}%'
                : '—'),
      _cell(fmt.format(item.lineTotal.abs()), bold: true),
    ];
    return cells;
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

  pw.Widget _cellWidget(pw.Widget child) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: child,
    );
  }

  pw.Widget _itemNameWidget(String name, String? description) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(name, style: const pw.TextStyle(fontSize: 9, color: _dark)),
        if (description != null && description.isNotEmpty)
          pw.Text(description,
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
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

    String fmtRate(double rate) =>
        rate == rate.truncateToDouble()
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
              color: _muted),
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
            ...rows.map((r) => pw.TableRow(
                  children: [
                    _cell(r.codeLabel),
                    _cell(fmt.format(r.taxableAmount.abs())),
                    _cell('${fmtRate(r.gstPct)}%'),
                    if (!isInterState) _cell(fmt.format(r.cgst.abs())),
                    if (!isInterState) _cell(fmt.format(r.sgst.abs())),
                    if (isInterState) _cell(fmt.format(r.igst.abs())),
                    _cell(fmt.format(r.total.abs()), bold: true),
                  ],
                )),
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

  pw.Widget _buildTotals(PdfDocumentData data, NumberFormat fmt) {
    final totals = data.totals;
    final isDC = data.type == PdfDocumentType.deliveryChallan;

    String fmtRate(double rate) =>
        rate == rate.truncateToDouble()
            ? rate.toStringAsFixed(0)
            : rate.toStringAsFixed(1);

    // Delivery Challan: compact single-row total (ex-tax, no GST section).
    if (isDC) {
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
              pw.Text('Total Value (Ex-tax)',
                  style: const pw.TextStyle(fontSize: 10, color: _dark)),
              pw.Text(
                fmt.format(totals.grandTotal.abs()),
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _dark),
              ),
            ],
          ),
        ),
      );
    }

    // Invoice / Quote: full breakdown with GST lines and optional paid/balance.
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 280,
        child: pw.Column(
          children: [
            _totalsRow('Subtotal', totals.subtotal, fmt),
            pw.Divider(color: _divider),
            if (totals.gstRows.isEmpty)
              _totalsRow(
                  totals.isInterState ? 'IGST' : 'CGST + SGST', 0, fmt,
                  isSmall: true)
            else
              for (final r in totals.gstRows) ...[
                if (totals.isInterState)
                  _totalsRow(
                      'IGST @${fmtRate(r.gstPct)}%', r.igst, fmt,
                      isSmall: true)
                else ...[
                  _totalsRow(
                      'CGST @${fmtRate(r.gstPct / 2)}%', r.cgst, fmt,
                      isSmall: true),
                  _totalsRow(
                      'SGST @${fmtRate(r.gstPct / 2)}%', r.sgst, fmt,
                      isSmall: true),
                ],
              ],
            pw.Divider(color: _muted),
            if (totals.freight > 0)
              _totalsRow('Freight', totals.freight, fmt, isSmall: true),
            if (totals.insurance > 0)
              _totalsRow('Insurance', totals.insurance, fmt, isSmall: true),
            if (totals.packing > 0)
              _totalsRow('Packing & Forwarding', totals.packing, fmt,
                  isSmall: true),
            _totalsRow('Total', totals.grandTotal, fmt,
                isBold: true, isLarge: true),
            if (totals.hasPayment) ...[
              pw.SizedBox(height: 8),
              _totalsRow('Paid', totals.paidAmount, fmt,
                  color: PdfColors.green700),
              _totalsRow('Balance Due', totals.balanceDue, fmt,
                  isBold: true, color: PdfColors.red700),
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
              fontSize: isLarge ? 14 : 12,
              fontWeight:
                  isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? (isSmall ? _muted : _dark),
            ),
          ),
          pw.Text(
            fmt.format(amount.abs()),
            style: pw.TextStyle(
              fontSize: isLarge ? 16 : 12,
              fontWeight:
                  isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? _dark,
            ),
          ),
        ],
      ),
    );
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
                color: _muted),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            children: entries.entries
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

  // ── Footer ────────────────────────────────────────────────────────────────

  pw.Widget _buildFooter(PdfDocumentData data) {
    final isDC = data.type == PdfDocumentType.deliveryChallan;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // DC: declaration + signatory box
        if (isDC) ...[
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
                            color: _muted),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'We declare that this invoice is true and correct and '
                        'the goods are being dispatched as per the details '
                        'mentioned above.',
                        style: const pw.TextStyle(
                            fontSize: 8, color: _muted),
                      ),
                      if (data.notes != null &&
                          data.notes!.isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Text('Notes: ${data.notes}',
                            style: const pw.TextStyle(
                                fontSize: 8, color: _dark)),
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
                          color: _dark),
                    ),
                    pw.SizedBox(height: 32),
                    pw.Container(height: 1, color: _dark),
                    pw.SizedBox(height: 4),
                    pw.Text('Authorised Signatory',
                        style: const pw.TextStyle(
                            fontSize: 7, color: _muted)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
        ],

        // Footer note (thank you / validity sentence)
        if (data.footerNote.isNotEmpty)
          pw.Text(
            data.footerNote,
            style: const pw.TextStyle(fontSize: 12),
          ),

        // Terms & conditions
        if (data.termsAndConditions != null &&
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

        pw.SizedBox(height: 8),
        pw.Text(
          'Generated on ${DateFormatter.formatFull(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    );
  }
}
