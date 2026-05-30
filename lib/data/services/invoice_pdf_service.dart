import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/business.dart';
import '../models/invoice.dart';
import '../models/party.dart';
import '../models/quote.dart';
import 'app_logger.dart';
import 'gst_calculator.dart';
import 'pdf_document_data.dart';
import 'pdf_layout_engine.dart';

/// Thin adapter that serialises [Invoice] / [Quote] domain objects into
/// [PdfDocumentData] and delegates all rendering to [PdfLayoutEngine].
///
/// Public API is unchanged — all callers continue to work without modification.
/// 100% local — no network calls.
class InvoicePdfService {
  InvoicePdfService._();
  static final instance = InvoicePdfService._();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<XFile> generateInvoicePdf(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
    bool showFreeWatermark = false,
    bool showUpiQr = false,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final upiQrBytes =
        (showUpiQr && business != null && (business.upiId?.isNotEmpty ?? false))
        ? await _buildUpiQrBytes(business, invoice.total, invoice.invoiceNo)
        : null;
    final data = _invoiceToData(
      invoice,
      business: business,
      customerParty: customerParty,
      logo: logo,
      termsAndConditions: termsAndConditions,
      showFreeWatermark: showFreeWatermark,
      upiQrBytes: upiQrBytes,
    );
    return PdfLayoutEngine.instance.generateXFile(
      data,
      DocumentTemplate.active,
      'Invoice_${invoice.invoiceNo}.pdf',
    );
  }

  Future<XFile> generateQuotePdf(
    Quote quote, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
    bool showFreeWatermark = false,
    bool showUpiQr = false,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final upiQrBytes =
        (showUpiQr && business != null && (business.upiId?.isNotEmpty ?? false))
        ? await _buildUpiQrBytes(business, quote.total, quote.quoteNo)
        : null;
    final data = _quoteToData(
      quote,
      business: business,
      customerParty: customerParty,
      logo: logo,
      termsAndConditions: termsAndConditions,
      showFreeWatermark: showFreeWatermark,
      upiQrBytes: upiQrBytes,
    );
    return PdfLayoutEngine.instance.generateXFile(
      data,
      DocumentTemplate.active,
      'Quote_${quote.quoteNo}.pdf',
    );
  }

  // ── Invoice serialiser ─────────────────────────────────────────────────────

  PdfDocumentData _invoiceToData(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
    pw.MemoryImage? logo,
    String? termsAndConditions,
    bool showFreeWatermark = false,
    Uint8List? upiQrBytes,
  }) {
    final sellerState = business?.state;
    final buyerState = customerParty?.state;

    final gstRows = _buildGstRows(
      invoice.items.toSplitInputs(),
      sellerState: sellerState,
      buyerState: buyerState,
    );
    final isInterState = gstRows.isNotEmpty
        ? gstRows.first.isInterState
        : GstCalculator.isInterState(sellerState, buyerState);

    return PdfDocumentData(
      type: PdfDocumentType.invoice,
      docNumber: invoice.invoiceNo,
      typeLabel: invoice.invoiceType.label.toUpperCase(),
      subTypeLabel:
          (invoice.invoiceType == InvoiceType.creditNote ||
                  invoice.invoiceType == InvoiceType.debitNote) &&
              invoice.originalInvoiceNo != null
          ? 'Against: ${invoice.originalInvoiceNo}'
          : null,
      statusLabel: invoice.status.label,
      statusColor: _invoiceStatusColor(invoice.status),
      issueDate: invoice.issueDate,
      dueDate: invoice.dueDate,
      seller: _sellerInfo(business, logo),
      buyer: PdfPartyInfo(
        name: invoice.customerName,
        gstin: invoice.customerGstin ?? customerParty?.gstin,
        address: customerParty?.formattedAddress,
        phone: customerParty?.phoneNumber,
        email: customerParty?.email,
        state: buyerState,
      ),
      shipTo: _buildShipTo(invoice),
      placeOfSupply: invoice.placeOfSupply,
      reverseCharge: invoice.reverseCharge,
      notes: invoice.notes,
      lineItems: invoice.items
          .map(
            (item) => PdfLineItem(
              name: item.itemName,
              description: item.description,
              hsnCode: item.hsnCode,
              qty: item.qty,
              unit: item.unit,
              unitPrice: item.unitPrice,
              taxPct: item.taxPct,
              discountPct: item.discountPct,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      totals: PdfTotals(
        subtotal: invoice.subtotal,
        gstRows: gstRows,
        isInterState: isInterState,
        freight: invoice.freightAmt,
        insurance: invoice.insuranceAmt,
        packing: invoice.packingAmt,
        grandTotal: invoice.total,
        paidAmount: invoice.paidAmount,
      ),
      termsAndConditions: termsAndConditions,
      footerNote: 'Thank you for your business!',
      upiQrBytes: upiQrBytes,
      showFreeWatermark: showFreeWatermark,
    );
  }

  // ── Delivery address helper ──────────────────────────────────────────────

  PdfPartyInfo? _buildShipTo(Invoice invoice) {
    final parts = [
      if (invoice.deliveryAddress != null &&
          invoice.deliveryAddress!.isNotEmpty)
        invoice.deliveryAddress!,
      if (invoice.deliveryCity != null && invoice.deliveryCity!.isNotEmpty)
        invoice.deliveryCity!,
      if (invoice.deliveryState != null && invoice.deliveryState!.isNotEmpty)
        invoice.deliveryState!,
      if (invoice.deliveryPincode != null &&
          invoice.deliveryPincode!.isNotEmpty)
        invoice.deliveryPincode!,
    ];
    if (parts.isEmpty) return null;
    return PdfPartyInfo(
      name: invoice.customerName,
      gstin: invoice.deliveryGstin,
      address: parts.join(', '),
      state: invoice.deliveryState,
    );
  }

  // ── Quote serialiser ───────────────────────────────────────────────────────

  PdfDocumentData _quoteToData(
    Quote quote, {
    Business? business,
    Party? customerParty,
    pw.MemoryImage? logo,
    String? termsAndConditions,
    bool showFreeWatermark = false,
    Uint8List? upiQrBytes,
  }) {
    final sellerState = business?.state;
    final buyerState = customerParty?.state;

    final gstRows = _buildGstRows(
      quote.items.toSplitInputs(),
      sellerState: sellerState,
      buyerState: buyerState,
    );
    final isInterState = gstRows.isNotEmpty
        ? gstRows.first.isInterState
        : GstCalculator.isInterState(sellerState, buyerState);

    // Subtotal = sum of (qty × unitPrice × (1 − discountPct/100)) per item.
    final itemSubtotal = quote.items.fold<double>(
      0,
      (s, item) =>
          s + (item.qty * item.unitPrice * (1 - item.discountPct / 100)),
    );

    final validNote = quote.validUntil != null
        ? 'This quote is valid until ${_shortDate(quote.validUntil!)}.'
        : 'This quote is valid until acceptance.';

    return PdfDocumentData(
      type: PdfDocumentType.quote,
      docNumber: quote.quoteNo,
      typeLabel: 'QUOTATION',
      subTypeLabel: 'For ${quote.invoiceType.label}',
      statusLabel: quote.status.label,
      statusColor: _quoteStatusColor(quote.status),
      issueDate: quote.createdAt,
      validUntil: quote.validUntil,
      seller: _sellerInfo(business, logo),
      buyer: PdfPartyInfo(
        name: quote.customerName,
        gstin: quote.customerGstin ?? customerParty?.gstin,
        address: customerParty?.formattedAddress,
        phone: customerParty?.phoneNumber,
        email: customerParty?.email,
        state: buyerState,
      ),
      placeOfSupply: quote.placeOfSupply,
      reverseCharge: quote.reverseCharge,
      notes: quote.notes,
      lineItems: quote.items
          .map(
            (item) => PdfLineItem(
              name: item.itemName,
              description: item.description,
              hsnCode: item.hsnCode,
              qty: item.qty,
              unit: item.unit,
              unitPrice: item.unitPrice,
              taxPct: item.taxPct,
              discountPct: item.discountPct,
              lineTotal: item.lineTotal,
            ),
          )
          .toList(),
      totals: PdfTotals(
        subtotal: itemSubtotal,
        gstRows: gstRows,
        isInterState: isInterState,
        freight: quote.freightAmt,
        insurance: quote.insuranceAmt,
        packing: quote.packingAmt,
        grandTotal: quote.total,
      ),
      termsAndConditions: termsAndConditions,
      footerNote: validNote,
      upiQrBytes: upiQrBytes,
      showFreeWatermark: showFreeWatermark,
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  PdfPartyInfo _sellerInfo(Business? business, pw.MemoryImage? logo) {
    if (business == null) return const PdfPartyInfo(name: 'Your Business');
    final addressParts = [
      business.address,
      business.city,
      business.state,
    ].where((e) => e != null && e.isNotEmpty).cast<String>().toList();
    return PdfPartyInfo(
      name: business.name,
      gstin: business.gstNo,
      address: addressParts.isEmpty ? null : addressParts.join(', '),
      phone: business.phone,
      phones: business.phones,
      email: business.email,
      state: business.state,
      logoImage: logo,
    );
  }

  List<PdfGstRow> _buildGstRows(
    List<GstSplitInput> splitInputs, {
    String? sellerState,
    String? buyerState,
  }) {
    return GstCalculator.summarise(
          sellerState: sellerState,
          buyerState: buyerState,
          items: splitInputs,
        )
        .map(
          (r) => PdfGstRow(
            codeLabel: r.codeLabel,
            taxableAmount: r.taxableAmount,
            gstPct: r.gstPct,
            cgst: r.cgst,
            sgst: r.sgst,
            igst: r.igst,
            total: r.total,
            isInterState: r.isInterState,
          ),
        )
        .toList();
  }

  String _shortDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── Status colours ─────────────────────────────────────────────────────────

  PdfColor _invoiceStatusColor(InvoiceStatus status) {
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
      case InvoiceStatus.cancelled:
        return PdfColors.grey400;
      case InvoiceStatus.pendingNumber:
        return PdfColors.grey600;
    }
  }

  PdfColor _quoteStatusColor(QuoteStatus status) {
    switch (status) {
      case QuoteStatus.accepted:
        return PdfColors.green700;
      case QuoteStatus.sent:
        return PdfColors.blue700;
      case QuoteStatus.rejected:
        return PdfColors.red700;
      case QuoteStatus.draft:
        return PdfColors.grey600;
      case QuoteStatus.pendingNumber:
        return PdfColors.grey600;
    }
  }

  // ── Logo loader ────────────────────────────────────────────────────────────

  Future<pw.MemoryImage?> _loadLogo(Business business) async {
    if (business.logoPath == null || business.logoPath!.isEmpty) return null;
    try {
      final file = File(business.logoPath!);
      if (await file.exists()) {
        return pw.MemoryImage(await file.readAsBytes());
      }
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to load business logo',
        category: 'invoice_pdf',
        error: e,
      );
    }
    return null;
  }

  // ── UPI QR helpers ──────────────────────────────────────────────────

  /// Builds a UPI deep-link URI for the given [business], invoice [amount], and
  /// transaction [ref] label.
  static String _buildUpiUri(Business business, double amount, String ref) {
    final pa = Uri.encodeComponent(business.upiId!);
    final pn = Uri.encodeComponent(business.name);
    final am = amount.toStringAsFixed(2);
    final tn = Uri.encodeComponent('Payment for $ref');
    return 'upi://pay?pa=$pa&pn=$pn&am=$am&tn=$tn&cu=INR';
  }

  /// Generates a 200×200 QR code from [upiUri] and returns PNG bytes.
  /// Returns null on any failure (no UPI ID, encoding error, etc.).
  static Future<Uint8List?> _buildUpiQrBytes(
    Business business,
    double amount,
    String ref,
  ) async {
    try {
      final upiUri = _buildUpiUri(business, amount, ref);
      final painter = QrPainter(
        data: upiUri,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
        ),
      );
      final image = await painter.toImage(200);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to generate UPI QR code',
        category: 'invoice_pdf',
        error: e,
      );
      return null;
    }
  }
}
