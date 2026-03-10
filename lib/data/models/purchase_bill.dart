import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PurchaseBillStatus { unpaid, paid, partiallyPaid }

extension PurchaseBillStatusExt on PurchaseBillStatus {
  String get label => const {
        PurchaseBillStatus.unpaid: 'Unpaid',
        PurchaseBillStatus.paid: 'Paid',
        PurchaseBillStatus.partiallyPaid: 'Partial',
      }[this]!;

  String get dbValue {
    switch (this) {
      case PurchaseBillStatus.partiallyPaid:
        return 'partially_paid';
      default:
        return name;
    }
  }

  static PurchaseBillStatus fromDb(String? v) {
    switch (v) {
      case 'paid':
        return PurchaseBillStatus.paid;
      case 'partially_paid':
        return PurchaseBillStatus.partiallyPaid;
      default:
        return PurchaseBillStatus.unpaid;
    }
  }
}

// ---------------------------------------------------------------------------
// ITC eligibility
// ---------------------------------------------------------------------------

/// Whether the Input Tax Credit on this bill can be availed.
enum ItcEligibility {
  /// Normal NRC/RC purchase — ITC fully claimable.
  eligible,

  /// Excluded category under s.17(5) — ITC blocked at source.
  blocked,

  /// User opted to mark as ineligible for other reasons.
  ineligible,
}

extension ItcEligibilityExt on ItcEligibility {
  String get label => const {
        ItcEligibility.eligible: 'Eligible',
        ItcEligibility.blocked: 'Blocked (s.17(5))',
        ItcEligibility.ineligible: 'Ineligible',
      }[this]!;

  String get dbValue => name;

  static ItcEligibility fromDb(String? v) {
    switch (v) {
      case 'blocked':
        return ItcEligibility.blocked;
      case 'ineligible':
        return ItcEligibility.ineligible;
      default:
        return ItcEligibility.eligible;
    }
  }
}

// ---------------------------------------------------------------------------
// ITC block reason (s.17(5) categories + user-defined)
// ---------------------------------------------------------------------------

enum ItcBlockReason {
  motorVehicle,
  foodBeverages,
  clubMembership,
  personalUse,
  construction,
  worksContract,
  other,
}

extension ItcBlockReasonExt on ItcBlockReason {
  String get label => const {
        ItcBlockReason.motorVehicle: 'Motor Vehicle',
        ItcBlockReason.foodBeverages: 'Food & Beverages',
        ItcBlockReason.clubMembership: 'Club Membership',
        ItcBlockReason.personalUse: 'Personal Use',
        ItcBlockReason.construction: 'Construction (immovable)',
        ItcBlockReason.worksContract: 'Works Contract',
        ItcBlockReason.other: 'Other',
      }[this]!;

  String get dbValue => const {
        ItcBlockReason.motorVehicle: 'motor_vehicle',
        ItcBlockReason.foodBeverages: 'food_beverages',
        ItcBlockReason.clubMembership: 'club_membership',
        ItcBlockReason.personalUse: 'personal_use',
        ItcBlockReason.construction: 'construction',
        ItcBlockReason.worksContract: 'works_contract',
        ItcBlockReason.other: 'other',
      }[this]!;

  static ItcBlockReason? fromDb(String? v) {
    switch (v) {
      case 'motor_vehicle':
        return ItcBlockReason.motorVehicle;
      case 'food_beverages':
        return ItcBlockReason.foodBeverages;
      case 'club_membership':
        return ItcBlockReason.clubMembership;
      case 'personal_use':
        return ItcBlockReason.personalUse;
      case 'construction':
        return ItcBlockReason.construction;
      case 'works_contract':
        return ItcBlockReason.worksContract;
      case 'other':
        return ItcBlockReason.other;
      default:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// ITC reversal reason (used when availed ITC is later reversed)
// ---------------------------------------------------------------------------

enum ItcReversalReason {
  rule42,     // Input/capital goods used for exempt + taxable supplies
  rule43,     // Capital goods — partial exemption
  section17_5, // Blocked category belatedly identified
  other,
}

extension ItcReversalReasonExt on ItcReversalReason {
  String get label => const {
        ItcReversalReason.rule42: 'Rule 42',
        ItcReversalReason.rule43: 'Rule 43',
        ItcReversalReason.section17_5: 'Section 17(5)',
        ItcReversalReason.other: 'Other',
      }[this]!;

  String get dbValue => const {
        ItcReversalReason.rule42: 'rule_42',
        ItcReversalReason.rule43: 'rule_43',
        ItcReversalReason.section17_5: 'section_17_5',
        ItcReversalReason.other: 'other',
      }[this]!;

  static ItcReversalReason? fromDb(String? v) {
    switch (v) {
      case 'rule_42':
        return ItcReversalReason.rule42;
      case 'rule_43':
        return ItcReversalReason.rule43;
      case 'section_17_5':
        return ItcReversalReason.section17_5;
      case 'other':
        return ItcReversalReason.other;
      default:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// PurchaseBillItem
// ---------------------------------------------------------------------------

class PurchaseBillItem extends Equatable {
  const PurchaseBillItem({
    this.id,
    required this.billId,
    required this.itemName,
    this.description,
    this.qty = 1,
    required this.unitPrice,
    this.taxPct = 0,
    this.discountPct = 0,
    required this.lineTotal,
    this.igstAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.hsnCode,
    this.unit = 'PCS',
    this.hsnOrSac = 'HSN',
  });

  final int? id;
  final int billId;
  final String itemName;
  final String? description;
  final double qty;
  final double unitPrice;
  final double taxPct;
  final double discountPct;
  final double lineTotal;
  final double igstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final String? hsnCode;
  final String unit;
  final String hsnOrSac;

  PurchaseBillItem copyWith({
    int? id,
    int? billId,
    String? itemName,
    String? description,
    double? qty,
    double? unitPrice,
    double? taxPct,
    double? discountPct,
    double? lineTotal,
    double? igstAmount,
    double? cgstAmount,
    double? sgstAmount,
    String? hsnCode,
    String? unit,
    String? hsnOrSac,
  }) =>
      PurchaseBillItem(
        id: id ?? this.id,
        billId: billId ?? this.billId,
        itemName: itemName ?? this.itemName,
        description: description ?? this.description,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        taxPct: taxPct ?? this.taxPct,
        discountPct: discountPct ?? this.discountPct,
        lineTotal: lineTotal ?? this.lineTotal,
        igstAmount: igstAmount ?? this.igstAmount,
        cgstAmount: cgstAmount ?? this.cgstAmount,
        sgstAmount: sgstAmount ?? this.sgstAmount,
        hsnCode: hsnCode ?? this.hsnCode,
        unit: unit ?? this.unit,
        hsnOrSac: hsnOrSac ?? this.hsnOrSac,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'bill_id': billId,
        'item_name': itemName,
        'description': description,
        'qty': qty,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'discount_pct': discountPct,
        'line_total': lineTotal,
        'igst_amount': igstAmount,
        'cgst_amount': cgstAmount,
        'sgst_amount': sgstAmount,
        'hsn_code': hsnCode,
        'unit': unit,
        'hsn_or_sac': hsnOrSac,
      };

  factory PurchaseBillItem.fromMap(Map<String, dynamic> m) => PurchaseBillItem(
        id: m['id'] as int?,
        billId: m['bill_id'] as int,
        itemName: m['item_name'] as String,
        description: m['description'] as String?,
        qty: (m['qty'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        taxPct: (m['tax_pct'] as num?)?.toDouble() ?? 0,
        discountPct: (m['discount_pct'] as num?)?.toDouble() ?? 0,
        lineTotal: (m['line_total'] as num).toDouble(),
        igstAmount: (m['igst_amount'] as num?)?.toDouble() ?? 0,
        cgstAmount: (m['cgst_amount'] as num?)?.toDouble() ?? 0,
        sgstAmount: (m['sgst_amount'] as num?)?.toDouble() ?? 0,
        hsnCode: m['hsn_code'] as String?,
        unit: (m['unit'] as String?) ?? 'PCS',
        hsnOrSac: (m['hsn_or_sac'] as String?) ?? 'HSN',
      );

  @override
  List<Object?> get props => [
        id, billId, itemName, description, qty, unitPrice, taxPct,
        discountPct, lineTotal, igstAmount, cgstAmount, sgstAmount,
        hsnCode, unit, hsnOrSac,
      ];
}

// ---------------------------------------------------------------------------
// PurchaseBill
// ---------------------------------------------------------------------------

class PurchaseBill extends Equatable {
  const PurchaseBill({
    this.id,
    required this.businessId,
    required this.billNo,
    this.vendorPartyId,
    required this.vendorName,
    this.vendorGstin,
    required this.billDate,
    this.dueDate,
    this.placeOfSupply,
    this.reverseCharge = false,
    this.subtotal = 0,
    this.igstAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.cessAmount = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.itcEligibility = ItcEligibility.eligible,
    this.itcBlockReason,
    this.itcAvailed = false,
    this.itcReversalReason,
    this.notes,
    this.attachmentPath,
    this.status = PurchaseBillStatus.unpaid,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  final int? id;
  final int businessId;

  /// Vendor's original bill / invoice number.
  final String billNo;
  final int? vendorPartyId;
  final String vendorName;
  final String? vendorGstin;
  final DateTime billDate;
  final DateTime? dueDate;

  /// 2-digit state code (place of supply).
  final String? placeOfSupply;

  /// Whether this bill is subject to Reverse Charge Mechanism (RCM).
  final bool reverseCharge;

  // ── Amounts ──────────────────────────────────────────────────────────────
  final double subtotal;
  final double igstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double cessAmount;
  final double taxTotal;
  final double total;
  final double paidAmount;

  // ── ITC ──────────────────────────────────────────────────────────────────
  final ItcEligibility itcEligibility;
  final ItcBlockReason? itcBlockReason;

  /// Whether ITC has been claimed on this bill in GSTR-3B.
  final bool itcAvailed;

  /// If ITC was reversed after availing, reason for reversal.
  final ItcReversalReason? itcReversalReason;

  // ── Metadata ─────────────────────────────────────────────────────────────
  final String? notes;
  final String? attachmentPath;
  final PurchaseBillStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Loaded items — not persisted directly on the bill row.
  final List<PurchaseBillItem> items;

  // ── Derived ──────────────────────────────────────────────────────────────
  double get balanceDue => total - paidAmount;
  bool get isFullyPaid => paidAmount >= total;

  /// Total eligible ITC (IGST + CGST + SGST) on this bill.
  double get itcTotal => itcEligibility == ItcEligibility.eligible
      ? igstAmount + cgstAmount + sgstAmount
      : 0;

  PurchaseBill copyWith({
    int? id,
    int? businessId,
    String? billNo,
    int? vendorPartyId,
    String? vendorName,
    String? vendorGstin,
    DateTime? billDate,
    DateTime? dueDate,
    String? placeOfSupply,
    bool? reverseCharge,
    double? subtotal,
    double? igstAmount,
    double? cgstAmount,
    double? sgstAmount,
    double? cessAmount,
    double? taxTotal,
    double? total,
    double? paidAmount,
    ItcEligibility? itcEligibility,
    ItcBlockReason? itcBlockReason,
    bool? itcAvailed,
    ItcReversalReason? itcReversalReason,
    String? notes,
    String? attachmentPath,
    PurchaseBillStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PurchaseBillItem>? items,
  }) =>
      PurchaseBill(
        id: id ?? this.id,
        businessId: businessId ?? this.businessId,
        billNo: billNo ?? this.billNo,
        vendorPartyId: vendorPartyId ?? this.vendorPartyId,
        vendorName: vendorName ?? this.vendorName,
        vendorGstin: vendorGstin ?? this.vendorGstin,
        billDate: billDate ?? this.billDate,
        dueDate: dueDate ?? this.dueDate,
        placeOfSupply: placeOfSupply ?? this.placeOfSupply,
        reverseCharge: reverseCharge ?? this.reverseCharge,
        subtotal: subtotal ?? this.subtotal,
        igstAmount: igstAmount ?? this.igstAmount,
        cgstAmount: cgstAmount ?? this.cgstAmount,
        sgstAmount: sgstAmount ?? this.sgstAmount,
        cessAmount: cessAmount ?? this.cessAmount,
        taxTotal: taxTotal ?? this.taxTotal,
        total: total ?? this.total,
        paidAmount: paidAmount ?? this.paidAmount,
        itcEligibility: itcEligibility ?? this.itcEligibility,
        itcBlockReason: itcBlockReason ?? this.itcBlockReason,
        itcAvailed: itcAvailed ?? this.itcAvailed,
        itcReversalReason: itcReversalReason ?? this.itcReversalReason,
        notes: notes ?? this.notes,
        attachmentPath: attachmentPath ?? this.attachmentPath,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        items: items ?? this.items,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'business_id': businessId,
        'bill_no': billNo,
        'vendor_party_id': vendorPartyId,
        'vendor_name': vendorName,
        'vendor_gstin': vendorGstin,
        'bill_date': billDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'place_of_supply': placeOfSupply,
        'reverse_charge': reverseCharge ? 1 : 0,
        'subtotal': subtotal,
        'igst_amount': igstAmount,
        'cgst_amount': cgstAmount,
        'sgst_amount': sgstAmount,
        'cess_amount': cessAmount,
        'tax_total': taxTotal,
        'total': total,
        'paid_amount': paidAmount,
        'itc_eligibility': itcEligibility.dbValue,
        'itc_block_reason': itcBlockReason?.dbValue,
        'itc_availed': itcAvailed ? 1 : 0,
        'itc_reversal_reason': itcReversalReason?.dbValue,
        'notes': notes,
        'attachment_path': attachmentPath,
        'status': status.dbValue,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PurchaseBill.fromMap(
    Map<String, dynamic> m, {
    List<PurchaseBillItem> items = const [],
  }) =>
      PurchaseBill(
        id: m['id'] as int?,
        businessId: m['business_id'] as int,
        billNo: m['bill_no'] as String,
        vendorPartyId: m['vendor_party_id'] as int?,
        vendorName: m['vendor_name'] as String,
        vendorGstin: m['vendor_gstin'] as String?,
        billDate: DateTime.parse(m['bill_date'] as String),
        dueDate: m['due_date'] != null
            ? DateTime.parse(m['due_date'] as String)
            : null,
        placeOfSupply: m['place_of_supply'] as String?,
        reverseCharge: (m['reverse_charge'] as int? ?? 0) == 1,
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        igstAmount: (m['igst_amount'] as num?)?.toDouble() ?? 0,
        cgstAmount: (m['cgst_amount'] as num?)?.toDouble() ?? 0,
        sgstAmount: (m['sgst_amount'] as num?)?.toDouble() ?? 0,
        cessAmount: (m['cess_amount'] as num?)?.toDouble() ?? 0,
        taxTotal: (m['tax_total'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        paidAmount: (m['paid_amount'] as num?)?.toDouble() ?? 0,
        itcEligibility:
            ItcEligibilityExt.fromDb(m['itc_eligibility'] as String?),
        itcBlockReason:
            ItcBlockReasonExt.fromDb(m['itc_block_reason'] as String?),
        itcAvailed: (m['itc_availed'] as int? ?? 0) == 1,
        itcReversalReason:
            ItcReversalReasonExt.fromDb(m['itc_reversal_reason'] as String?),
        notes: m['notes'] as String?,
        attachmentPath: m['attachment_path'] as String?,
        status: PurchaseBillStatusExt.fromDb(m['status'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        items: items,
      );

  @override
  List<Object?> get props => [
        id, businessId, billNo, vendorPartyId, vendorName, vendorGstin,
        billDate, dueDate, placeOfSupply, reverseCharge,
        subtotal, igstAmount, cgstAmount, sgstAmount, cessAmount,
        taxTotal, total, paidAmount,
        itcEligibility, itcBlockReason, itcAvailed, itcReversalReason,
        notes, attachmentPath, status, createdAt, updatedAt,
      ];
}
