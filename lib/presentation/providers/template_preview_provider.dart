import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/models/document_template_record.dart';
import '../../data/services/pdf_document_data.dart';
import '../../data/services/pdf_layout_engine.dart';

// ── Stable cache key ─────────────────────────────────────────────────────────

/// Encodes all rendering-relevant fields of [record] + [dpi] into a string
/// that can be used as a [FutureProvider.family] key.
///
/// Any change to accent colour, header style, logo toggle, decimal digits,
/// page size or dpi will produce a different key → a new provider instance
/// → a fresh render.
String templatePreviewKey(DocumentTemplateRecord record, int dpi) =>
    '${record.id}'
    '|${record.accentColorHex}'
    '|${record.headerStyleName}'
    '|${record.showLogo}'
    '|${record.amountDecimalDigits}'
    '|${record.pageSizeName}'
    '|${record.fontFamilyName}'
    '|${record.bodyFontSize}'
    '|${record.titleFontSize}'
    '|${record.pageMargin}'
    '|${record.sectionSpacing}'
    '|${record.itemColumnWidthPct}'
    '|${record.headerAlignmentName}'
    '|$dpi';

// ── Isolate entry-point ──────────────────────────────────────────────────────

/// Top-level function required by [compute].
///
/// Builds a sample invoice PDF and returns the raw bytes.
/// No platform channels involved → safe in a background isolate.
Future<Uint8List> _buildSamplePdfBytes(DocumentTemplate template) async {
  final data = _sampleDocumentData();
  // PdfLayoutEngine.instance creates a fresh singleton in the background
  // isolate — it has no shared state, so this is safe.
  return PdfLayoutEngine.instance.generateBytes(data, template);
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

/// Provides a rasterised PNG thumbnail ([Uint8List]) for the given
/// [templatePreviewKey] string.
///
/// Uses a two-step pipeline:
///   1. Background isolate: generate PDF bytes via [PdfLayoutEngine].
///   2. Main isolate: rasterise first page via [Printing.raster].
///
/// [ref.keepAlive()] ensures list-screen thumbnails are not re-rendered when
/// the user scrolls or rebuilds the list.
final templatePreviewProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, key) async {
      // Keep the result alive for the lifetime of the app session so scrolling
      // the template list doesn't re-trigger expensive PDF → raster pipelines.
      ref.keepAlive();

      final template = _templateFromKey(key);
      final dpi = double.parse(key.split('|')[13]);

      // ── Step 1: PDF bytes in a background isolate ──────────────────────────
      final pdfBytes = await compute(_buildSamplePdfBytes, template);

      // ── Step 2: Rasterise first page on the main isolate ─────────────────
      // Printing.raster uses platform channels → must run on main isolate.
      final rasters = Printing.raster(pdfBytes, pages: [0], dpi: dpi);
      final firstPage = await rasters.first;
      return firstPage.toPng();
    });

// ── Key codec ────────────────────────────────────────────────────────────────

DocumentTemplate _templateFromKey(String key) {
  final p = key.split('|');
  // p[0] = id, p[1] = accentColorHex (#RRGGBB), p[2] = headerStyleName,
  // p[3] = showLogo, p[4] = amountDecimalDigits, p[5] = pageSizeName,
  // p[6..12] = advanced layout settings, p[13] = dpi

  final accentHex = p[1].replaceFirst('#', '');
  final accentInt = int.tryParse(accentHex, radix: 16) ?? 0x1B5E20;
  final accentColor = PdfColor.fromInt(0xFF000000 | accentInt);

  final headerStyle = p[2] == 'banner'
      ? PdfHeaderStyle.banner
      : PdfHeaderStyle.minimal;

  final pageSize = _pageSizeFromName(p[5]);

  return DocumentTemplate(
    id: p[0],
    name: p[0], // name doesn't affect rendering
    accentColor: accentColor,
    headerStyle: headerStyle,
    showLogo: p[3] == 'true',
    amountDecimalDigits: int.tryParse(p[4]) ?? 0,
    pageSize: pageSize,
    fontFamily: PdfFontFamily.values.firstWhere(
      (f) => f.name == p[6],
      orElse: () => PdfFontFamily.helvetica,
    ),
    bodyFontSize: double.tryParse(p[7]) ?? 9,
    titleFontSize: double.tryParse(p[8]) ?? 22,
    pageMargin: double.tryParse(p[9]) ?? 32,
    sectionSpacing: double.tryParse(p[10]) ?? 20,
    itemColumnWidthPct: double.tryParse(p[11]) ?? 45,
    headerAlignment: p[12] == 'right'
        ? PdfHeaderAlignment.right
        : PdfHeaderAlignment.left,
  );
}

PageSize _pageSizeFromName(String name) {
  switch (name) {
    case 'a5':
      return PageSize.a5;
    case 'letter':
      return PageSize.letter;
    case 'thermal58':
      return PageSize.thermal58;
    case 'thermal80':
      return PageSize.thermal80;
    case 'a4':
    default:
      return PageSize.a4;
  }
}

// ── Sample document data ──────────────────────────────────────────────────────

/// Constructs a minimal but realistic-looking sample invoice for preview
/// rendering. No real DB data is read — everything is hardcoded.
PdfDocumentData _sampleDocumentData() {
  final now = DateTime(2026, 3, 4);
  final due = DateTime(2026, 3, 18);

  return PdfDocumentData(
    type: PdfDocumentType.invoice,
    docNumber: 'INV-0042',
    typeLabel: 'TAX INVOICE',
    statusLabel: 'PAID',
    statusColor: PdfColors.green700,
    issueDate: now,
    dueDate: due,
    seller: const PdfPartyInfo(
      name: 'Kash Cube Store',
      gstin: '27AADCK1234A1Z5',
      address: '12, MG Road, Pune – 411001',
      phone: '+91 98765 43210',
    ),
    buyer: const PdfPartyInfo(
      name: 'Sample Customer',
      address: '45, Nehru Nagar, Mumbai – 400001',
    ),
    placeOfSupply: 'Maharashtra',
    lineItems: const [
      PdfLineItem(
        name: 'Product A',
        qty: 2,
        unit: 'pcs',
        unitPrice: 1500,
        taxPct: 18,
        lineTotal: 3000,
      ),
      PdfLineItem(
        name: 'Service B',
        qty: 1,
        unit: 'hr',
        unitPrice: 2500,
        taxPct: 18,
        lineTotal: 2500,
      ),
      PdfLineItem(
        name: 'Part C',
        qty: 5,
        unit: 'nos',
        unitPrice: 400,
        taxPct: 5,
        lineTotal: 2000,
      ),
    ],
    totals: const PdfTotals(subtotal: 7500, grandTotal: 8750, paidAmount: 8750),
    footerNote: 'Thank you for your business!',
  );
}
