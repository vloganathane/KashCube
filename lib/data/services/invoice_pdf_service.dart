import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../models/business.dart';
import '../models/invoice.dart';
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
  Future<File> generateInvoicePdf(Invoice invoice, {Business? business}) async {
    final pdf = pw.Document();
    final logo = business != null ? await _loadBusinessLogo(business) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildInvoiceHeader(invoice, business: business, logo: logo),
          pw.SizedBox(height: 24),
          _buildInvoiceDetails(invoice),
          pw.SizedBox(height: 24),
          _buildItemsTable(invoice.items),
          pw.SizedBox(height: 16),
          _buildTotalsWithGst(invoice),
          pw.SizedBox(height: 32),
          _buildFooter(invoice),
        ],
      ),
    );

    return _savePdf(pdf, 'Invoice_${invoice.invoiceNo}.pdf');
  }

  /// Generate PDF for a quote.
  Future<File> generateQuotePdf(Quote quote, {Business? business}) async {
    final pdf = pw.Document();
    final logo = business != null ? await _loadBusinessLogo(business) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildQuoteHeader(quote, business: business, logo: logo),
          pw.SizedBox(height: 24),
          _buildQuoteDetails(quote),
          pw.SizedBox(height: 24),
          _buildQuoteItemsTable(quote.items),
          pw.SizedBox(height: 16),
          _buildQuoteTotalsWithGst(quote),
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
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 28,
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

  pw.Widget _buildInvoiceDetails(Invoice invoice) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
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
          ],
        ),
        if (invoice.notes != null && invoice.notes!.isNotEmpty)
          pw.Container(
            width: 200,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NOTES',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  invoice.notes!,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _buildItemsTable(List<InvoiceItem> items) {
    // Check if we need to show tax and discount columns
    final hasTax = items.any((item) => item.taxPct > 0);
    final hasDiscount = items.any((item) => item.discountPct > 0);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('Item', isHeader: true),
            _tableCell('Qty', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Rate', isHeader: true, align: pw.TextAlign.right),
            if (hasTax) _tableCell('Tax %', isHeader: true, align: pw.TextAlign.center),
            if (hasDiscount) _tableCell('Disc %', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Amount', isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        // Items
        ...items.map((item) => pw.TableRow(
              children: [
                _tableCell(_buildItemName(item.itemName, item.description)),
                _tableCell(item.qty.toString(),
                    align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.unitPrice),
                    align: pw.TextAlign.right),
                if (hasTax) _tableCell(item.taxPct > 0 ? '${item.taxPct.toStringAsFixed(1)}%' : '—',
                    align: pw.TextAlign.center),
                if (hasDiscount) _tableCell(item.discountPct > 0 ? '${item.discountPct.toStringAsFixed(1)}%' : '—',
                    align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.lineTotal),
                    align: pw.TextAlign.right,
                    isBold: true),
              ],
            )),
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

  pw.Widget _buildTotalsWithGst(Invoice invoice) {
    final subtotal = invoice.items.fold<double>(
      0,
      (sum, item) => sum + (item.qty * item.unitPrice * (1 - item.discountPct / 100)),
    );
    final totalTax = invoice.total - subtotal;
    
    // For simplicity, split GST equally as CGST + SGST
    // In production, check business state to determine IGST vs CGST+SGST
    final cgst = totalTax / 2;
    final sgst = totalTax / 2;

    return pw.Container(
      width: 250,
      child: pw.Column(
        children: [
          _totalsRow('Subtotal', subtotal),
          pw.Divider(color: PdfColors.grey300),
          _totalsRow('CGST', cgst, isSmall: true),
          _totalsRow('SGST', sgst, isSmall: true),
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
                  'QUOTE',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
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

  pw.Widget _buildQuoteDetails(Quote quote) {
    return pw.Row(
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
          ],
        ),
        if (quote.notes != null && quote.notes!.isNotEmpty)
          pw.Container(
            width: 200,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NOTES',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  quote.notes!,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _buildQuoteItemsTable(List<QuoteItem> items) {
    // Check if we need to show tax and discount columns
    final hasTax = items.any((item) => item.taxPct > 0);
    final hasDiscount = items.any((item) => item.discountPct > 0);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('Item', isHeader: true),
            _tableCell('Qty', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Rate', isHeader: true, align: pw.TextAlign.right),
            if (hasTax) _tableCell('Tax %', isHeader: true, align: pw.TextAlign.center),
            if (hasDiscount) _tableCell('Disc %', isHeader: true, align: pw.TextAlign.center),
            _tableCell('Amount', isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        // Items
        ...items.map((item) => pw.TableRow(
              children: [
                _tableCell(_buildItemName(item.itemName, item.description)),
                _tableCell(item.qty.toString(),
                    align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.unitPrice),
                    align: pw.TextAlign.right),
                if (hasTax) _tableCell(item.taxPct > 0 ? '${item.taxPct.toStringAsFixed(1)}%' : '—',
                    align: pw.TextAlign.center),
                if (hasDiscount) _tableCell(item.discountPct > 0 ? '${item.discountPct.toStringAsFixed(1)}%' : '—',
                    align: pw.TextAlign.center),
                _tableCell(_formatCurrency(item.lineTotal),
                    align: pw.TextAlign.right,
                    isBold: true),
              ],
            )),
      ],
    );
  }

  pw.Widget _buildQuoteTotalsWithGst(Quote quote) {
    final subtotal = quote.items.fold<double>(
      0,
      (sum, item) => sum + (item.qty * item.unitPrice * (1 - item.discountPct / 100)),
    );
    final totalTax = quote.total - subtotal;
    
    // Split GST equally as CGST + SGST
    final cgst = totalTax / 2;
    final sgst = totalTax / 2;

    return pw.Container(
      width: 250,
      child: pw.Column(
        children: [
          _totalsRow('Subtotal', subtotal),
          pw.Divider(color: PdfColors.grey300),
          _totalsRow('CGST', cgst, isSmall: true),
          _totalsRow('SGST', sgst, isSmall: true),
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
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
