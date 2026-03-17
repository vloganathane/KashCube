/// Invoice state-machine event — append-only audit log.
///
/// One row per status transition on an invoice. Used to reconstruct the
/// canonical `status` when two devices sync conflicting updates to the same
/// invoice (the "won" state comes from the highest-priority event per the
/// state machine: draft→sent→viewed→partial→paid / cancelled beats all).
class InvoiceEvent {
  const InvoiceEvent({
    this.id,
    required this.invoiceId,
    required this.eventType,
    this.eventData,
    required this.occurredAt,
    required this.deviceId,
    required this.syncId,
  });

  final int? id;

  /// Matches `invoices.sync_id` (not the integer PK).
  final String invoiceId;

  /// E.g. `'status_changed'`, `'payment_recorded'`, `'sent'`, `'viewed'`.
  final String eventType;

  /// JSON string with event-specific payload (nullable for simple events).
  final String? eventData;

  final DateTime occurredAt;

  /// `my_identity.identity_id` of the device that generated this event.
  final String deviceId;

  /// Globally unique ID — used for deduplication during sync.
  final String syncId;

  factory InvoiceEvent.fromMap(Map<String, dynamic> map) => InvoiceEvent(
        id:          map['id'] as int?,
        invoiceId:   map['invoice_id'] as String,
        eventType:   map['event_type'] as String,
        eventData:   map['event_data'] as String?,
        occurredAt:  DateTime.parse(map['occurred_at'] as String),
        deviceId:    map['device_id'] as String,
        syncId:      map['sync_id'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'invoice_id':  invoiceId,
        'event_type':  eventType,
        if (eventData != null) 'event_data': eventData,
        'occurred_at': occurredAt.toIso8601String(),
        'device_id':   deviceId,
        'sync_id':     syncId,
      };

  @override
  String toString() => 'InvoiceEvent($syncId, $eventType on $invoiceId)';
}
