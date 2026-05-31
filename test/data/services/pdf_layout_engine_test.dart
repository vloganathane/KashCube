import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/models/document_template_record.dart';
import 'package:kash_cube/data/services/pdf_document_data.dart';
import 'package:kash_cube/data/services/pdf_layout_engine.dart';
import 'package:pdf/pdf.dart';

void main() {
  test('document template record persists advanced layout settings', () {
    final record = DocumentTemplateRecord(
      id: 7,
      name: 'Advanced',
      basedOn: 'modern',
      accentColorHex: '#1B5E20',
      headerStyleName: 'minimal',
      showLogo: true,
      amountDecimalDigits: 2,
      pageSizeName: 'a4',
      fontFamilyName: 'courier',
      bodyFontSize: 10,
      titleFontSize: 26,
      pageMargin: 24,
      sectionSpacing: 14,
      itemColumnWidthPct: 55,
      headerAlignmentName: 'right',
      builderConfigJson: PdfTemplateConfig(
        hiddenSections: {'gst'},
        rowDensity: 'compact',
        footerMessage: 'Please retain this invoice.',
      ).encode(),
      isActive: true,
      isPreset: false,
      createdAt: '2026-05-31T00:00:00.000',
    );

    final restored = DocumentTemplateRecord.fromMap({
      'id': record.id,
      ...record.toMap(),
    });

    expect(restored.fontFamilyName, 'courier');
    expect(restored.bodyFontSize, 10);
    expect(restored.titleFontSize, 26);
    expect(restored.pageMargin, 24);
    expect(restored.sectionSpacing, 14);
    expect(restored.itemColumnWidthPct, 55);
    expect(restored.headerAlignmentName, 'right');
    expect(restored.builderConfig.hiddenSections, contains('gst'));
    expect(restored.builderConfig.rowDensity, 'compact');
    expect(restored.builderConfig.footerMessage, 'Please retain this invoice.');
  });

  test('normalizes legacy logo positions', () {
    expect(
      PdfTemplateConfig.decode('{"logoPosition":"left"}').logoPosition,
      'besideLeft',
    );
    expect(
      PdfTemplateConfig.decode('{"logoPosition":"center"}').logoPosition,
      'aboveCenter',
    );
    expect(
      PdfTemplateConfig.decode('{"logoPosition":"right"}').logoPosition,
      'besideRight',
    );
  });

  test(
    'generates PDF bytes with advanced document template settings',
    () async {
      const template = DocumentTemplate(
        id: 'advanced-test',
        name: 'Advanced Test',
        accentColor: PdfColors.blue700,
        headerStyle: PdfHeaderStyle.banner,
        fontFamily: PdfFontFamily.times,
        bodyFontSize: 11,
        titleFontSize: 28,
        pageMargin: 20,
        sectionSpacing: 12,
        itemColumnWidthPct: 60,
        headerAlignment: PdfHeaderAlignment.right,
        config: PdfTemplateConfig(
          sectionOrder: ['header', 'items', 'parties', 'totals', 'footer'],
          columns: [
            PdfTemplateColumn(
              id: 'item',
              label: 'Service',
              widthPct: 65,
              alignment: PdfTextAlign.left,
            ),
            PdfTemplateColumn(
              id: 'qty',
              label: 'Hours',
              widthPct: 10,
              alignment: PdfTextAlign.right,
            ),
            PdfTemplateColumn(
              id: 'amount',
              label: 'Fee',
              widthPct: 25,
              alignment: PdfTextAlign.right,
            ),
          ],
          rowDensity: 'compact',
          totalsAlignment: 'left',
          showAmountInWords: true,
          paymentDisplay: 'text',
          paymentText: 'UPI: sample@upi',
          footerMessage: 'Custom footer message',
          signatureLabel: 'Approved by',
          titleStyle: 'boxed',
          dividerThickness: 4,
        ),
      );
      final data = PdfDocumentData(
        type: PdfDocumentType.invoice,
        docNumber: 'INV-TEST',
        typeLabel: 'TAX INVOICE',
        statusLabel: 'DUE',
        statusColor: PdfColors.red700,
        issueDate: DateTime(2026, 5, 31),
        seller: const PdfPartyInfo(name: 'Kash Cube Store'),
        buyer: const PdfPartyInfo(name: 'Sample Customer'),
        lineItems: const [
          PdfLineItem(
            name: 'A longer item description for width allocation',
            qty: 2,
            unitPrice: 100,
            lineTotal: 200,
          ),
        ],
        totals: const PdfTotals(subtotal: 200, grandTotal: 200),
        footerNote: 'Thank you for your business.',
      );

      final bytes = await PdfLayoutEngine.instance.generateBytes(
        data,
        template,
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
}
