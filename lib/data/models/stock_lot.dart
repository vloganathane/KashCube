import 'package:equatable/equatable.dart';

enum StockLotStatus {
  active,
  depleted,
  expired,
  blocked;
}

/// A physical lot/batch of an inventory item received via a purchase bill.
///
/// FEFO (First Expired First Out) ordering uses [expiryDate]:
/// - Non-null expiry lots are consumed before no-expiry lots.
/// - Within expiry lots, earliest expiry is consumed first.
class StockLot extends Equatable {
  const StockLot({
    this.id,
    required this.businessId,
    required this.itemId,
    this.purchaseBillId,
    this.lotNo,
    this.expiryDate,
    this.mfgDate,
    required this.unitCost,
    required this.qtyIn,
    required this.qtyRemaining,
    this.status = StockLotStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int businessId;
  final int itemId;

  /// FK to the purchase bill that created this lot (nullable for manual lots).
  final int? purchaseBillId;

  /// Batch / Lot number as printed on the packaging.
  final String? lotNo;

  /// Expiry date (date only; time is irrelevant for lot tracking).
  final DateTime? expiryDate;

  /// Manufacturing / production date.
  final DateTime? mfgDate;

  /// Per-unit cost at time of purchase.
  final double unitCost;

  /// Total quantity received.
  final double qtyIn;

  /// Current remaining quantity available for allocation.
  final double qtyRemaining;

  final StockLotStatus status;

  final String? notes;

  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isDepleted =>
      qtyRemaining <= 0 || status == StockLotStatus.depleted;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  /// Days until expiry (negative if already expired, null if no expiry set).
  int? get daysToExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'business_id': businessId,
        'item_id': itemId,
        if (purchaseBillId != null) 'purchase_bill_id': purchaseBillId,
        'lot_no': lotNo,
        // Store as ISO date string (date-only: YYYY-MM-DD)
        'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
        'mfg_date': mfgDate?.toIso8601String().substring(0, 10),
        'unit_cost': unitCost,
        'qty_in': qtyIn,
        'qty_remaining': qtyRemaining,
        'status': status.name,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory StockLot.fromMap(Map<String, dynamic> m) => StockLot(
        id: m['id'] as int?,
        businessId: m['business_id'] as int,
        itemId: m['item_id'] as int,
        purchaseBillId: m['purchase_bill_id'] as int?,
        lotNo: m['lot_no'] as String?,
        expiryDate: m['expiry_date'] != null
            ? DateTime.tryParse(m['expiry_date'] as String)
            : null,
        mfgDate: m['mfg_date'] != null
            ? DateTime.tryParse(m['mfg_date'] as String)
            : null,
        unitCost: (m['unit_cost'] as num).toDouble(),
        qtyIn: (m['qty_in'] as num).toDouble(),
        qtyRemaining: (m['qty_remaining'] as num).toDouble(),
        status: StockLotStatus.values.firstWhere(
          (s) => s.name == (m['status'] as String?),
          orElse: () => StockLotStatus.active,
        ),
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [
        id,
        businessId,
        itemId,
        lotNo,
        expiryDate,
        qtyRemaining,
        status,
      ];
}
