# Invoice Payment Reminder System — Specification

**Status:** 🚧 NOT IMPLEMENTED (Gap Analysis)  
**Priority:** HIGH — Essential for business billing workflow  
**Effort:** ~15 hours  
**Dependencies:** Week 21-22 (Billing) ✅ COMPLETE, Week 23-24 (Party Management) ⏳ PENDING

---

## Current State Analysis

### ✅ What EXISTS:
1. **NotificationService** — Local notifications for scheduled payments & loans
2. **Transaction reminders** — Manual WhatsApp/SMS/Email for lent/borrowed transactions
3. **Party detail reminders** — Send payment reminders for credits/loans
4. **Invoice model** — Has `dueDate`, `isOverdue` getter, `status` (paid/overdue)
5. **Database indexes** — `idx_invoices_due` on due_date, `idx_invoices_status` on status

### ❌ What's MISSING:
1. **No `reminder_sent_at` column** in invoices table (DB v18)
2. **No automatic reminders** — System doesn't notify about upcoming/overdue invoices
3. **No manual "Send Reminder" button** on invoice detail screen
4. **No reminder scheduling** — NotificationService doesn't handle invoices
5. **No reminder templates** for invoices (only exists for credits/loans)
6. **No reminder tracking** — Can't see when last reminder was sent

---

## Problem Statement

**Business Scenario:**
> "I sent Invoice INV-2026-005 to Kumar on Feb 20 with a due date of Feb 27. Today is Feb 27 and I haven't received payment. I need to:
> 1. Get notified that payment is due today
> 2. Send a polite payment reminder via WhatsApp
> 3. Track that I sent a reminder (avoid duplicate nagging)
> 4. Get notified if payment is still overdue tomorrow"

**Current Workaround:**
- User must manually check invoice list for overdue entries
- No system reminder — easy to forget to follow up
- Must manually compose WhatsApp message each time
- No tracking of reminder history

---

## Proposed Solution

### Two-Layer Reminder System:

**1. Automatic Notifications (Silent Background)**
- **1 day before due** — "Invoice INV-2026-005 due tomorrow (₹47,880)"
- **On due date (9 AM)** — "Invoice INV-2026-005 due today (₹47,880)"
- **1 day overdue (9 AM)** — "Invoice INV-2026-005 is overdue (₹47,880)"
- **3 days overdue (9 AM)** — "Invoice INV-2026-005 is 3 days overdue"
- **7 days overdue (9 AM)** — "Invoice INV-2026-005 is 7 days overdue"

**2. Manual Reminders (User-Initiated)**
- "Send Payment Reminder" button on invoice detail screen
- Opens bottom sheet with WhatsApp/SMS/Email options
- Pre-filled message template (user-editable)
- Logs `reminder_sent_at` timestamp

---

## Implementation Plan

### Phase 1: Database & Model (2 hours)

**DB Migration v18 → v19:**
```sql
ALTER TABLE invoices ADD COLUMN reminder_sent_at TEXT;
ALTER TABLE invoices ADD COLUMN booking_id INTEGER;  -- for Week 25-27 bookings

CREATE INDEX idx_invoices_reminder ON invoices(reminder_sent_at);

-- For automatic overdue detection
CREATE INDEX idx_invoices_unpaid_due ON invoices(status, due_date) 
  WHERE status IN ('sent', 'partiallyPaid');
```

**Invoice Model Update:**
```dart
class Invoice extends Equatable {
  // ... existing fields ...
  final DateTime? reminderSentAt;  // NEW: Last manual reminder sent
  final int? bookingId;  // NEW: For bookings feature
  
  // NEW: Helper to determine if reminder is needed
  bool get needsReminder =>
      status != InvoiceStatus.paid &&
      status != InvoiceStatus.draft &&
      dueDate != null &&
      (reminderSentAt == null ||
       DateTime.now().difference(reminderSentAt!).inDays >= 3);
}
```

### Phase 2: Manual Reminder UI (5 hours)

**Invoice Detail Screen:**
```dart
// Add "Send Reminder" button (visible only for sent/overdue/partiallyPaid)
if (invoice.status == InvoiceStatus.sent ||
    invoice.status == InvoiceStatus.overdue ||
    invoice.status == InvoiceStatus.partiallyPaid) {
  OutlinedButton.icon(
    icon: const Icon(Icons.notifications_outlined),
    label: const Text('Send Payment Reminder'),
    onPressed: () => _sendPaymentReminder(context, ref),
  ),
}
```

**Reminder Bottom Sheet:**
```dart
class _InvoiceReminderSheet extends StatelessWidget {
  final Invoice invoice;
  final Party? customerParty;  // For phone/email
  final String businessName;
  
  // Options:
  // - WhatsApp (if party has phone)
  // - SMS (if party has phone)
  // - Email (if party has email)
  // - Copy message to clipboard
  
  String _generateMessage() {
    final daysOverdue = invoice.isOverdue
        ? DateTime.now().difference(invoice.dueDate!).inDays
        : 0;
    
    if (daysOverdue > 0) {
      return 'Hi ${invoice.customerName},\n\n'
          'Invoice ${invoice.invoiceNo} for ${CurrencyFormatter.format(invoice.balanceDue)} '
          'was due on ${DateFormatter.format(invoice.dueDate!)} '
          '($daysOverdue day${daysOverdue > 1 ? 's' : ''} overdue).\n\n'
          'Please pay when convenient.\n\n'
          '— $businessName';
    } else {
      return 'Hi ${invoice.customerName},\n\n'
          'Reminder: Invoice ${invoice.invoiceNo} for ${CurrencyFormatter.format(invoice.balanceDue)} '
          'is due ${invoice.dueDate != null ? 'on ${DateFormatter.format(invoice.dueDate!)}' : 'soon'}.\n\n'
          '— $businessName';
    }
  }
}
```

**Repository Method:**
```dart
// InvoiceRepositoryImpl
Future<void> markReminderSent(int invoiceId) async {
  final db = await _db.database;
  await db.update(
    'invoices',
    {
      'reminder_sent_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [invoiceId],
  );
}
```

### Phase 3: Automatic Notifications (6 hours)

**Extend NotificationService:**
```dart
class NotificationService {
  // Existing: _billBase = 10000, _loanBase = 20000
  static const _invoiceBase = 30000;  // NEW: Base for invoice reminders
  
  /// Schedule invoice payment reminders for unpaid invoices with due dates
  Future<void> scheduleInvoiceReminders(List<Invoice> invoices) async {
    if (!_initialized) await initialize();
    final now = tz.TZDateTime.now(tz.local);
    
    for (final invoice in invoices) {
      // Skip paid, draft, or no due date
      if (invoice.status == InvoiceStatus.paid ||
          invoice.status == InvoiceStatus.draft ||
          invoice.dueDate == null) continue;
      
      final due = invoice.dueDate!;
      final dueMorning = tz.TZDateTime(
          tz.local, due.year, due.month, due.day, 9, 0, 0);
      final baseId = _invoiceBase + (invoice.id ?? 0);
      
      // 1 day before due
      final dayBefore = dueMorning.subtract(const Duration(days: 1));
      if (dayBefore.isAfter(now)) {
        await _scheduleOne(
          id: baseId + 1000,
          title: 'Invoice due tomorrow',
          body: '${invoice.invoiceNo} — ${CurrencyFormatter.format(invoice.balanceDue)}',
          at: dayBefore,
          important: false,
        );
      }
      
      // On due date
      if (dueMorning.isAfter(now)) {
        await _scheduleOne(
          id: baseId + 2000,
          title: 'Invoice due today',
          body: '${invoice.invoiceNo} — ${CurrencyFormatter.format(invoice.balanceDue)}',
          at: dueMorning,
          important: true,
        );
      }
      
      // Overdue reminders (1, 3, 7 days)
      if (invoice.isOverdue) {
        final today = DateTime.now();
        final daysOverdue = today.difference(due).inDays;
        
        for (final daysPast in [1, 3, 7]) {
          if (daysOverdue >= daysPast) {
            final reminderDate = tz.TZDateTime(
              tz.local,
              due.year,
              due.month,
              due.day + daysPast,
              9,
              0,
              0,
            );
            if (reminderDate.isAfter(now)) {
              await _scheduleOne(
                id: baseId + 3000 + daysPast,
                title: 'Invoice overdue',
                body: '${invoice.invoiceNo} — $daysPast day${daysPast > 1 ? 's' : ''} overdue',
                at: reminderDate,
                important: true,
              );
            }
          }
        }
      }
    }
  }
}
```

**Integration with Invoice Provider:**
```dart
// Re-schedule notifications whenever invoices change
final invoicesProvider =
    StateNotifierProvider<InvoicesNotifier, AsyncValue<List<Invoice>>>(
  (ref) => InvoicesNotifier(ref.read(invoiceRepositoryProvider))..load(),
);

class InvoicesNotifier extends StateNotifier<AsyncValue<List<Invoice>>> {
  // ... existing code ...
  
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final invoices = await _repo.getAll();
      state = AsyncValue.data(invoices);
      
      // NEW: Update notification schedule
      await ref
          .read(notificationServiceProvider)
          .scheduleInvoiceReminders(invoices);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
```

### Phase 4: Polish & Testing (2 hours)

**UI Indicators:**
- Badge on invoice card: "Reminder sent 2 days ago"
- Disable "Send Reminder" button if sent within last 24 hours
- Show reminder count in party detail: "3 reminders sent"

**Edge Cases:**
- Don't send reminder if invoice paid today
- Cancel all invoice notifications when invoice marked paid
- Don't send reminder if customer just made partial payment
- Clear reminder_sent_at when invoice due date changes

**Testing:**
- Create test invoice with due date = tomorrow
- Verify notification appears at 9 AM day before
- Tap "Send Reminder" → verify WhatsApp opens with correct message
- Mark invoice paid → verify notification cancelled

---

## Message Templates

### Before Due (Manual):
```
Hi Kumar,

Reminder: Invoice INV-2026-005 for ₹47,880 is due on 27 Feb 2026.

— Hydrogen Cafe
```

### Overdue (Manual):
```
Hi Kumar,

Invoice INV-2026-005 for ₹47,880 was due on 27 Feb 2026 (2 days overdue).

Please pay when convenient.

— Hydrogen Cafe
```

### Notification (Automatic):
```
Title: Invoice due today
Body: INV-2026-005 — ₹47,880
```

---

## Integration Points

**Dependency: Week 23-24 (Party Management)**
- Need `party.phone` for WhatsApp/SMS reminders
- Need `party.email` for email reminders
- Reminder sheet reuses same pattern as credit/loan reminders

**Synergy: Week 25-27 (Bookings)**
- Booking invoices inherit reminder system automatically
- Reminder logic works for all invoice types (quote-based, standalone, booking)

---

## Success Metrics

**Developer:**
- Reminders sent via WhatsApp: 80%+ open rate (WhatsApp analytics outside our scope)
- Automatic notifications: 90%+ delivered (Android guarantees)
- Zero duplicate reminders within 24 hours

**User:**
- "I never forget to follow up on overdue invoices"
- "Payment collection time reduced from 7 days to 3 days average"
- "Professional reminder messages save time — no more typing"

---

## Roadmap Placement

**Option A: Add to Week 23-24 (Party Management)**
- Makes sense: reminders need party phone/email
- Increases Week 23-24 from 40h → 55h
- **Pro:** Completes billing feature fully
- **Con:** Delays Party Management completion

**Option B: New Week 24.5 (Invoice Reminders Standalone)**
- Separate 15-hour sprint
- Depends on Week 23-24 completion (party phone/email)
- **Pro:** Keeps Week 23-24 focused
- **Con:** Adds extra week to timeline

**Option C: Defer to Week 28-29 (Retention & Reach)**
- "Smart due-date notifications" already planned
- Extend that section to include invoice reminders
- **Pro:** Natural fit with retention features
- **Con:** Billing feature incomplete without reminders

---

## Recommendation

**🎯 Option A: Add to Week 23-24**

**Rationale:**
1. Billing (Week 21-22) is incomplete without reminders
2. Party Management already adding phone/email fields
3. Reuse existing reminder sheet pattern (credits/loans)
4. Business users expect reminder functionality in billing software
5. Only 15 extra hours — reasonable scope addition

**Updated Week 23-24 Deliverables:**
- Parties with full contact details ✅
- WhatsApp/SMS/Email reminders for credits/loans ✅
- **Invoice payment reminders (automatic + manual)** ← NEW
- Party detail unified history ✅

**Updated Time Estimate:** 40h → 55h

---

## Next Steps (If Approved)

1. **DB Migration:** Add reminder_sent_at to invoices (v19)
2. **Manual Reminder UI:** Send Payment Reminder button + bottom sheet
3. **Automatic Scheduling:** Extend NotificationService for invoices
4. **Integration:** Hook into invoicesProvider.load()
5. **Testing:** Verify reminders work end-to-end

**Timeline:** 2 days focused work (15 hours)

---

**Status:** READY FOR IMPLEMENTATION — Waiting for user approval on roadmap placement.
