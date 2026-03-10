import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../../core/utils/csv_exporter.dart';
import '../../core/utils/gstin_validator.dart';
import '../../data/models/invoice.dart';
import '../../domain/repositories/business_repository.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../presentation/providers/business_provider.dart';
import '../../presentation/providers/invoice_provider.dart';

// ─── Row Models ─────────────────────────────────────────────────────────────

/// Table 4 — B2B taxable invoice row (one per invoice × GST rate bucket).
class Gstr1B2bRow {
  const Gstr1B2bRow({
    required this.receiverGstin,
    required this.receiverName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.invoiceValue,
    required this.placeOfSupply,
    required this.reverseCharge,
    required this.invoiceType,
    this.ecomGstin,
    required this.rate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  final String receiverGstin;
  final String receiverName;
  final String invoiceNo;
  final String invoiceDate;
  final double invoiceValue;
  final String placeOfSupply;
  final bool reverseCharge;
  final String invoiceType;
  final String? ecomGstin;
  final double rate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;

  List<dynamic> toCsvRow() => [
        receiverGstin,
        receiverName,
        invoiceNo,
        invoiceDate,
        _amount(invoiceValue),
        placeOfSupply,
        reverseCharge ? 'Y' : 'N',
        invoiceType,
        ecomGstin ?? '',
        _pct(rate),
        _amount(taxableValue),
        _amount(cgst),
        _amount(sgst),
        _amount(igst),
      ];

  static const List<String> csvHeaders = [
    'GSTIN of Receiver',
    'Receiver Name',
    'Invoice No',
    'Invoice Date',
    'Invoice Value',
    'Place of Supply (State Code)',
    'Reverse Charge (Y/N)',
    'Invoice Type',
    'E-Commerce GSTIN',
    'Rate (%)',
    'Taxable Value',
    'CGST Amount',
    'SGST Amount',
    'IGST Amount',
  ];
}

/// Table 5 — B2C Large inter-state invoice aggregate row (per state × rate).
class Gstr1B2cLargeRow {
  const Gstr1B2cLargeRow({
    required this.placeOfSupply,
    required this.rate,
    required this.taxableValue,
    required this.igst,
    this.ecomGstin,
  });

  final String placeOfSupply;
  final double rate;
  final double taxableValue;
  final double igst;
  final String? ecomGstin;

  List<dynamic> toCsvRow() => [
        placeOfSupply,
        _pct(rate),
        _amount(taxableValue),
        _amount(igst),
        ecomGstin ?? '',
      ];

  static const List<String> csvHeaders = [
    'Place of Supply (State Code)',
    'Rate (%)',
    'Taxable Value',
    'IGST Amount',
    'E-Commerce GSTIN',
  ];
}

/// Table 7 — B2C Small consolidated row (per OE/type × state × rate).
class Gstr1B2cSmallRow {
  const Gstr1B2cSmallRow({
    required this.type,
    required this.placeOfSupply,
    required this.rate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  final String type; // 'OE' = Others/Exempted
  final String placeOfSupply;
  final double rate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;

  List<dynamic> toCsvRow() => [
        type,
        placeOfSupply,
        _pct(rate),
        _amount(taxableValue),
        _amount(cgst),
        _amount(sgst),
        _amount(igst),
      ];

  static const List<String> csvHeaders = [
    'Type (OE = Others)',
    'Place of Supply (State Code)',
    'Rate (%)',
    'Taxable Value',
    'CGST',
    'SGST',
    'IGST',
  ];
}

/// Table 9 — Credit/Debit Note row (registered receivers).
class Gstr1CdnRow {
  const Gstr1CdnRow({
    required this.receiverGstin,
    required this.noteNo,
    required this.noteDate,
    required this.noteType,
    required this.placeOfSupply,
    required this.originalInvoiceNo,
    required this.originalInvoiceDate,
    required this.value,
    required this.rate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  final String receiverGstin;
  final String noteNo;
  final String noteDate;
  final String noteType; // 'C' = Credit Note, 'D' = Debit Note
  final String placeOfSupply;
  final String originalInvoiceNo;
  final String originalInvoiceDate;
  final double value;
  final double rate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;

  List<dynamic> toCsvRow() => [
        receiverGstin,
        noteNo,
        noteDate,
        noteType,
        placeOfSupply,
        originalInvoiceNo,
        originalInvoiceDate,
        _amount(value),
        _pct(rate),
        _amount(taxableValue),
        _amount(cgst),
        _amount(sgst),
        _amount(igst),
      ];

  static const List<String> csvHeaders = [
    'GSTIN of Receiver',
    'Note No',
    'Note Date',
    'Note Type (C/D)',
    'Place of Supply',
    'Original Invoice No',
    'Original Invoice Date',
    'Value',
    'Rate (%)',
    'Taxable Value',
    'CGST',
    'SGST',
    'IGST',
  ];
}

/// Table 12 — HSN/SAC summary row.
class Gstr1HsnRow {
  const Gstr1HsnRow({
    required this.hsnCode,
    required this.description,
    required this.uqc,
    required this.totalQty,
    required this.totalValue,
    required this.taxableValue,
    required this.igst,
    required this.cgst,
    required this.sgst,
    this.cess = 0,
  });

  final String hsnCode;
  final String description;
  final String uqc;
  final double totalQty;
  final double totalValue;
  final double taxableValue;
  final double igst;
  final double cgst;
  final double sgst;
  final double cess;

  List<dynamic> toCsvRow() => [
        hsnCode,
        description,
        uqc,
        totalQty.toStringAsFixed(3),
        _amount(totalValue),
        _amount(taxableValue),
        _amount(igst),
        _amount(cgst),
        _amount(sgst),
        _amount(cess),
      ];

  static const List<String> csvHeaders = [
    'HSN/SAC',
    'Description',
    'UQC (GSTN Unit Code)',
    'Total Quantity',
    'Total Value',
    'Taxable Value',
    'Integrated Tax Amount',
    'Central Tax Amount',
    'State/UT Tax Amount',
    'Cess Amount',
  ];
}

/// Table 13 — Document summary row.
class Gstr1DocSummaryRow {
  const Gstr1DocSummaryRow({
    required this.natureOfDocument,
    required this.seriesFrom,
    required this.seriesTo,
    required this.totalSubmitted,
    required this.cancelled,
  });

  final String natureOfDocument;
  final String seriesFrom;
  final String seriesTo;
  final int totalSubmitted;
  final int cancelled;

  List<dynamic> toCsvRow() => [
        natureOfDocument,
        seriesFrom,
        seriesTo,
        totalSubmitted,
        cancelled,
      ];

  static const List<String> csvHeaders = [
    'Nature of Document',
    'Series From',
    'Series To',
    'Total Submitted',
    'Cancelled',
  ];
}

// ─── Workbook Container ──────────────────────────────────────────────────────

/// Container for all GSTR-1 tables for a given business × period.
class Gstr1Workbook {
  const Gstr1Workbook({
    required this.businessGstin,
    required this.businessName,
    required this.from,
    required this.to,
    required this.returnPeriodLabel,
    required this.tableB2b,
    required this.tableB2cLarge,
    required this.tableB2cSmall,
    required this.tableCdn,
    required this.tableHsn,
    required this.tableDocSummary,
  });

  final String businessGstin;
  final String businessName;
  final DateTime from;
  final DateTime to;

  /// Format expected by GSTN: "MMYYYY" (e.g. "032026").
  final String returnPeriodLabel;

  /// T4 — B2B taxable invoices (one row per invoice × rate bucket).
  final List<Gstr1B2bRow> tableB2b;

  /// T5 — B2C Large inter-state invoices > ₹2,50,000.
  final List<Gstr1B2cLargeRow> tableB2cLarge;

  /// T7 — B2C Small consolidated rows.
  final List<Gstr1B2cSmallRow> tableB2cSmall;

  /// T9 — Credit/Debit notes to registered receivers.
  final List<Gstr1CdnRow> tableCdn;

  /// T12 — HSN/SAC summary.
  final List<Gstr1HsnRow> tableHsn;

  /// T13 — Document summary.
  final List<Gstr1DocSummaryRow> tableDocSummary;

  // ─── Headline numbers for PDF summary ─────────────────────────────────────

  int get totalB2bInvoices {
    final nos = <String>{};
    for (final r in tableB2b) {
      nos.add(r.invoiceNo);
    }
    return nos.length;
  }

  int get totalB2cLargeInvoices => tableB2cLarge.length;

  int get totalB2cSmallRows => tableB2cSmall.length;

  double get totalTaxableValue {
    double total = 0;
    for (final r in tableB2b) {
      total += r.taxableValue;
    }
    for (final r in tableB2cLarge) {
      total += r.taxableValue;
    }
    for (final r in tableB2cSmall) {
      total += r.taxableValue;
    }
    for (final r in tableCdn) {
      total += r.taxableValue;
    }
    return total;
  }

  double get totalCgst {
    double t = 0;
    for (final r in tableB2b) {
      t += r.cgst;
    }
    for (final r in tableB2cSmall) {
      t += r.cgst;
    }
    for (final r in tableCdn) {
      t += r.cgst;
    }
    return t;
  }

  double get totalSgst {
    double t = 0;
    for (final r in tableB2b) {
      t += r.sgst;
    }
    for (final r in tableB2cSmall) {
      t += r.sgst;
    }
    for (final r in tableCdn) {
      t += r.sgst;
    }
    return t;
  }

  double get totalIgst {
    double t = 0;
    for (final r in tableB2b) {
      t += r.igst;
    }
    for (final r in tableB2cLarge) {
      t += r.igst;
    }
    for (final r in tableB2cSmall) {
      t += r.igst;
    }
    for (final r in tableCdn) {
      t += r.igst;
    }
    return t;
  }

  double get totalTaxLiability => totalCgst + totalSgst + totalIgst;
}

// ─── UQC Map ─────────────────────────────────────────────────────────────────

/// App unit label → GSTN UQC code.
/// Mirrors `EwayBillService._uomMap` — kept local to avoid coupling.
const Map<String, String> _uqcMap = {
  'pcs': 'NOS',
  'nos': 'NOS',
  'number': 'NOS',
  'numbers': 'NOS',
  'unit': 'UNT',
  'units': 'UNT',
  'kg': 'KGS',
  'kgs': 'KGS',
  'kilogram': 'KGS',
  'kilograms': 'KGS',
  'gm': 'GMS',
  'gms': 'GMS',
  'gram': 'GMS',
  'grams': 'GMS',
  'g': 'GMS',
  'mt': 'MTR',
  'mtr': 'MTR',
  'metre': 'MTR',
  'metres': 'MTR',
  'meter': 'MTR',
  'meters': 'MTR',
  'm': 'MTR',
  'cm': 'CMS',
  'cms': 'CMS',
  'lt': 'LTR',
  'ltr': 'LTR',
  'litre': 'LTR',
  'litres': 'LTR',
  'liter': 'LTR',
  'liters': 'LTR',
  'ml': 'MLT',
  'mlt': 'MLT',
  'millilitre': 'MLT',
  'millilitres': 'MLT',
  'box': 'BOX',
  'boxes': 'BOX',
  'bag': 'BAG',
  'bags': 'BAG',
  'doz': 'DOZ',
  'dozen': 'DOZ',
  'dozens': 'DOZ',
  'set': 'SET',
  'sets': 'SET',
  'sqm': 'SQM',
  'sqmt': 'SQM',
  'sq.m': 'SQM',
  'sqft': 'SQF',
  'sq.ft': 'SQF',
  'roll': 'ROL',
  'rolls': 'ROL',
  'pair': 'PAR',
  'pairs': 'PAR',
  'bundle': 'BDL',
  'bundles': 'BDL',
  'ton': 'TON',
  'tons': 'TON',
  'tonne': 'TON',
  'tonnes': 'TON',
  'hour': 'HRS',
  'hours': 'HRS',
  'hr': 'HRS',
  'hrs': 'HRS',
  'day': 'DAY',
  'days': 'DAY',
  'month': 'MON',
  'months': 'MON',
  'year': 'YRS',
  'years': 'YRS',
  'service': 'OTH',
  'job': 'OTH',
};

String _unitToUqc(String unit) =>
    _uqcMap[unit.trim().toLowerCase()] ?? 'OTH';

// ─── Formatting helpers ──────────────────────────────────────────────────────

String _amount(double v) => v.toStringAsFixed(2);
String _pct(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

String _fmtDate(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  return '$d/$m/${dt.year}';
}

// ─── Service ─────────────────────────────────────────────────────────────────

/// Aggregates invoices for a business + period into a [Gstr1Workbook].
///
/// This is a pure data-layer service — no UI dependencies.
/// All GST splits are computed from per-item `taxPct` values.
class Gstr1Service {
  const Gstr1Service({
    required BusinessRepository businessRepo,
    required InvoiceRepository invoiceRepo,
  })  : _business = businessRepo,
        _invoice = invoiceRepo;

  final BusinessRepository _business;
  final InvoiceRepository _invoice;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Generates the full GSTR-1 workbook for [businessId] and the date range
  /// [[from], [to]] (both inclusive, date part only).
  Future<Gstr1Workbook> generateWorkbook({
    required int businessId,
    required DateTime from,
    required DateTime to,
  }) async {
    final business = await _business.getById(businessId);
    if (business == null) {
      throw ArgumentError('Business $businessId not found');
    }

    final sellerGstin = business.gstNo ?? '';
    final sellerStateCode = GstinValidator.stateCodeFrom(sellerGstin) ?? '';

    final allInvoices = await _invoice.getForPeriod(
      businessId: businessId,
      from: from,
      to: to,
    );

    // Exclude drafts
    final invoices = allInvoices
        .where((inv) => inv.status != InvoiceStatus.draft)
        .toList();

    // ── Accumulator maps ──

    // T4 B2B: key = invoiceNo + '|' + rate
    final Map<String, _B2bAcc> b2bMap = {};

    // T5 B2C Large: key = placeOfSupply + '|' + rate
    final Map<String, _B2cAcc> b2cLargeMap = {};

    // T7 B2C Small: key = placeOfSupply + '|' + rate
    final Map<String, _B2cAcc> b2cSmallMap = {};

    // T9 CDN: list (no aggregation — one row per note × rate)
    final List<Gstr1CdnRow> cdnRows = [];

    // T12 HSN: key = hsnCode + '|' + rate
    final Map<String, _HsnAcc> hsnMap = {};

    // T13 Doc counts
    int totalInvoiceCount = 0;
    int cancelledInvoiceCount = 0;
    int creditNoteCount = 0;
    int debitNoteCount = 0;
    int reverseChargeCount = 0;
    String? seriesFirst;
    String? seriesLast;
    String? cnSeriesFirst;
    String? cnSeriesLast;
    String? dnSeriesFirst;
    String? dnSeriesLast;

    for (final inv in invoices) {
      final isInterState = sellerStateCode.isNotEmpty &&
          inv.placeOfSupply != null &&
          inv.placeOfSupply != sellerStateCode;
      final pos = inv.placeOfSupply ?? '96'; // 96 = Other Territory

      // Track series for T13
      if (inv.invoiceType == InvoiceType.taxInvoice ||
          inv.invoiceType == InvoiceType.billOfSupply) {
        totalInvoiceCount++;
        if (inv.status == InvoiceStatus.cancelled) {
          cancelledInvoiceCount++;
        }
        if (inv.reverseCharge) reverseChargeCount++;
        final no = inv.invoiceNo;
        seriesFirst = _minStr(seriesFirst, no);
        seriesLast = _maxStr(seriesLast, no);
      } else if (inv.invoiceType == InvoiceType.creditNote) {
        creditNoteCount++;
        cnSeriesFirst = _minStr(cnSeriesFirst, inv.invoiceNo);
        cnSeriesLast = _maxStr(cnSeriesLast, inv.invoiceNo);
      } else if (inv.invoiceType == InvoiceType.debitNote) {
        debitNoteCount++;
        dnSeriesFirst = _minStr(dnSeriesFirst, inv.invoiceNo);
        dnSeriesLast = _maxStr(dnSeriesLast, inv.invoiceNo);
      }

      // Group items by rate bucket
      final Map<double, _RateBucket> rateBuckets = {};
      for (final item in inv.items) {
        final rate = item.taxPct;
        final taxable = item.unitPrice * item.qty * (1 - item.discountPct / 100);
        rateBuckets.putIfAbsent(rate, () => _RateBucket(rate)).add(
              taxable: taxable,
              lineTotal: item.lineTotal,
              qty: item.qty,
              hsnCode: item.hsnCode,
              uqc: _unitToUqc(item.unit),
              itemName: item.itemName,
            );
      }
      // If invoice has no items (shouldn't happen), create a single 0% bucket
      if (rateBuckets.isEmpty) {
        final emptyBucket = _RateBucket(0);
        emptyBucket.add(
          taxable: inv.subtotal,
          lineTotal: inv.total,
          qty: 1,
          hsnCode: null,
          uqc: 'OTH',
          itemName: inv.customerName,
        );
        rateBuckets[0] = emptyBucket;
      }

      final invDateStr = _fmtDate(inv.issueDate);

      for (final bucket in rateBuckets.values) {
        final rate = bucket.rate;
        final taxable = bucket.taxableValue;

        // Tax split
        final double igst;
        final double cgst;
        final double sgst;
        if (isInterState) {
          igst = taxable * rate / 100;
          cgst = 0;
          sgst = 0;
        } else {
          igst = 0;
          cgst = taxable * rate / 200;
          sgst = taxable * rate / 200;
        }

        // ── T4 / T5 / T7 routing ──────────────────────────────────────────
        if (inv.invoiceType == InvoiceType.taxInvoice) {
          if (inv.customerGstin != null && inv.customerGstin!.isNotEmpty) {
            // T4
            final key = '${inv.invoiceNo}|$rate';
            b2bMap
                .putIfAbsent(
                  key,
                  () => _B2bAcc(
                    receiverGstin: inv.customerGstin!,
                    receiverName: inv.customerName,
                    invoiceNo: inv.invoiceNo,
                    invoiceDate: invDateStr,
                    invoiceValue: inv.total,
                    placeOfSupply: pos,
                    reverseCharge: inv.reverseCharge,
                    invoiceType: 'Regular',
                    rate: rate,
                  ),
                )
                .add(taxable: taxable, cgst: cgst, sgst: sgst, igst: igst);
          } else if (isInterState && inv.total > 250000) {
            // T5
            final key = '$pos|$rate';
            b2cLargeMap
                .putIfAbsent(key, () => _B2cAcc(pos, rate))
                .add(taxable: taxable, cgst: cgst, sgst: sgst, igst: igst);
          } else {
            // T7
            final key = '$pos|$rate';
            b2cSmallMap
                .putIfAbsent(key, () => _B2cAcc(pos, rate))
                .add(taxable: taxable, cgst: cgst, sgst: sgst, igst: igst);
          }
        } else if (inv.invoiceType == InvoiceType.billOfSupply) {
          // Bill of Supply → T7 with zero taxes
          final key = '$pos|0';
          b2cSmallMap
              .putIfAbsent(key, () => _B2cAcc(pos, 0))
              .add(taxable: taxable, cgst: 0, sgst: 0, igst: 0);
        } else if (inv.invoiceType == InvoiceType.creditNote ||
            inv.invoiceType == InvoiceType.debitNote) {
          // T9 — only for registered receivers
          if (inv.customerGstin != null && inv.customerGstin!.isNotEmpty) {
            cdnRows.add(Gstr1CdnRow(
              receiverGstin: inv.customerGstin!,
              noteNo: inv.invoiceNo,
              noteDate: invDateStr,
              noteType:
                  inv.invoiceType == InvoiceType.creditNote ? 'C' : 'D',
              placeOfSupply: pos,
              originalInvoiceNo: inv.originalInvoiceNo ?? '',
              originalInvoiceDate: inv.originalInvoiceDate != null
                  ? _fmtDate(DateTime.tryParse(inv.originalInvoiceDate!) ??
                      inv.issueDate)
                  : '',
              value: inv.total,
              rate: rate,
              taxableValue: taxable,
              cgst: cgst,
              sgst: sgst,
              igst: igst,
            ));
          }
        }

        // ── T12 HSN accumulation (all non-draft invoices) ─────────────────
        for (final hsnEntry in bucket.hsnEntries) {
          final hsnKey = '${hsnEntry.hsnCode ?? "UNKNOWN"}|$rate';
          hsnMap
              .putIfAbsent(
                hsnKey,
                () => _HsnAcc(hsnEntry.hsnCode ?? 'UNKNOWN',
                    hsnEntry.itemName, hsnEntry.uqc, rate),
              )
              .add(
                qty: hsnEntry.qty,
                lineTotal: hsnEntry.lineTotal,
                taxable: hsnEntry.taxable,
                igst: isInterState
                    ? hsnEntry.taxable * rate / 100
                    : 0,
                cgst: isInterState
                    ? 0
                    : hsnEntry.taxable * rate / 200,
                sgst: isInterState
                    ? 0
                    : hsnEntry.taxable * rate / 200,
              );
        }
      }
    }

    // ── Materialise T4 ───────────────────────────────────────────────────────
    final b2bRows = b2bMap.values
        .map((a) => Gstr1B2bRow(
              receiverGstin: a.receiverGstin,
              receiverName: a.receiverName,
              invoiceNo: a.invoiceNo,
              invoiceDate: a.invoiceDate,
              invoiceValue: a.invoiceValue,
              placeOfSupply: a.placeOfSupply,
              reverseCharge: a.reverseCharge,
              invoiceType: a.invoiceType,
              rate: a.rate,
              taxableValue: a.taxableValue,
              cgst: a.cgst,
              sgst: a.sgst,
              igst: a.igst,
            ))
        .toList();

    // ── Materialise T5 ───────────────────────────────────────────────────────
    final b2cLargeRows = b2cLargeMap.values
        .map((a) => Gstr1B2cLargeRow(
              placeOfSupply: a.pos,
              rate: a.rate,
              taxableValue: a.taxableValue,
              igst: a.igst,
            ))
        .toList();

    // ── Materialise T7 ───────────────────────────────────────────────────────
    final b2cSmallRows = b2cSmallMap.values
        .map((a) => Gstr1B2cSmallRow(
              type: 'OE',
              placeOfSupply: a.pos,
              rate: a.rate,
              taxableValue: a.taxableValue,
              cgst: a.cgst,
              sgst: a.sgst,
              igst: a.igst,
            ))
        .toList();

    // ── Materialise T12 ──────────────────────────────────────────────────────
    final hsnRows = hsnMap.values
        .map((a) => Gstr1HsnRow(
              hsnCode: a.hsnCode,
              description: a.description,
              uqc: a.uqc,
              totalQty: a.totalQty,
              totalValue: a.totalValue,
              taxableValue: a.taxableValue,
              igst: a.igst,
              cgst: a.cgst,
              sgst: a.sgst,
            ))
        .toList();

    // ── Materialise T13 ──────────────────────────────────────────────────────
    final docRows = <Gstr1DocSummaryRow>[
      Gstr1DocSummaryRow(
        natureOfDocument: 'Invoices for outward supply',
        seriesFrom: seriesFirst ?? '',
        seriesTo: seriesLast ?? '',
        totalSubmitted: totalInvoiceCount,
        cancelled: cancelledInvoiceCount,
      ),
      if (reverseChargeCount > 0)
        Gstr1DocSummaryRow(
          natureOfDocument: 'Invoices for inward supply (reverse charge)',
          seriesFrom: seriesFirst ?? '',
          seriesTo: seriesLast ?? '',
          totalSubmitted: reverseChargeCount,
          cancelled: 0,
        ),
      if (creditNoteCount > 0)
        Gstr1DocSummaryRow(
          natureOfDocument: 'Credit Notes',
          seriesFrom: cnSeriesFirst ?? '',
          seriesTo: cnSeriesLast ?? '',
          totalSubmitted: creditNoteCount,
          cancelled: 0,
        ),
      if (debitNoteCount > 0)
        Gstr1DocSummaryRow(
          natureOfDocument: 'Debit Notes',
          seriesFrom: dnSeriesFirst ?? '',
          seriesTo: dnSeriesLast ?? '',
          totalSubmitted: debitNoteCount,
          cancelled: 0,
        ),
    ];

    final returnPeriodLabel =
        '${to.month.toString().padLeft(2, '0')}${to.year}';

    return Gstr1Workbook(
      businessGstin: sellerGstin,
      businessName: business.name,
      from: from,
      to: to,
      returnPeriodLabel: returnPeriodLabel,
      tableB2b: b2bRows,
      tableB2cLarge: b2cLargeRows,
      tableB2cSmall: b2cSmallRows,
      tableCdn: cdnRows,
      tableHsn: hsnRows,
      tableDocSummary: docRows,
    );
  }

  // ─── CSV ZIP Export ──────────────────────────────────────────────────────────

  /// Exports [workbook] as 6 CSV files bundled in a ZIP archive.
  ///
  /// Returns an [XFile] pointing to the ZIP that can be shared via share_plus.
  Future<XFile> exportCsvZip(Gstr1Workbook workbook) async {
    final period = workbook.returnPeriodLabel;
    final gstin = workbook.businessGstin;
    final prefix = 'GSTR1_${period}_$gstin';

    Future<File> csv(
      String name,
      List<String> headers,
      List<List<dynamic>> rows,
    ) =>
        CsvExporter.writeToTemp(name, CsvExporter.encode(headers, rows));

    final files = await Future.wait([
      csv('${prefix}_T4_B2B.csv', Gstr1B2bRow.csvHeaders,
          workbook.tableB2b.map((r) => r.toCsvRow()).toList()),
      csv('${prefix}_T5_B2CLarge.csv', Gstr1B2cLargeRow.csvHeaders,
          workbook.tableB2cLarge.map((r) => r.toCsvRow()).toList()),
      csv('${prefix}_T7_B2CSmall.csv', Gstr1B2cSmallRow.csvHeaders,
          workbook.tableB2cSmall.map((r) => r.toCsvRow()).toList()),
      csv('${prefix}_T9_CDN.csv', Gstr1CdnRow.csvHeaders,
          workbook.tableCdn.map((r) => r.toCsvRow()).toList()),
      csv('${prefix}_T12_HSN.csv', Gstr1HsnRow.csvHeaders,
          workbook.tableHsn.map((r) => r.toCsvRow()).toList()),
      csv('${prefix}_T13_DocSummary.csv', Gstr1DocSummaryRow.csvHeaders,
          workbook.tableDocSummary.map((r) => r.toCsvRow()).toList()),
    ]);

    return CsvExporter.zipFiles('$prefix.zip', files);
  }
}

// ─── Private Accumulator Helpers ────────────────────────────────────────────

class _B2bAcc {
  _B2bAcc({
    required this.receiverGstin,
    required this.receiverName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.invoiceValue,
    required this.placeOfSupply,
    required this.reverseCharge,
    required this.invoiceType,
    required this.rate,
  });

  final String receiverGstin;
  final String receiverName;
  final String invoiceNo;
  final String invoiceDate;
  final double invoiceValue;
  final String placeOfSupply;
  final bool reverseCharge;
  final String invoiceType;
  final double rate;

  double taxableValue = 0;
  double cgst = 0;
  double sgst = 0;
  double igst = 0;

  void add(
      {required double taxable,
      required double cgst,
      required double sgst,
      required double igst}) {
    taxableValue += taxable;
    this.cgst += cgst;
    this.sgst += sgst;
    this.igst += igst;
  }
}

class _B2cAcc {
  _B2cAcc(this.pos, this.rate);

  final String pos;
  final double rate;

  double taxableValue = 0;
  double cgst = 0;
  double sgst = 0;
  double igst = 0;

  void add(
      {required double taxable,
      required double cgst,
      required double sgst,
      required double igst}) {
    taxableValue += taxable;
    this.cgst += cgst;
    this.sgst += sgst;
    this.igst += igst;
  }
}

class _HsnItem {
  _HsnItem({
    required this.hsnCode,
    required this.itemName,
    required this.uqc,
    required this.qty,
    required this.lineTotal,
    required this.taxable,
  });

  final String? hsnCode;
  final String itemName;
  final String uqc;
  final double qty;
  final double lineTotal;
  final double taxable;
}

class _RateBucket {
  _RateBucket(this.rate);

  final double rate;
  final List<_HsnItem> hsnEntries = [];
  double taxableValue = 0;

  void add({
    required double taxable,
    required double lineTotal,
    required double qty,
    required String? hsnCode,
    required String uqc,
    required String itemName,
  }) {
    taxableValue += taxable;
    hsnEntries.add(_HsnItem(
      hsnCode: hsnCode,
      itemName: itemName,
      uqc: uqc,
      qty: qty,
      lineTotal: lineTotal,
      taxable: taxable,
    ));
  }
}

class _HsnAcc {
  _HsnAcc(this.hsnCode, this.description, this.uqc, this.rate);

  final String hsnCode;
  final String description;
  final String uqc;
  final double rate;

  double totalQty = 0;
  double totalValue = 0;
  double taxableValue = 0;
  double igst = 0;
  double cgst = 0;
  double sgst = 0;

  void add({
    required double qty,
    required double lineTotal,
    required double taxable,
    required double igst,
    required double cgst,
    required double sgst,
  }) {
    totalQty += qty;
    totalValue += lineTotal;
    taxableValue += taxable;
    this.igst += igst;
    this.cgst += cgst;
    this.sgst += sgst;
  }
}

// ─── Series helpers ──────────────────────────────────────────────────────────

String _minStr(String? a, String b) {
  if (a == null) return b;
  return a.compareTo(b) <= 0 ? a : b;
}

String _maxStr(String? a, String b) {
  if (a == null) return b;
  return a.compareTo(b) >= 0 ? a : b;
}

// ─── Riverpod Provider ───────────────────────────────────────────────────────

final gstr1ServiceProvider = Provider<Gstr1Service>((ref) {
  return Gstr1Service(
    businessRepo: ref.read(businessRepositoryProvider),
    invoiceRepo: ref.read(invoiceRepositoryProvider),
  );
});
