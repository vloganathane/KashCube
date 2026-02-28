import 'package:intl/intl.dart';

import 'reminder_item.dart';

/// When the notification/reminder fires relative to the due date.
enum NotificationTiming {
  /// 1-3 days before due/booking date.
  beforeDue,

  /// On the due date or booking day.
  onDue,

  /// After the due date has passed.
  overdue,
}

/// Generates context-aware WhatsApp/SMS/Email reminder messages.
class NotificationTemplate {
  const NotificationTemplate(this.type, this.timing);

  final ReminderType type;
  final NotificationTiming timing;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Generate the full message body for [item].
  /// [senderName] is the business/user name shown in the sign-off.
  String generateMessage(ReminderItem item, String senderName) {
    switch (type) {
      case ReminderType.invoice:
        return _invoiceMessage(item, senderName);
      case ReminderType.booking:
        return _bookingMessage(item, senderName);
      case ReminderType.credit:
        return _creditMessage(item, senderName);
      case ReminderType.bill:
        return _billMessage(item, senderName);
    }
  }

  /// Determine appropriate timing from the reminder item's due state.
  static NotificationTiming timingFor(ReminderItem item) {
    if (item.isOverdue) return NotificationTiming.overdue;
    if (item.daysUntilDue <= 1) return NotificationTiming.onDue;
    return NotificationTiming.beforeDue;
  }

  // ── Private generators ───────────────────────────────────────────────────

  String _invoiceMessage(ReminderItem item, String sender) {
    final amtStr = _formatAmount(item.amount);
    if (timing == NotificationTiming.overdue) {
      final days = item.daysUntilDue.abs();
      return 'Hi ${item.partyName},\n'
          'Invoice ${item.title} for $amtStr was due $days day${days > 1 ? 's' : ''} ago. '
          'Kindly make the payment at your earliest convenience.\n— $sender';
    } else if (timing == NotificationTiming.beforeDue) {
      final dateStr = DateFormat('d MMM yyyy').format(item.dueDate);
      return 'Hi ${item.partyName},\n'
          'Invoice ${item.title} for $amtStr is due on $dateStr. '
          'Please arrange payment before the due date.\n— $sender';
    } else {
      return 'Hi ${item.partyName},\n'
          'Invoice ${item.title} for $amtStr is due today. '
          'Kindly make the payment at your earliest convenience.\n— $sender';
    }
  }

  String _bookingMessage(ReminderItem item, String sender) {
    final dateStr = DateFormat('d MMM yyyy').format(item.dueDate);
    final timeStr = DateFormat('h:mm a').format(item.dueDate);
    if (timing == NotificationTiming.beforeDue) {
      return 'Hi ${item.partyName},\n'
          'Reminder: Your appointment for "${item.title}" is scheduled on '
          '$dateStr at $timeStr. See you then!\n— $sender';
    }
    return 'Hi ${item.partyName},\n'
        'Your appointment for "${item.title}" is today at $timeStr. '
        'Looking forward to seeing you!\n— $sender';
  }

  String _creditMessage(ReminderItem item, String sender) {
    final amtStr = _formatAmount(item.amount);
    if (timing == NotificationTiming.overdue) {
      final days = item.daysUntilDue.abs();
      return 'Hi ${item.partyName},\n'
          'Reminder: Outstanding balance of $amtStr was due $days day${days > 1 ? 's' : ''} ago. '
          'Kindly settle the amount at your earliest convenience.\n— $sender';
    }
    final dateStr = DateFormat('d MMM yyyy').format(item.dueDate);
    return 'Hi ${item.partyName},\n'
        'Friendly reminder: Outstanding balance of $amtStr is due on $dateStr. '
        'Please let me know when you can settle.\n— $sender';
  }

  String _billMessage(ReminderItem item, String sender) {
    final amtStr = _formatAmount(item.amount);
    final dateStr = DateFormat('d MMM yyyy').format(item.dueDate);
    return 'Hi ${item.partyName},\n'
        'Bill payment "${item.title}" for $amtStr is due on $dateStr. '
        'Please ensure timely payment.\n— $sender';
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Indian number formatting with ₹ prefix.
  String _formatAmount(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }
}
