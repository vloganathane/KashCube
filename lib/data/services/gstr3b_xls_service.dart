// ---------------------------------------------------------------------------
// Gstr3bXlsService
// ---------------------------------------------------------------------------
// Generates a CA-ready GSTR-3B Offset Summary XLSX with three sheets:
//   Sheet 1 – Outward Supply (Table 3.1)
//   Sheet 2 – Inward + ITC (Tables 3.1d, 4)
//   Sheet 3 – Offset Result (cash-to-pay summary)
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'gstr3b_service.dart';

class Gstr3bXlsService {
  Gstr3bXlsService._();
  static final instance = Gstr3bXlsService._();

  static final _amtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  // ── Public API ────────────────────────────────────────────────────────────

  Future<File> generate(Gstr3bWorkbook wb) async {
    final excel = Excel.createExcel();
    // Remove the default blank sheet
    excel.delete('Sheet1');

    _buildOutwardSheet(excel, wb);
    _buildInwardItcSheet(excel, wb);
    _buildOffsetSheet(excel, wb);

    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final safeGstin = wb.businessGstin.replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    final safePeriod = wb.period.replaceAll(' ', '_');
    final file = File('${dir.path}/GSTR3B_${safePeriod}_$safeGstin.xlsx');
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── Sheet helpers ─────────────────────────────────────────────────────────

  static CellStyle _titleStyle() => CellStyle(
    bold: true,
    fontSize: 13,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#1B5E20'),
    horizontalAlign: HorizontalAlign.Center,
  );

  static CellStyle _subTitleStyle() => CellStyle(
    bold: true,
    fontSize: 10,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#1B5E20'),
    horizontalAlign: HorizontalAlign.Center,
  );

  static CellStyle _headerStyle() => CellStyle(
    bold: true,
    fontSize: 9,
    fontColorHex: ExcelColor.fromHexString('#1B5E20'),
    backgroundColorHex: ExcelColor.fromHexString('#E8F5E9'),
    horizontalAlign: HorizontalAlign.Center,
  );

  static CellStyle _labelStyle() => CellStyle(
    bold: false,
    fontSize: 9,
    horizontalAlign: HorizontalAlign.Left,
  );

  static CellStyle _totalStyle() => CellStyle(
    bold: true,
    fontSize: 9,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#2E7D32'),
    horizontalAlign: HorizontalAlign.Right,
  );

  static CellStyle _amtStyle() =>
      CellStyle(fontSize: 9, horizontalAlign: HorizontalAlign.Right);

  void _writeCell(
    Sheet sheet,
    int row,
    int col,
    dynamic value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value is double || value is int) {
      cell.value = DoubleCellValue(value is int ? value.toDouble() : value);
    } else {
      cell.value = TextCellValue(value.toString());
    }
    if (style != null) cell.cellStyle = style;
  }

  void _writeTitleBlock(
    Sheet sheet,
    String title,
    String businessName,
    String gstin,
    String period,
    int startRow,
  ) {
    // Row 0: title
    _writeCell(sheet, startRow, 0, title, style: _titleStyle());
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: startRow),
    );

    // Row 1: business + gstin
    _writeCell(sheet, startRow + 1, 0, businessName, style: _subTitleStyle());
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow + 1),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: startRow + 1),
    );
    _writeCell(
      sheet,
      startRow + 1,
      4,
      'GSTIN: $gstin',
      style: _subTitleStyle(),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: startRow + 1),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: startRow + 1),
    );

    // Row 2: period
    _writeCell(
      sheet,
      startRow + 2,
      0,
      'Period: $period',
      style: _subTitleStyle(),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow + 2),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: startRow + 2),
    );
  }

  // ── Sheet 1: Table 3.1 Outward ───────────────────────────────────────────

  void _buildOutwardSheet(Excel excel, Gstr3bWorkbook wb) {
    final sheet = excel['Table 3.1 – Outward Supply'];

    _writeTitleBlock(
      sheet,
      'GSTR-3B — Table 3.1: Outward Supply Liability',
      wb.businessName,
      wb.businessGstin,
      wb.period,
      0,
    );

    // Column headers (row 4)
    const headers = [
      'Category',
      'Taxable Value',
      'IGST',
      'CGST',
      'SGST',
      'CESS',
      'Total Tax',
    ];
    for (int c = 0; c < headers.length; c++) {
      _writeCell(sheet, 4, c, headers[c], style: _headerStyle());
    }

    // Data rows
    final rows = [
      ['(a) Outward Taxable (Regular)', wb.outwardRegular],
      ['(b) Zero Rated / Exports', wb.outwardZeroRated],
      ['(c) Nil / Exempted', wb.outwardNilExempted],
      ['(d) Inward (RCM)', wb.rcmLiability],
    ];

    int r = 5;
    for (final row in rows) {
      final label = row[0] as String;
      final amt = row[1] as Gstr3bTaxAmounts;
      _writeCell(sheet, r, 0, label, style: _labelStyle());
      _writeCell(sheet, r, 1, amt.taxableValue, style: _amtStyle());
      _writeCell(sheet, r, 2, amt.igst, style: _amtStyle());
      _writeCell(sheet, r, 3, amt.cgst, style: _amtStyle());
      _writeCell(sheet, r, 4, amt.sgst, style: _amtStyle());
      _writeCell(sheet, r, 5, amt.cess, style: _amtStyle());
      _writeCell(sheet, r, 6, amt.totalTax, style: _amtStyle());
      r++;
    }

    // Total row
    final tl = wb.totalLiability;
    _writeCell(sheet, r, 0, 'TOTAL LIABILITY', style: _totalStyle());
    _writeCell(sheet, r, 1, tl.taxableValue, style: _totalStyle());
    _writeCell(sheet, r, 2, tl.igst, style: _totalStyle());
    _writeCell(sheet, r, 3, tl.cgst, style: _totalStyle());
    _writeCell(sheet, r, 4, tl.sgst, style: _totalStyle());
    _writeCell(sheet, r, 5, tl.cess, style: _totalStyle());
    _writeCell(sheet, r, 6, tl.totalTax, style: _totalStyle());

    // Column widths
    sheet.setColumnWidth(0, 36);
    for (int c = 1; c <= 6; c++) {
      sheet.setColumnWidth(c, 16);
    }
  }

  // ── Sheet 2: Table 4 ITC ─────────────────────────────────────────────────

  void _buildInwardItcSheet(Excel excel, Gstr3bWorkbook wb) {
    final sheet = excel['Table 4 – ITC'];

    _writeTitleBlock(
      sheet,
      'GSTR-3B — Table 4: Input Tax Credit (ITC)',
      wb.businessName,
      wb.businessGstin,
      wb.period,
      0,
    );

    // Section A: ITC Available
    _writeCell(sheet, 4, 0, 'A. ITC AVAILABLE', style: _subTitleStyle());
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4),
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 4),
    );

    const headers = ['Category', 'IGST', 'CGST', 'SGST', 'CESS', 'Total'];
    for (int c = 0; c < headers.length; c++) {
      _writeCell(sheet, 5, c, headers[c], style: _headerStyle());
    }

    final itcRows = [
      ['(1) Eligible ITC (Import + B2B)', wb.itcEligible],
      ['(2) ITC Reversed (Rule 42 / 43)', wb.itcReversed],
      ['(3) ITC Blocked (Sec. 17(5))', wb.itcBlocked],
    ];

    int r = 6;
    for (final row in itcRows) {
      final label = row[0] as String;
      final amt = row[1] as Gstr3bTaxAmounts;
      _writeCell(sheet, r, 0, label, style: _labelStyle());
      _writeCell(sheet, r, 1, amt.igst, style: _amtStyle());
      _writeCell(sheet, r, 2, amt.cgst, style: _amtStyle());
      _writeCell(sheet, r, 3, amt.sgst, style: _amtStyle());
      _writeCell(sheet, r, 4, amt.cess, style: _amtStyle());
      _writeCell(sheet, r, 5, amt.totalTax, style: _amtStyle());
      r++;
    }

    final netItc = wb.netItc;
    _writeCell(
      sheet,
      r,
      0,
      'NET ITC (Eligible − Reversed)',
      style: _totalStyle(),
    );
    _writeCell(sheet, r, 1, netItc.igst, style: _totalStyle());
    _writeCell(sheet, r, 2, netItc.cgst, style: _totalStyle());
    _writeCell(sheet, r, 3, netItc.sgst, style: _totalStyle());
    _writeCell(sheet, r, 4, netItc.cess, style: _totalStyle());
    _writeCell(sheet, r, 5, netItc.totalTax, style: _totalStyle());

    sheet.setColumnWidth(0, 36);
    for (int c = 1; c <= 5; c++) {
      sheet.setColumnWidth(c, 16);
    }
  }

  // ── Sheet 3: Offset Result ────────────────────────────────────────────────

  void _buildOffsetSheet(Excel excel, Gstr3bWorkbook wb) {
    final sheet = excel['ITC Offset & Cash Payable'];

    _writeTitleBlock(
      sheet,
      'GSTR-3B — ITC Offset & Cash Ledger Summary',
      wb.businessName,
      wb.businessGstin,
      wb.period,
      0,
    );

    final result = wb.offsetData.compute();

    // Section: Paid by ITC
    _writeCell(
      sheet,
      4,
      0,
      'PAID BY ITC (Credit Utilisation)',
      style: _subTitleStyle(),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 4),
    );

    const colHeader = ['Head', 'IGST', 'CGST', 'SGST'];
    for (int c = 0; c < colHeader.length; c++) {
      _writeCell(sheet, 5, c, colHeader[c], style: _headerStyle());
    }

    final creditRows = [
      [
        'By Credit',
        result.igstByCredit,
        result.cgstByCredit,
        result.sgstByCredit,
      ],
    ];
    int r = 6;
    for (final row in creditRows) {
      _writeCell(sheet, r, 0, row[0], style: _labelStyle());
      _writeCell(sheet, r, 1, row[1], style: _amtStyle());
      _writeCell(sheet, r, 2, row[2], style: _amtStyle());
      _writeCell(sheet, r, 3, row[3], style: _amtStyle());
      r++;
    }

    r++; // blank row
    // Section: Cash Required
    _writeCell(
      sheet,
      r,
      0,
      'CASH LEDGER PAYMENT REQUIRED',
      style: _subTitleStyle(),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r),
    );
    r++;

    for (int c = 0; c < colHeader.length; c++) {
      _writeCell(sheet, r, c, colHeader[c], style: _headerStyle());
    }
    r++;

    final cashRows = [
      [
        'Cash Required',
        result.igstByCash,
        result.cgstByCash,
        result.sgstByCash,
      ],
    ];
    for (final row in cashRows) {
      _writeCell(sheet, r, 0, row[0], style: _labelStyle());
      _writeCell(sheet, r, 1, row[1], style: _amtStyle());
      _writeCell(sheet, r, 2, row[2], style: _amtStyle());
      _writeCell(sheet, r, 3, row[3], style: _amtStyle());
      r++;
    }

    // Total cash row (prominent)
    final totalCash = result.totalCash;
    r++;
    _writeCell(sheet, r, 0, 'TOTAL CASH TO PAY', style: _totalStyle());
    _writeCell(
      sheet,
      r,
      1,
      _amtFmt.format(totalCash),
      style: CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#B71C1C'),
        horizontalAlign: HorizontalAlign.Right,
      ),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r),
    );

    r += 2;
    // Credit carry-forward
    _writeCell(
      sheet,
      r,
      0,
      'CREDIT BALANCE CARRY FORWARD',
      style: _subTitleStyle(),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r),
    );
    r++;
    for (int c = 0; c < colHeader.length; c++) {
      _writeCell(sheet, r, c, colHeader[c], style: _headerStyle());
    }
    r++;
    _writeCell(sheet, r, 0, 'Carry Forward', style: _labelStyle());
    _writeCell(sheet, r, 1, result.igstCreditBalance, style: _amtStyle());
    _writeCell(sheet, r, 2, result.cgstCreditBalance, style: _amtStyle());
    _writeCell(sheet, r, 3, result.sgstCreditBalance, style: _amtStyle());

    sheet.setColumnWidth(0, 36);
    for (int c = 1; c <= 3; c++) {
      sheet.setColumnWidth(c, 18);
    }
  }
}
