import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business.dart';
import 'gst_calculator.dart';
import 'pdf_cache_manager.dart';
import '../models/invoice.dart';
import '../models/party.dart';
import '../models/quote.dart';
import '../../core/utils/date_formatter.dart';

/// Service for generating PDF documents for invoices and quotes.
/// 100% local - no network calls.
class InvoicePdfService {
  InvoicePdfService._();
  static final instance = InvoicePdfService._();

  // PDF-friendly currency formatter (uses "Rs." instead of ₹ symbol)
  static final _indianFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs.',
    decimalDigits: 0,
  );

  /// Format amount for PDF (using Rs. prefix that renders correctly)
  String _formatCurrency(double amount) {
    return _indianFormat.format(amount.abs());
  }

  /// Load business logo from file system if available
  Future<pw.MemoryImage?> _loadBusinessLogo(Business business) async {
    if (business.logoPath == null || business.logoPath!.isEmpty) {
      return null;
    }
    try {
      final file = File(business.logoPath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.MemoryImage(bytes);
      }
    } catch (e) {
      // Logo load failed, continue without it
    }
    return null;
  }

  /// Generate PDF for an invoice with GST breakdown.
  Future<File> generateInvoicePdf(Invoice invoice, {Business? business, Party? customerParty}) async {
    final pdf = pw.Document();
    final logo = business != null ? await _loadBusinessLogo(business) : null;

    final sellerState = business?.state;
    final buyerState = customerParty?.state;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildInvoiceHeader(invoice, business: business, logo: logo),
          pw.SizedBox(height: 24),
          _buildInvoiceDetails(invoice,
              customerParty: customerParty,
              sellerState: sellerState,
              buyerState: buyerState),
          pw.SizedBox(height: 24),
          _buildItemsTable(invoice.items),
          pw.SizedBox(height: 16),
          _buildGstSummaryTable(invoice.items,
              sellerState: sellerState, buyerState: buyerState),
          pw.SizedBox(height: 8),
          _buildTotalsWithGst(invoice,
              sellerState: sellerState, buyerState: buyerState),
          pw.SizedBox(height: 32),
          _buildFooter(invoice),
        ],
      ),
    );

    return _savePdf(pdf, 'Invoice_${invoice.invoiceNo}.pdf');
  }

  /// Generate PDF for a quote.
  Future<File> generateQuotePdf(Quote quote, {Business? business, Party? customerParty}) async {
    final pdf = pw.Document();
    final logo = business != null ? await _loadBusinessLogo(business) : null;

    final sellerState = business?.state;
    final buyerState = customerParty?.state;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildQuoteHeader(quote, business: business, logo: logo),
          pw.SizedBox(height: 24),
          _buildQuoteDetails(quote,
              customerParty: customerParty,
              sellerState: sellerState,
              buyerState: buyerState),
          pw.SizedBox(height: 24),
          _buildQuoteItemsTable(quote.items),
          pw.SizedBox(height: 16),
          _buildQuoteGstSummaryTable(quote.items,
              sellerState: sellerState, buyerState: buyerState),
          pw.SizedBox(height: 8),
          _buildQuoteTotalsWithGst(quote,
              sellerState: sellerState, buyerState: buyerState),
          pw.SizedBox(height: 32),
          _buildQuoteFooter(quote),
        ],
      ),
    );

    return _savePdf(pdf, 'Quote_${quote.quoteNo}.pdf');
  }

  // ── Invoice Components ─────────────────────────────────────────────────────

  pw.Widget _buildInvoiceHeader(Invoice invoice, {Business? business, pw.MemoryImage? logo}) {
    return pw.Column(
      children: [
        // Business info if available
        if (business != null) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo, width: 60, height: 60),
                    pw.SizedBox(width: 16),
                  ],
                  pw.Container(
                    width: logo != null? 240 : 300,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          business.name,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    if (business.gstNo != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'GSTIN: ${business.gstNo}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                    if (business.address != null || business.city != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        [business.address, business.city, business.state]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(', '),
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                    if (business.phone != null || business.email != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        [business.phone, business.email]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' | '),
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 24),
      pw.Divider(),
      pw.SizedBox(height: 16),
    ],
    // Invoice header
    pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  invoice.invoiceType.label.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  invoice.invoiceNo,
                  style: pw.TextStyle(
                    fontSize: 16,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${DateFormatter.format(invoice.issueDate)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                if (invoice.dueDate != null)
                  pw.Text(
                    'Due: ${DateFormatter.format(invoice.dueDate!)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                pw.SizedBox(height: 4),
                _buildStatusBadge(invoice.status),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildStatusBadge(InvoiceStatus status) {
    final color = _getStatusColor(status);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        status.label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  PdfColor _getStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.paid:
        return PdfColors.green700;
      case InvoiceStatus.sent:
        return PdfColors.blue700;
      case InvoiceStatus.overdue:
        return PdfColors.red700;
      case InvoiceStatus.partiallyPaid:
        return PdfColors.orange700;
      case InvoiceStatus.draft:
        return PdfColors.grey600;
    }
  }

  pw.Widget _buildInvoiceDetails(
    Invoice invoice, {
    Party? customerParty,
    String? sellerState,
    String? buyerState,
  }) {
    final effectiveBuyerGstin =
        invoice.customerGstin ?? customerParty?.gstin;
    final effectivePlaceOfSupply =
        invoice.placeOfSupply ?? buyerState ?? '';
    final isInterState =
        GstCalculator.isInterState(sellerState, buyerState);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // Bill To block
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BILL TO',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  invoice.customerName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (effectiveBuyerGstin != null &&
                    effectiveBuyerGstin.isNotEmpty) ...[  
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'GSTIN: $effectiveBuyerGstin',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
                if (customerParty != null)
                  ..._buildPartyDetails(customerParty,
                      skipGstin: effectiveBuyerGstin != null),
              ],
            ),
            // GST metadata block
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (effectivePlaceOfSupply.isNotEmpty) ...[  
                    _metaRow('Place of Supply', effectivePlaceOfSupply),
                    pw.SizedBox(height: 4),
                  ],
                  _metaRow(
                    'Supply Type',
                    isInterState ? 'Inter-State (IGST)' : 'Intra-State (CGST+SGST)',
                  ),
                  pw.SizedBox(height: 4),
                  _metaRow(
                    'Reverse Charge',
                    invoice.reverseCharge ? 'Yes' : 'No',
                  ),
                  if (invoice.notes != null &&
                      invoice.notes!.isNotEmpty) ...[  
                    pw.SizedBox(height: 6),
                    pw.Divider(color: PdfColors.grey300),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'NOTES',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      invoice.notes!,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
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
              color: PdfColors.grey700,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildItemsTable(List<InvoiceItem> items) {
    final hasTax = items.any((item) => item.taxPct > 0);
    final hasDiscount = items.any((item) => item.discountPct > 0);
    final hasHsn = items.any((item) => item.hsnCode != null && item.hsnCode!.isNotEmpty);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('Item', isHeader: true),
            if (hasHsn) _tableCell('HSN/SAC', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Qty', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Rate', isHeader: true, align: pw.TextAlign.right),
            if (hasTax) _tableCell('Tax %', isHeader: true, align: pw.TextAlign.center),
            if (hasDiscount) _tableCell('Disc %', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Amount', isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        ...items.map((item) => pw.TableRow(
              children: [
                _tableCell(_buildItemName(item.itemName, item.description)),
                if (hasHsn)
                  _tableCell(
                    item.hsnCode != null && item.hsnCode!.isNotEmpty
                        ? item.hsnCode!
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                _tableCell(item.qty.toString(), align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.unitPrice),
                    align: pw.TextAlign.right),
                if (hasTax)
                  _tableCell(
                    item.taxPct > 0
                        ? '${item.taxPct.toStringAsFixed(1)}%'
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                if (hasDiscount)
                  _tableCell(
                    item.discountPct > 0
                        ? '${item.discountPct.toStringAsFixed(1)}%'
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                _tableCell(_formatCurrency(item.lineTotal),
                    align: pw.TextAlign.right, isBold: true),
              ],
            )),
      ],
    );
  }

  /// HSN/SAC-grouped GST summary table (mandatory on Tax Invoices).
  pw.Widget _buildGstSummaryTable(
    List<InvoiceItem> items, {
    String? sellerState,
    String? buyerState,
  }) {
    final rows = GstCalculator.summarise(
      sellerState: sellerState,
      buyerState: buyerState,
      items: items.toSplitInputs(),
    );
    if (rows.isEmpty) return pw.SizedBox.shrink();

    final isInterState = rows.first.isInterState;
    final totTaxable = rows.fold<double>(0, (s, r) => s + r.taxableAmount);
    final totCgst = rows.fold<double>(0, (s, r) => s + r.cgst);
    final totSgst = rows.fold<double>(0, (s, r) => s + r.sgst);
    final totIgst = rows.fold<double>(0, (s, r) => s + r.igst);
    final totGst = rows.fold<double>(0, (s, r) => s + r.total);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'GST Summary',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _tableCell('HSN/SAC', isHeader: true),
                _tableCell('Taxable Amt', isHeader: true, align: pw.TextAlign.right),
                _tableCell('Rate', isHeader: true, align: pw.TextAlign.center),
                if (!isInterState)
                  _tableCell('CGST', isHeader: true, align: pw.TextAlign.right),
                if (!isInterState)
                  _tableCell('SGST', isHeader: true, align: pw.TextAlign.right),
                if (isInterState)
                  _tableCell('IGST', isHeader: true, align: pw.TextAlign.right),
                _tableCell('Total Tax', isHeader: true, align: pw.TextAlign.right),
              ],
            ),
            ...rows.map((r) => pw.TableRow(
                  children: [
                    _tableCell(r.codeLabel),
                    _tableCell(_formatCurrency(r.taxableAmount),
                        align: pw.TextAlign.right),
                    _tableCell('${r.gstPct.toStringAsFixed(r.gstPct == r.gstPct.truncateToDouble() ? 0 : 1)}%',
                        align: pw.TextAlign.center),
                    if (!isInterState)
                      _tableCell(_formatCurrency(r.cgst),
                          align: pw.TextAlign.right),
                    if (!isInterState)
                      _tableCell(_formatCurrency(r.sgst),
                          align: pw.TextAlign.right),
                    if (isInterState)
                      _tableCell(_formatCurrency(r.igst),
                          align: pw.TextAlign.right),
                    _tableCell(_formatCurrency(r.total),
                        align: pw.TextAlign.right, isBold: true),
                  ],
                )),
            // Totals row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _tableCell('Total', isHeader: true),
                _tableCell(_formatCurrency(totTaxable),
                    align: pw.TextAlign.right, isBold: true),
                _tableCell('', align: pw.TextAlign.center),
                if (!isInterState)
                  _tableCell(_formatCurrency(totCgst),
                      align: pw.TextAlign.right, isBold: true),
                if (!isInterState)
                  _tableCell(_formatCurrency(totSgst),
                      align: pw.TextAlign.right, isBold: true),
                if (isInterState)
                  _tableCell(_formatCurrency(totIgst),
                      align: pw.TextAlign.right, isBold: true),
                _tableCell(_formatCurrency(totGst),
                    align: pw.TextAlign.right, isBold: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildItemName(String name, String? description) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(name),
        if (description != null && description.isNotEmpty)
          pw.Text(
            description,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
      ],
    );
  }

  pw.Widget _tableCell(
    dynamic content, {
    bool isHeader = false,
    bool isBold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: content is pw.Widget
          ? content
          : pw.Text(
              content.toString(),
              style: pw.TextStyle(
                fontSize: isHeader ? 10 : 11,
                fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isHeader ? PdfColors.grey700 : PdfColors.black,
              ),
              textAlign: align,
            ),
    );
  }

pw.Widget _buildTotalsWithGst(
    Invoice invoice, {
    String? sellerState,
    String? buyerState,
  }) {
    final subtotal = invoice.items.fold<double>(
      0,
      (sum, item) =>
          sum + (item.qty * item.unitPrice * (1 - item.discountPct / 100)),
    );
    final isInterState = GstCalculator.isInterState(sellerState, buyerState);
    double totalCgst = 0, totalSgst = 0, totalIgst = 0;
    for (final item in invoice.items) {
      if (item.taxPct <= 0) continue;
      final taxable = item.qty * item.unitPrice * (1 - item.discountPct / 100);
      final split = GstCalculator.calculate(
        sellerState: sellerState,
        buyerState: buyerState,
        taxableAmount: taxable,
        gstPct: item.taxPct,
      );
      totalCgst += split.cgst;
      totalSgst += split.sgst;
      totalIgst += split.igst;
    }

    return pw.Container(
      width: 280,
      child: pw.Column(
        children: [
          _totalsRow('Subtotal', subtotal),
          pw.Divider(color: PdfColors.grey300),
          if (!isInterState) ...[  
            _totalsRow('CGST', totalCgst, isSmall: true),
            _totalsRow('SGST', totalSgst, isSmall: true),
          ] else
            _totalsRow('IGST', totalIgst, isSmall: true),
          pw.Divider(color: PdfColors.grey400),
          _totalsRow('Total', invoice.total, isBold: true, isLarge: true),
          if (invoice.paidAmount > 0) ...[
            pw.SizedBox(height: 8),
            _totalsRow('Paid', invoice.paidAmount, color: PdfColors.green700),
            _totalsRow(
              'Balance Due',
              invoice.total - invoice.paidAmount,
              isBold: true,
              color: PdfColors.red700,
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _totalsRow(
    String label,
    double amount, {
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
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? (isSmall ? PdfColors.grey600 : PdfColors.black),
            ),
          ),
          pw.Text(
            _formatCurrency(amount),
            style: pw.TextStyle(
              fontSize: isLarge ? 16 : 12,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Thank you for your business!',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Generated on ${DateFormatter.formatFull(DateTime.now())}',
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey500,
          ),
        ),
      ],
    );
  }

  // ── Quote Components ───────────────────────────────────────────────────────

  pw.Widget _buildQuoteHeader(Quote quote, {Business? business, pw.MemoryImage? logo}) {
    return pw.Column(
      children: [
        // Business info if available
        if (business != null) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo, width: 60, height: 60),
                    pw.SizedBox(width: 16),
                  ],
                  pw.Container(
                    width: logo != null ? 240 : 300,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          business.name,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    if (business.gstNo != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'GSTIN: ${business.gstNo}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                    if (business.address != null || business.city != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        [business.address, business.city, business.state]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(', '),
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                    if (business.phone != null || business.email != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        [business.phone, business.email]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' | '),
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 24),
      pw.Divider(),
      pw.SizedBox(height: 16),
    ],
    // Quote header
    pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'QUOTATION',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'For ${quote.invoiceType.label}',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  quote.quoteNo,
                  style: pw.TextStyle(
                    fontSize: 16,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Date: ${DateFormatter.format(quote.createdAt)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                if (quote.validUntil != null)
                  pw.Text(
                    'Valid Until: ${DateFormatter.format(quote.validUntil!)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                pw.SizedBox(height: 4),
                _buildQuoteStatusBadge(quote.status),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildQuoteStatusBadge(QuoteStatus status) {
    final color = _getQuoteStatusColor(status);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        status.label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  PdfColor _getQuoteStatusColor(QuoteStatus status) {
    switch (status) {
      case QuoteStatus.accepted:
        return PdfColors.green700;
      case QuoteStatus.sent:
        return PdfColors.blue700;
      case QuoteStatus.rejected:
        return PdfColors.red700;
      case QuoteStatus.draft:
        return PdfColors.grey600;
    }
  }

  pw.Widget _buildQuoteDetails(
    Quote quote, {
    Party? customerParty,
    String? sellerState,
    String? buyerState,
  }) {
    final effectiveBuyerGstin =
        quote.customerGstin ?? customerParty?.gstin;
    final effectivePlaceOfSupply =
        quote.placeOfSupply ?? buyerState ?? '';
    final isInterState =
        GstCalculator.isInterState(sellerState, buyerState);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'QUOTE FOR',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  quote.customerName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (effectiveBuyerGstin != null &&
                    effectiveBuyerGstin.isNotEmpty) ...[  
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'GSTIN: $effectiveBuyerGstin',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
                if (customerParty != null)
                  ..._buildPartyDetails(customerParty,
                      skipGstin: effectiveBuyerGstin != null),
              ],
            ),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (effectivePlaceOfSupply.isNotEmpty) ...[  
                    _metaRow('Place of Supply', effectivePlaceOfSupply),
                    pw.SizedBox(height: 4),
                  ],
                  _metaRow(
                    'Supply Type',
                    isInterState
                        ? 'Inter-State (IGST)'
                        : 'Intra-State (CGST+SGST)',
                  ),
                  pw.SizedBox(height: 4),
                  _metaRow(
                    'Reverse Charge',
                    quote.reverseCharge ? 'Yes' : 'No',
                  ),
                  if (quote.notes != null && quote.notes!.isNotEmpty) ...[  
                    pw.SizedBox(height: 6),
                    pw.Divider(color: PdfColors.grey300),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'NOTES',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(quote.notes!,
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build party contact details for PDF.
  ///
  /// [skipGstin] avoids printing GSTIN twice when the caller has already
  /// rendered it from `invoice.customerGstin` / `quote.customerGstin`.
  List<pw.Widget> _buildPartyDetails(Party party, {bool skipGstin = false}) {
    final details = <pw.Widget>[];
    
    if (party.phoneNumber != null && party.phoneNumber!.isNotEmpty) {
      details.add(pw.SizedBox(height: 4));
      details.add(
        pw.Text(
          '+91 ${party.phoneNumber!}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }
    
    if (party.email != null && party.email!.isNotEmpty) {
      details.add(pw.SizedBox(height: 2));
      details.add(
        pw.Text(
          party.email!,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }
    
    if (party.gstin != null && party.gstin!.isNotEmpty && !skipGstin) {
      details.add(pw.SizedBox(height: 2));
      details.add(
        pw.Text(
          'GSTIN: ${party.gstin!}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }
    
    if (party.formattedAddress != null) {
      details.add(pw.SizedBox(height: 4));
      details.add(
        pw.Container(
          constraints: const pw.BoxConstraints(maxWidth: 250),
          child: pw.Text(
            party.formattedAddress!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
      );
    }
    
    return details;
  }

  pw.Widget _buildQuoteItemsTable(List<QuoteItem> items) {
    final hasTax = items.any((item) => item.taxPct > 0);
    final hasDiscount = items.any((item) => item.discountPct > 0);
    final hasHsn = items.any(
        (item) => item.hsnCode != null && item.hsnCode!.isNotEmpty);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('Item', isHeader: true),
            if (hasHsn)
              _tableCell('HSN/SAC', isHeader: true,
                  align: pw.TextAlign.center),
            _tableCell('Qty', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Rate', isHeader: true, align: pw.TextAlign.right),
            if (hasTax)
              _tableCell('Tax %', isHeader: true,
                  align: pw.TextAlign.center),
            if (hasDiscount)
              _tableCell('Disc %', isHeader: true,
                  align: pw.TextAlign.center),
            _tableCell('Amount', isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        ...items.map((item) => pw.TableRow(
              children: [
                _tableCell(_buildItemName(item.itemName, item.description)),
                if (hasHsn)
                  _tableCell(
                    item.hsnCode != null && item.hsnCode!.isNotEmpty
                        ? item.hsnCode!
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                _tableCell(item.qty.toString(),
                    align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.unitPrice),
                    align: pw.TextAlign.right),
                if (hasTax)
                  _tableCell(
                    item.taxPct > 0
                        ? '${item.taxPct.toStringAsFixed(1)}%'
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                if (hasDiscount)
                  _tableCell(
                    item.discountPct > 0
                        ? '${item.discountPct.toStringAsFixed(1)}%'
                        : '—',
                    align: pw.TextAlign.center,
                  ),
                _tableCell(_formatCurrency(item.lineTotal),
                    align: pw.TextAlign.right, isBold: true),
              ],
            )),
      ],
    );
  }

  pw.Widget _buildQuoteGstSummaryTable(
    List<QuoteItem> items, {
    String? sellerState,
    String? buyerState,
  }) {
    final rows = GstCalculator.summarise(
      sellerState: sellerState,
      buyerState: buyerState,
      items: items.toSplitInputs(),
    );
    if (rows.isEmpty) return pw.SizedBox.shrink();

    final isInterState = rows.first.isInterState;
    final totTaxable = rows.fold<double>(0, (s, r) => s + r.taxableAmount);
    final totCgst = rows.fold<double>(0, (s, r) => s + r.cgst);
    final totSgst = rows.fold<double>(0, (s, r) => s + r.sgst);
    final totIgst = rows.fold<double>(0, (s, r) => s + r.igst);
    final totGst = rows.fold<double>(0, (s, r) => s + r.total);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'GST Summary',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _tableCell('HSN/SAC', isHeader: true),
                _tableCell('Taxable Amt', isHeader: true,
                    align: pw.TextAlign.right),
                _tableCell('Rate', isHeader: true,
                    align: pw.TextAlign.center),
                if (!isInterState)
                  _tableCell('CGST', isHeader: true,
                      align: pw.TextAlign.right),
                if (!isInterState)
                  _tableCell('SGST', isHeader: true,
                      align: pw.TextAlign.right),
                if (isInterState)
                  _tableCell('IGST', isHeader: true,
                      align: pw.TextAlign.right),
                _tableCell('Total Tax', isHeader: true,
                    align: pw.TextAlign.right),
              ],
            ),
            ...rows.map((r) => pw.TableRow(
                  children: [
                    _tableCell(r.codeLabel),
                    _tableCell(_formatCurrency(r.taxableAmount),
                        align: pw.TextAlign.right),
                    _tableCell(
                      '${r.gstPct.toStringAsFixed(r.gstPct == r.gstPct.truncateToDouble() ? 0 : 1)}%',
                      align: pw.TextAlign.center,
                    ),
                    if (!isInterState)
                      _tableCell(_formatCurrency(r.cgst),
                          align: pw.TextAlign.right),
                    if (!isInterState)
                      _tableCell(_formatCurrency(r.sgst),
                          align: pw.TextAlign.right),
                    if (isInterState)
                      _tableCell(_formatCurrency(r.igst),
                          align: pw.TextAlign.right),
                    _tableCell(_formatCurrency(r.total),
                        align: pw.TextAlign.right, isBold: true),
                  ],
                )),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _tableCell('Total', isHeader: true),
                _tableCell(_formatCurrency(totTaxable),
                    align: pw.TextAlign.right, isBold: true),
                _tableCell('', align: pw.TextAlign.center),
                if (!isInterState)
                  _tableCell(_formatCurrency(totCgst),
                      align: pw.TextAlign.right, isBold: true),
                if (!isInterState)
                  _tableCell(_formatCurrency(totSgst),
                      align: pw.TextAlign.right, isBold: true),
                if (isInterState)
                  _tableCell(_formatCurrency(totIgst),
                      align: pw.TextAlign.right, isBold: true),
                _tableCell(_formatCurrency(totGst),
                    align: pw.TextAlign.right, isBold: true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildQuoteTotalsWithGst(
    Quote quote, {
    String? sellerState,
    String? buyerState,
  }) {
    final subtotal = quote.items.fold<double>(
      0,
      (sum, item) =>
          sum + (item.qty * item.unitPrice * (1 - item.discountPct / 100)),
    );
    double totalCgst = 0, totalSgst = 0, totalIgst = 0;
    for (final item in quote.items) {
      if (item.taxPct <= 0) continue;
      final taxable = item.qty * item.unitPrice * (1 - item.discountPct / 100);
      final split = GstCalculator.calculate(
        sellerState: sellerState,
        buyerState: buyerState,
        taxableAmount: taxable,
        gstPct: item.taxPct,
      );
      totalCgst += split.cgst;
      totalSgst += split.sgst;
      totalIgst += split.igst;
    }
    final isInterState = GstCalculator.isInterState(sellerState, buyerState);

    return pw.Container(
      width: 280,
      child: pw.Column(
        children: [
          _totalsRow('Subtotal', subtotal),
          pw.Divider(color: PdfColors.grey300),
          if (!isInterState) ...[  
            _totalsRow('CGST', totalCgst, isSmall: true),
            _totalsRow('SGST', totalSgst, isSmall: true),
          ] else
            _totalsRow('IGST', totalIgst, isSmall: true),
          pw.Divider(color: PdfColors.grey400),
          _totalsRow('Total', quote.total, isBold: true, isLarge: true),
        ],
      ),
    );
  }

  pw.Widget _buildQuoteFooter(Quote quote) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'This quote is valid until ${quote.validUntil != null ? DateFormatter.format(quote.validUntil!) : "acceptance"}.',
          style: const pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Generated on ${DateFormatter.formatFull(DateTime.now())}',
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey500,
          ),
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<File> _savePdf(pw.Document pdf, String filename) async {
    // Route through PdfCacheManager — enforces FY-prefixed names,
    // 24-hour eviction, and the 3-file cap.
    final path = await PdfCacheManager.instance.tempPath(filename);
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
