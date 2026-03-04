import 'package:equatable/equatable.dart';

import 'invoice.dart';

// ---------------------------------------------------------------------------
// BookingItem — line-item for a business booking
//
// Mirrors InvoiceItem schema so booking_items → invoice_items conversion
// is a trivial 1:1 field map (see [toInvoiceItem]).
//
// Key differences from InvoiceItem:
//   • bookingId FK instead of invoiceId
//   • sacCode (always SAC for services, never HSN)
//   • unit defaults to 'session' (vs 'PCS' for products)
//   • serviceItemId links back to item_catalog for auto-fill
//   • sortOrder controls display order
// ---------------------------------------------------------------------------

class BookingItem extends Equatable {
  const BookingItem({
    this.id,
    required this.bookingId,
    required this.itemName,
    this.description,
    this.qty = 1,
    this.unit = 'session',
    required this.unitPrice,
    this.taxPct = 0,
    this.discountPct = 0,
    required this.lineTotal,
    this.sacCode,
    this.sortOrder = 0,
    this.serviceItemId,
  });

  final int? id;
  final int bookingId;
  final String itemName;
  final String? description;

  /// Quantity — for day-rate services this equals the number of days.
  final double qty;

  /// Unit label printed on booking confirmation: 'days', 'hrs', 'session', 'pcs' …
  final String unit;

  final double unitPrice;

  /// GST rate % (0, 5, 12, 18, 28).
  final double taxPct;

  final double discountPct;

  /// Stored (not always recomputed) — qty × unitPrice × (1−disc%) × (1+tax%)
  final double lineTotal;

  /// SAC code for this service (e.g. '998311' for hotel accommodation).
  /// Auto-filled from item_catalog when a catalog service is selected.
  final String? sacCode;

  final int sortOrder;

  /// FK to item_catalog (null = custom / ad-hoc service).
  final int? serviceItemId;

  // ── Derived ──────────────────────────────────────────────────────────────

  double get subtotalBeforeTax => qty * unitPrice * (1 - discountPct / 100);

  double get taxAmount => subtotalBeforeTax * taxPct / 100;

  // ── Conversion ───────────────────────────────────────────────────────────

  /// Maps this item to an [InvoiceItem] for the Booking → Invoice flow.
  /// [invoiceId] is the newly created invoice's id (or 0 as placeholder).
  InvoiceItem toInvoiceItem(int invoiceId) => InvoiceItem(
        invoiceId: invoiceId,
        itemName: itemName,
        description: description,
        qty: qty,
        unitPrice: unitPrice,
        taxPct: taxPct,
        discountPct: discountPct,
        lineTotal: lineTotal,
        hsnCode: sacCode,
        unit: unit,
        hsnOrSac: 'SAC',
      );

  // ── copyWith ─────────────────────────────────────────────────────────────

  BookingItem copyWith({
    int? id,
    int? bookingId,
    String? itemName,
    String? description,
    double? qty,
    String? unit,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
    double? lineTotal,
    String? sacCode,
    int? sortOrder,
    int? serviceItemId,
  }) {
    return BookingItem(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
      qty: qty ?? this.qty,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPct: taxPct ?? this.taxPct,
      discountPct: discountPct ?? this.discountPct,
      lineTotal: lineTotal ?? this.lineTotal,
      sacCode: sacCode ?? this.sacCode,
      sortOrder: sortOrder ?? this.sortOrder,
      serviceItemId: serviceItemId ?? this.serviceItemId,
    );
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'booking_id': bookingId,
        'item_name': itemName,
        'description': description,
        'qty': qty,
        'unit': unit,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'discount_pct': discountPct,
        'line_total': lineTotal,
        'sac_code': sacCode,
        'sort_order': sortOrder,
        'service_item_id': serviceItemId,
      };

  factory BookingItem.fromMap(Map<String, dynamic> map) => BookingItem(
        id: map['id'] as int?,
        bookingId: map['booking_id'] as int,
        itemName: map['item_name'] as String,
        description: map['description'] as String?,
        qty: (map['qty'] as num).toDouble(),
        unit: (map['unit'] as String?) ?? 'session',
        unitPrice: (map['unit_price'] as num).toDouble(),
        taxPct: (map['tax_pct'] as num?)?.toDouble() ?? 0,
        discountPct: (map['discount_pct'] as num?)?.toDouble() ?? 0,
        lineTotal: (map['line_total'] as num).toDouble(),
        sacCode: map['sac_code'] as String?,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        serviceItemId: map['service_item_id'] as int?,
      );

  @override
  List<Object?> get props => [
        id,
        bookingId,
        itemName,
        qty,
        unit,
        unitPrice,
        taxPct,
        discountPct,
        lineTotal,
        sortOrder,
      ];
}
