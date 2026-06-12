import 'booking.dart';
import 'invoice.dart';
import 'transaction.dart';

/// The type of entity that can be reminded about.
enum ReminderType { invoice, booking, credit, bill }

extension ReminderTypeLabel on ReminderType {
  String get label {
    switch (this) {
      case ReminderType.invoice:
        return 'Invoice';
      case ReminderType.booking:
        return 'Booking';
      case ReminderType.credit:
        return 'Credit';
      case ReminderType.bill:
        return 'Bill';
    }
  }
}

/// Unified reminder item — wraps any reminder-capable entity so that
/// [ReminderBottomSheet] and [NotificationTemplate] can work with all features
/// through a single API.
class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.partyName,
    this.partyPhone,
    this.partyEmail,
    this.reminderSentAt,
    this.metadata = const {},
  });

  /// Unique string identifier: "invoice_123", "booking_456", "transaction_789"
  final String id;

  final ReminderType type;

  /// Human-readable title shown in the bottom sheet header.
  final String title;

  /// Amount for display in the reminder message.
  final double amount;

  /// Due date or appointment datetime.
  final DateTime dueDate;

  final String partyName;
  final String? partyPhone;
  final String? partyEmail;

  /// When the last manual reminder was sent via WhatsApp/SMS/Email.
  final DateTime? reminderSentAt;

  /// Feature-specific extra data (invoice number, service name, etc.).
  final Map<String, dynamic> metadata;

  // ── Derived helpers ──────────────────────────────────────────────────────

  bool get isOverdue => DateTime.now().isAfter(dueDate);

  /// Days until due: negative means overdue.
  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;

  // ── Factory constructors ─────────────────────────────────────────────────

  factory ReminderItem.fromInvoice(
    Invoice invoice, {
    String? partyPhone,
    String? partyEmail,
  }) {
    return ReminderItem(
      id: 'invoice_${invoice.id}',
      type: ReminderType.invoice,
      title: invoice.invoiceNo,
      amount: invoice.balanceDue,
      dueDate: invoice.dueDate ?? invoice.issueDate,
      partyName: invoice.customerName,
      partyPhone: partyPhone,
      partyEmail: partyEmail,
      reminderSentAt: invoice.reminderSentAt,
      metadata: {'invoice_id': invoice.id, 'status': invoice.status.name},
    );
  }

  factory ReminderItem.fromBooking(
    Booking booking, {
    String? partyPhone,
    String? partyEmail,
  }) {
    return ReminderItem(
      id: 'booking_${booking.id}',
      type: ReminderType.booking,
      title: booking.serviceName,
      amount: booking.totalAmount,
      dueDate: booking.startDatetime,
      partyName: booking.customerName,
      partyPhone: partyPhone,
      partyEmail: partyEmail,
      reminderSentAt: booking.reminderSentAt,
      metadata: {
        'booking_id': booking.id,
        'service_name': booking.serviceName,
        'status': booking.status.name,
      },
    );
  }

  factory ReminderItem.fromTransaction(
    Transaction transaction, {
    String? partyPhone,
    String? partyEmail,
  }) {
    return ReminderItem(
      id: 'transaction_${transaction.id}',
      type: ReminderType.credit,
      title: transaction.category,
      amount: transaction.amount,
      dueDate: transaction.dueDate ?? transaction.date,
      partyName: transaction.partyName ?? '',
      partyPhone: partyPhone,
      partyEmail: partyEmail,
      reminderSentAt: transaction.reminderSentAt,
      metadata: {
        'transaction_id': transaction.id,
        'type': transaction.type.name,
      },
    );
  }
}
