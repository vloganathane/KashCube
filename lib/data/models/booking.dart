import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum BookingType { business, personal }

extension BookingTypeExt on BookingType {
  String get label {
    switch (this) {
      case BookingType.business:
        return 'Booking';
      case BookingType.personal:
        return 'Schedule';
    }
  }

  String get dbValue => name; // 'business' or 'personal'

  static BookingType fromDb(String? v) {
    if (v == 'personal') return BookingType.personal;
    return BookingType.business; // default
  }
}

enum BookingStatus { pending, confirmed, completed, cancelled, noShow }

extension BookingStatusExt on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.noShow:
        return 'No-show';
    }
  }

  String get dbValue {
    switch (this) {
      case BookingStatus.noShow:
        return 'no_show';
      default:
        return name;
    }
  }

  static BookingStatus fromDb(String? v) {
    switch (v) {
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
        return BookingStatus.cancelled;
      case 'no_show':
        return BookingStatus.noShow;
      default:
        return BookingStatus.pending;
    }
  }
}

// ---------------------------------------------------------------------------
// Booking Model
// ---------------------------------------------------------------------------

class Booking extends Equatable {
  const Booking({
    this.id,
    this.customerPartyId,
    required this.customerName,
    this.serviceItemId,
    required this.serviceName,
    required this.startDatetime,
    this.endDatetime,
    this.durationMinutes,
    this.status = BookingStatus.pending,
    this.bookingType = BookingType.business,
    required this.totalAmount,
    this.advanceAmount = 0,
    this.invoiceId,
    this.notes,
    this.notificationScheduledAt,
    this.confirmedAt,
    this.businessId,
    this.bookingRef,
    this.createdAt,
    this.updatedAt,
    this.reminderSentAt,
    this.paidAmount = 0,
  });

  final int? id;
  final int? customerPartyId;
  final String customerName;
  final int? serviceItemId;
  final String serviceName;
  final DateTime startDatetime;
  final DateTime? endDatetime;
  final int? durationMinutes;
  final BookingStatus status;
  final BookingType bookingType;
  final double totalAmount;
  final double advanceAmount;

  /// Running total of all payments received (advance + subsequent payments).
  /// Mirrors [Invoice.paidAmount]. Set to [advanceAmount] at booking creation.
  final double paidAmount;
  final int? invoiceId;
  final String? notes;
  final DateTime? notificationScheduledAt;
  final DateTime? confirmedAt;
  final int? businessId;
  final String? bookingRef;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Timestamp of the last manual reminder sent (WhatsApp/SMS/Email).
  final DateTime? reminderSentAt;

  /// Outstanding balance = [totalAmount] − [paidAmount].
  double get balanceDue => (totalAmount - paidAmount).clamp(0, double.infinity);

  /// True when [paidAmount] covers the full [totalAmount].
  bool get isFullyPaid => paidAmount >= totalAmount;

  Booking copyWith({
    int? id,
    int? customerPartyId,
    String? customerName,
    int? serviceItemId,
    String? serviceName,
    DateTime? startDatetime,
    DateTime? endDatetime,
    int? durationMinutes,
    BookingStatus? status,
    BookingType? bookingType,
    double? totalAmount,
    double? advanceAmount,
    double? paidAmount,
    int? invoiceId,
    String? notes,
    DateTime? notificationScheduledAt,
    DateTime? confirmedAt,
    int? businessId,
    String? bookingRef,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reminderSentAt,
  }) {
    return Booking(
      id: id ?? this.id,
      customerPartyId: customerPartyId ?? this.customerPartyId,
      customerName: customerName ?? this.customerName,
      serviceItemId: serviceItemId ?? this.serviceItemId,
      serviceName: serviceName ?? this.serviceName,
      startDatetime: startDatetime ?? this.startDatetime,
      endDatetime: endDatetime ?? this.endDatetime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      bookingType: bookingType ?? this.bookingType,
      totalAmount: totalAmount ?? this.totalAmount,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      invoiceId: invoiceId ?? this.invoiceId,
      notes: notes ?? this.notes,
      notificationScheduledAt:
          notificationScheduledAt ?? this.notificationScheduledAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      businessId: businessId ?? this.businessId,
      bookingRef: bookingRef ?? this.bookingRef,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_party_id': customerPartyId,
      'customer_name': customerName,
      'service_item_id': serviceItemId,
      'service_name': serviceName,
      'start_datetime': startDatetime.toIso8601String(),
      'end_datetime': endDatetime?.toIso8601String(),
      'duration_minutes': durationMinutes,
      'status': status.dbValue,
      'booking_type': bookingType.dbValue,
      'total_amount': totalAmount,
      'advance_amount': advanceAmount,
      'paid_amount': paidAmount,
      'invoice_id': invoiceId,
      'notes': notes,
      'notification_scheduled_at': notificationScheduledAt?.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
      'business_id': businessId,
      'booking_ref': bookingRef,
      'created_at':
          createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'reminder_sent_at': reminderSentAt?.toIso8601String(),
    };
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as int?,
      customerPartyId: map['customer_party_id'] as int?,
      customerName: map['customer_name'] as String,
      serviceItemId: map['service_item_id'] as int?,
      serviceName: map['service_name'] as String,
      startDatetime: DateTime.parse(map['start_datetime'] as String),
      endDatetime: map['end_datetime'] != null
          ? DateTime.parse(map['end_datetime'] as String)
          : null,
      durationMinutes: map['duration_minutes'] as int?,
      status: BookingStatusExt.fromDb(map['status'] as String?),
      bookingType: BookingTypeExt.fromDb(map['booking_type'] as String?),
      totalAmount: (map['total_amount'] as num).toDouble(),
      advanceAmount: (map['advance_amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      invoiceId: map['invoice_id'] as int?,
      notes: map['notes'] as String?,
      notificationScheduledAt: map['notification_scheduled_at'] != null
          ? DateTime.parse(map['notification_scheduled_at'] as String)
          : null,
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.parse(map['confirmed_at'] as String)
          : null,
      businessId: map['business_id'] as int?,
      bookingRef: map['booking_ref'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      reminderSentAt: map['reminder_sent_at'] != null
          ? DateTime.parse(map['reminder_sent_at'] as String)
          : null,
    );
  }

  /// Checks if booking is multi-day (reservation vs appointment)
  bool get isMultiDay {
    if (endDatetime == null) return false;
    return endDatetime!.difference(startDatetime).inHours >= 24;
  }

  /// Checks if booking is overdue (start time passed, still pending)
  bool get isOverdue {
    return status == BookingStatus.pending &&
        DateTime.now().isAfter(startDatetime);
  }

  /// Returns formatted duration string.
  /// ≥ 1440 min (24 h) → "X nights",  ≥ 60 min → "X hrs",  else → "X min"
  String get durationLabel {
    if (durationMinutes == null) return '';
    if (durationMinutes! >= 1440) {
      final nights = (durationMinutes! / 1440).round();
      return '$nights ${nights == 1 ? 'night' : 'nights'}';
    }
    if (durationMinutes! < 60) {
      return '$durationMinutes min';
    }
    final hours = durationMinutes! / 60;
    if (hours.truncate() == hours) {
      return '${hours.toInt()} hrs';
    }
    return '${hours.toStringAsFixed(1)} hrs';
  }

  @override
  List<Object?> get props => [
    id,
    customerPartyId,
    customerName,
    serviceItemId,
    serviceName,
    startDatetime,
    endDatetime,
    durationMinutes,
    status,
    bookingType,
    totalAmount,
    advanceAmount,
    paidAmount,
    invoiceId,
    notes,
    notificationScheduledAt,
    confirmedAt,
    businessId,
    bookingRef,
    createdAt,
    updatedAt,
  ];
}
