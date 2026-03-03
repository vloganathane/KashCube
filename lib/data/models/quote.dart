import 'package:equatable/equatable.dart';

import 'invoice.dart' show InvoiceType, InvoiceTypeExt;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum QuoteStatus { draft, sent, accepted, rejected }

extension QuoteStatusExt on QuoteStatus {
  String get label {
    switch (this) {
      case QuoteStatus.draft:
        return 'Draft';
      case QuoteStatus.sent:
        return 'Sent';
      case QuoteStatus.accepted:
        return 'Accepted';
      case QuoteStatus.rejected:
        return 'Rejected';
    }
  }

  String get dbValue => name;

  static QuoteStatus fromDb(String? v) {
    switch (v) {
      case 'sent':
        return QuoteStatus.sent;
      case 'accepted':
        return QuoteStatus.accepted;
      case 'rejected':
        return QuoteStatus.rejected;
      default:
        return QuoteStatus.draft;
    }
  }
}

// ---------------------------------------------------------------------------
// QuoteItem
// ---------------------------------------------------------------------------

class QuoteItem extends Equatable {
  const QuoteItem({
    this.id,
    required this.quoteId,
    required this.itemName,
    this.description,
    this.qty = 1,
    required this.unitPrice,
    this.taxPct = 0,
    this.discountPct = 0,
    required this.lineTotal,
    this.hsnCode,
    this.unit = 'PCS',
    this.hsnOrSac = 'HSN',
  });

  final int? id;
  final int quoteId;
  final String itemName;
  final String? description;
  final double qty;
  final double unitPrice;
  final double taxPct;
  final double discountPct;
  final double lineTotal;
  /// HSN (product) or SAC (service) code.
  final String? hsnCode;
  /// GST UOM code.
  final String unit;
  /// 'HSN' for products, 'SAC' for services.
  final String hsnOrSac;

  QuoteItem copyWith({
    int? id,
    int? quoteId,
    String? itemName,
    String? description,
    double? qty,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
    double? lineTotal,
    String? hsnCode,
    String? unit,
    String? hsnOrSac,
  }) {
    return QuoteItem(
      id: id ?? this.id,
      quoteId: quoteId ?? this.quoteId,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPct: taxPct ?? this.taxPct,
      discountPct: discountPct ?? this.discountPct,
      lineTotal: lineTotal ?? this.lineTotal,
      hsnCode: hsnCode ?? this.hsnCode,
      unit: unit ?? this.unit,
      hsnOrSac: hsnOrSac ?? this.hsnOrSac,
    );
  }

  /// Compute line total: qty × unitPrice × (1 - discountPct/100) × (1 + taxPct/100)
  static double computeLineTotal({
    required double qty,
    required double unitPrice,
    double taxPct = 0,
    double discountPct = 0,
  }) {
    final discounted = unitPrice * (1 - discountPct / 100);
    return qty * discounted * (1 + taxPct / 100);
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'quote_id': quoteId,
        'item_name': itemName,
        'description': description,
        'qty': qty,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'discount_pct': discountPct,
        'line_total': lineTotal,
        'hsn_code': hsnCode,
        'unit': unit,
        'hsn_or_sac': hsnOrSac,
      };

  factory QuoteItem.fromMap(Map<String, dynamic> map) => QuoteItem(
        id: map['id'] as int?,
        quoteId: map['quote_id'] as int,
        itemName: map['item_name'] as String,
        description: map['description'] as String?,
        qty: (map['qty'] as num).toDouble(),
        unitPrice: (map['unit_price'] as num).toDouble(),
        taxPct: (map['tax_pct'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discount_pct'] as num?)?.toDouble() ?? 0,
        lineTotal: (map['line_total'] as num).toDouble(),
        hsnCode: map['hsn_code'] as String?,
        unit: (map['unit'] as String?) ?? 'PCS',
        hsnOrSac: (map['hsn_or_sac'] as String?) ?? 'HSN',
      );

  @override
  List<Object?> get props =>
      [id, quoteId, itemName, qty, unitPrice, taxPct, discountPct, lineTotal];
}

// ---------------------------------------------------------------------------
// Quote
// ---------------------------------------------------------------------------

class Quote extends Equatable {
  const Quote({
    this.id,
    required this.quoteNo,
    this.businessId,
    this.customerPartyId,
    required this.customerName,
    this.status = QuoteStatus.draft,
    this.validUntil,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountPct = 0,
    this.total = 0,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.invoiceType = InvoiceType.taxInvoice,
    this.placeOfSupply,
    this.reverseCharge = false,
    this.customerGstin,
    this.freightAmt = 0,
    this.insuranceAmt = 0,
    this.packingAmt = 0,
  });

  final int? id;
  final String quoteNo;
  final int? businessId;
  final int? customerPartyId;
  final String customerName;
  final QuoteStatus status;
  final DateTime? validUntil;
  final double subtotal;
  final double taxTotal;
  final double discountPct;
  final double total;
  final String? notes;
  final List<QuoteItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Tax Invoice / Bill of Supply (determines what this converts to).
  final InvoiceType invoiceType;
  /// GSTN place of supply state code.
  final String? placeOfSupply;
  /// Whether reverse charge applies.
  final bool reverseCharge;
  /// Buyer GSTIN snapshot.
  final String? customerGstin;
  /// Freight charges (post-tax, shown separately on quote).
  final double freightAmt;
  /// Insurance charges (post-tax, shown separately on quote).
  final double insuranceAmt;
  /// Packing & forwarding charges (post-tax, shown separately on quote).
  final double packingAmt;

  Quote copyWith({
    int? id,
    String? quoteNo,
    int? businessId,
    int? customerPartyId,
    String? customerName,
    QuoteStatus? status,
    DateTime? validUntil,
    double? subtotal,
    double? taxTotal,
    double? discountPct,
    double? total,
    String? notes,
    List<QuoteItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    InvoiceType? invoiceType,
    String? placeOfSupply,
    bool? reverseCharge,
    String? customerGstin,
    double? freightAmt,
    double? insuranceAmt,
    double? packingAmt,
  }) {
    return Quote(
      id: id ?? this.id,
      quoteNo: quoteNo ?? this.quoteNo,
      businessId: businessId ?? this.businessId,
      customerPartyId: customerPartyId ?? this.customerPartyId,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      validUntil: validUntil ?? this.validUntil,
      subtotal: subtotal ?? this.subtotal,
      taxTotal: taxTotal ?? this.taxTotal,
      discountPct: discountPct ?? this.discountPct,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      invoiceType: invoiceType ?? this.invoiceType,
      placeOfSupply: placeOfSupply ?? this.placeOfSupply,
      reverseCharge: reverseCharge ?? this.reverseCharge,
      customerGstin: customerGstin ?? this.customerGstin,
      freightAmt: freightAmt ?? this.freightAmt,
      insuranceAmt: insuranceAmt ?? this.insuranceAmt,
      packingAmt: packingAmt ?? this.packingAmt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'quote_no': quoteNo,
        'business_id': businessId,
        'customer_party_id': customerPartyId,
        'customer_name': customerName,
        'status': status.dbValue,
        'valid_until': validUntil?.toIso8601String(),
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_pct': discountPct,
        'total': total,
        'notes': notes,
        'invoice_type': invoiceType.dbValue,
        'place_of_supply': placeOfSupply,
        'reverse_charge': reverseCharge ? 1 : 0,
        'customer_gstin': customerGstin,
        'freight_amt': freightAmt,
        'insurance_amt': insuranceAmt,
        'packing_amt': packingAmt,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Quote.fromMap(Map<String, dynamic> map,
      {List<QuoteItem> items = const []}) =>
      Quote(
        id: map['id'] as int?,
        quoteNo: map['quote_no'] as String,
        businessId: map['business_id'] as int?,
        customerPartyId: map['customer_party_id'] as int?,
        customerName: map['customer_name'] as String,
        status: QuoteStatusExt.fromDb(map['status'] as String?),
        validUntil: map['valid_until'] != null
            ? DateTime.parse(map['valid_until'] as String)
            : null,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        taxTotal: (map['tax_total'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discount_pct'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        items: items,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        invoiceType: InvoiceTypeExt.fromDb(map['invoice_type'] as String?),
        placeOfSupply: map['place_of_supply'] as String?,
        reverseCharge: (map['reverse_charge'] as int? ?? 0) == 1,
        customerGstin: map['customer_gstin'] as String?,
        freightAmt: (map['freight_amt'] as num?)?.toDouble() ?? 0,
        insuranceAmt: (map['insurance_amt'] as num?)?.toDouble() ?? 0,
        packingAmt: (map['packing_amt'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [id, quoteNo, customerName, status, total];
}
