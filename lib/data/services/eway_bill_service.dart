// e-Way Bill JSON export service.
//
// Generates a GSTN EWB_Import_Template–compatible JSON file from a
// local Invoice record, then shares it via share_plus.
//
// GSTN e-Way Bill JSON specification:
//   https://ewaybillgst.gov.in/apidocs/
//
// No network calls — JSON is built locally and written to the temp directory.
// The caller (or the user via the share sheet) decides where to send it.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/gstin_validator.dart' show GstinValidator;
import '../models/business.dart';
import '../models/invoice.dart';
import '../models/party.dart';
import 'gst_calculator.dart';

/// Builds and shares an e-Way Bill–compatible JSON file for a given invoice.
///
/// Usage:
/// ```dart
/// await EwayBillService.instance.exportAndShare(
///   invoice,
///   business: activeBusiness,
///   customerParty: party,
/// );
/// ```
class EwayBillService {
  EwayBillService._();
  static final EwayBillService instance = EwayBillService._();

  // ─── GSTN UOM code mapping ──────────────────────────────────────────────
  // Maps app unit strings (case-insensitive) → GSTN EWB UOM codes.
  // Full GSTN UOM list: https://ewaybillgst.gov.in/Others/MasterCodes.aspx
  static const Map<String, String> _uomMap = {
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
    'flat': 'OTH',
    'lump': 'OTH',
  };

  // ─── Public API ─────────────────────────────────────────────────────────

  /// Builds the e-Way Bill JSON for [invoice] and immediately shares it.
  ///
  /// [business] is the seller (your business profile).
  /// [customerParty] is the buyer (optional; name/GSTIN are also on the invoice).
  ///
  /// Returns the temporary [File] that was created and shared.
  Future<File> exportAndShare(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
  }) async {
    final file = await _writeJson(invoice, business: business, customerParty: customerParty);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'e-Way Bill — ${invoice.invoiceNo}',
      text: 'e-Way Bill JSON for invoice ${invoice.invoiceNo}',
    );
    return file;
  }

  /// Builds the e-Way Bill JSON for [invoice] and returns the [File].
  ///
  /// Does not share — use this when you need the file path (e.g. to open it).
  Future<File> buildJsonFile(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
  }) =>
      _writeJson(invoice, business: business, customerParty: customerParty);

  /// Returns the e-Way Bill payload as a [Map] without writing any file.
  ///
  /// Useful for debugging or unit-testing the JSON structure.
  Map<String, dynamic> buildPayload(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
  }) =>
      _buildPayload(invoice, business: business, customerParty: customerParty);

  // ─── Internal ────────────────────────────────────────────────────────────

  Future<File> _writeJson(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
  }) async {
    final payload = _buildPayload(invoice, business: business, customerParty: customerParty);
    final json = const JsonEncoder.withIndent('  ').convert(payload);

    final dir = await _ewayDir();
    final filename = 'EWB_${invoice.invoiceNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')}.json';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(json, flush: true);
    return file;
  }

  Future<Directory> _ewayDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/eway');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Map<String, dynamic> _buildPayload(
    Invoice invoice, {
    Business? business,
    Party? customerParty,
  }) {
    // ── Supply-type detection ─────────────────────────────────────────────
    // 'O' = outward (sales invoice), 'I' = inward (purchase).
    // KashCube only creates sales invoices, so always outward.
    const supplyType = 'O';
    const subSupplyType = '1'; // 1 = supply

    // ── Doc type mapping ──────────────────────────────────────────────────
    final docType = _docTypeCode(invoice.invoiceType);

    // ── Date formatting (DD/MM/YYYY per GSTN spec) ─────────────────────────
    final docDate = _ewbDate(invoice.issueDate);

    // ── Seller details (From party) ───────────────────────────────────────
    final fromGstin = (business?.gstNo?.trim().isNotEmpty ?? false)
        ? business!.gstNo!.trim().toUpperCase()
        : 'URP'; // Unregistered Person
    final fromStateCode = _stateCodeInt(fromGstin, business?.state);
    final fromPincode = _pincodeInt(business?.pincode);

    // ── Buyer details (To party) ──────────────────────────────────────────
    final toGstin = (invoice.customerGstin?.trim().isNotEmpty ?? false)
        ? invoice.customerGstin!.trim().toUpperCase()
        : (customerParty?.gstin?.trim().isNotEmpty ?? false)
            ? customerParty!.gstin!.trim().toUpperCase()
            : 'URP';
    final toStateCode = _stateCodeInt(
      toGstin,
      customerParty?.state ?? invoice.placeOfSupply,
    );
    final toPincode = _pincodeInt(customerParty?.pincode);

    // ── GST values ────────────────────────────────────────────────────────
    final sellerState = business?.state ?? '';
    final buyerState = customerParty?.state ?? invoice.placeOfSupply ?? '';
    final isInterState = GstCalculator.isInterState(sellerState, buyerState);

    double cgstTotal = 0;
    double sgstTotal = 0;
    double igstTotal = 0;

    final itemList = <Map<String, dynamic>>[];
    for (var i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      final taxableAmount = _taxableAmount(item);
      final split = GstCalculator.calculate(
        sellerState: sellerState,
        buyerState: buyerState,
        taxableAmount: taxableAmount,
        gstPct: item.taxPct,
      );

      cgstTotal += split.cgst;
      sgstTotal += split.sgst;
      igstTotal += split.igst;

      itemList.add({
        'itemNo': i + 1,
        'productName': item.itemName,
        'productDesc': item.description ?? '',
        'hsnCode': item.hsnCode ?? '',
        'quantity': item.qty,
        'qtyUnit': _gstnUom(item.unit),
        'cgstRate': isInterState ? 0.0 : _half(item.taxPct),
        'sgstRate': isInterState ? 0.0 : _half(item.taxPct),
        'igstRate': isInterState ? item.taxPct : 0.0,
        'cessRate': 0.0,
        'cessNonAdvol': 0,
        'taxableAmount': _round2(taxableAmount),
      });
    }

    // Round to 2dp
    cgstTotal = _round2(cgstTotal);
    sgstTotal = _round2(sgstTotal);
    igstTotal = _round2(igstTotal);
    final totInvValue = _round2(invoice.total);

    return {
      // ── doc header ────────────────────────────────────────────────────
      'supplyType': supplyType,
      'subSupplyType': subSupplyType,
      'subSupplyDesc': '',
      'docType': docType,
      'docNo': invoice.invoiceNo,
      'docDate': docDate,

      // ── from (seller) ─────────────────────────────────────────────────
      'fromGstin': fromGstin,
      'fromTrdName': business?.name ?? '',
      'fromAddr1': business?.address ?? '',
      'fromAddr2': '',
      'fromPlace': business?.city ?? business?.state ?? '',
      'fromPincode': fromPincode,
      'actFromStateCode': fromStateCode,
      'fromStateCode': fromStateCode,

      // ── to (buyer) ────────────────────────────────────────────────────
      'toGstin': toGstin,
      'toTrdName': invoice.customerName,
      'toAddr1': customerParty?.address ?? '',
      'toAddr2': '',
      'toPlace': customerParty?.city ?? customerParty?.state ?? '',
      'toPincode': toPincode,
      'actToStateCode': toStateCode,
      'toStateCode': toStateCode,

      // ── transaction ───────────────────────────────────────────────────
      'transactionType': 1,
      'dispatchFromGSTIN': '',
      'dispatchFromTradeName': '',
      'shipToGSTIN': '',
      'shipToTradeName': '',

      // ── amounts ───────────────────────────────────────────────────────
      'totalValue': _round2(invoice.subtotal),
      'cgstValue': cgstTotal,
      'sgstValue': sgstTotal,
      'igstValue': igstTotal,
      'cessValue': 0.0,
      'cessNonAdvolValue': 0.0,
      'otherValue': 0.0,
      'totInvValue': totInvValue,

      // ── transport (user fills after export) ────────────────────────────
      'transMode': '1',
      'transDistance': '',
      'transporterName': '',
      'transporterId': '',
      'transDocNo': '',
      'transDocDate': '',
      'vehicleNo': '',
      'vehicleType': 'R',

      // ── items ─────────────────────────────────────────────────────────
      'itemList': itemList,
    };
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Maps [InvoiceType] to the GSTN docType code.
  static String _docTypeCode(InvoiceType type) {
    switch (type) {
      case InvoiceType.taxInvoice:
        return 'INV';
      case InvoiceType.billOfSupply:
        return 'BIL';
      case InvoiceType.creditNote:
        return 'CRN';
      case InvoiceType.debitNote:
        return 'DBN';
    }
  }

  /// Formats [date] as DD/MM/YYYY (GSTN e-Way Bill date format).
  static String _ewbDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  /// Returns the numeric GSTN state code from a GSTIN string,
  /// falling back to a name-based lookup via [GstinValidator], then 0.
  static int _stateCodeInt(String gstin, String? stateName) {
    if (gstin.length >= 2 && gstin != 'URP') {
      final code = gstin.substring(0, 2);
      final parsed = int.tryParse(code);
      if (parsed != null && parsed > 0) return parsed;
    }
    if (stateName != null && stateName.isNotEmpty) {
      // Attempt to extract from state name by checking known state codes.
      // GstinValidator has the state→code map but it's inverted; scan all codes.
      for (var entry in _stateCodeByName.entries) {
        if (stateName.trim().toLowerCase().contains(entry.key)) {
          return entry.value;
        }
      }
    }
    return 0;
  }

  // Partial name → GSTN state code (int) for fallback lookups.
  static const Map<String, int> _stateCodeByName = {
    'jammu': 1,
    'himachal': 2,
    'punjab': 3,
    'chandigarh': 4,
    'uttarakhand': 5,
    'uttaranchal': 5,
    'haryana': 6,
    'delhi': 7,
    'rajasthan': 8,
    'uttar pradesh': 9,
    'bihar': 10,
    'sikkim': 11,
    'arunachal': 12,
    'nagaland': 13,
    'manipur': 14,
    'mizoram': 15,
    'tripura': 16,
    'meghalaya': 17,
    'assam': 18,
    'west bengal': 19,
    'jharkhand': 20,
    'odisha': 21,
    'orissa': 21,
    'chhattisgarh': 22,
    'madhya pradesh': 23,
    'gujarat': 24,
    'dadra': 26,
    'maharashtra': 27,
    'andhra': 28, // old AP code; also 37 (Telangana split)
    'karnataka': 29,
    'goa': 30,
    'lakshadweep': 31,
    'kerala': 32,
    'tamil nadu': 33,
    'puducherry': 34,
    'pondicherry': 34,
    'andaman': 35,
    'telangana': 36,
    'ladakh': 38,
  };

  /// Converts a pincode string to int, or 0 if null/unparseable.
  static int _pincodeInt(String? pincode) =>
      int.tryParse(pincode?.trim() ?? '') ?? 0;

  /// Maps app unit labels to GSTN UOM codes.
  static String _gstnUom(String unit) =>
      _uomMap[unit.trim().toLowerCase()] ?? 'OTH';

  /// Returns half of [pct] (for CGST = SGST = GST/2), rounded to 2dp.
  static double _half(double pct) => _round2(pct / 2);

  /// Rounds to 2 decimal places.
  static double _round2(double v) =>
      (v * 100).roundToDouble() / 100;

  /// Taxable amount for a line item = line_total minus tax (back-calculate).
  ///
  /// line_total = (qty * unit_price * (1 - discount%/100)) * (1 + tax%/100)
  /// taxable    = line_total / (1 + tax%/100)
  static double _taxableAmount(InvoiceItem item) {
    if (item.taxPct == 0) return _round2(item.lineTotal);
    return _round2(item.lineTotal / (1 + item.taxPct / 100));
  }
}
