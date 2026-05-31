import 'package:pdf/pdf.dart';

import '../../data/services/pdf_document_data.dart';

/// Data-transfer object for a row in the [document_templates] SQLite table.
///
/// Convert to a [DocumentTemplate] (used by the PDF engine) with
/// [toDocumentTemplate].
class DocumentTemplateRecord {
  const DocumentTemplateRecord({
    required this.id,
    required this.name,
    required this.basedOn,
    required this.accentColorHex,
    required this.headerStyleName,
    required this.showLogo,
    required this.amountDecimalDigits,
    required this.pageSizeName,
    this.fontFamilyName = 'helvetica',
    this.bodyFontSize = 9,
    this.titleFontSize = 22,
    this.pageMargin = 32,
    this.sectionSpacing = 20,
    this.itemColumnWidthPct = 45,
    this.headerAlignmentName = 'left',
    required this.isActive,
    required this.isPreset,
    required this.createdAt,
  });

  final int id;

  /// User-visible template name, e.g. 'Modern' or 'My Custom Template'.
  final String name;

  /// Preset basis: 'classic' | 'modern' | 'plain' | 'receipt'.
  final String basedOn;

  /// Hex colour string for the accent, e.g. '#1B5E20'.
  final String accentColorHex;

  /// 'banner' or 'minimal'.
  final String headerStyleName;

  final bool showLogo;
  final int amountDecimalDigits;

  /// 'a4' | 'a5' | 'letter' | 'thermal58' | 'thermal80'.
  final String pageSizeName;
  final String fontFamilyName;
  final double bodyFontSize;
  final double titleFontSize;
  final double pageMargin;
  final double sectionSpacing;
  final double itemColumnWidthPct;
  final String headerAlignmentName;

  final bool isActive;
  final bool isPreset;
  final String createdAt;

  // ─── Derived properties ────────────────────────────────────────────────────

  PdfColor get accentColor {
    final hex = accentColorHex.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0x1B5E20;
    return PdfColor.fromInt(0xFF000000 | value);
  }

  PdfHeaderStyle get headerStyle => headerStyleName == 'banner'
      ? PdfHeaderStyle.banner
      : PdfHeaderStyle.minimal;

  PageSize get pageSize => PageSize.values.firstWhere(
    (p) => p.name == pageSizeName,
    orElse: () => PageSize.a4,
  );

  bool get isThermal => pageSize.isThermal;

  // ─── Conversions ───────────────────────────────────────────────────────────

  /// Build a [DocumentTemplate] suitable for passing to [PdfLayoutEngine].
  DocumentTemplate toDocumentTemplate() => DocumentTemplate(
    // Presets keep their well-known id so DocumentTemplate.fromId() works.
    // User-created templates use 'tpl_<db_id>'.
    id: isPreset ? basedOn : 'tpl_$id',
    name: name,
    accentColor: accentColor,
    headerStyle: headerStyle,
    showLogo: showLogo,
    amountDecimalDigits: amountDecimalDigits,
    pageSize: pageSize,
    fontFamily: PdfFontFamily.values.firstWhere(
      (f) => f.name == fontFamilyName,
      orElse: () => PdfFontFamily.helvetica,
    ),
    bodyFontSize: bodyFontSize,
    titleFontSize: titleFontSize,
    pageMargin: pageMargin,
    sectionSpacing: sectionSpacing,
    itemColumnWidthPct: itemColumnWidthPct,
    headerAlignment: headerAlignmentName == 'right'
        ? PdfHeaderAlignment.right
        : PdfHeaderAlignment.left,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'based_on': basedOn,
    'accent_color_hex': accentColorHex,
    'header_style': headerStyleName,
    'show_logo': showLogo ? 1 : 0,
    'amount_decimal_digits': amountDecimalDigits,
    'page_size': pageSizeName,
    'font_family': fontFamilyName,
    'body_font_size': bodyFontSize,
    'title_font_size': titleFontSize,
    'page_margin': pageMargin,
    'section_spacing': sectionSpacing,
    'item_column_width_pct': itemColumnWidthPct,
    'header_alignment': headerAlignmentName,
    'is_active': isActive ? 1 : 0,
    'is_preset': isPreset ? 1 : 0,
    'created_at': createdAt,
  };

  factory DocumentTemplateRecord.fromMap(Map<String, Object?> m) =>
      DocumentTemplateRecord(
        id: m['id'] as int,
        name: m['name'] as String,
        basedOn: m['based_on'] as String,
        accentColorHex: m['accent_color_hex'] as String,
        headerStyleName: m['header_style'] as String,
        showLogo: (m['show_logo'] as int) == 1,
        amountDecimalDigits: m['amount_decimal_digits'] as int,
        pageSizeName: m['page_size'] as String,
        fontFamilyName: m['font_family'] as String? ?? 'helvetica',
        bodyFontSize: (m['body_font_size'] as num?)?.toDouble() ?? 9,
        titleFontSize: (m['title_font_size'] as num?)?.toDouble() ?? 22,
        pageMargin: (m['page_margin'] as num?)?.toDouble() ?? 32,
        sectionSpacing: (m['section_spacing'] as num?)?.toDouble() ?? 20,
        itemColumnWidthPct:
            (m['item_column_width_pct'] as num?)?.toDouble() ?? 45,
        headerAlignmentName: m['header_alignment'] as String? ?? 'left',
        isActive: (m['is_active'] as int) == 1,
        isPreset: (m['is_preset'] as int) == 1,
        createdAt: m['created_at'] as String,
      );

  DocumentTemplateRecord copyWith({
    int? id,
    String? name,
    String? basedOn,
    String? accentColorHex,
    String? headerStyleName,
    bool? showLogo,
    int? amountDecimalDigits,
    String? pageSizeName,
    String? fontFamilyName,
    double? bodyFontSize,
    double? titleFontSize,
    double? pageMargin,
    double? sectionSpacing,
    double? itemColumnWidthPct,
    String? headerAlignmentName,
    bool? isActive,
    bool? isPreset,
    String? createdAt,
  }) => DocumentTemplateRecord(
    id: id ?? this.id,
    name: name ?? this.name,
    basedOn: basedOn ?? this.basedOn,
    accentColorHex: accentColorHex ?? this.accentColorHex,
    headerStyleName: headerStyleName ?? this.headerStyleName,
    showLogo: showLogo ?? this.showLogo,
    amountDecimalDigits: amountDecimalDigits ?? this.amountDecimalDigits,
    pageSizeName: pageSizeName ?? this.pageSizeName,
    fontFamilyName: fontFamilyName ?? this.fontFamilyName,
    bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    titleFontSize: titleFontSize ?? this.titleFontSize,
    pageMargin: pageMargin ?? this.pageMargin,
    sectionSpacing: sectionSpacing ?? this.sectionSpacing,
    itemColumnWidthPct: itemColumnWidthPct ?? this.itemColumnWidthPct,
    headerAlignmentName: headerAlignmentName ?? this.headerAlignmentName,
    isActive: isActive ?? this.isActive,
    isPreset: isPreset ?? this.isPreset,
    createdAt: createdAt ?? this.createdAt,
  );
}
