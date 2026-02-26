# Bookings Feature Specification

**Version:** 1.0  
**Target:** Week 25-27 (Post-Billing)  
**Effort:** 75 hours  
**Design Principle:** Dead simple UI, passes 5-second test

---

## Overview

Enable service businesses (doctors, homestays, cabs, travel agencies) to manage time-based bookings with automatic invoice generation. All local, zero network calls, seamless integration with existing features.

### Target Verticals

| Business | Bookable Unit | Duration | Use Case |
|----------|---------------|----------|----------|
| **Doctor/Clinic** | Appointment | 15-30 min | Patient consultations, follow-ups |
| **Homestay/Hotel** | Room | Multi-day (nights) | Guest reservations, check-in/out |
| **Cab/Driver** | Trip | Hours or single run | Airport transfers, city rides |
| **Travel Agency** | Tour package | Multi-day | Group tours, pilgrimage trips |

---

## Core Workflow

```
1. Customer calls/WhatsApp → Business creates booking
   ↓
2. Booking status: PENDING → Send WhatsApp confirmation (OS intent)
   ↓
3. Customer confirms → Status: CONFIRMED → Auto-reminder (day before)
   ↓
4. Service date arrives → Notification: "Raj's transfer today 2:30 PM"
   ↓
5. Service completed → Tap [Complete & Invoice]
   ↓
6. Draft invoice created (pre-filled) → User edits/sends
   ↓
7. Invoice paid → Booking archived
```

---

## UI Design (5-Second Test Compliant)

### 1. Home Screen Integration

**Decision:** NO new home tile — use Speed-dial FAB

```dart
SpeedDialFAB (when Business Mode enabled):
  - Add Transaction
  - Loan·Lend
  - Bills & Pay
  - New Booking  ← Added here

Access bookings list via:
  - Reports tab → "Bookings Overview" card
  - Or: Add small "View All Bookings" link in speed dial
```

**Rationale:** Home screen stays clean (4-tile layout), FAB is contextual action center.

---

### 2. Bookings List Screen

```
┌─────────────────────────────────┐
│ ← Bookings          [Filter]    │
├─────────────────────────────────┤
│ TODAY                            │
│                                  │
│ 10:00 AM                         │
│ Dr. Sharma • Consultation        │
│ Confirmed • ₹500                 │  ← Status WORD visible
│ [Complete & Invoice]             │  ← Action visible
│ ─────────────────────────────── │
│ 2:30 PM                          │
│ Raj • Airport Transfer           │
│ Pending • ₹1,200                 │
│ [Send Confirmation]              │
│ ─────────────────────────────── │
│ TOMORROW                         │
│                                  │
│ 28 Feb - 2 Mar                   │
│ Kumar Family • Room 101          │
│ Confirmed • ₹4,500               │
│ ─────────────────────────────── │
│ ⌄ Show Past (12)                 │  ← Collapsed by default
│ ⌄ Show Cancelled (2)             │
└─────────────────────────────────┘
```

**Key Design Decisions:**
- ✅ Status as TEXT ("Confirmed", "Pending"), not just colored dots
- ✅ Primary action button visible on card (no detail tap needed for common actions)
- ✅ Consistent card pattern: `[Time] → [Name] • [Service] → [Status] • [Amount] → [Action]`
- ✅ Date grouping: TODAY, TOMORROW, THIS WEEK, PAST (auto-collapse old ones)
- ✅ Swipe left → [Cancel], Swipe right → [Complete] (for confirmed today bookings)

**Filter Options (top-right):**
- All
- Today
- Upcoming (next 7 days)
- Confirmed only
- Pending only

---

### 3. Create Booking (Bottom Sheet)

```
┌─────────────────────────────────┐
│ ● New Booking                    │
├─────────────────────────────────┤
│ Customer                         │
│ [Raj Enterprises ▼]             │  ← Reuse PartyPickerField
│                                  │
│ Service  (₹1,200 • 1.5 hrs)     │  ← Price shows after selection
│ [Airport Transfer ▼]            │  ← Reuse catalog picker
│                                  │
│ [Today 3:00 PM]  [Tomorrow]     │  ← Quick buttons + calendar icon
│                                  │
│           [Book]                 │
└─────────────────────────────────┘
```

**Smart Defaults:**
- Amount: Pre-filled from catalog item
- Duration: Pre-filled from catalog item (used for multi-day detection)
- Status: Auto-set to "Pending"
- Date picker intelligence:
  - If service duration < 3 hours → Time picker (appointment)
  - If duration ≥ 24 hours → Date range picker (reservation)
  - If duration 3-24 hours → Date + time picker (trip)

**Optional fields (added via "More Options" link):**
- Advance payment amount
- Notes
- Custom duration override

---

### 4. Booking Detail Screen

```
┌─────────────────────────────────┐
│ ← 2:30 PM          [Edit] [•••] │
├─────────────────────────────────┤
│ 👤 Raj Enterprises              │
│    +91 98765 43210              │
│    [WhatsApp] [Call]            │
├─────────────────────────────────┤
│ 🚗 Airport Transfer              │
│    27 Feb • 2:30 PM              │
│    Duration: 1.5 hours           │
│    Notes: Terminal 2, Flight AI204│
├─────────────────────────────────┤
│ Status: Pending Confirmation    │
│ Amount: ₹1,200                   │
│ Advance: ₹0                      │
├─────────────────────────────────┤
│ [Confirm Booking]                │  ← Marks confirmed + sends WhatsApp
│                                  │
│ [Complete & Invoice]             │  ← Pre-fills invoice, navigates to edit
│                                  │
│ Other Actions:                   │
│ Cancel • Mark No-show • Duplicate│
└─────────────────────────────────┘
```

**Action Behavior:**
- **Confirm**: Status → Confirmed, opens WhatsApp with: `"Hi Raj, your airport transfer is confirmed for 27 Feb 2:30 PM. ₹1,200. — [Business Name]"`
- **Complete & Invoice**: Creates draft invoice, navigates to InvoiceDetailScreen for review/send
- **Mark No-show**: Status → No-show, affects customer trust score (visible in party detail)
- **Cancel**: Confirmation dialog → Status → Cancelled

---

## Database Schema

### New Table (DB v11)

```sql
bookings (
  id INTEGER PRIMARY KEY,
  customer_party_id INTEGER,
  customer_name TEXT,
  
  service_item_id INTEGER,  -- links to item_catalog
  service_name TEXT,         -- denormalized for history
  
  start_datetime TEXT,       -- ISO 8601
  end_datetime TEXT,         -- NULL for single-time appointments
  duration_minutes INTEGER,  -- derived or manual
  
  status TEXT,               -- 'pending' | 'confirmed' | 'completed' | 'cancelled' | 'no_show'
  
  total_amount REAL,
  advance_amount REAL DEFAULT 0,
  
  invoice_id INTEGER,        -- linked after completion
  
  notes TEXT,
  notification_scheduled_at TEXT,  -- timestamp when reminder notification scheduled
  confirmed_at TEXT,
  
  business_id INTEGER,
  booking_ref TEXT,          -- BK-2026-001 format
  
  created_at TEXT,
  updated_at TEXT,
  
  FOREIGN KEY (customer_party_id) REFERENCES parties(id),
  FOREIGN KEY (service_item_id) REFERENCES item_catalog(id),
  FOREIGN KEY (invoice_id) REFERENCES invoices(id),
  FOREIGN KEY (business_id) REFERENCES businesses(id)
);

CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_start_datetime ON bookings(start_datetime);
CREATE INDEX idx_bookings_customer ON bookings(customer_party_id);
CREATE INDEX idx_bookings_business ON bookings(business_id);
```

### Extend Existing Tables

```sql
-- Item Catalog (enable bookable services)
ALTER TABLE item_catalog ADD COLUMN duration_minutes INTEGER DEFAULT 30;
ALTER TABLE item_catalog ADD COLUMN is_bookable INTEGER DEFAULT 0;

-- No changes to invoices or parties tables (foreign keys already flexible)
```

---

## Status Flow

```
CREATE BOOKING
  ↓
PENDING (yellow badge, "Send Confirmation" button visible)
  ↓ User taps [Confirm] or [Send Confirmation]
CONFIRMED (green badge, WhatsApp message sent)
  ↓ Auto-notification scheduled (24 hours before start_datetime)
  ↓ Service date arrives
  ↓ User taps [Complete & Invoice]
COMPLETED (gray checkmark, archived from main list)
  ↓ Invoice created and linked
  ↓ Invoice paid
PAID (moved to Past section)

Alternative paths:
PENDING/CONFIRMED → [Cancel] → CANCELLED (strike-through, always collapsed)
CONFIRMED → [No-show] → NO_SHOW (red badge, affects customer trust)
```

---

## Integration with Existing Features

### 1. Item Catalog (Week 21-22)

**Enhancement:**
```dart
Add/Edit Catalog Item screen:
  
  [ ] Enable bookings
    When checked:
      Duration: [30] minutes  ← Required, default 30
      (Used to determine picker type: time vs date range)
      
  Service automatically bookable when this is checked.
  Appears in booking service picker.
```

**Code Reuse:** 100% reuse of ItemCatalogScreen in pick mode

---

### 2. Party Management (Week 9B)

**Integration Points:**
- Customer picker: Reuse `PartyPickerField` widget (0 new code)
- Confirmation messages: Reuse WhatsApp/SMS OS intent pattern (0 new code)
- Party detail screen: Add "Bookings" tab showing:
  - Upcoming bookings (next 30 days)
  - Past bookings (last 90 days)
  - No-show rate (affects trust/credit decisions)
  - Total bookings count
  - Average booking value

**Code Reuse:** 90% reuse, +10% for bookings tab UI

---

### 3. Invoice Creation + Automatic Transaction Recording (Week 21-22)

**Design Principle:** Invoice payment → Transaction creation is fully automatic. Zero manual entry, impossible to forget.

> **📋 Note:** This is an **invoice-layer enhancement** (Week 21-22) that benefits bookings and all invoice types. The bookings feature simply triggers invoice creation; the automatic transaction creation is universal and works for:
> - ✅ Booking invoices (from [Complete & Paid])
> - ✅ Quote invoices (converted quote → [Mark as Paid])
> - ✅ Standalone invoices (created directly → [Mark as Paid])
>
> This design lives here because bookings are the **primary driver** for this enhancement — service businesses can't afford manual transaction entry after every appointment.

#### Flow 1: [Complete & Paid] (One-Tap Payment Recording)

```dart
User taps [Complete & Paid] on booking:

1. Show quick payment method picker (bottom sheet):
   ┌─────────────────────────────┐
   │ Payment Received            │
   │ ₹1,200                      │
   │                             │
   │ [Cash*] [UPI] [Card] [Bank] │  (* = last used for this customer)
   │                             │
   │ [Other Date...]            │
   └─────────────────────────────┘
   
2. User taps payment method (Cash/UPI/Card) → Auto-complete:
   a. Create invoice (status: paid, paid_at: now, payment_method: Cash)
   b. AUTO-CREATE TRANSACTION:
      transaction = Transaction(
        type: TransactionType.income,
        mode: TransactionMode.business,
        amount: invoice.total,
        partyId: booking.customerPartyId,
        paymentMethod: PaymentMethod.cash,
        description: 'Invoice ${invoice.invoiceNo}',
        linkedInvoiceId: invoice.id,
        linkedBookingId: booking.id,
        businessId: booking.businessId,
        date: DateTime.now(),
      );
   c. Update booking (status: paid)
   
3. Done! Income recorded in 2 taps.
```

**Smart Defaults:**
- Payment method: Remember last method used per customer (95% same method)
- Date: Defaults to today (95% of bookings paid on completion)
- Amount: Auto-filled from booking.totalAmount

#### Flow 2: [Invoice Later] (Delayed Payment)

```dart
User taps [Invoice Later] on booking:

1. Create draft invoice (status: draft, unpaid)
2. Update booking (status: completed, invoiceId: invoice.id)
3. Navigate to InvoiceDetailScreen
4. User reviews, edits, [Send] to customer

--- Later, when customer pays ---

5. User opens invoice detail → taps [Mark as Paid]
6. Quick payment method picker appears (same as above)
7. User selects method → AUTOMATIC TRANSACTION CREATED
8. Invoice status: paid, booking status: paid
```

#### Universal Automatic Transaction Creation

**Applies to ALL invoice payments:**
- ✅ Booking invoices (from [Complete & Paid])
- ✅ Quote invoices (converted quote → [Mark as Paid])
- ✅ Standalone invoices (created directly → [Mark as Paid])

**Event-driven architecture:**
```dart
// InvoiceRepositoryImpl
Future<void> markAsPaid({
  required Invoice invoice,
  required PaymentMethod paymentMethod,
  required DateTime paidDate,
  double? partialAmount,  // Optional: for partial payments
}) async {
  // 1. Update invoice
  invoice.status = partialAmount != null && partialAmount < invoice.total
      ? InvoiceStatus.partiallyPaid
      : InvoiceStatus.paid;
  invoice.paidAt = paidDate;
  invoice.paymentMethod = paymentMethod.name;
  invoice.paidAmount = (invoice.paidAmount ?? 0) + (partialAmount ?? invoice.total);
  await _db.update('invoices', invoice.toMap());
  
  // 2. AUTO-CREATE TRANSACTION (atomic)
  final amountToRecord = partialAmount ?? (invoice.total - (invoice.paidAmount ?? 0));
  final transaction = Transaction(
    type: TransactionType.income,
    mode: TransactionMode.business,
    amount: amountToRecord,
    partyId: invoice.customerPartyId,
    paymentMethod: paymentMethod,
    description: partialAmount != null
        ? 'Partial payment - Invoice ${invoice.invoiceNo}'
        : 'Invoice ${invoice.invoiceNo}',
    linkedInvoiceId: invoice.id,
    linkedBookingId: invoice.bookingId,
    businessId: invoice.businessId,
    date: paidDate,
  );
  await transactionRepository.add(transaction);
  
  // 3. Update linked booking (if exists)
  if (invoice.bookingId != null && invoice.status == InvoiceStatus.paid) {
    await _db.update('bookings', 
      {'status': 'paid'}, 
      where: 'id = ?', 
      whereArgs: [invoice.bookingId]);
  }
}
```

#### Partial Payment Support

```dart
User can record multiple payments:

 Invoice: ₹10,000 (wedding photography)
  Payment 1: ₹3,000 (advance) → Transaction 1 created
  Payment 2: ₹7,000 (final)   → Transaction 2 created
  
Invoice tracks total paid_amount, links to both transactions.
```

#### Data Integrity Rules

1. **Paid invoices are locked** — can't edit amount/items after payment
2. **Transaction deletion shows warning** — "This transaction is linked to Invoice INV-2024-042. Deleting will affect invoice status."
3. **Bidirectional links** — Invoice → Transaction, Transaction → Invoice, Transaction → Booking
4. **Business isolation** — transaction.businessId ensures multi-business accounting accuracy

**Code Reuse:** 95% reuse of invoice creation flow, +5% for automatic transaction creation

---

### 4. Business Selector (Week 21-22)

**Integration:**
- If multiple businesses exist, show business dropdown in create booking form
- If single business, auto-assign booking.businessId
- Reuse exact same dropdown widget from quote_builder_screen

**Code Reuse:** 100% reuse

---

### 5. Notifications (Local)

**Use `flutter_local_notifications` directly** (already in dependencies)

```dart
class BookingNotificationService {
  Future<void> scheduleReminder(Booking booking) async {
    final reminderTime = booking.startDatetime.subtract(Duration(hours: 24));
    
    await flutterLocalNotificationsPlugin.zonedSchedule(
      booking.id,  // notification ID = booking ID
      'Reminder: ${booking.customerName}',
      '${booking.serviceName} tomorrow at ${formatTime(booking.startDatetime)}',
      tz.TZDateTime.from(reminderTime, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'bookings_channel',
          'Booking Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    
    // Update booking record
    booking.notificationScheduledAt = reminderTime.toIso8601String();
  }
  
  Future<void> cancelReminder(int bookingId) async {
    await flutterLocalNotificationsPlugin.cancel(bookingId);
  }
}
```

**Store notification metadata on booking itself** (notification_scheduled_at column)

**DO NOT reuse ScheduledPayment table** — it's for recurring bills, not one-time booking reminders

---

### 6. Global Search (Week 5)

**Enhancement:**
```dart
Extend global search to include bookings:

Search query: "Raj"
Results:
  Transactions (2)
    - Raj Enterprises • ₹5,000 • 15 Feb
  
  Credits (1)
    - Raj • ₹2,000 pending
  
  Bookings (1)  ← NEW
    - Raj • Airport Transfer • 27 Feb 2:30 PM • Pending

Search matches:
  - booking.customer_name
  - booking.service_name
  - booking.notes
  - booking.booking_ref (BK-2026-042)
```

**Effort:** +3 hours to extend search provider

---

### 7. Reports Integration

**Separate from Financial Reports:**

Add "Bookings Overview" card in Reports tab:

```
┌─────────────────────────────────────┐
│ Reports                             │
├─────────────────────────────────────┤
│ [Monthly] [P&L] [Categories] [Bookings]  ← New tab
│                                     │
│ Bookings This Month                 │
│  Completed: 45 (₹67,500)           │
│  Confirmed: 12 (₹18,000 pipeline)  │
│  Pending: 3                         │
│  No-shows: 2 (4% rate)             │
│                                     │
│ Service Performance:                │
│  1. Consultation (18) — ₹27,000    │
│  2. Room Booking (8) — ₹32,000     │
│  3. Airport Transfer (12) — ₹14,400│
│                                     │
│ [View All Bookings]                 │
└─────────────────────────────────────┘
```

**Key Decision:**
- Bookings are **operational metrics**, not financial metrics
- Only invoiced bookings appear in P&L (via invoice records)
- Confirmed bookings = "pipeline" (future income), not realized income

**Effort:** +5 hours for reports card

---

## Vertical-Specific Behaviors

**All stored in single `bookings` table, UI adapts based on duration:**

### Appointments (< 3 hours)
```dart
Example: Doctor consultation (30 min)

Create form shows:
  - Time picker (Today 3:00 PM dropdown)
  - Single date + time

List item shows:
  - 3:00 PM (time prominent)
  - Dr. Sharma • Consultation
```

### Reservations (≥ 24 hours)
```dart
Example: Homestay room (3 nights = 4320 min)

Create form shows:
  - Date range picker (28 Feb → 2 Mar)
  - "Check-in" and "Check-out" labels

List item shows:
  - 28 Feb - 2 Mar
  - Kumar Family • Room 101
  - 3 nights • ₹4,500
```

### Trips (3-24 hours)
```dart
Example: Airport transfer (90 min)

Create form shows:
  - Date + time picker (27 Feb 2:30 PM)
  - Duration shown but not editable

List item shows:
  - 27 Feb 2:30 PM
  - Raj • Airport Transfer
  - 1.5 hrs • ₹1,200
```

### Packages (Multi-day, < 24 hours per day)
```dart
Example: 3-day tour (can be modeled as reservation)

Create form shows:
  - Date range picker
  - Notes field for itinerary

User can create package as item in catalog:
  - "3-Day Kashmir Tour"
  - Duration: 4320 minutes (3 days)
  - Price: ₹25,000
```

**No separate booking types in DB** — duration determines UI behavior.

---

## Implementation Phases

### Prerequisites (Must Be Complete)
- ✅ Week 21-22: Billing (invoices, catalogs, PDF)
- ✅ Week 9B: Party Management (phone, email, WhatsApp messages)
- ✅ `flutter_local_notifications` package configured (already in deps)

---

### Phase 1: Core Bookings (Week 25-26, ~55 hours)

**DB & Models:**
- [ ] DB migration v11: `bookings` table with indexes
- [ ] Extend `item_catalog` table: duration_minutes, is_bookable columns
- [ ] Booking model (freezed, equatable)
- [ ] BookingRepository interface (domain layer)
- [ ] BookingRepositoryImpl (SQLite, data layer)

**State Management:**
- [ ] BookingsProvider (StateNotifier + AsyncValue)
- [ ] bookingByIdProvider (for detail screen)
- [ ] upcomingBookingsProvider (filtered: next 7 days)

**UI Screens:**
- [ ] Bookings list screen:
  - Date-grouped list (TODAY, TOMORROW, THIS WEEK, PAST)
  - Status badges with text labels
  - Primary action button on each card
  - Swipe actions (complete left, cancel right)
  - Filter options (top-right icon)
- [ ] Booking detail screen:
  - Customer info with WhatsApp/Call buttons
  - Service details with notes
  - Status display
  - Action buttons (Confirm, Complete & Invoice, Cancel, No-show)
- [ ] Create booking bottom sheet:
  - Customer picker (reuse PartyPickerField)
  - Service picker (reuse catalog picker with is_bookable filter)
  - Smart date/time picker (buttons: Today/Tomorrow + calendar icon)
  - Single [Book] button

**Business Logic:**
- [ ] Status flow: pending → confirmed → completed
- [ ] Booking reference generation (BK-YYYY-NNN format)
- [ ] Date/time picker intelligence (duration-based)
- [ ] Invoice creation on completion (pre-fill draft)

**Deliverable:** Basic booking CRUD working, manual notifications

---

### Phase 2: Integrations (Week 26, ~20 hours)

**Catalog Integration:**
- [ ] Add "Enable bookings" checkbox to catalog item form
- [ ] Add duration field (default 30 minutes)
- [ ] Filter bookable items in service picker

**Invoice Integration:**
- [ ] "Complete & Invoice" button implementation
- [ ] Pre-fill invoice from booking (customer, items, amount minus advance)
- [ ] Link invoice.bookingId foreign key
- [ ] Navigate to InvoiceDetailScreen for review
- [ ] Auto-update booking status when invoice paid

**Party Integration:**
- [ ] Add "Bookings" tab to party detail screen
- [ ] Show upcoming/past bookings
- [ ] Show no-show rate
- [ ] Show total bookings + avg value

**Messages Integration:**
- [ ] [Confirm] button → WhatsApp OS intent with template message
- [ ] Template: "Hi [name], your [service] is confirmed for [date] [time]. ₹[amount]. — [business]"

**Deliverable:** Seamless flow from booking → invoice → payment

---

### Phase 3: Notifications & Polish (Week 27, ~15 hours)

**Notifications:**
- [ ] BookingNotificationService using local_notifications
- [ ] Schedule reminder 24h before start_datetime when status → confirmed
- [ ] Cancel notification when booking cancelled/completed
- [ ] Notification tap → opens booking detail screen
- [ ] Store notification_scheduled_at timestamp on booking

**Search Integration:**
- [ ] Extend global search to include bookings
- [ ] Search by customer name, service name, notes, booking ref

**Reports Integration:**
- [ ] "Bookings Overview" card in Reports tab
- [ ] Stats: completed count/amount, confirmed pipeline, no-show rate
- [ ] Top services list (by booking count + revenue)
- [ ] [View All Bookings] button → navigates to bookings list

**Speed-dial FAB:**
- [ ] Add "New Booking" action when Business Mode enabled
- [ ] Opens create booking bottom sheet

**Polish:**
- [ ] Empty state (no bookings yet)
- [ ] Loading states (skeleton cards)
- [ ] Error handling (failed invoice creation, etc.)
- [ ] Confirmation dialogs (cancel, no-show actions)
- [ ] Multi-day booking duration display (e.g., "3 nights")

**Deliverable:** Production-ready bookings feature, fully integrated

---

### Phase 4: Optional Enhancements (Post-launch, ~30 hours)

**Only build if users demand:**

- [ ] Calendar view toggle ([List] [Week] tabs)
  - Week view: 7 columns, 9AM-6PM rows
  - Drag-to-reschedule
  - Color-coded status
  - Uses `table_calendar` package
  - **Effort:** +15 hours

- [ ] Recurring bookings
  - "Repeat weekly" checkbox
  - Generate series of bookings
  - Link parent/child bookings
  - **Effort:** +10 hours

- [ ] Staff assignment (multi-staff businesses)
  - Add `staff_member_id` column
  - Filter bookings by staff
  - Calendar view per staff
  - **Effort:** +15 hours

- [ ] Conflict detection
  - Check overlapping appointment times
  - Room double-booking prevention
  - Configurable per service type
  - **Effort:** +5 hours

---

## Testing Checklist

### Unit Tests
- [ ] Booking model creation, copyWith, equality
- [ ] Repository CRUD operations
- [ ] Status flow transitions
- [ ] Booking reference generation (BK-YYYY-NNN)
- [ ] Date/time calculations (multi-day duration, reminders)

### Widget Tests
- [ ] Bookings list renders correctly
- [ ] Date grouping (TODAY, TOMORROW, etc.)
- [ ] Status badges display correct text + color
- [ ] Primary action buttons appear based on status
- [ ] Create form validation (customer, service required)
- [ ] Swipe actions trigger correct callbacks

### Integration Tests
- [ ] Create booking → appears in list
- [ ] Confirm booking → status updates, WhatsApp intent called
- [ ] Complete booking → invoice created with correct values
- [ ] Invoice paid → booking status updates
- [ ] Cancel booking → status updates, removed from upcoming
- [ ] No-show tracking → party detail shows no-show count
- [ ] Notification scheduled when confirmed
- [ ] Search finds bookings by customer name

### Manual Testing Scenarios
- [ ] Doctor: 30-min appointment, confirm, complete, invoice paid
- [ ] Homestay: 3-night reservation, check-in/out dates, advance payment
- [ ] Cab: Airport transfer, trip notes, complete on same day
- [ ] Travel agency: Multi-day package, group booking, installments
- [ ] No-show scenario: customer doesn't show, affects trust score
- [ ] Edit booking: change time, change amount, add notes
- [ ] Duplicate booking: copy existing for next week

---

## Open Questions & Decisions

### 1. Auto-invoice or manual?
**Decision:** Create draft invoice, user reviews/edits before sending
- Allows service fee adjustments
- User maintains control
- Follows existing invoice flow pattern

### 2. How to handle advance payments?
**Decision:** 
- Advance amount field in booking (optional)
- When complete & invoice: `invoice.amount = total - advance`
- Note in invoice: "Advance ₹500 already received"
- No separate transaction created for advance (recorded on booking)

### 3. Should bookings appear in financial reports?
**Decision:** No, they're operational metrics
- Only invoiced bookings → income reports (via invoice records)
- Bookings have separate "pipeline" reports
- Keeps P&L clean (accrual accounting, not cash)

### 4. Recurring bookings in v1?
**Decision:** No, add in Phase 4 if users request
- Manual duplicate booking is sufficient for v1
- Adds significant complexity
- Validate demand first

### 5. Calendar view in v1?
**Decision:** No, list view only
- List is simpler, faster to build
- Most small businesses (< 10 bookings/day) don't need visual calendar
- Add in Phase 4 if users demand it

### 6. Device calendar integration?
**Decision:** No read permission, write-only option
- Offer "Add to Calendar" button (opens system calendar, zero permission)
- Never read device calendar (privacy violation)
- User can use their preferred calendar app alongside

---

## Success Metrics

**Week 30 (3 weeks post-launch):**
- 100+ bookings created by 10+ businesses
- 70%+ booking completion rate (not cancelled/no-show)
- 80%+ invoices created via "Complete & Invoice" (vs manual)
- Zero critical bugs
- < 3 feature requests for calendar view (validates list-first approach)

**Week 40 (3 months post-launch):**
- 1,000+ bookings/month across all users
- 5+ different business types using feature (not just one vertical)
- Retention: 60%+ of booking users still active
- NPS: 8+ from business mode users

---

## Risk Mitigation

### Risk 1: Users demand calendar view immediately
**Mitigation:** Phase 4 calendar spec already designed (+15 hours)
**Likelihood:** Medium (30% of users may request)

### Risk 2: Notification delivery unreliable
**Mitigation:** Use Android AlarmManager for critical reminders (guaranteed delivery)
**Likelihood:** Low (local_notifications is battle-tested)

### Risk 3: Invoice integration feels clunky
**Mitigation:** Ensure pre-fill is 95% accurate, user edits in familiar invoice screen
**Test:** Manual testing with 5 verticals before launch

### Risk 4: Multi-staff businesses can't use it
**Mitigation:** Phase 4 staff assignment ready to build if validated
**Acceptance:** Single-staff businesses are 80% of target market (sufficient for v1)

---

## Future Enhancements (Year 2+)

### Online Booking Portal (Relaxes privacy rule)
**Concept:** Customer-facing web page for self-booking
- Relaxes "zero network" rule
- Requires minimal PHP/Node server (open-source, self-hostable)
- Customer sees availability, books slot
- Notification sent to business owner's KashCube app
- Business confirms/rejects
- **Effort:** ~8 weeks (full web app + API)

### SMS Gateway Integration (Premium tier)
**Concept:** Two-way SMS for confirmations (India regulation-compliant)
- Use approved SMS gateway (Twilio India, ValueFirst)
- Send confirmation SMS automatically (not WhatsApp fallback)
- Customer replies YES to confirm
- **Cost:** ₹0.10-0.25 per SMS
- **Effort:** ~2 weeks integration

### Payment Link Integration
**Concept:** Collect advance via UPI QR/link
- Generate UPI deepllink: `upi://pay?pa=business@upi&pn=Name&am=1200`
- Send in confirmation message
- Customer pays → app shows "Paid" badge (manual mark by business)
- **Effort:** ~1 week

---

## Appendix: Status Badge Colors

| Status | Color | Text | Badge Style |
|--------|-------|------|-------------|
| Pending | Yellow/Orange | "Pending" | Outlined badge, `warning` theme color |
| Confirmed | Green | "Confirmed" | Filled badge, `success` theme color |
| Completed | Gray | "Completed ✓" | Filled badge, `surfaceVariant` color |
| Cancelled | Gray | "Cancelled" | Strike-through text, no badge |
| No-show | Red | "No-show" | Filled badge, `error` theme color |

---

## Appendix: Booking Reference Format

```
BK-YYYY-NNN

Examples:
  BK-2026-001  (first booking of 2026)
  BK-2026-042  (42nd booking of 2026)
  BK-2027-001  (resets each year)

Generation logic:
  1. Query max booking_ref for current year
  2. Parse number, increment
  3. Format with zero-padding (3 digits)
  4. Store in bookings.booking_ref column
```

---

## Appendix: WhatsApp Message Templates

### Confirmation
```
Hi [customer_name],

Your [service_name] is confirmed for [date] [time].

Amount: ₹[total_amount]
[if advance > 0: Advance paid: ₹[advance_amount]]

See you then!
— [business_name]
```

### Reminder (day before)
```
Reminder: [customer_name]

Your [service_name] is tomorrow at [time].

— [business_name]
```

### Cancellation
```
Hi [customer_name],

Your [service_name] appointment on [date] [time] has been cancelled.

Please call to reschedule.
— [business_name]
```

**Note:** All messages editable in WhatsApp before sending (OS intent opens WhatsApp with pre-filled text)

---

**End of Specification**

**Next Steps:**
1. Complete Week 21-22 (Billing) + Week 9B (Party Management)
2. Review this spec with test users (5 businesses)
3. Build Phase 1 (Core Bookings)
4. Validate with real bookings data
5. Build Phase 2-3 (Integrations + Polish)
6. Launch and monitor metrics
