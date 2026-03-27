# Unified Notifications & Reminders System

**Status:** Planned  
**Target:** Week 30-31 (After Bookings & Beta Prep)  
**Effort:** 25-30 hours  
**Dependencies:** All core features (Invoices, Bookings, Credits, Bills)

---

## Problem Statement

Currently, Kash Cube has **fragmented reminder capabilities**:

✅ **Partially Implemented:**
- `transactions.reminder_sent_at` exists for loans/credits (DB v12)
- `NotificationService` handles scheduled_payments and loans
- Manual reminders in `party_detail_screen.dart` (WhatsApp/SMS/Email)

❌ **Missing:**
- Invoice payment reminders (no `invoices.reminder_sent_at`)
- Booking/appointment reminders (not implemented)
- Unified template system for messages
- Settings/preferences for notification channels
- WhatsApp/SMS/Email for automatic notifications (only push exists)
- Communication service abstraction

**Business Impact:**
- Users must manually track overdue invoices
- No automated follow-ups for appointments
- Inconsistent user experience across features
- Each feature team would re-implement reminders differently

---

## Strategic Approach

Instead of implementing reminders **per-feature** (invoice reminders in Week 23-24, booking reminders in Week 25-27, etc.), implement them **once as a unified system** that serves all features.

### Benefits:
1. **DRY Architecture** - Single codebase for all reminder logic
2. **Consistent UX** - Same notification behavior across all features
3. **Easier Maintenance** - One place to fix bugs or add channels
4. **Privacy Preserved** - All communication happens locally (SMS/WhatsApp deep links)
5. **Extensible** - New features inherit reminder capabilities automatically

---

## Scope: What's Included

### 1. Automatic Push Notifications
Trigger local push notifications for:
- **Credits/Loans**: Payment due dates (1 day before, on due, 1/3/7 days overdue)
- **Invoices**: Payment due dates (1 day before, on due, 1/3/7 days overdue)
- **Bookings**: Appointment times (1 day before, 2 hours before)
- **Scheduled Payments**: Bill payment due dates (3 days before, 1 day before, on due)

### 2. Manual Reminders (WhatsApp/SMS/Email)
User-initiated reminders with pre-filled templates:
- "Send Payment Reminder" for invoices/credits
- "Send Appointment Reminder" for bookings
- "Send Bill Payment Reminder" for scheduled transactions
- Logs `reminder_sent_at` to prevent duplicates

### 3. Notification Templates
Context-aware message generation:
```
Invoice: "Hi [customer], Invoice [INV-2026-005] for ₹25,000 
         is due on 1 Mar 2026. — [Business Name]"
         
Booking: "Hi [customer], Your appointment for [Service] is 
         scheduled on 1 Mar 2026 at 10:00 AM. — [Business Name]"
         
Credit:  "Hi [party], Reminder: Outstanding balance ₹15,000 
         due on 1 Mar 2026. — [Your Name]"
```

### 4. Communication Channels
- **Push Notifications**: flutter_local_notifications (already integrated)
- **WhatsApp**: Deep link `https://wa.me/91[phone]?text=[message]`
- **SMS**: Deep link `sms:[phone]?body=[message]`
- **Email**: Deep link `mailto:[email]?subject=[subject]&body=[message]`

### 5. Settings & Preferences
User controls which notifications to enable:
- Toggle automatic notifications ON/OFF globally
- Per-feature toggles (Invoices, Bookings, Credits, Bills)
- Choose preferred reminder timing (1 day before vs 3 days before)
- Quiet hours (don't send notifications between 10 PM - 8 AM)

---

## Architecture Design

### Database Schema

Add `reminder_sent_at` to all reminder-capable tables:

```sql
-- DB Migration v19 → v20 (Unified Reminders)

-- Already exists: transactions.reminder_sent_at (v12)

-- Add to invoices table
ALTER TABLE invoices ADD COLUMN reminder_sent_at TEXT;
CREATE INDEX idx_invoices_reminder ON invoices(reminder_sent_at, due_date);

-- Add to bookings table (when created in Week 25-27)
ALTER TABLE bookings ADD COLUMN reminder_sent_at TEXT;
CREATE INDEX idx_bookings_reminder ON bookings(reminder_sent_at, booking_date);

-- Settings table for notification preferences
CREATE TABLE notification_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  setting_key TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1,
  value TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Default notification settings
INSERT INTO notification_settings (setting_key, enabled, value) VALUES
  ('notifications_enabled', 1, NULL),
  ('credits_notifications', 1, NULL),
  ('invoices_notifications', 1, NULL),
  ('bookings_notifications', 1, NULL),
  ('bills_notifications', 1, NULL),
  ('reminder_days_before', 1, '1'),
  ('quiet_hours_start', 1, '22:00'),
  ('quiet_hours_end', 1, '08:00');
```

### Service Layer Architecture

```
lib/data/services/
├── notification_service.dart         # Existing - local push notifications
└── communication_service.dart        # NEW - WhatsApp/SMS/Email abstraction

lib/domain/repositories/
└── notification_settings_repository.dart  # NEW - settings CRUD

lib/data/models/
├── reminder_item.dart                # NEW - unified reminder model
└── notification_template.dart        # NEW - message template system
```

### Core Models

**lib/data/models/reminder_item.dart:**
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'reminder_item.freezed.dart';

/// Unified reminder item for all features
@freezed
class ReminderItem with _$ReminderItem {
  const factory ReminderItem({
    required String id,              // invoice_123, booking_456, transaction_789
    required ReminderType type,      // invoice, booking, credit, bill
    required String title,           // "Invoice INV-2026-005"
    required double amount,          // for display
    required DateTime dueDate,       // or booking date
    required String partyName,       // customer/party name
    String? partyPhone,              // for WhatsApp/SMS
    String? partyEmail,              // for Email
    DateTime? reminderSentAt,        // last manual reminder
    Map<String, dynamic>? metadata,  // feature-specific data
  }) = _ReminderItem;

  const ReminderItem._();

  /// Check if reminder is overdue
  bool get isOverdue => DateTime.now().isAfter(dueDate);

  /// Days until due (negative if overdue)
  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;

  /// Should show automatic notification
  bool get shouldNotify {
    final days = daysUntilDue;
    // 1 day before, on due date, 1/3/7 days overdue
    return days == 1 || days == 0 || days == -1 || days == -3 || days == -7;
  }
}

enum ReminderType {
  invoice,
  booking,
  credit,
  bill,
}
```

**lib/data/models/notification_template.dart:**
```dart
class NotificationTemplate {
  final ReminderType type;
  final NotificationTiming timing;  // beforeDue, onDue, overdue

  const NotificationTemplate(this.type, this.timing);

  /// Generate message for WhatsApp/SMS/Email
  String generateMessage(ReminderItem item, String businessName) {
    switch (type) {
      case ReminderType.invoice:
        return _invoiceMessage(item, businessName);
      case ReminderType.booking:
        return _bookingMessage(item, businessName);
      case ReminderType.credit:
        return _creditMessage(item, businessName);
      case ReminderType.bill:
        return _billMessage(item, businessName);
    }
  }

  String _invoiceMessage(ReminderItem item, String business) {
    if (timing == NotificationTiming.overdue) {
      final days = item.daysUntilDue.abs();
      return 'Hi ${item.partyName}, '
          'Invoice ${item.title} for ${formatIndianCurrency(item.amount)} '
          'was due ${days} day${days > 1 ? 's' : ''} ago. '
          'Please make payment at your earliest convenience. — $business';
    } else if (timing == NotificationTiming.beforeDue) {
      return 'Hi ${item.partyName}, '
          'Invoice ${item.title} for ${formatIndianCurrency(item.amount)} '
          'is due tomorrow (${formatDate(item.dueDate)}). — $business';
    } else {
      return 'Hi ${item.partyName}, '
          'Invoice ${item.title} for ${formatIndianCurrency(item.amount)} '
          'is due today. — $business';
    }
  }

  // Similar for _bookingMessage, _creditMessage, _billMessage
}

enum NotificationTiming {
  beforeDue,   // 1-3 days before
  onDue,       // on due date or booking time
  overdue,     // after due date
}
```

### CommunicationService (NEW)

**lib/data/services/communication_service.dart:**
```dart
import 'package:url_launcher/url_launcher.dart';

/// Service for sending WhatsApp/SMS/Email reminders
class CommunicationService {
  /// Send WhatsApp message (deep link)
  Future<bool> sendWhatsApp(String phone, String message) async {
    // Format phone: remove +91, spaces, hyphens
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\+]'), '');
    final formatted = cleaned.startsWith('91') ? cleaned : '91$cleaned';
    
    final url = 'https://wa.me/$formatted?text=${Uri.encodeComponent(message)}';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Send SMS (deep link)
  Future<bool> sendSMS(String phone, String message) async {
    final url = 'sms:$phone?body=${Uri.encodeComponent(message)}';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Send Email (deep link)
  Future<bool> sendEmail(String email, String subject, String body) async {
    final url = 'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
```

### Unified Reminder Bottom Sheet

**lib/presentation/widgets/reminder_bottom_sheet.dart:**
```dart
class ReminderBottomSheet extends ConsumerStatefulWidget {
  final ReminderItem item;
  final String businessName;
  final VoidCallback onReminderSent;

  const ReminderBottomSheet({
    required this.item,
    required this.businessName,
    required this.onReminderSent,
    super.key,
  });

  @override
  ConsumerState<ReminderBottomSheet> createState() => _ReminderBottomSheetState();
}

class _ReminderBottomSheetState extends ConsumerState<ReminderBottomSheet> {
  final _commService = CommunicationService();
  
  // Generate template message based on item type
  String get _message {
    final template = NotificationTemplate(
      widget.item.type,
      widget.item.isOverdue 
        ? NotificationTiming.overdue 
        : NotificationTiming.onDue,
    );
    return template.generateMessage(widget.item, widget.businessName);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize: 0.65,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            children: [
              // Header
              Text('Send Reminder', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              
              // Preview message
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_message),
              ),
              const SizedBox(height: AppSpacing.lg),
              
              // Channel options
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: Colors.green),
                title: const Text('WhatsApp'),
                enabled: widget.item.partyPhone != null,
                onTap: () => _sendReminder('whatsapp'),
              ),
              ListTile(
                leading: const Icon(Icons.message_outlined, color: Colors.blue),
                title: const Text('SMS'),
                enabled: widget.item.partyPhone != null,
                onTap: () => _sendReminder('sms'),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined, color: Colors.orange),
                title: const Text('Email'),
                enabled: widget.item.partyEmail != null,
                onTap: () => _sendReminder('email'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendReminder(String channel) async {
    bool success = false;
    
    switch (channel) {
      case 'whatsapp':
        success = await _commService.sendWhatsApp(widget.item.partyPhone!, _message);
      case 'sms':
        success = await _commService.sendSMS(widget.item.partyPhone!, _message);
      case 'email':
        final subject = '${widget.item.type.name.capitalize()} Reminder';
        success = await _commService.sendEmail(widget.item.partyEmail!, subject, _message);
    }

    if (success && mounted) {
      Navigator.pop(context);
      widget.onReminderSent(); // Mark reminder_sent_at in DB
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder sent')),
      );
    }
  }
}
```

### NotificationService Extension

**lib/data/services/notification_service.dart (Extended):**
```dart
class NotificationService {
  // Existing methods...

  /// Schedule notifications for ALL reminder types
  Future<void> scheduleAllReminders() async {
    final settings = await _settingsRepo.getNotificationSettings();
    if (!settings['notifications_enabled']) return;

    // Fetch all reminder items from repositories
    final invoices = await _invoiceRepo.getUpcomingInvoices();
    final bookings = await _bookingRepo.getUpcomingBookings();
    final credits = await _transactionRepo.getUpcomingCredits();
    final bills = await _transactionRepo.getUpcomingBills();

    // Convert to ReminderItem list
    final reminders = [
      ...invoices.map((inv) => ReminderItem.fromInvoice(inv)),
      ...bookings.map((bk) => ReminderItem.fromBooking(bk)),
      ...credits.map((tx) => ReminderItem.fromTransaction(tx)),
      ...bills.map((tx) => ReminderItem.fromTransaction(tx)),
    ];

    // Filter based on user preferences
    final filtered = reminders.where((item) {
      final typeEnabled = settings['${item.type.name}_notifications'] ?? true;
      return typeEnabled && item.shouldNotify;
    }).toList();

    // Schedule platform notifications
    for (final reminder in filtered) {
      await _schedulePlatformNotification(reminder);
    }
  }

  Future<void> _schedulePlatformNotification(ReminderItem item) async {
    // Check quiet hours
    final now = DateTime.now();
    final quietStart = _parseTime(await _getSetting('quiet_hours_start'));
    final quietEnd = _parseTime(await _getSetting('quiet_hours_end'));
    
    if (_isQuietHours(now, quietStart, quietEnd)) {
      // Reschedule for next morning
      final scheduledTime = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1))
          .add(quietEnd);
      // Schedule notification at scheduledTime
    }

    // Generate notification content
    final template = NotificationTemplate(item.type, _getTiming(item));
    final title = _getNotificationTitle(item);
    final body = template.generateMessage(item, await _getBusinessName());

    // Use flutter_local_notifications
    await flutterLocalNotificationsPlugin.zonedSchedule(
      item.id.hashCode,
      title,
      body,
      tz.TZDateTime.from(item.dueDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Payment & Appointment Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
```

---

## Implementation Plan

### Phase 1: Database & Models (4 hours)

**Tasks:**
1. Create DB migration v19→v20
   - Add `reminder_sent_at` to invoices, bookings tables
   - Create `notification_settings` table
   - Insert default settings
2. Create `ReminderItem` model (freezed)
3. Create `NotificationTemplate` model
4. Add factory methods: `ReminderItem.fromInvoice()`, `fromBooking()`, `fromTransaction()`

**Acceptance Criteria:**
- ✅ All tables have `reminder_sent_at` column
- ✅ notification_settings table created with defaults
- ✅ ReminderItem model builds without errors
- ✅ Can convert Invoice/Booking/Transaction → ReminderItem

---

### Phase 2: Services & Repositories (8 hours)

**Tasks:**
1. Create `CommunicationService` (WhatsApp/SMS/Email)
2. Create `NotificationSettingsRepository` (abstract + impl)
3. Extend `NotificationService.scheduleAllReminders()`
4. Add `markReminderSent(id, type)` to each repository
5. Create Riverpod providers for services

**Acceptance Criteria:**
- ✅ Can send WhatsApp/SMS/Email via deep links
- ✅ Can fetch/update notification settings
- ✅ scheduleAllReminders() processes all reminder types
- ✅ reminder_sent_at updates correctly in DB

---

### Phase 3: UI Components (6 hours)

**Tasks:**
1. Create `ReminderBottomSheet` widget
2. Add "Send Reminder" buttons to:
   - `invoice_detail_screen.dart`
   - `booking_detail_screen.dart` (Week 25-27)
   - `party_detail_screen.dart` (already exists - refactor to use ReminderBottomSheet)
3. Create `NotificationSettingsScreen` in Settings tab
4. Add toggle switches for each feature

**Acceptance Criteria:**
- ✅ Can open reminder sheet from invoice/booking/credit detail
- ✅ Sheet shows preview of message
- ✅ Can select WhatsApp/SMS/Email
- ✅ Settings screen allows enabling/disabling notifications per feature

---

### Phase 4: Integration & Testing (5 hours)

**Tasks:**
1. Call `scheduleAllReminders()` on app startup
2. Call `scheduleAllReminders()` after creating/updating invoices/bookings
3. Test notifications at different times (before due, on due, overdue)
4. Test quiet hours (notifications delayed)
5. Test manual reminders (mark reminder_sent_at)
6. Test with no phone/email (disable options)

**Acceptance Criteria:**
- ✅ Notifications appear at correct times (1 day before, on due, overdue)
- ✅ Manual reminders open correct app (WhatsApp/SMS/Email)
- ✅ reminder_sent_at prevents duplicate reminders within 24 hours
- ✅ Settings respected (disabled features don't notify)
- ✅ Quiet hours work (no notifications 10 PM - 8 AM)

---

### Phase 5: Polish & Documentation (2 hours)

**Tasks:**
1. Add loading states to reminder bottom sheet
2. Add error handling (no app available for WhatsApp)
3. Update user guide with notification settings
4. Add unit tests for NotificationTemplate
5. Add widget tests for ReminderBottomSheet

**Acceptance Criteria:**
- ✅ User sees loading spinner while opening app
- ✅ User sees error if WhatsApp not installed
- ✅ Documentation updated with reminder behavior
- ✅ Tests pass for template generation

---

## Roadmap Integration

### Option A: Week 30-31 — Unified Notifications (25-30h) ✅ RECOMMENDED

**Justification:**
- All core features complete (Invoices, Bookings, Credits, Bills)
- Can implement once for all features
- Week 28-29 (Retention) has "smart due-date notifications" — this is that feature
- Natural endpoint before Beta Release

**Timeline:**
- Week 28-29: Retention features (nudges, insights, backup)
- **Week 30-31: Unified Notifications & Reminders (25-30h)**
- Week 32: Beta Prep (final testing, polish)

### Option B: Defer to Post-Beta (v1.1)

**Justification:**
- MVP can launch with manual reminders only
- Add automatic notifications as v1.1 feature
- Reduces pre-launch scope

**Risk:**
- Users expect automatic reminders in financial apps
- Competitors have this feature
- May hurt retention if users forget payments

---

## Privacy & Architecture Notes

### ✅ Privacy Preserved:
- **No Server Calls**: All notifications are local (flutter_local_notifications)
- **No Data Transmission**: WhatsApp/SMS/Email are deep links (OS handles communication)
- **No Analytics**: No tracking of which reminders are sent
- **No Cloud Sync**: Settings stored in local SQLite

### 🏗️ Architecture Principles:
- **Single Responsibility**: CommunicationService only handles deep links
- **Repository Pattern**: NotificationSettingsRepository abstracts DB
- **Provider Pattern**: Riverpod providers for dependency injection
- **Template Pattern**: NotificationTemplate for message generation
- **Observer Pattern**: Providers listen to DB changes, auto-refresh notifications

---

## Success Metrics (Post-Launch)

After implementing this feature, track:
1. **User Engagement**: % of users who enable automatic notifications
2. **Payment Recovery**: % of overdue invoices paid within 3 days of reminder
3. **Appointment Attendance**: % of bookings confirmed after reminder
4. **Channel Preference**: WhatsApp vs SMS vs Email usage
5. **Quiet Hours Adoption**: % of users who customize quiet hours

---

## Future Enhancements (Post-MVP)

1. **Custom Templates**: Allow users to edit message templates
2. **Reminder Rules**: "Remind me 3 days before for invoices > ₹10,000"
3. **Batch Reminders**: Send reminders for multiple overdue invoices at once
4. **Escalation**: Send Email if WhatsApp not opened within 2 days
5. **Voice Reminders**: Integrate with Google Assistant/Siri Shortcuts
6. **Multi-Language**: Templates in Hindi, Tamil, Telugu, etc.

---

## Appendix: Code Samples

### Sample Notification Settings Screen

```dart
class NotificationSettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Notifications'),
            subtitle: const Text('Receive reminders for payments and appointments'),
            value: settings['notifications_enabled'] ?? true,
            onChanged: (val) => ref.read(notificationSettingsProvider.notifier)
                .updateSetting('notifications_enabled', val),
          ),
          const Divider(),
          if (settings['notifications_enabled'] ?? true) ...[
            SwitchListTile(
              title: const Text('Invoice Reminders'),
              value: settings['invoices_notifications'] ?? true,
              onChanged: (val) => ref.read(notificationSettingsProvider.notifier)
                  .updateSetting('invoices_notifications', val),
            ),
            SwitchListTile(
              title: const Text('Booking Reminders'),
              value: settings['bookings_notifications'] ?? true,
              onChanged: (val) => ref.read(notificationSettingsProvider.notifier)
                  .updateSetting('bookings_notifications', val),
            ),
            SwitchListTile(
              title: const Text('Credit/Loan Reminders'),
              value: settings['credits_notifications'] ?? true,
              onChanged: (val) => ref.read(notificationSettingsProvider.notifier)
                  .updateSetting('credits_notifications', val),
            ),
            SwitchListTile(
              title: const Text('Bill Payment Reminders'),
              value: settings['bills_notifications'] ?? true,
              onChanged: (val) => ref.read(notificationSettingsProvider.notifier)
                  .updateSetting('bills_notifications', val),
            ),
            const Divider(),
            ListTile(
              title: const Text('Quiet Hours'),
              subtitle: Text('${settings['quiet_hours_start']} - ${settings['quiet_hours_end']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Open time picker
              },
            ),
          ],
        ],
      ),
    );
  }
}
```

---

**End of Specification**
