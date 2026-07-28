import 'package:equatable/equatable.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ChallanStatus { draft, dispatched, returned, converted, pendingNumber }

extension ChallanStatusExt on ChallanStatus {
  String get label => const {
    ChallanStatus.draft: 'Draft',
    ChallanStatus.dispatched: 'Dispatched',
    ChallanStatus.returned: 'Returned',
    ChallanStatus.converted: 'Converted',
    ChallanStatus.pendingNumber: 'Awaiting No.',
  }[this]!;

  String get dbValue => const {
    ChallanStatus.draft: 'draft',
    ChallanStatus.dispatched: 'dispatched',
    ChallanStatus.returned: 'returned',
    ChallanStatus.converted: 'converted',
    ChallanStatus.pendingNumber: 'pending_number',
  }[this]!;

  static ChallanStatus fromDb(String? v) {
    switch (v) {
      case 'dispatched':
        return ChallanStatus.dispatched;
      case 'returned':
        return ChallanStatus.returned;
      case 'converted':
        return ChallanStatus.converted;
      case 'pending_number':
        return ChallanStatus.pendingNumber;
      default:
        return ChallanStatus.draft;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

enum ChallanPurpose { supply, jobWork, branchTransfer, returnable, approval }

extension ChallanPurposeExt on ChallanPurpose {
  String get label => const {
    ChallanPurpose.supply: 'Supply',
    ChallanPurpose.jobWork: 'Job Work',
    ChallanPurpose.branchTransfer: 'Branch Transfer',
    ChallanPurpose.returnable: 'Returnable Goods',
    ChallanPurpose.approval: 'Approval / Trial',
  }[this]!;

  String get dbValue => const {
    ChallanPurpose.supply: 'supply',
    ChallanPurpose.jobWork: 'job_work',
    ChallanPurpose.branchTransfer: 'branch_transfer',
    ChallanPurpose.returnable: 'returnable',
    ChallanPurpose.approval: 'approval',
  }[this]!;

  static ChallanPurpose fromDb(String? v) {
    switch (v) {
      case 'job_work':
        return ChallanPurpose.jobWork;
      case 'branch_transfer':
        return ChallanPurpose.branchTransfer;
      case 'returnable':
        return ChallanPurpose.returnable;
      case 'approval':
        return ChallanPurpose.approval;
      default:
        return ChallanPurpose.supply;
    }
  }
}

// ── ChallanItem ───────────────────────────────────────────────────────────────

class ChallanItem extends Equatable {
  const ChallanItem({
    this.id,
    required this.challanId,
    required this.itemName,
    this.description,
    this.qty = 1,
    this.unit = 'PCS',
    this.unitPrice = 0,
    this.hsnCode,
    this.hsnOrSac = 'HSN',
    this.catalogItemId,
  });

  final int? id;
  final int challanId;
  final String itemName;
  final String? description;
  final double qty;
  final String unit;
  final double unitPrice;
  final String? hsnCode;
  final String hsnOrSac;

  /// FK to [item_catalog.id] — null for manually-typed items.
  final int? catalogItemId;

  double get lineTotal => qty * unitPrice;

  ChallanItem copyWith({
    int? id,
    int? challanId,
    String? itemName,
    String? description,
    double? qty,
    String? unit,
    double? unitPrice,
    String? hsnCode,
    String? hsnOrSac,
    int? catalogItemId,
  }) => ChallanItem(
    id: id ?? this.id,
    challanId: challanId ?? this.challanId,
    itemName: itemName ?? this.itemName,
    description: description ?? this.description,
    qty: qty ?? this.qty,
    unit: unit ?? this.unit,
    unitPrice: unitPrice ?? this.unitPrice,
    hsnCode: hsnCode ?? this.hsnCode,
    hsnOrSac: hsnOrSac ?? this.hsnOrSac,
    catalogItemId: catalogItemId ?? this.catalogItemId,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'challan_id': challanId,
    'item_name': itemName,
    'description': description,
    'qty': qty,
    'unit': unit,
    'unit_price': unitPrice,
    'line_total': lineTotal,
    'hsn_code': hsnCode,
    'hsn_or_sac': hsnOrSac,
    'catalog_item_id': catalogItemId,
  };

  factory ChallanItem.fromMap(Map<String, dynamic> map) => ChallanItem(
    id: map['id'] as int?,
    challanId: map['challan_id'] as int,
    itemName: map['item_name'] as String,
    description: map['description'] as String?,
    qty: (map['qty'] as num).toDouble(),
    unit: (map['unit'] as String?) ?? 'PCS',
    unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
    hsnCode: map['hsn_code'] as String?,
    hsnOrSac: (map['hsn_or_sac'] as String?) ?? 'HSN',
    catalogItemId: map['catalog_item_id'] as int?,
  );

  @override
  List<Object?> get props => [id, challanId, itemName, qty, unitPrice];
}

// ── DeliveryChallan ───────────────────────────────────────────────────────────

class DeliveryChallan extends Equatable {
  const DeliveryChallan({
    this.id,
    required this.challanNo,
    this.customerPartyId,
    required this.customerName,
    this.status = ChallanStatus.draft,
    required this.challanDate,
    this.dispatchDate,
    this.expectedReturnDate,
    this.purpose = ChallanPurpose.supply,
    this.subtotal = 0,
    this.notes,
    this.businessId,
    this.customerGstin,
    this.placeOfSupply,
    this.vehicleNo,
    this.transporterName,
    this.transportMode,
    this.distanceKm,
    this.convertedInvoiceId,
    this.ewbNo,
    this.deliveryAddress,
    this.deliveryCity,
    this.deliveryState,
    this.deliveryPincode,
    this.deliveryGstin,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String challanNo;
  final int? customerPartyId;
  final String customerName;
  final ChallanStatus status;
  final DateTime challanDate;
  final DateTime? dispatchDate;
  final DateTime? expectedReturnDate;
  final ChallanPurpose purpose;
  final double subtotal;
  final String? notes;
  final int? businessId;
  final String? customerGstin;
  final String? placeOfSupply;
  final String? vehicleNo;
  final String? transporterName;

  /// GSTN transport mode: '1'=Road '2'=Rail '3'=Air '4'=Ship
  final String? transportMode;
  final int? distanceKm;
  final int? convertedInvoiceId;
  final String? ewbNo;

  /// Delivery address snapshot — recorded at time of dispatch.
  final String? deliveryAddress;
  final String? deliveryCity;
  final String? deliveryState;
  final String? deliveryPincode;

  /// Delivery location GSTIN (may differ from customer billing GSTIN).
  final String? deliveryGstin;
  final List<ChallanItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isConverted => convertedInvoiceId != null;
  bool get hasEwb => ewbNo != null && ewbNo!.isNotEmpty;

  DeliveryChallan copyWith({
    int? id,
    String? challanNo,
    int? customerPartyId,
    String? customerName,
    ChallanStatus? status,
    DateTime? challanDate,
    DateTime? dispatchDate,
    DateTime? expectedReturnDate,
    ChallanPurpose? purpose,
    double? subtotal,
    String? notes,
    int? businessId,
    String? customerGstin,
    String? placeOfSupply,
    String? vehicleNo,
    String? transporterName,
    String? transportMode,
    int? distanceKm,
    int? convertedInvoiceId,
    String? ewbNo,
    String? deliveryAddress,
    String? deliveryCity,
    String? deliveryState,
    String? deliveryPincode,
    String? deliveryGstin,
    List<ChallanItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DeliveryChallan(
    id: id ?? this.id,
    challanNo: challanNo ?? this.challanNo,
    customerPartyId: customerPartyId ?? this.customerPartyId,
    customerName: customerName ?? this.customerName,
    status: status ?? this.status,
    challanDate: challanDate ?? this.challanDate,
    dispatchDate: dispatchDate ?? this.dispatchDate,
    expectedReturnDate: expectedReturnDate ?? this.expectedReturnDate,
    purpose: purpose ?? this.purpose,
    subtotal: subtotal ?? this.subtotal,
    notes: notes ?? this.notes,
    businessId: businessId ?? this.businessId,
    customerGstin: customerGstin ?? this.customerGstin,
    placeOfSupply: placeOfSupply ?? this.placeOfSupply,
    vehicleNo: vehicleNo ?? this.vehicleNo,
    transporterName: transporterName ?? this.transporterName,
    transportMode: transportMode ?? this.transportMode,
    distanceKm: distanceKm ?? this.distanceKm,
    convertedInvoiceId: convertedInvoiceId ?? this.convertedInvoiceId,
    ewbNo: ewbNo ?? this.ewbNo,
    deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    deliveryCity: deliveryCity ?? this.deliveryCity,
    deliveryState: deliveryState ?? this.deliveryState,
    deliveryPincode: deliveryPincode ?? this.deliveryPincode,
    deliveryGstin: deliveryGstin ?? this.deliveryGstin,
    items: items ?? this.items,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'challan_no': challanNo,
    'customer_party_id': customerPartyId,
    'customer_name': customerName,
    'status': status.dbValue,
    'challan_date': challanDate.toIso8601String(),
    'dispatch_date': dispatchDate?.toIso8601String(),
    'expected_return_date': expectedReturnDate?.toIso8601String(),
    'purpose': purpose.dbValue,
    'subtotal': subtotal,
    'notes': notes,
    'business_id': businessId,
    'customer_gstin': customerGstin,
    'place_of_supply': placeOfSupply,
    'vehicle_no': vehicleNo,
    'transporter_name': transporterName,
    'transport_mode': transportMode,
    'distance_km': distanceKm,
    'converted_invoice_id': convertedInvoiceId,
    'ewb_no': ewbNo,
    'delivery_address': deliveryAddress,
    'delivery_city': deliveryCity,
    'delivery_state': deliveryState,
    'delivery_pincode': deliveryPincode,
    'delivery_gstin': deliveryGstin,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory DeliveryChallan.fromMap(
    Map<String, dynamic> map, {
    List<ChallanItem> items = const [],
  }) => DeliveryChallan(
    id: map['id'] as int?,
    challanNo: map['challan_no'] as String,
    customerPartyId: map['customer_party_id'] as int?,
    customerName: map['customer_name'] as String,
    status: ChallanStatusExt.fromDb(map['status'] as String?),
    challanDate: DateTime.parse(map['challan_date'] as String),
    dispatchDate: map['dispatch_date'] != null
        ? DateTime.parse(map['dispatch_date'] as String)
        : null,
    expectedReturnDate: map['expected_return_date'] != null
        ? DateTime.parse(map['expected_return_date'] as String)
        : null,
    purpose: ChallanPurposeExt.fromDb(map['purpose'] as String?),
    subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
    notes: map['notes'] as String?,
    businessId: map['business_id'] as int?,
    customerGstin: map['customer_gstin'] as String?,
    placeOfSupply: map['place_of_supply'] as String?,
    vehicleNo: map['vehicle_no'] as String?,
    transporterName: map['transporter_name'] as String?,
    transportMode: map['transport_mode'] as String?,
    distanceKm: map['distance_km'] as int?,
    convertedInvoiceId: map['converted_invoice_id'] as int?,
    ewbNo: map['ewb_no'] as String?,
    deliveryAddress: map['delivery_address'] as String?,
    deliveryCity: map['delivery_city'] as String?,
    deliveryState: map['delivery_state'] as String?,
    deliveryPincode: map['delivery_pincode'] as String?,
    deliveryGstin: map['delivery_gstin'] as String?,
    items: items,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );

  @override
  List<Object?> get props => [
    id,
    challanNo,
    customerName,
    status,
    subtotal,
    updatedAt,
  ];
}
