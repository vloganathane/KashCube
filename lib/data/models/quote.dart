import 'package:equatable/equatable.dart';

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
  });

  final int? id;
  final String quoteNo;
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

  Quote copyWith({
    int? id,
    String? quoteNo,
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
  }) {
    return Quote(
      id: id ?? this.id,
      quoteNo: quoteNo ?? this.quoteNo,
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
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'quote_no': quoteNo,
        'customer_party_id': customerPartyId,
        'customer_name': customerName,
        'status': status.dbValue,
        'valid_until': validUntil?.toIso8601String(),
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_pct': discountPct,
        'total': total,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Quote.fromMap(Map<String, dynamic> map,
      {List<QuoteItem> items = const []}) =>
      Quote(
        id: map['id'] as int?,
        quoteNo: map['quote_no'] as String,
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
      );

  @override
  List<Object?> get props => [id, quoteNo, customerName, status, total];
}
