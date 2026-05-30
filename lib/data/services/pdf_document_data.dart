import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ── Template ──────────────────────────────────────────────────────────────────

/// Controls how the business / header block is rendered.
enum PdfHeaderStyle {
  /// Full-width coloured banner (current Delivery Challan style).
  banner,

  /// White background with a thin accent rule below the business block
  /// (current Invoice style).
  minimal,
}

/// Output paper / roll size for PDF generation.
enum PageSize {
  a4,
  a5,
  letter,

  /// 58 mm thermal receipt roll (common budget printers).
  thermal58,

  /// 80 mm thermal receipt roll (most common commercial printers).
  thermal80;

  /// The [PdfPageFormat] for this size.
  ///
  /// Thermal sizes use a 200 mm placeholder height; the layout engine
  /// uses MultiPage so content automatically flows across roll segments.
  PdfPageFormat get pageFormat {
    switch (this) {
      case PageSize.a4:
        return PdfPageFormat.a4;
      case PageSize.a5:
        return PdfPageFormat.a5;
      case PageSize.letter:
        return PdfPageFormat.letter;
      case PageSize.thermal58:
        return PdfPageFormat(
          58 * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
        );
      case PageSize.thermal80:
        return PdfPageFormat(
          80 * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
        );
    }
  }

  bool get isThermal =>
      this == PageSize.thermal58 || this == PageSize.thermal80;

  String get label {
    switch (this) {
      case PageSize.a4:
        return 'A4';
      case PageSize.a5:
        return 'A5';
      case PageSize.letter:
        return 'Letter';
      case PageSize.thermal58:
        return '58 mm';
      case PageSize.thermal80:
        return '80 mm';
    }
  }
}

/// Immutable style configuration for PDF rendering.
///
/// Phase 1: three built-in presets.
/// Phase 2 will add persistence + a user-facing picker in Settings.
class DocumentTemplate {
  const DocumentTemplate({
    required this.id,
    required this.name,
    required this.accentColor,
    required this.headerStyle,
    this.showLogo = true,
    this.amountDecimalDigits = 2,
    this.pageSize = PageSize.a4,
  });

  final String id;
  final String name;
  final PdfColor accentColor;
  final PdfHeaderStyle headerStyle;

  /// Whether to render the business logo in the header (if one is set).
  final bool showLogo;

  /// Decimal places used when formatting currency amounts.
  /// 0 = whole rupees (typical for invoices), 2 = paise (typical for DCs).
  final int amountDecimalDigits;

  /// Output paper / roll size.
  final PageSize pageSize;

  /// True when this template targets a 58 mm or 80 mm thermal roll.
  bool get isThermal => pageSize.isThermal;

  /// The [PdfPageFormat] for this template's [pageSize].
  PdfPageFormat get pageFormat => pageSize.pageFormat;

  // ── Built-in presets ────────────────────────────────────────────────────────

  /// Classic: full-width green banner — current Delivery Challan look.
  static const classic = DocumentTemplate(
    id: 'classic',
    name: 'Classic',
    accentColor: PdfColor.fromInt(0xFF1B5E20),
    headerStyle: PdfHeaderStyle.banner,
    amountDecimalDigits: 2,
  );

  /// Modern: white header with accent rule — current Invoice / Quote look.
  static const modern = DocumentTemplate(
    id: 'modern',
    name: 'Modern',
    accentColor: PdfColor.fromInt(0xFF1B5E20),
    headerStyle: PdfHeaderStyle.minimal,
    amountDecimalDigits: 0,
  );

  /// Plain: strictly black-and-white, no colour accents, no logo.
  static const plain = DocumentTemplate(
    id: 'plain',
    name: 'Plain',
    accentColor: PdfColors.black,
    headerStyle: PdfHeaderStyle.minimal,
    showLogo: false,
    amountDecimalDigits: 0,
  );

  /// Thermal Receipt: monochrome 80 mm roll, no logo, no colour.
  static const receipt = DocumentTemplate(
    id: 'receipt',
    name: 'Thermal Receipt',
    accentColor: PdfColors.black,
    headerStyle: PdfHeaderStyle.minimal,
    showLogo: false,
    amountDecimalDigits: 0,
    pageSize: PageSize.thermal80,
  );

  // ── Industry presets ────────────────────────────────────────────────────────

  /// Pharmacy / medical billing: teal accent, banner header, 2 decimal places.
  static const pharmacy = DocumentTemplate(
    id: 'pharmacy',
    name: 'Pharmacy',
    accentColor: PdfColor.fromInt(0xFF006064),
    headerStyle: PdfHeaderStyle.banner,
    amountDecimalDigits: 2,
  );

  /// Restaurant / café billing: warm brown accent, banner header.
  static const restaurant = DocumentTemplate(
    id: 'restaurant',
    name: 'Restaurant',
    accentColor: PdfColor.fromInt(0xFF5D4037),
    headerStyle: PdfHeaderStyle.banner,
    amountDecimalDigits: 0,
  );

  /// Professional services (CA, consultant, agency): blue accent, minimal header.
  static const service = DocumentTemplate(
    id: 'service',
    name: 'Service',
    accentColor: PdfColor.fromInt(0xFF1565C0),
    headerStyle: PdfHeaderStyle.minimal,
    amountDecimalDigits: 0,
  );

  /// Freelancer / independent contractor: slate accent, no logo, minimal header.
  static const freelancer = DocumentTemplate(
    id: 'freelancer',
    name: 'Freelancer',
    accentColor: PdfColor.fromInt(0xFF37474F),
    headerStyle: PdfHeaderStyle.minimal,
    showLogo: false,
    amountDecimalDigits: 2,
  );

  /// Generic (all industries): same layout as Modern with explicit naming.
  static const generic = DocumentTemplate(
    id: 'generic',
    name: 'Generic',
    accentColor: PdfColor.fromInt(0xFF1B5E20),
    headerStyle: PdfHeaderStyle.minimal,
    amountDecimalDigits: 0,
  );

  static const List<DocumentTemplate> presets = [
    classic, modern, plain, receipt,
    pharmacy, restaurant, service, freelancer, generic,
  ];

  static DocumentTemplate fromId(String id) =>
      presets.firstWhere((t) => t.id == id, orElse: () => modern);

  // ── Active template singleton (written by Riverpod notifier on startup/change)
  static DocumentTemplate _active = modern;
  static DocumentTemplate get active => _active;
  static void setActive(DocumentTemplate t) => _active = t;
}

// ── Document type ─────────────────────────────────────────────────────────────

enum PdfDocumentType { invoice, quote, deliveryChallan, booking }

// ── Party info ────────────────────────────────────────────────────────────────

/// Represents one party (seller or buyer) in a PDF document.
class PdfPartyInfo {
  const PdfPartyInfo({
    required this.name,
    this.gstin,
    this.address,
    this.phone,
    this.phones,
    this.email,
    this.state,
    this.logoImage,
  });

  final String name;
  final String? gstin;
  final String? address;
  final String? phone;
  final List<String>? phones;
  final String? email;
  final String? state;

  /// Pre-loaded logo bytes — set only on the seller; null on buyer.
  final pw.MemoryImage? logoImage;
}

// ── Line items ────────────────────────────────────────────────────────────────

class PdfLineItem {
  const PdfLineItem({
    required this.name,
    this.description,
    this.hsnCode,
    required this.qty,
    this.unit,
    required this.unitPrice,
    this.taxPct = 0,
    this.discountPct = 0,
    required this.lineTotal,
  });

  final String name;
  final String? description;
  final String? hsnCode;
  final double qty;
  final String? unit;
  final double unitPrice;
  final double taxPct;
  final double discountPct;
  final double lineTotal;
}

// ── GST row ───────────────────────────────────────────────────────────────────

/// One row in the GST summary table.
class PdfGstRow {
  const PdfGstRow({
    required this.codeLabel,
    required this.taxableAmount,
    required this.gstPct,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.isInterState,
  });

  final String codeLabel;
  final double taxableAmount;
  final double gstPct;
  final double cgst;
  final double sgst;
  final double igst;
  final double total;
  final bool isInterState;
}

// ── Totals ────────────────────────────────────────────────────────────────────

class PdfTotals {
  const PdfTotals({
    required this.subtotal,
    this.gstRows = const [],
    this.isInterState = false,
    this.freight = 0,
    this.insurance = 0,
    this.packing = 0,
    required this.grandTotal,
    this.paidAmount = 0,
  });

  final double subtotal;
  final List<PdfGstRow> gstRows;
  final bool isInterState;
  final double freight;
  final double insurance;
  final double packing;
  final double grandTotal;
  final double paidAmount;

  double get balanceDue => grandTotal - paidAmount;
  bool get hasGst => gstRows.isNotEmpty;
  bool get hasExtras => freight > 0 || insurance > 0 || packing > 0;
  bool get hasPayment => paidAmount > 0;
}

// ── Transport info (DC only) ──────────────────────────────────────────────────

class PdfTransportInfo {
  const PdfTransportInfo({
    this.transporterName,
    this.vehicleNo,
    this.transportMode,
    this.distanceKm,
    this.dispatchDate,
  });

  final String? transporterName;
  final String? vehicleNo;
  final String? transportMode;
  final int? distanceKm;
  final DateTime? dispatchDate;

  bool get isEmpty =>
      (transporterName == null || transporterName!.isEmpty) &&
      (vehicleNo == null || vehicleNo!.isEmpty) &&
      distanceKm == null;
}

// ── Document data ─────────────────────────────────────────────────────────────

/// Unified, document-type-agnostic data carrier for all PDF documents.
///
/// Both [InvoicePdfService] and [DeliveryChallanPdfService] serialise their
/// domain models into this class and hand it to [PdfLayoutEngine].
class PdfDocumentData {
  const PdfDocumentData({
    required this.type,
    required this.docNumber,
    required this.typeLabel,
    this.subTypeLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.issueDate,
    this.dueDate,
    this.validUntil,
    required this.seller,
    required this.buyer,
    this.shipTo,
    this.placeOfSupply,
    this.reverseCharge = false,
    this.notes,
    required this.lineItems,
    required this.totals,
    this.transport,
    this.purpose,
    this.ewbNo,
    this.termsAndConditions,
    required this.footerNote,
    this.upiQrBytes,
    this.showFreeWatermark = false,
  });

  final PdfDocumentType type;

  /// Human-readable document number (invoice no, quote no, challan no).
  final String docNumber;

  /// Heading shown on the document, e.g. 'TAX INVOICE', 'QUOTATION',
  /// 'DELIVERY CHALLAN'.
  final String typeLabel;

  /// Optional sub-heading, e.g. 'For Tax Invoice' on a quote.
  final String? subTypeLabel;

  final String statusLabel;
  final PdfColor statusColor;

  final DateTime issueDate;
  final DateTime? dueDate;     // invoice only
  final DateTime? validUntil;  // quote only

  final PdfPartyInfo seller;
  final PdfPartyInfo buyer;

  /// Delivery / ship-to address (invoice + DC only). When non-null the layout
  /// engine renders a SHIP TO block beside the BILL TO block.
  final PdfPartyInfo? shipTo;

  final String? placeOfSupply;
  final bool reverseCharge;
  final String? notes;

  final List<PdfLineItem> lineItems;
  final PdfTotals totals;

  // ── DC-specific ─────────────────────────────────────────────────────────────

  /// Transport / e-way details; null for Invoice and Quote.
  final PdfTransportInfo? transport;

  /// Challan purpose label, e.g. 'Supply of Goods'.
  final String? purpose;

  /// E-way Bill number.
  final String? ewbNo;

  // ── Footer ───────────────────────────────────────────────────────────────────

  final String? termsAndConditions;

  /// Primary footer sentence, e.g. 'Thank you for your business!' for invoices,
  /// validity sentence for quotes, empty for DC (which uses a declaration block).
  final String footerNote;

  /// Pre-rendered QR code image bytes (PNG) for UPI payment on invoices.
  /// Null when not applicable (DC, Booking), when the business has no UPI ID,
  /// or when the active tier is Free.
  final Uint8List? upiQrBytes;

  /// When true, a "Created with KashCube Free" watermark banner is rendered
  /// at the bottom of the document. Set to true for Free-tier users.
  final bool showFreeWatermark;
}
