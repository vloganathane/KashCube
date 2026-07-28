import 'dart:typed_data';
import 'dart:convert';

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

enum PdfFontFamily { helvetica, times, courier }

enum PdfHeaderAlignment { left, right }

enum PdfTextAlign { left, center, right }

class PdfTemplateColumn {
  const PdfTemplateColumn({
    required this.id,
    required this.label,
    required this.widthPct,
    required this.alignment,
    this.visible = true,
  });

  final String id;
  final String label;
  final double widthPct;
  final PdfTextAlign alignment;
  final bool visible;

  PdfTemplateColumn copyWith({
    String? label,
    double? widthPct,
    PdfTextAlign? alignment,
    bool? visible,
  }) => PdfTemplateColumn(
    id: id,
    label: label ?? this.label,
    widthPct: widthPct ?? this.widthPct,
    alignment: alignment ?? this.alignment,
    visible: visible ?? this.visible,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'widthPct': widthPct,
    'alignment': alignment.name,
    'visible': visible,
  };

  factory PdfTemplateColumn.fromJson(Map<String, Object?> json) =>
      PdfTemplateColumn(
        id: json['id'] as String,
        label: json['label'] as String,
        widthPct: (json['widthPct'] as num).toDouble(),
        alignment: PdfTextAlign.values.firstWhere(
          (value) => value.name == json['alignment'],
          orElse: () => PdfTextAlign.left,
        ),
        visible: json['visible'] as bool? ?? true,
      );
}

class PdfTemplateConfig {
  const PdfTemplateConfig({
    this.sectionOrder = defaultSectionOrder,
    this.hiddenSections = const {},
    this.columns = defaultColumns,
    this.businessFontSize = 16,
    this.headingFontSize = 10,
    this.totalsFontSize = 12,
    this.footerFontSize = 8,
    this.businessBold = true,
    this.headingBold = true,
    this.totalsBold = true,
    this.rowDensity = 'standard',
    this.logoPosition = 'besideLeft',
    this.logoSize = 48,
    this.titleStyle = 'plain',
    this.dividerThickness = 2,
    this.totalsAlignment = 'right',
    this.showSubtotal = true,
    this.showTaxBreakdown = true,
    this.showPaid = true,
    this.showBalance = true,
    this.showAmountInWords = false,
    this.balanceColorHex = '#C62828',
    this.paymentDisplay = 'qr',
    this.paymentText = '',
    this.footerMessage = '',
    this.showTerms = true,
    this.showSignature = true,
    this.signatureLabel = 'Authorised Signatory',
    this.signatureAlignment = 'right',
    this.showGeneratedDate = true,
    this.showDocumentNumber = true,
    this.showDates = true,
    this.showGstin = true,
    this.showAddresses = true,
    this.showNotes = true,
  });

  static const defaultSectionOrder = [
    'header',
    'parties',
    'items',
    'gst',
    'totals',
    'transport',
    'footer',
  ];

  static const defaultColumns = [
    PdfTemplateColumn(
      id: 'index',
      label: '#',
      widthPct: 4,
      alignment: PdfTextAlign.left,
    ),
    PdfTemplateColumn(
      id: 'item',
      label: 'Item / Description',
      widthPct: 35,
      alignment: PdfTextAlign.left,
    ),
    PdfTemplateColumn(
      id: 'hsn',
      label: 'HSN',
      widthPct: 8,
      alignment: PdfTextAlign.left,
    ),
    PdfTemplateColumn(
      id: 'qty',
      label: 'Qty',
      widthPct: 7,
      alignment: PdfTextAlign.right,
    ),
    PdfTemplateColumn(
      id: 'unit',
      label: 'Unit',
      widthPct: 6,
      alignment: PdfTextAlign.left,
    ),
    PdfTemplateColumn(
      id: 'rate',
      label: 'Rate',
      widthPct: 11,
      alignment: PdfTextAlign.right,
    ),
    PdfTemplateColumn(
      id: 'tax',
      label: 'Tax %',
      widthPct: 7,
      alignment: PdfTextAlign.right,
    ),
    PdfTemplateColumn(
      id: 'discount',
      label: 'Disc %',
      widthPct: 7,
      alignment: PdfTextAlign.right,
    ),
    PdfTemplateColumn(
      id: 'amount',
      label: 'Amount',
      widthPct: 15,
      alignment: PdfTextAlign.right,
    ),
  ];

  final List<String> sectionOrder;
  final Set<String> hiddenSections;
  final List<PdfTemplateColumn> columns;
  final double businessFontSize;
  final double headingFontSize;
  final double totalsFontSize;
  final double footerFontSize;
  final bool businessBold;
  final bool headingBold;
  final bool totalsBold;
  final String rowDensity;
  final String logoPosition;
  final double logoSize;
  final String titleStyle;
  final double dividerThickness;
  final String totalsAlignment;
  final bool showSubtotal;
  final bool showTaxBreakdown;
  final bool showPaid;
  final bool showBalance;
  final bool showAmountInWords;
  final String balanceColorHex;
  final String paymentDisplay;
  final String paymentText;
  final String footerMessage;
  final bool showTerms;
  final bool showSignature;
  final String signatureLabel;
  final String signatureAlignment;
  final bool showGeneratedDate;
  final bool showDocumentNumber;
  final bool showDates;
  final bool showGstin;
  final bool showAddresses;
  final bool showNotes;

  double get rowVerticalPadding {
    switch (rowDensity) {
      case 'compact':
        return 2;
      case 'spacious':
        return 7;
      default:
        return 4;
    }
  }

  bool shows(String section) => !hiddenSections.contains(section);

  PdfTemplateConfig copyWith({
    List<String>? sectionOrder,
    Set<String>? hiddenSections,
    List<PdfTemplateColumn>? columns,
    double? businessFontSize,
    double? headingFontSize,
    double? totalsFontSize,
    double? footerFontSize,
    bool? businessBold,
    bool? headingBold,
    bool? totalsBold,
    String? rowDensity,
    String? logoPosition,
    double? logoSize,
    String? titleStyle,
    double? dividerThickness,
    String? totalsAlignment,
    bool? showSubtotal,
    bool? showTaxBreakdown,
    bool? showPaid,
    bool? showBalance,
    bool? showAmountInWords,
    String? balanceColorHex,
    String? paymentDisplay,
    String? paymentText,
    String? footerMessage,
    bool? showTerms,
    bool? showSignature,
    String? signatureLabel,
    String? signatureAlignment,
    bool? showGeneratedDate,
    bool? showDocumentNumber,
    bool? showDates,
    bool? showGstin,
    bool? showAddresses,
    bool? showNotes,
  }) => PdfTemplateConfig(
    sectionOrder: sectionOrder ?? this.sectionOrder,
    hiddenSections: hiddenSections ?? this.hiddenSections,
    columns: columns ?? this.columns,
    businessFontSize: businessFontSize ?? this.businessFontSize,
    headingFontSize: headingFontSize ?? this.headingFontSize,
    totalsFontSize: totalsFontSize ?? this.totalsFontSize,
    footerFontSize: footerFontSize ?? this.footerFontSize,
    businessBold: businessBold ?? this.businessBold,
    headingBold: headingBold ?? this.headingBold,
    totalsBold: totalsBold ?? this.totalsBold,
    rowDensity: rowDensity ?? this.rowDensity,
    logoPosition: logoPosition ?? this.logoPosition,
    logoSize: logoSize ?? this.logoSize,
    titleStyle: titleStyle ?? this.titleStyle,
    dividerThickness: dividerThickness ?? this.dividerThickness,
    totalsAlignment: totalsAlignment ?? this.totalsAlignment,
    showSubtotal: showSubtotal ?? this.showSubtotal,
    showTaxBreakdown: showTaxBreakdown ?? this.showTaxBreakdown,
    showPaid: showPaid ?? this.showPaid,
    showBalance: showBalance ?? this.showBalance,
    showAmountInWords: showAmountInWords ?? this.showAmountInWords,
    balanceColorHex: balanceColorHex ?? this.balanceColorHex,
    paymentDisplay: paymentDisplay ?? this.paymentDisplay,
    paymentText: paymentText ?? this.paymentText,
    footerMessage: footerMessage ?? this.footerMessage,
    showTerms: showTerms ?? this.showTerms,
    showSignature: showSignature ?? this.showSignature,
    signatureLabel: signatureLabel ?? this.signatureLabel,
    signatureAlignment: signatureAlignment ?? this.signatureAlignment,
    showGeneratedDate: showGeneratedDate ?? this.showGeneratedDate,
    showDocumentNumber: showDocumentNumber ?? this.showDocumentNumber,
    showDates: showDates ?? this.showDates,
    showGstin: showGstin ?? this.showGstin,
    showAddresses: showAddresses ?? this.showAddresses,
    showNotes: showNotes ?? this.showNotes,
  );

  String encode() => jsonEncode({
    'sectionOrder': sectionOrder,
    'hiddenSections': hiddenSections.toList(),
    'columns': columns.map((column) => column.toJson()).toList(),
    'businessFontSize': businessFontSize,
    'headingFontSize': headingFontSize,
    'totalsFontSize': totalsFontSize,
    'footerFontSize': footerFontSize,
    'businessBold': businessBold,
    'headingBold': headingBold,
    'totalsBold': totalsBold,
    'rowDensity': rowDensity,
    'logoPosition': logoPosition,
    'logoSize': logoSize,
    'titleStyle': titleStyle,
    'dividerThickness': dividerThickness,
    'totalsAlignment': totalsAlignment,
    'showSubtotal': showSubtotal,
    'showTaxBreakdown': showTaxBreakdown,
    'showPaid': showPaid,
    'showBalance': showBalance,
    'showAmountInWords': showAmountInWords,
    'balanceColorHex': balanceColorHex,
    'paymentDisplay': paymentDisplay,
    'paymentText': paymentText,
    'footerMessage': footerMessage,
    'showTerms': showTerms,
    'showSignature': showSignature,
    'signatureLabel': signatureLabel,
    'signatureAlignment': signatureAlignment,
    'showGeneratedDate': showGeneratedDate,
    'showDocumentNumber': showDocumentNumber,
    'showDates': showDates,
    'showGstin': showGstin,
    'showAddresses': showAddresses,
    'showNotes': showNotes,
  });

  factory PdfTemplateConfig.decode(String raw) {
    if (raw.isEmpty || raw == '{}') return const PdfTemplateConfig();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PdfTemplateConfig(
        sectionOrder:
            (json['sectionOrder'] as List?)?.cast<String>() ??
            defaultSectionOrder,
        hiddenSections:
            (json['hiddenSections'] as List?)?.cast<String>().toSet() ??
            const {},
        columns:
            (json['columns'] as List?)
                ?.map(
                  (value) => PdfTemplateColumn.fromJson(
                    (value as Map).cast<String, Object?>(),
                  ),
                )
                .toList() ??
            defaultColumns,
        businessFontSize: (json['businessFontSize'] as num?)?.toDouble() ?? 16,
        headingFontSize: (json['headingFontSize'] as num?)?.toDouble() ?? 10,
        totalsFontSize: (json['totalsFontSize'] as num?)?.toDouble() ?? 12,
        footerFontSize: (json['footerFontSize'] as num?)?.toDouble() ?? 8,
        businessBold: json['businessBold'] as bool? ?? true,
        headingBold: json['headingBold'] as bool? ?? true,
        totalsBold: json['totalsBold'] as bool? ?? true,
        rowDensity: json['rowDensity'] as String? ?? 'standard',
        logoPosition: _normalizedLogoPosition(
          json['logoPosition'] as String? ?? 'besideLeft',
        ),
        logoSize: (json['logoSize'] as num?)?.toDouble() ?? 48,
        titleStyle: json['titleStyle'] as String? ?? 'plain',
        dividerThickness: (json['dividerThickness'] as num?)?.toDouble() ?? 2,
        totalsAlignment: json['totalsAlignment'] as String? ?? 'right',
        showSubtotal: json['showSubtotal'] as bool? ?? true,
        showTaxBreakdown: json['showTaxBreakdown'] as bool? ?? true,
        showPaid: json['showPaid'] as bool? ?? true,
        showBalance: json['showBalance'] as bool? ?? true,
        showAmountInWords: json['showAmountInWords'] as bool? ?? false,
        balanceColorHex: json['balanceColorHex'] as String? ?? '#C62828',
        paymentDisplay: json['paymentDisplay'] as String? ?? 'qr',
        paymentText: json['paymentText'] as String? ?? '',
        footerMessage: json['footerMessage'] as String? ?? '',
        showTerms: json['showTerms'] as bool? ?? true,
        showSignature: json['showSignature'] as bool? ?? true,
        signatureLabel:
            json['signatureLabel'] as String? ?? 'Authorised Signatory',
        signatureAlignment: json['signatureAlignment'] as String? ?? 'right',
        showGeneratedDate: json['showGeneratedDate'] as bool? ?? true,
        showDocumentNumber: json['showDocumentNumber'] as bool? ?? true,
        showDates: json['showDates'] as bool? ?? true,
        showGstin: json['showGstin'] as bool? ?? true,
        showAddresses: json['showAddresses'] as bool? ?? true,
        showNotes: json['showNotes'] as bool? ?? true,
      );
    } catch (_) {
      return const PdfTemplateConfig();
    }
  }
}

String _normalizedLogoPosition(String value) {
  return switch (value) {
    'left' => 'besideLeft',
    'center' => 'aboveCenter',
    'right' => 'besideRight',
    _ => value,
  };
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
        return PdfPageFormat(58 * PdfPageFormat.mm, 200 * PdfPageFormat.mm);
      case PageSize.thermal80:
        return PdfPageFormat(80 * PdfPageFormat.mm, 200 * PdfPageFormat.mm);
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
    this.fontFamily = PdfFontFamily.helvetica,
    this.bodyFontSize = 9,
    this.titleFontSize = 22,
    this.pageMargin = 32,
    this.sectionSpacing = 20,
    this.itemColumnWidthPct = 45,
    this.headerAlignment = PdfHeaderAlignment.left,
    this.config = const PdfTemplateConfig(),
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
  final PdfFontFamily fontFamily;
  final double bodyFontSize;
  final double titleFontSize;
  final double pageMargin;
  final double sectionSpacing;
  final double itemColumnWidthPct;
  final PdfHeaderAlignment headerAlignment;
  final PdfTemplateConfig config;

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

  /// Corporate Ledger: black-and-white invoice layout with dense tabular
  /// sections and a ledger-style feel.
  static const ledger = DocumentTemplate(
    id: 'ledger',
    name: 'Corporate Ledger',
    accentColor: PdfColors.black,
    headerStyle: PdfHeaderStyle.minimal,
    showLogo: true,
    amountDecimalDigits: 2,
    pageSize: PageSize.a4,
    fontFamily: PdfFontFamily.times,
    bodyFontSize: 8.5,
    titleFontSize: 26,
    pageMargin: 24,
    sectionSpacing: 12,
    itemColumnWidthPct: 42,
    headerAlignment: PdfHeaderAlignment.left,
    config: PdfTemplateConfig(
      sectionOrder: ['header', 'parties', 'items', 'gst', 'totals', 'footer'],
      columns: [
        PdfTemplateColumn(
          id: 'index',
          label: 'SL. No.',
          widthPct: 5,
          alignment: PdfTextAlign.center,
        ),
        PdfTemplateColumn(
          id: 'hsn',
          label: 'HSN Code',
          widthPct: 9,
          alignment: PdfTextAlign.left,
        ),
        PdfTemplateColumn(
          id: 'item',
          label: 'Product Name / Description',
          widthPct: 46,
          alignment: PdfTextAlign.left,
        ),
        PdfTemplateColumn(
          id: 'qty',
          label: 'Qty.',
          widthPct: 10,
          alignment: PdfTextAlign.center,
        ),
        PdfTemplateColumn(
          id: 'rate',
          label: 'Unit Price',
          widthPct: 15,
          alignment: PdfTextAlign.right,
        ),
        PdfTemplateColumn(
          id: 'amount',
          label: 'Total',
          widthPct: 15,
          alignment: PdfTextAlign.right,
        ),
      ],
      rowDensity: 'compact',
      logoPosition: 'aboveRight',
      logoSize: 52,
      titleStyle: 'boxed',
      dividerThickness: 2,
      totalsAlignment: 'right',
      showSubtotal: true,
      showTaxBreakdown: true,
      showPaid: true,
      showBalance: true,
      showAmountInWords: false,
      balanceColorHex: '#000000',
      paymentDisplay: 'text',
      paymentText: '',
      footerMessage: '',
      showTerms: true,
      showSignature: true,
      signatureLabel: 'For Authorised Signatory',
      signatureAlignment: 'right',
      showGeneratedDate: false,
      showDocumentNumber: true,
      showDates: true,
      showGstin: true,
      showAddresses: true,
      showNotes: true,
    ),
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
    classic,
    ledger,
    modern,
    plain,
    receipt,
    pharmacy,
    restaurant,
    service,
    freelancer,
    generic,
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
    this.logoIsWide = false,
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

  /// True when the logo is significantly wider than it is tall.
  final bool logoIsWide;
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

// ── Copy requirement ─────────────────────────────────────────────────────────

class PdfCopyInfo {
  const PdfCopyInfo({
    required this.heading,
    required this.copyCount,
    required this.copyLabels,
    required this.copyLines,
  });

  final String heading;
  final int copyCount;
  final List<String> copyLabels;
  final List<String> copyLines;

  String labelForCopy(int index) {
    if (index < 0 || index >= copyLabels.length) {
      throw RangeError.index(index, copyLabels);
    }
    return copyLabels[index];
  }

  String filenameSuffixForCopy(int index) {
    switch (index) {
      case 0:
        return 'Original';
      case 1:
        return 'Duplicate';
      case 2:
        return 'Triplicate';
      case 3:
        return 'Quadruplicate';
      default:
        return 'Copy ${index + 1}';
    }
  }
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
    this.copyInfo,
    this.copyLabel,
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
  final DateTime? dueDate; // invoice only
  final DateTime? validUntil; // quote only

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
  final PdfCopyInfo? copyInfo;
  final String? copyLabel;

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
