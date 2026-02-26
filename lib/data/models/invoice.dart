import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum InvoiceStatus { draft, sent, paid, overdue, partiallyPaid }

extension InvoiceStatusExt on InvoiceStatus {
  String get label {
    switch (this) {
      case InvoiceStatus.draft:
        return 'Draft';
      case InvoiceStatus.sent:
        return 'Sent';
      case InvoiceStatus.paid:
        return 'Paid';
      case InvoiceStatus.overdue:
        return 'Overdue';
      case InvoiceStatus.partiallyPaid:
        return 'Partial';
    }
  }

  String get dbValue {
    switch (this) {
      case InvoiceStatus.partiallyPaid:
        return 'partially_paid';
      default:
        return name;
    }
  }

  static InvoiceStatus fromDb(String? v) {
    switch (v) {
      case 'sent':
        return InvoiceStatus.sent;
      case 'paid':
        return InvoiceStatus.paid;
      case 'overdue':
        return InvoiceStatus.overdue;
      case 'partially_paid':
        return InvoiceStatus.partiallyPaid;
      default:
        return InvoiceStatus.draft;
    }
  }
}

// ---------------------------------------------------------------------------
// InvoiceItem
// ---------------------------------------------------------------------------

class InvoiceItem extends Equatable {
  const InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.itemName,
    this.description,
    this.qty = 1,
    required this.unitPrice,
    this.taxPct = 0,
    this.discountPct = 0,
    required this.lineTotal,
  });

  final int? id;
  final int invoiceId;
  final String itemName;
  final String? description;
  final double qty;
  final double unitPrice;
  final double taxPct;
  final double discountPct;
  final double lineTotal;

  InvoiceItem copyWith({
    int? id,
    int? invoiceId,
    String? itemName,
    String? description,
    double? qty,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
    double? lineTotal,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPct: taxPct ?? this.taxPct,
      discountPct: discountPct ?? this.discountPct,
      lineTotal: lineTotal ?? this.lineTotal,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'invoice_id': invoiceId,
        'item_name': itemName,
        'description': description,
        'qty': qty,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'discount_pct': discountPct,
        'line_total': lineTotal,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        id: map['id'] as int?,
        invoiceId: map['invoice_id'] as int,
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
      [id, invoiceId, itemName, qty, unitPrice, taxPct, discountPct, lineTotal];
}

// ---------------------------------------------------------------------------
// Invoice
// ---------------------------------------------------------------------------

class Invoice extends Equatable {
  const Invoice({
    this.id,
    required this.invoiceNo,
    this.quoteId,
    this.customerPartyId,
    required this.customerName,
    this.status = InvoiceStatus.draft,
    required this.issueDate,
    this.dueDate,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountPct = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String invoiceNo;
  final int? quoteId;
  final int? customerPartyId;
  final String customerName;
  final InvoiceStatus status;
  final DateTime issueDate;
  final DateTime? dueDate;
  final double subtotal;
  final double taxTotal;
  final double discountPct;
  final double total;
  final double paidAmount;
  final String? notes;
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get balanceDue => total - paidAmount;
  bool get isOverdue =>
      dueDate != null &&
      dueDate!.isBefore(DateTime.now()) &&
      status != InvoiceStatus.paid;

  Invoice copyWith({
    int? id,
    String? invoiceNo,
    int? quoteId,
    int? customerPartyId,
    String? customerName,
    InvoiceStatus? status,
    DateTime? issueDate,
    DateTime? dueDate,
    double? subtotal,
    double? taxTotal,
    double? discountPct,
    double? total,
    double? paidAmount,
    String? notes,
    List<InvoiceItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      quoteId: quoteId ?? this.quoteId,
      customerPartyId: customerPartyId ?? this.customerPartyId,
      customerName: customerName ?? this.customerName,
      status: status ?? this.status,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      subtotal: subtotal ?? this.subtotal,
      taxTotal: taxTotal ?? this.taxTotal,
      discountPct: discountPct ?? this.discountPct,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'invoice_no': invoiceNo,
        'quote_id': quoteId,
        'customer_party_id': customerPartyId,
        'customer_name': customerName,
        'status': status.dbValue,
        'issue_date': issueDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_pct': discountPct,
        'total': total,
        'paid_amount': paidAmount,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, dynamic> map,
      {List<InvoiceItem> items = const []}) =>
      Invoice(
        id: map['id'] as int?,
        invoiceNo: map['invoice_no'] as String,
        quoteId: map['quote_id'] as int?,
        customerPartyId: map['customer_party_id'] as int?,
        customerName: map['customer_name'] as String,
        status: InvoiceStatusExt.fromDb(map['status'] as String?),
        issueDate: DateTime.parse(map['issue_date'] as String),
        dueDate: map['due_date'] != null
            ? DateTime.parse(map['due_date'] as String)
            : null,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        taxTotal: (map['tax_total'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discount_pct'] as num?)?.toDouble() ?? 0,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        items: items,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, invoiceNo, customerName, status, total, paidAmount];
}
