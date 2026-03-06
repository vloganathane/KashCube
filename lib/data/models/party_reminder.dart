import 'package:equatable/equatable.dart';

/// Channels through which a payment reminder can be sent.
enum ReminderChannel {
  whatsapp,
  sms,
  email;

  String get label => switch (this) {
        whatsapp => 'WhatsApp',
        sms => 'SMS',
        email => 'Email',
      };

  String get iconName => switch (this) {
        whatsapp => 'chat',
        sms => 'message',
        email => 'email',
      };

  static ReminderChannel fromString(String s) => switch (s) {
        'sms' => sms,
        'email' => email,
        _ => whatsapp,
      };
}

/// Represents a single payment reminder sent to a party.
class PartyReminder extends Equatable {
  const PartyReminder({
    this.id,
    required this.partyName,
    required this.channel,
    required this.message,
    this.invoiceRefs,
    this.invoiceCount = 0,
    this.totalOutstanding,
    this.businessId,
    required this.sentAt,
  });

  final int? id;

  /// Matches [Party.name] — no FK so reminders survive party renames/deletes.
  final String partyName;

  /// Delivery channel (whatsapp / sms / email).
  final ReminderChannel channel;

  /// Full message text that was sent.
  final String message;

  /// Comma-separated invoice numbers included in the reminder (may be null).
  final String? invoiceRefs;

  /// Number of invoices referenced.
  final int invoiceCount;

  /// Total outstanding amount at the time of sending.
  final double? totalOutstanding;

  /// Business context for this reminder. `null` = personal.
  final int? businessId;

  /// UTC timestamp of when the reminder was dispatched.
  final DateTime sentAt;

  // ── Helpers ──────────────────────────────────────────────────────────────

  List<String> get invoiceRefList =>
      invoiceRefs?.split(',').where((s) => s.isNotEmpty).toList() ?? [];

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory PartyReminder.fromMap(Map<String, dynamic> map) => PartyReminder(
        id: map['id'] as int?,
        partyName: map['party_name'] as String,
        channel:
            ReminderChannel.fromString(map['channel'] as String? ?? 'whatsapp'),
        message: map['message'] as String? ?? '',
        invoiceRefs: map['invoice_refs'] as String?,
        invoiceCount: (map['invoice_count'] as int?) ?? 0,
        totalOutstanding:
            (map['total_outstanding'] as num?)?.toDouble(),
        businessId: map['business_id'] as int?,
        sentAt: DateTime.parse(map['sent_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'party_name': partyName,
        'channel': channel.name,
        'message': message,
        'invoice_refs': invoiceRefs,
        'invoice_count': invoiceCount,
        'total_outstanding': totalOutstanding,
        'business_id': businessId,
        'sent_at': sentAt.toIso8601String(),
      };

  PartyReminder copyWith({
    int? id,
    String? partyName,
    ReminderChannel? channel,
    String? message,
    String? invoiceRefs,
    int? invoiceCount,
    double? totalOutstanding,
    int? businessId,
    DateTime? sentAt,
  }) =>
      PartyReminder(
        id: id ?? this.id,
        partyName: partyName ?? this.partyName,
        channel: channel ?? this.channel,
        message: message ?? this.message,
        invoiceRefs: invoiceRefs ?? this.invoiceRefs,
        invoiceCount: invoiceCount ?? this.invoiceCount,
        totalOutstanding: totalOutstanding ?? this.totalOutstanding,
        businessId: businessId ?? this.businessId,
        sentAt: sentAt ?? this.sentAt,
      );

  @override
  List<Object?> get props => [
        id,
        partyName,
        channel,
        message,
        invoiceRefs,
        invoiceCount,
        totalOutstanding,
        businessId,
        sentAt,
      ];
}
