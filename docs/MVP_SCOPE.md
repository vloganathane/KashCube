# MVP Scope Definition
# ExpenseOwl - Minimum Viable Product

**Timeline:** 6 weeks  
**Target:** Personal + Small Business (Indian market)  
**Platform:** Android first (iOS later)

---

## 1. MVP Philosophy

### 1.1 Core Principle
**"Use it every day for 2 weeks"**

If we (developers) don't use ExpenseOwl daily after Week 6, MVP has failed. The app must solve a real problem immediately.

### 1.2 What MVP Is
✅ Core functionality that works flawlessly  
✅ Simple, intuitive UI  
✅ Reliable SMS parsing for top 5 banks/UPI apps  
✅ Basic tracking + reports  
✅ Essential privacy (PIN lock)

### 1.3 What MVP Is NOT
❌ Feature-complete  
❌ Polished animations  
❌ Multi-language support  
❌ Advanced analytics  
❌ Cloud sync  
❌ Invoice generation

---

## 2. In-Scope Features

### 2.1 Transaction Management ✅

#### Auto-Capture (SMS Parsing)
- **UPI Apps:** PhonePe, Google Pay, Paytm, BHIM (top 4)
- **Banks:** HDFC, ICICI, SBI, Axis, Kotak (top 5)
- **Transaction Types:**
  - UPI sent/received
  - Credit card spend
  - Debit card spend
  - Bank account debits/credits
  
**Success Criteria:** 90%+ accuracy on supported banks/apps

#### Manual Entry
- Add income/expense manually
- Fields:
  - Amount *
  - Category *
  - Party name (optional)
  - Date (default: today)
  - Notes (optional)
  - Payment method
  
#### Edit/Delete
- Edit any field
- Delete with confirmation
- Soft delete (keep in database with `deleted_at`)

#### Categories
**10 Pre-defined Categories:**
1. Food & Dining
2. Transportation
3. Shopping
4. Bills & Utilities
5. Healthcare
6. Entertainment
7. Groceries
8. Education
9. Business Expense
10. Other

**Category Management:**
- View categorized transactions
- Re-categorize existing transactions
- Cannot add custom categories (MVP limitation)

---

### 2.2 Credit Management (Udhar/Khata) ✅

#### Give Credit
- Record money given to customers
- Fields:
  - Customer name *
  - Amount *
  - Date
  - Due date (optional)
  - Notes
  
#### Track Pending Credits
- See all outstanding credits
- Total amount pending
- Customer-wise breakdown
- Overdue highlighting (if due date passed)

#### Auto-Link Repayments
**Core Differentiator:**
When customer pays back:
1. Detects Payment SMS (UPI received from that customer)
2. Matches customer name (fuzzy matching)
3. Suggests linking to pending credit
4. User confirms/rejects
5. Updates credit status (partial/fully paid)

**Example:**
```
Day 1: Given ₹5000 credit to "Ramesh"
Day 7: Received SMS "Rs.2000 from RAMESH KUMAR via PhonePe"
App shows: "Link this ₹2000 to Ramesh's pending credit?"
User taps "Yes"
Result: Ramesh now owes ₹3000
```

#### Credit History
- View all credits (pending + cleared)
- Customer detail page:
  - Total credit given
  - Total repaid
  - Pending amount
  - Transaction history
  
---

### 2.3 Reports & Analytics ✅

#### Daily Summary
- Today's income
- Today's expenses
- Net (income - expenses)
- Transaction count
- Top 3 categories

#### Monthly View
- Current month stats
- Category breakdown (pie chart)
- Day-by-day trend (line graph)
- Compare with last month

#### Yearly Overview
- Year total income/expense
- Month-by-month bar chart
- Best/worst month
- Top category

#### Filters
- Date range picker
- Category filter
- Income vs Expense toggle
- Search by merchant/party name

**Charts Library:** fl_chart (simple, no-frills)

---

### 2.4 Search & Filter ✅

#### Search
- Search by:
  - Party/merchant name
  - Amount (exact or range)
  - Category
  - Date range
  - Notes/description
  
#### Sort
- Date (newest first - default)
- Amount (high to low)
- Category name

#### Quick Filters
- Today
- This Week
- This Month
- Last Month
- Custom Range

---

### 2.5 Security & Privacy ✅

#### PIN Lock
- 4-digit PIN (mandatory on first launch)
- Lock app on minimize
- Auto-lock after 5 minutes inactive
- Change PIN in settings

#### Biometric (Optional)
- Fingerprint unlock (if device supports)
- Face unlock (if device supports)
- Fallback to PIN if biometric fails

#### SMS Permissions
- Request READ_SMS permission
- Explain why we need it (educational screen)
- Allow "deny permission" (app still works with manual entry)
- No SMS sent to external servers

#### Data Privacy
- All data stored locally (SQLite)
- No internet connection required
- No analytics tracking
- No login/signup required

---

### 2.6 Backup & Restore ✅

#### Local Backup
- Export database to `.db` file
- Save to device storage / share via file manager
- Encrypted zip (optional, password-protected)

#### Restore
- Import `.db` file
- Overwrites current data (with warning)
- Validate file before import

**No Cloud Backup** (MVP limitation - future feature)

---

### 2.7 Settings ✅

#### Preferences
- App PIN (set/change)
- Biometric toggle
- Auto-categorize transactions (on/off)
- Hide/show balance on home screen

#### Data Management
- Backup database
- Restore database
- Clear all data (with confirmation)
- Export to CSV (simple export)

#### About
- App version
- Privacy policy
- How SMS parsing works (educational)
- Credits & license

---

## 3. Out-of-Scope (MVP)

### 3.1 Deferred Features

#### Not in MVP (Build Later)
1. **Budget Management** - Add in Week 7-8
   - Set monthly budgets by category
   - Overspend alerts
   - Budget vs actual comparison

2. **Invoice Generation** - Week 11+
   - Create GST invoices
   - Share PDF invoices
   - Business branding

3. **Multi-Currency** - Future
   - Foreign transactions
   - Currency conversion

4. **Recurring Transactions** - Week 9+
   - Auto-add monthly bills
   - Subscription tracking

5. **Tags** - Week 10+
   - Add custom tags to transactions
   - Tag-based filtering

6. **Advanced Analytics** - Phase 2
   - Spending insights
   - ML predictions
   - Cashflow forecasts

7. **Multi-Language** - Phase 2
   - Hindi, Tamil, Telugu support
   - Regional SMS parsing

8. **Receipt Scanning** - Phase 3
   - OCR for receipts
   - Attach photos to transactions

9. **Cloud Sync** - Phase 3 (if needed)
   - Multi-device sync
   - Encrypted cloud backup

10. **Multi-User** - Phase 2
    - Shared accounts
    - Family mode
    - Business team access

11. **Tax Reports** - Phase 2
    - GST reports
    - Income tax statements

12. **Notifications** - Week 9+
    - Due date reminders
    - Collection reminders

13. **Widgets** - Week 10+
    - Home screen widget
    - Quick add transaction

14. **Dark Mode** - Week 8 (nice-to-have)

15. **Export Options** - Week 9+
    - Export to PDF
    - Share reports via WhatsApp

---

## 4. MVP User Stories

### 4.1 As a Small Business Owner

**Story 1: Auto-Track UPI Transactions**
```
Given: I accept UPI payments from customers
When: Customer pays via PhonePe/GPay
Then: Transaction auto-captured in app
And: I can see it in today's summary
```

**Story 2: Manage Customer Credits**
```
Given: I give credit to regular customer "Ramesh"
When: I record ₹5000 credit in app
Then: I can see pending amount of ₹5000
When: Ramesh pays ₹2000 via UPI
Then: App suggests linking payment to credit
And: Pending amount updates to ₹3000
```

**Story 3: Monthly Reports**
```
Given: Month end arrived
When: I open monthly report
Then: I see total income, expenses, and net profit
And: I see category-wise breakdown
And: I can compare with last month
```

### 4.2 As a Freelancer

**Story 1: Track Project Payments**
```
Given: Client paid me ₹50,000
When: Payment SMS arrives
Then: Auto-captured as income
And: I can add client name manually
And: I can categorize as "Business Income"
```

**Story 2: Track Expenses**
```
Given: I spent ₹450 on Swiggy
When: Payment SMS arrives
Then: Auto-captured as expense
And: Auto-categorized as "Food & Dining"
And: I can edit if wrong
```

**Story 3: Yearly Tax Prep**
```
Given: Tax filing time
When: I open yearly report
Then: I see total income for year
And: I can export to CSV
And: I can filter by business expenses only
```

### 4.3 As a Privacy-Conscious User

**Story 1: No Data Leaks**
```
Given: I installed ExpenseOwl
When: I use the app
Then: No data sent to internet
And: All data stays on my phone
And: I can verify no permissions except SMS
```

**Story 2: Secure with PIN**
```
Given: I set up 4-digit PIN
When: App is closed/minimized
Then: PIN required to re-open
And: No one else can see my transactions
```

**Story 3: Backup Control**
```
Given: I want to backup my data
When: I tap "Backup Database"
Then: File saved to my device
And: I can share it via file manager
And: I control where it goes (not auto-cloud)
```

---

## 5. Success Metrics (MVP)

### 5.1 Development Milestones

**Week 1-2: Foundation**
- [x] Flutter project setup
- [ ] Database schema implemented
- [ ] SMS permissions working
- [ ] Basic transaction CRUD
- [ ] SMS parser for top 2 UPI apps working

**Week 3-4: Core Features**
- [ ] All 5 banks + 4 UPI apps parsing
- [ ] Credit management (give/track/link)
- [ ] Categories working
- [ ] Home screen with daily summary

**Week 5-6: Polish & Reports**
- [ ] Monthly/yearly reports
- [ ] Charts rendering correctly
- [ ] PIN lock working
- [ ] Backup/restore working
- [ ] Bug fixes & testing

### 5.2 Quality Metrics

**SMS Parsing Accuracy:** ≥90%
- Test with 100 real SMS samples
- Success = correctly extracted amount + party

**Performance:**
- App launch: <2 seconds (cold start)
- Transaction list scroll: 60 FPS
- Database query: <100ms
- Parse SMS: <100ms

**Reliability:**
- Zero crashes in self-dogfooding
- No data loss during backup/restore
- No duplicate transactions (deduplication working)

**Usability:**
- New user can add manual transaction in <30 seconds
- New user understands SMS parsing in <2 minutes
- PIN setup takes <1 minute

### 5.3 Business Validation

**Self-Dogfooding:**
- All developers use app for 2 weeks (Week 7-8)
- Track ≥20 real transactions each
- Give credit to ≥2 people
- Use monthly report at month-end

**Friends & Family Beta (Week 9-10):**
- 10 beta testers
- Each uses for 1 month
- Collect feedback on top 3 pain points
- Track crash rate

**Success Criteria:**
- ✅ 80%+ beta testers continue after trial
- ✅ NPS score ≥40
- ✅ <5% crash rate
- ✅ Top requested feature = something NOT in MVP (validation that core is solid)

---

## 6. MVP Technical Constraints

### 6.1 Technology Limits

**Framework:** Flutter 3.16+ (stable channel)
**Min SDK:** Android 8.0 (API 26) - covers 95%+ users
**Target SDK:** Android 14 (API 34)
**Database:** SQLite (sqflite package)
**State:** Riverpod 2.4+ (no Provider, no BLoC)
**SMS:** telephony 0.2.0 (Android only)

**No Third-Party Services:**
- No Firebase (Analytics, Crashlytics, etc.)
- No Sentry
- No cloud database
- No payment gateway (free app)

### 6.2 Design Constraints

**UI:** Material Design 3 (default Flutter theme)
**Colors:** Single brand color (customizable in code)
**Icons:** Material Icons (built-in)
**No Custom Illustrations:** Text + icons only
**No Onboarding Flow:** Jump straight to permission request

### 6.3 Data Constraints

**SMS History:** Only parse new SMS (after app install)
- No scanning old messages (privacy concern)
- User can manually add historical transactions

**Storage:** 
- App size: <20 MB
- Database: ~1 MB per 1000 transactions (minimal)

**No Network:**
- Zero API calls
- No update checks
- No telemetry

---

## 7. MVP Screens (Detailed)

### 7.1 Home Screen

**Top Section:**
- Greeting: "Good Morning, User!"
- Today's Balance: ₹X,XXX (Income - Expense)
- Quick Stats:
  - Income today: ₹XXX (green)
  - Expenses today: ₹XXX (red)

**Middle Section:**
- "Recent Transactions" (last 10)
  - Transaction tile:
    - Icon (category icon)
    - Merchant name
    - Amount (colored: green income, red expense)
    - Date & time
    
**Bottom:**
- FAB (Floating Action Button): "+ Add Transaction"

**App Bar:**
- Logo/Title: "ExpenseOwl"
- Actions:
  - Search icon
  - Settings icon

### 7.2 Transactions Screen (Full List)

**Top:**
- Filter chips: Today, This Week, This Month, Custom
- Search bar

**List:**
- Grouped by date
  - Date header (e.g., "Today", "Yesterday", "Feb 22")
  - Transactions under each date
  
**Tile:**
- Tap to view details
- Long-press for quick actions (Edit/Delete)

### 7.3 Add/Edit Transaction Screen

**Form Fields:**
1. Amount (number input, required)
2. Category (dropdown, 10 options)
3. Type (Income / Expense toggle)
4. Party Name (text, optional)
5. Date (date picker, default today)
6. Payment Method (Cash, UPI, Card, Bank Transfer)
7. Notes (multi-line text, optional)

**Buttons:**
- Save (primary)
- Cancel (secondary)

### 7.4 Transaction Detail Screen

**Display:**
- Amount (large, colored)
- Category (with icon)
- Party name
- Date & time
- Payment method
- Notes
- SMS body (if auto-captured)
- Reference ID (if available)

**Actions:**
- Edit button
- Delete button

### 7.5 Credits Screen

**Top:**
- Total Pending: ₹XX,XXX (highlighted)
- Total Given: ₹XX,XXX
- Total Collected: ₹XX,XXX

**Tabs:**
- Pending (default)
- Cleared

**Pending List:**
- Customer name
- Amount pending
- Due date (if set)
- Overdue badge (red) if past due

**Tap on Customer:**
- Opens Customer Detail Screen

### 7.6 Customer Detail Screen

**Header:**
- Customer name
- Phone number (if captured from SMS)

**Stats:**
- Total credit given: ₹X,XXX
- Total repaid: ₹X,XXX
- Pending: ₹X,XXX

**History:**
- List of all credits given
- List of all repayments (linked)
- Grouped by date

**Actions:**
- "Give Credit" button
- "Record Payment" button

### 7.7 Reports Screen

**Tabs:**
- Daily
- Monthly (default)
- Yearly

**Monthly View:**
- Month selector (Feb 2026)
- Cards:
  - Total Income (green)
  - Total Expense (red)
  - Net (Income - Expense)
  - Savings Rate (%)
  
- Pie Chart: Category breakdown
- Line Chart: Daily trend
- Compare with last month (simple text)

**Yearly View:**
- Year selector (2026)
- Cards:
  - Total Income
  - Total Expense
  - Net
  
- Bar Chart: Month-by-month
- Top category (highest expense)

### 7.8 Settings Screen

**Sections:**

1. **Security**
   - Change PIN
   - Biometric lock (toggle)

2. **Preferences**
   - Auto-categorize (toggle, default on)
   - Hide balance on home (toggle, default off)

3. **Data**
   - Backup Database
   - Restore Database
   - Clear All Data

4. **About**
   - Version: 1.0.0
   - Privacy Policy (simple markdown page)
   - How it Works (educational)

---

## 8. MVP Testing Plan

### 8.1 Unit Tests

**Models:**
- Transaction serialization
- Category validation

**Database:**
- CRUD operations
- Query correctness

**SMS Parser:**
- 100+ SMS samples
- Edge cases (malformed SMS)

**Target:** 80%+ code coverage

### 8.2 Widget Tests

**Screens:**
- Home screen renders
- Add transaction form validation
- Settings screen navigation

**Widgets:**
- Transaction tile displays correctly
- Charts render without errors

**Target:** All critical user paths covered

### 8.3 Integration Tests

**Flows:**
1. Add transaction → View in list
2. Parse SMS → Auto-create transaction
3. Give credit → Link repayment
4. Backup → Restore → Verify data

**Target:** 5-10 key user journeys

### 8.4 Manual Testing

**Devices:**
- Test on ≥3 Android devices (different manufacturers)
- Low-end device (2GB RAM)
- Mid-range device (4GB RAM)
- High-end device (8GB+ RAM)

**Scenarios:**
- Fresh install
- Upgrade from previous version (future)
- Low storage warnings
- High transaction volume (1000+ transactions)

### 8.5 Beta Testing

**Duration:** 2 weeks (Week 9-10)
**Testers:** 10 friends & family
**Distribution:** APK via WhatsApp / Google Drive
**Feedback:** Google Form

**Questions:**
1. Did SMS parsing work for your bank/UPI app?
2. Were categories accurate?
3. Did you use credit management?
4. Any crashes or bugs?
5. Top 3 requested features?
6. Would you continue using after trial?

---

## 9. MVP Definition of Done

### 9.1 Feature Checklist

- [x] Database schema implemented
- [ ] SMS permissions flow working
- [ ] SMS parser for 4 UPI apps (PhonePe, GPay, Paytm, BHIM)
- [ ] SMS parser for 5 banks (HDFC, ICICI, SBI, Axis, Kotak)
- [ ] Manual transaction add/edit/delete
- [ ] 10 categories working
- [ ] Credit tracking (give/track)
- [ ] Auto-link repayments
- [ ] Home screen with daily summary
- [ ] Transaction list with search/filter
- [ ] Monthly report with charts
- [ ] Yearly report
- [ ] PIN lock working
- [ ] Biometric unlock (optional)
- [ ] Backup/restore working
- [ ] Settings screen complete

### 9.2 Quality Checklist

- [ ] Zero crashes in self-dogfooding (2 weeks)
- [ ] SMS parsing ≥90% accurate (100 sample SMS)
- [ ] App launch <2 seconds
- [ ] 60 FPS scrolling
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Tested on 3 devices
- [ ] Beta tested with 10 users
- [ ] Privacy policy written
- [ ] README updated with features

### 9.3 Documentation Checklist

- [x] PRD complete
- [x] Technical architecture documented
- [x] Database schema documented
- [x] SMS parsing spec documented
- [x] MVP scope defined (this document)
- [ ] API documentation (if any)
- [ ] User guide (simple markdown)
- [ ] Developer setup guide

---

## 10. Next Steps After MVP

### Week 7-8: Internal Dogfooding
- All developers use app daily
- Fix critical bugs
- Improve UX based on own usage

### Week 9-10: Beta Testing
- 10 friends & family testers
- Collect feedback
- Priority bug fixes

### Week 11-12: Budget Feature
- Add monthly budgets
- Overspend warnings
- Compare budget vs actual

### Week 13-14: Polish
- Dark mode (high demand)
- Recurring transactions
- Notifications

### Week 15+: Public Launch Prep
- Google Play listing
- Screenshots
- App icon finalization
- Marketing materials

---

## 11. Success = Daily Use

**The Only Metric That Matters:**
> "Do we use ExpenseOwl every single day after Week 6?"

If YES:
- ✅ MVP succeeded
- ✅ Core value delivered
- ✅ Ready to scale

If NO:
- ❌ Missing critical feature
- ❌ UX too complex
- ❌ SMS parsing not working
- ❌ Need to pivot

**Be Honest. Ship Fast. Iterate.**

---

**Next Document:** [Screen Flows](./SCREEN_FLOWS.md)
