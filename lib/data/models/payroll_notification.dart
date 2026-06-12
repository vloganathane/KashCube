/// A payroll notification delivered from a primary (employer) device to a
/// secondary (employee) device via the sync outbox protocol.
class PayrollNotification {
  const PayrollNotification({
    required this.id,
    required this.notificationId,
    required this.sourceIdentityId,
    required this.businessName,
    required this.amount,
    required this.currency,
    this.referenceLabel,
    required this.paidOn,
    required this.receivedAt,
    required this.status,
    this.createdTransactionId,
  });

  final int id;
  final String notificationId;
  final String sourceIdentityId;
  final String businessName;
  final double amount;
  final String currency;
  final String? referenceLabel;
  final String paidOn;
  final DateTime receivedAt;
  final String status; // 'pending' | 'added' | 'dismissed'
  final int? createdTransactionId;

  factory PayrollNotification.fromMap(Map<String, dynamic> map) =>
      PayrollNotification(
        id: map['id'] as int,
        notificationId: map['notification_id'] as String,
        sourceIdentityId: map['source_identity_id'] as String,
        businessName: map['business_name'] as String,
        amount: (map['amount'] as num).toDouble(),
        currency: map['currency'] as String? ?? 'INR',
        referenceLabel: map['reference_label'] as String?,
        paidOn: map['paid_on'] as String,
        receivedAt: DateTime.parse(map['received_at'] as String),
        status: map['status'] as String,
        createdTransactionId: map['created_transaction_id'] as int?,
      );

  PayrollNotification copyWith({String? status, int? createdTransactionId}) =>
      PayrollNotification(
        id: id,
        notificationId: notificationId,
        sourceIdentityId: sourceIdentityId,
        businessName: businessName,
        amount: amount,
        currency: currency,
        referenceLabel: referenceLabel,
        paidOn: paidOn,
        receivedAt: receivedAt,
        status: status ?? this.status,
        createdTransactionId: createdTransactionId ?? this.createdTransactionId,
      );
}
