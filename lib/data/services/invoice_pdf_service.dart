import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business.dart';
import '../models/invoice.dart';
import '../models/party.dart';
import '../models/quote.dart';
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

  Future<File> generateInvoicePdf(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final data = _invoiceToData(
      invoice,
      business: business,
      customerParty: customerParty,
      logo: logo,
      termsAndConditions: termsAndConditions,
    );
    return PdfLayoutEngine.instance.generate(
      data,
      DocumentTemplate.modern,
      'Invoice_${invoice.invoiceNo}.pdf',
    );
  }

  Future<File> generateQuotePdf(
    Quote quote, {
    Business? business,
    Party? customerParty,
    String? termsAndConditions,
  }) async {
    final logo = business != null ? await _loadLogo(business) : null;
    final data = _quoteToData(
      quote,
      business: business,
      customerParty: customerParty,
      logo: logo,
      termsAndConditions: termsAndConditions,
    );
    return PdfLayoutEngine.instance.generate(
      data,
      DocumentTemplate.modern,
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
      placeOfSupply: invoice.placeOfSupply,
      reverseCharge: invoice.reverseCharge,
      notes: invoice.notes,
      lineItems: invoice.items
          .map((item) => PdfLineItem(
                name: item.itemName,
                description: item.description,
                hsnCode: item.hsnCode,
                qty: item.qty,
                unit: item.unit,
                unitPrice: item.unitPrice,
                taxPct: item.taxPct,
                discountPct: item.discountPct,
                lineTotal: item.lineTotal,
              ))
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
    );
  }

  // ── Quote serialiser ───────────────────────────────────────────────────────

  PdfDocumentData _quoteToData(
    Quote quote, {
    Business? business,
    Party? customerParty,
    pw.MemoryImage? logo,
    String? termsAndConditions,
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
          .map((item) => PdfLineItem(
                name: item.itemName,
                description: item.description,
                hsnCode: item.hsnCode,
                qty: item.qty,
                unit: item.unit,
                unitPrice: item.unitPrice,
                taxPct: item.taxPct,
                discountPct: item.discountPct,
                lineTotal: item.lineTotal,
              ))
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
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  PdfPartyInfo _sellerInfo(Business? business, pw.MemoryImage? logo) {
    if (business == null) return const PdfPartyInfo(name: 'Your Business');
    final addressParts = [business.address, business.city, business.state]
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toList();
    return PdfPartyInfo(
      name: business.name,
      gstin: business.gstNo,
      address: addressParts.isEmpty ? null : addressParts.join(', '),
      phone: business.phone,
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
        .map((r) => PdfGstRow(
              codeLabel: r.codeLabel,
              taxableAmount: r.taxableAmount,
              gstPct: r.gstPct,
              cgst: r.cgst,
              sgst: r.sgst,
              igst: r.igst,
              total: r.total,
              isInterState: r.isInterState,
            ))
        .toList();
  }

  String _shortDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
    } catch (_) {}
    return null;
  }
}
