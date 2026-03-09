import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum InvoiceStatus { draft, sent, paid, overdue, partiallyPaid, cancelled }

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
      case InvoiceStatus.cancelled:
        return 'Cancelled';
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
      case 'cancelled':
        return InvoiceStatus.cancelled;
      default:
        return InvoiceStatus.draft;
    }
  }
}

// ---------------------------------------------------------------------------
// InvoiceType
// ---------------------------------------------------------------------------

enum InvoiceType { taxInvoice, billOfSupply, creditNote, debitNote }

extension InvoiceTypeExt on InvoiceType {
  String get label => const {
    InvoiceType.taxInvoice:   'Tax Invoice',
    InvoiceType.billOfSupply: 'Bill of Supply',
    InvoiceType.creditNote:   'Credit Note',
    InvoiceType.debitNote:    'Debit Note',
  }[this]!;

  String get dbValue => const {
    InvoiceType.taxInvoice:   'tax_invoice',
    InvoiceType.billOfSupply: 'bill_of_supply',
    InvoiceType.creditNote:   'credit_note',
    InvoiceType.debitNote:    'debit_note',
  }[this]!;

  static InvoiceType fromDb(String? v) {
    switch (v) {
      case 'bill_of_supply': return InvoiceType.billOfSupply;
      case 'credit_note':    return InvoiceType.creditNote;
      case 'debit_note':     return InvoiceType.debitNote;
      default:               return InvoiceType.taxInvoice;
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
    this.hsnCode,
    this.unit = 'PCS',
    this.hsnOrSac = 'HSN',
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
  /// HSN (product) or SAC (service) code — printed on invoice.
  final String? hsnCode;
  /// GST UOM code (e.g. 'PCS', 'KGS') from e-Way Bill master list.
  final String unit;
  /// 'HSN' for products, 'SAC' for services.
  final String hsnOrSac;

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
    String? hsnCode,
    String? unit,
    String? hsnOrSac,
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
      hsnCode: hsnCode ?? this.hsnCode,
      unit: unit ?? this.unit,
      hsnOrSac: hsnOrSac ?? this.hsnOrSac,
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
        'hsn_code': hsnCode,
        'unit': unit,
        'hsn_or_sac': hsnOrSac,
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
        hsnCode: map['hsn_code'] as String?,
        unit: (map['unit'] as String?) ?? 'PCS',
        hsnOrSac: (map['hsn_or_sac'] as String?) ?? 'HSN',
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
    this.challanId,
    this.businessId,
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
    this.paidAt,
    this.paymentMethod,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.reminderSentAt,
    this.invoiceType = InvoiceType.taxInvoice,
    this.placeOfSupply,
    this.reverseCharge = false,
    this.customerGstin,
    this.irn,
    this.irnAckNo,
    this.irnAckDate,
    this.qrCodeData,
    // ── e-Way Bill fields (v36) ────────────────────────────────────────────
    this.ewbNo,
    this.ewbGeneratedAt,
    this.ewbValidUntil,
    this.vehicleNo,
    this.transporterName,
    this.transporterGstin,
    this.transportMode,
    this.distanceKm,
    this.freightAmt = 0,
    this.insuranceAmt = 0,
    this.packingAmt = 0,
    // ── Delivery address snapshot (v46) ──────────────────────────────────────
    this.deliveryAddress,
    this.deliveryCity,
    this.deliveryState,
    this.deliveryPincode,
    this.deliveryGstin,
    // ── Credit/Debit Note original-invoice link (v47) ────────────────────────
    this.originalInvoiceId,
    this.originalInvoiceNo,
    this.originalInvoiceDate,
  });

  final int? id;
  final String invoiceNo;
  final int? quoteId;
  /// ID of the Delivery Challan this invoice was converted from (null if not from DC).
  final int? challanId;
  final int? businessId;
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
  /// When the invoice was marked as paid (null if not paid).
  final DateTime? paidAt;
  /// Payment method used (null if not paid). Stored as PaymentMethod enum name.
  final String? paymentMethod;
  final String? notes;
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Timestamp of the last manual reminder sent (WhatsApp/SMS/Email).
  final DateTime? reminderSentAt;
  /// Tax Invoice / Bill of Supply / Credit Note / Debit Note.
  final InvoiceType invoiceType;
  /// GSTN place of supply state code (e.g. '29' for Karnataka).
  final String? placeOfSupply;
  /// Whether reverse charge mechanism applies (GST rule 9).
  final bool reverseCharge;
  /// Buyer GSTIN — snapshot at time of invoice creation.
  final String? customerGstin;

  // ── e-Invoice / IRP fields (v34) ─────────────────────────────────────────
  /// IRN (Invoice Reference Number) assigned by the IRP portal.
  final String? irn;
  /// IRP acknowledgement number returned after IRN registration.
  final String? irnAckNo;
  /// IRP acknowledgement date (ISO8601 string, e.g. '2024-04-01T10:30:00').
  final String? irnAckDate;
  /// Signed QR code data from the IRP (for printing on invoice).
  final String? qrCodeData;

  /// `true` when an IRN has been assigned to this invoice.
  bool get hasEInvoice => irn != null && irn!.isNotEmpty;

  // ── e-Way Bill fields (v36) ───────────────────────────────────────────────
  /// EWB number assigned by GSTN portal (manually entered or via GSP).
  final String? ewbNo;
  /// When the EWB was generated / entered.
  final DateTime? ewbGeneratedAt;
  /// Validity expiry computed as generated_at + floor(distance/100) days.
  final DateTime? ewbValidUntil;
  /// Vehicle registration number (e.g. KA01AB1234).
  final String? vehicleNo;
  /// Transporter trade name.
  final String? transporterName;
  /// Transporter GSTIN (optional).
  final String? transporterGstin;
  /// GSTN transport mode code: '1'=Road, '2'=Rail, '3'=Air, '4'=Ship.
  final String? transportMode;
  /// Distance in km — used to compute validity period.
  final int? distanceKm;
  /// Freight charges (post-tax, shown separately on invoice).
  final double freightAmt;
  /// Insurance charges (post-tax, shown separately on invoice).
  final double insuranceAmt;
  /// Packing & forwarding charges (post-tax, shown separately on invoice).
  final double packingAmt;

  // ── Delivery address snapshot (v46) ──────────────────────────────────────
  /// Street/area part of the delivery address — snapshot at invoice creation.
  final String? deliveryAddress;
  final String? deliveryCity;
  final String? deliveryState;
  final String? deliveryPincode;
  /// Delivery location GSTIN (may differ from the customer's billing GSTIN).
  final String? deliveryGstin;

  // ── Credit/Debit Note original-invoice link (v47) ────────────────────────
  /// FK to the original invoice (only non-null for creditNote / debitNote).
  final int? originalInvoiceId;
  /// Snapshot of the original invoice number at the time this note was created.
  final String? originalInvoiceNo;
  /// Snapshot of the original invoice date (ISO-8601, e.g. '2026-01-15').
  final String? originalInvoiceDate;

  /// `true` when an e-Way Bill has been generated for this invoice.
  bool get hasEwb => ewbNo != null && ewbNo!.isNotEmpty;

  /// Validity status: null if no EWB; true if still valid; false if expired.
  bool? get ewbIsValid {
    if (!hasEwb || ewbValidUntil == null) return null;
    return ewbValidUntil!.isAfter(DateTime.now());
  }

  double get balanceDue => total - paidAmount;
  bool get isOverdue =>
      dueDate != null &&
      dueDate!.isBefore(DateTime.now()) &&
      status != InvoiceStatus.paid;

  Invoice copyWith({
    int? id,
    String? invoiceNo,
    int? quoteId,
    int? challanId,
    int? businessId,
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
    DateTime? paidAt,
    String? paymentMethod,
    String? notes,
    List<InvoiceItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reminderSentAt,
    InvoiceType? invoiceType,
    String? placeOfSupply,
    bool? reverseCharge,
    String? customerGstin,
    String? irn,
    String? irnAckNo,
    String? irnAckDate,
    String? qrCodeData,
    String? ewbNo,
    DateTime? ewbGeneratedAt,
    DateTime? ewbValidUntil,
    String? vehicleNo,
    String? transporterName,
    String? transporterGstin,
    String? transportMode,
    int? distanceKm,
    double? freightAmt,
    double? insuranceAmt,
    double? packingAmt,
    String? deliveryAddress,
    String? deliveryCity,
    String? deliveryState,
    String? deliveryPincode,
    String? deliveryGstin,
    int? originalInvoiceId,
    String? originalInvoiceNo,
    String? originalInvoiceDate,
  }) {
    return Invoice(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      quoteId: quoteId ?? this.quoteId,
      challanId: challanId ?? this.challanId,
      businessId: businessId ?? this.businessId,
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
      paidAt: paidAt ?? this.paidAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
      invoiceType: invoiceType ?? this.invoiceType,
      placeOfSupply: placeOfSupply ?? this.placeOfSupply,
      reverseCharge: reverseCharge ?? this.reverseCharge,
      customerGstin: customerGstin ?? this.customerGstin,
      irn: irn ?? this.irn,
      irnAckNo: irnAckNo ?? this.irnAckNo,
      irnAckDate: irnAckDate ?? this.irnAckDate,
      qrCodeData: qrCodeData ?? this.qrCodeData,
      ewbNo: ewbNo ?? this.ewbNo,
      ewbGeneratedAt: ewbGeneratedAt ?? this.ewbGeneratedAt,
      ewbValidUntil: ewbValidUntil ?? this.ewbValidUntil,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      transporterName: transporterName ?? this.transporterName,
      transporterGstin: transporterGstin ?? this.transporterGstin,
      transportMode: transportMode ?? this.transportMode,
      distanceKm: distanceKm ?? this.distanceKm,
      freightAmt: freightAmt ?? this.freightAmt,
      insuranceAmt: insuranceAmt ?? this.insuranceAmt,
      packingAmt: packingAmt ?? this.packingAmt,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryCity: deliveryCity ?? this.deliveryCity,
      deliveryState: deliveryState ?? this.deliveryState,
      deliveryPincode: deliveryPincode ?? this.deliveryPincode,
      deliveryGstin: deliveryGstin ?? this.deliveryGstin,
      originalInvoiceId: originalInvoiceId ?? this.originalInvoiceId,
      originalInvoiceNo: originalInvoiceNo ?? this.originalInvoiceNo,
      originalInvoiceDate: originalInvoiceDate ?? this.originalInvoiceDate,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'invoice_no': invoiceNo,
        'quote_id': quoteId,
        'challan_id': challanId,
        'business_id': businessId,
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
        'paid_at': paidAt?.toIso8601String(),
        'payment_method': paymentMethod,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'reminder_sent_at': reminderSentAt?.toIso8601String(),
        'invoice_type': invoiceType.dbValue,
        'place_of_supply': placeOfSupply,
        'reverse_charge': reverseCharge ? 1 : 0,
        'customer_gstin': customerGstin,
        'irn': irn,
        'irn_ack_no': irnAckNo,
        'irn_ack_date': irnAckDate,
        'qr_code_data': qrCodeData,
        'ewb_no': ewbNo,
        'ewb_generated_at': ewbGeneratedAt?.toIso8601String(),
        'ewb_valid_until': ewbValidUntil?.toIso8601String(),
        'vehicle_no': vehicleNo,
        'transporter_name': transporterName,
        'transporter_gstin': transporterGstin,
        'transport_mode': transportMode,
        'distance_km': distanceKm,
        'freight_amt': freightAmt,
        'insurance_amt': insuranceAmt,
        'packing_amt': packingAmt,
        'delivery_address': deliveryAddress,
        'delivery_city': deliveryCity,
        'delivery_state': deliveryState,
        'delivery_pincode': deliveryPincode,
        'delivery_gstin': deliveryGstin,
        'original_invoice_id': originalInvoiceId,
        'original_invoice_no': originalInvoiceNo,
        'original_invoice_date': originalInvoiceDate,
      };

  factory Invoice.fromMap(Map<String, dynamic> map,
      {List<InvoiceItem> items = const []}) =>
      Invoice(
        id: map['id'] as int?,
        invoiceNo: map['invoice_no'] as String,
        quoteId: map['quote_id'] as int?,
        challanId: map['challan_id'] as int?,
        businessId: map['business_id'] as int?,
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
        paidAt: map['paid_at'] != null
            ? DateTime.parse(map['paid_at'] as String)
            : null,
        paymentMethod: map['payment_method'] as String?,
        notes: map['notes'] as String?,
        items: items,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        reminderSentAt: map['reminder_sent_at'] != null
            ? DateTime.parse(map['reminder_sent_at'] as String)
            : null,
        invoiceType: InvoiceTypeExt.fromDb(map['invoice_type'] as String?),
        placeOfSupply: map['place_of_supply'] as String?,
        reverseCharge: (map['reverse_charge'] as int? ?? 0) == 1,
        customerGstin: map['customer_gstin'] as String?,
        irn: map['irn'] as String?,
        irnAckNo: map['irn_ack_no'] as String?,
        irnAckDate: map['irn_ack_date'] as String?,
        qrCodeData: map['qr_code_data'] as String?,
        ewbNo: map['ewb_no'] as String?,
        ewbGeneratedAt: map['ewb_generated_at'] != null
            ? DateTime.parse(map['ewb_generated_at'] as String)
            : null,
        ewbValidUntil: map['ewb_valid_until'] != null
            ? DateTime.parse(map['ewb_valid_until'] as String)
            : null,
        vehicleNo: map['vehicle_no'] as String?,
        transporterName: map['transporter_name'] as String?,
        transporterGstin: map['transporter_gstin'] as String?,
        transportMode: map['transport_mode'] as String?,
        distanceKm: map['distance_km'] as int?,
        freightAmt: (map['freight_amt'] as num?)?.toDouble() ?? 0,
        insuranceAmt: (map['insurance_amt'] as num?)?.toDouble() ?? 0,
        packingAmt: (map['packing_amt'] as num?)?.toDouble() ?? 0,
        deliveryAddress: map['delivery_address'] as String?,
        deliveryCity: map['delivery_city'] as String?,
        deliveryState: map['delivery_state'] as String?,
        deliveryPincode: map['delivery_pincode'] as String?,
        deliveryGstin: map['delivery_gstin'] as String?,
        originalInvoiceId: map['original_invoice_id'] as int?,
        originalInvoiceNo: map['original_invoice_no'] as String?,
        originalInvoiceDate: map['original_invoice_date'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, invoiceNo, customerName, status, total, paidAmount, reminderSentAt];
}
