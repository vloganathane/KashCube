# Screen Flows & User Journeys
# Kash Cube Navigation Map

**Version:** 2.0  
**Date:** February 25, 2026  
**Status:** Implementation Phase

---

## 1. App Navigation Structure

### 1.1 Navigation Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Kash Cube App                        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────┐                                         │
│  │  PIN Lock    │ ◄─── App Launch / Resume               │
│  │  Screen      │                                         │
│  └──────┬──────┘                                         │
│         │ Authenticated                                   │
│         ▼                                                 │
│  ┌──────────────────────────────────────────────┐        │
│  │          Bottom Navigation Bar                │        │
│  ├──────────┬──────────┬──────────┬─────────────┤        │
│  │  Home    │  Trans-  │ Ledger   │  Reports    │        │
│  │  Screen  │  actions │ Screen   │  Screen     │        │
│  └────┬─────┴────┬─────┴────┬─────┴──────┬──────┘        │
│       │          │          │            │                │
│       ▼          ▼          ▼            ▼                │
│   [Details]  [Add/Edit] [Party     [Filters]              │
│                          Detail]                          │
│                                                          │
│  Global: FAB (+) → Add Transaction                       │
│  Global: AppBar → Search, Settings                       │
└──────────────────────────────────────────────────────────┘
```

### 1.2 Screen Inventory (MVP)

| # | Screen | Route | Access |
|---|--------|-------|--------|
| 1 | PIN Lock | `/lock` | App launch |
| 2 | PIN Setup | `/pin-setup` | First launch only |
| 3 | SMS Permission | `/sms-permission` | First launch only |
| 4 | Home | `/` | Bottom nav tab 1 |
| 5 | Transactions List | `/transactions` | Bottom nav tab 2 |
| 6 | Add Transaction | `/transactions/add` | FAB button |
| 7 | Edit Transaction | `/transactions/edit/:id` | Transaction tile |
| 8 | Transaction Detail | `/transactions/:id` | Transaction tile tap |
| 9 | Ledger | `/ledger` | Bottom nav tab 3 |
| 10 | Party Detail | `/ledger/party/:name` | Party tile tap |
| 11 | Reports | `/reports` | Bottom nav tab 4 |
| 13 | Search | `/search` | AppBar search icon |
| 14 | Settings | `/settings` | AppBar settings icon |
| 15 | Backup/Restore | `/settings/backup` | Settings |
| 16 | Privacy Policy | `/settings/privacy` | Settings |
| 17 | About | `/settings/about` | Settings |

---

## 2. First Launch Flow

### 2.1 Onboarding Sequence

```
App Install & First Open
         │
         ▼
┌─────────────────┐
│  Welcome Screen  │  "Welcome to Kash Cube 🧊"
│  (1 of 3)       │  "Track expenses privately"
└────────┬────────┘
         │ Next
         ▼
┌─────────────────┐
│  PIN Setup       │  "Set a 4-digit PIN"
│  (2 of 3)       │  [_ _ _ _]
│                  │  "Confirm PIN"
│                  │  [_ _ _ _]
└────────┬────────┘
         │ PIN Set ✓
         ▼
┌─────────────────┐
│  SMS Permission  │  "Auto-capture transactions?"
│  (3 of 3)       │
│                  │  📱 "We read bank/UPI SMS to
│                  │      automatically track your
│                  │      transactions"
│                  │
│                  │  ✅ "Only financial SMS parsed"
│                  │  ✅ "Data stays on your phone"
│                  │  ✅ "No SMS sent to any server"
│                  │
│                  │  [Allow SMS Access]
│                  │  [Skip - I'll add manually]
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Home Screen     │  Ready to use!
│  (Empty State)   │  "No transactions yet"
│                  │  "Tap + to add your first one"
└─────────────────┘
```

### 2.2 Flow Rules

- PIN setup is **mandatory** (cannot skip)
- SMS permission is **optional** (can skip)
- Welcome screen shown **only once** (flag in settings DB)
- If PIN already set, skip to PIN Lock on subsequent launches

---

## 3. Core User Flows

### 3.1 Flow: Auto-Capture Transaction (SMS)

**Trigger:** Financial SMS received  
**User Involvement:** Minimal (background process)

```
SMS Received (Background)
         │
         ▼
┌─────────────────┐
│  SMS Parser      │  Parse sender ID, extract data
│  (Background)    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  Known     Unknown
  Sender    Sender
    │         │
    ▼         ▼
  Parse     Ignore
  Amount,   (discard)
  Merchant
    │
    ▼
┌─────────────────┐
│  Check Duplicate │  Same amount + date + merchant?
└────────┬────────┘
    ┌────┴────┐
    │         │
    ▼         ▼
  New       Duplicate
    │         │
    ▼         ▼
  Save to   Merge/
  Database  Skip
    │
    ▼
┌─────────────────┐
│  Notification    │  "₹450 to Swiggy (Food)"
│  (Optional)      │  [View] [Edit Category]
└─────────────────┘
    │
    ▼
  Transaction appears in Home Screen
  Recent Transactions list
```

### 3.2 Flow: Manual Add Transaction

**Trigger:** User taps FAB (+) button  
**Screens:** Home → Add Transaction → Home

```
Home Screen
    │
    │ Tap FAB (+)
    ▼
┌───────────────────────────────────┐
│  Add Transaction Screen           │
│                                   │
│  ┌─────────────────────────────┐  │
│  │ [Income] [Expense] ← Toggle │  │
│  └─────────────────────────────┘  │
│                                   │
│  Amount:  ₹ [__________]         │
│                                   │
│  Category: [▼ Select category ]   │
│   ┌──────────────────────────┐   │
│   │ 🍽️ Food     🚗 Transport │   │
│   │ 🛍️ Shopping  📄 Bills     │   │
│   │ 🎬 Entertain 🏥 Health   │   │
│   │ 🎓 Education 📦 Other    │   │
│   │ 💼 Salary    🏢 Business │   │
│   └──────────────────────────┘   │
│                                   │
│  Party:   [__________] (optional) │
│                                   │
│  Date:    [📅 Feb 24, 2026]      │
│                                   │
│  Method:  [Cash|UPI|Card|Bank]    │
│                                   │
│  Notes:   [__________] (optional) │
│                                   │
│  ┌──────────┐  ┌──────────┐      │
│  │  Cancel   │  │  ✓ Save  │      │
│  └──────────┘  └──────────┘      │
└───────────────────────────────────┘
    │
    │ Save
    ▼
Home Screen (transaction added to list)
```

### 3.3 Flow: Give Credit (Udhar)

**Trigger:** User opens Credits tab, taps "Give Credit"  
**Screens:** Credits → Give Credit → Credits (updated)

```
Credits Screen
    │
    │ Tap "Give Credit" button
    ▼
┌───────────────────────────────────┐
│  Give Credit Screen               │
│                                   │
│  Customer:  [__________] *        │
│   └─ Autocomplete from existing   │
│      customers or add new         │
│                                   │
│  Amount:    ₹ [__________] *      │
│                                   │
│  Date:      [📅 Feb 24, 2026]    │
│                                   │
│  Due Date:  [📅 Optional]        │
│                                   │
│  Notes:     [__________]          │
│                                   │
│  ┌──────────┐  ┌──────────┐      │
│  │  Cancel   │  │  ✓ Save  │      │
│  └──────────┘  └──────────┘      │
└───────────────────────────────────┘
    │
    │ Save
    ▼
Credits Screen
  ┌─────────────────────────────┐
  │ Pending Credits              │
  │                              │
  │ 🔴 Ramesh Kumar    ₹5,000  │
  │    Due: Mar 10, 2026        │
  │                              │
  │ 🟡 Priya Sharma    ₹2,500  │
  │    No due date              │
  │                              │
  │ Total Pending: ₹7,500      │
  └─────────────────────────────┘
```

### 3.4 Flow: Auto-Link Settlement

**Trigger:** UPI payment received from someone with pending lent transaction  
**User Involvement:** Confirm/reject link suggestion

```
SMS Received: "Rs.2000 from RAMESH KUMAR via PhonePe"
         │
         ▼
┌─────────────────┐
│  Parser detects  │  Amount: ₹2,000
│  incoming UPI    │  From: RAMESH KUMAR
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Party Matcher   │  Search pending lent txns for
│                  │  "Ramesh" (fuzzy match)
└────────┬────────┘
         │
         ▼  Match found!
┌─────────────────────────────────────┐
│  Notification / In-App Dialog       │
│                                     │
│  "Settlement detected?"             │
│                                     │
│  ₹2,000 received from Ramesh Kumar │
│                                     │
│  Pending lent:    ₹5,000            │
│  This settlement: ₹2,000            │
│  Remaining:       ₹3,000            │
│                                     │
│  ┌───────────┐  ┌──────────────┐   │
│  │  Just      │  │  ✓ Link as   │   │
│  │  Income    │  │  Settlement  │   │
│  └───────────┘  └──────────────┘   │
└─────────────────────────────────────┘
         │
         │ User taps "Link as Settlement"
         ▼
Transaction saved as type `receivedBack`
linkedTransactionId = original lent txn ID
Ledger updated: Ramesh ₹5,000 → ₹3,000
```

### 3.5 Flow: View Reports

**Trigger:** User taps Reports tab  
**Screens:** Reports (with tab switching)

```
Reports Screen
    │
    ▼
┌───────────────────────────────────────┐
│  [Daily] [Monthly] [Yearly]  ← Tabs  │
├───────────────────────────────────────┤
│                                       │
│  Monthly Report: February 2026        │
│  ◄ Jan 2026    [Feb 2026]   Mar ►    │
│                                       │
│  ┌────────┐ ┌────────┐ ┌────────┐   │
│  │ Income │ │Expense │ │  Net   │   │
│  │₹75,000 │ │₹42,300 │ │₹32,700│   │
│  │  🟢    │ │  🔴    │ │  🔵   │   │
│  └────────┘ └────────┘ └────────┘   │
│                                       │
│  ┌───────────────────────────────┐   │
│  │   Category Breakdown (Pie)    │   │
│  │                               │   │
│  │      Food 35%                 │   │
│  │      Transport 20%            │   │
│  │      Bills 18%                │   │
│  │      Shopping 15%             │   │
│  │      Other 12%                │   │
│  └───────────────────────────────┘   │
│                                       │
│  ┌───────────────────────────────┐   │
│  │   Daily Trend (Line Chart)    │   │
│  │   ╱╲  ╱╲                     │   │
│  │  ╱  ╲╱  ╲   ╱               │   │
│  │ ╱         ╲ ╱                │   │
│  │1  5  10  15  20  24          │   │
│  └───────────────────────────────┘   │
│                                       │
│  vs Last Month:                       │
│  Expenses ▲ 12% more than Jan         │
└───────────────────────────────────────┘
```

### 3.6 Flow: Search Transactions

**Trigger:** User taps search icon in AppBar  
**Screens:** Any → Search → Transaction Detail

```
Any Screen (AppBar search icon)
    │
    │ Tap 🔍
    ▼
┌───────────────────────────────────┐
│  Search Screen                    │
│                                   │
│  [🔍 Search transactions...    ] │
│                                   │
│  Quick Filters:                   │
│  [Today] [This Week] [This Month]│
│  [Income Only] [Expense Only]    │
│                                   │
│  ── Results ──                    │
│                                   │
│  (type to search by merchant,    │
│   amount, category, or notes)    │
│                                   │
│  Feb 24 ─────────────────────    │
│  🍽️ Swiggy          -₹450      │
│  🚗 Uber             -₹280      │
│                                   │
│  Feb 23 ─────────────────────    │
│  💼 Client Payment   +₹25,000   │
│  📄 Electricity Bill  -₹1,200   │
└────────┬──────────────────────────┘
         │
         │ Tap transaction
         ▼
Transaction Detail Screen
```

### 3.7 Flow: Backup & Restore

**Trigger:** User opens Settings → Backup  
**Screens:** Settings → Backup/Restore

```
Settings Screen
    │
    │ Tap "Backup Database"
    ▼
┌───────────────────────────────────┐
│  Backup Options                   │
│                                   │
│  📦 Create Backup                │
│                                   │
│  Last backup: Feb 20, 2026       │
│  Database size: 2.4 MB           │
│  Transactions: 1,247             │
│                                   │
│  ┌─────────────────────────────┐ │
│  │  📤 Backup Now              │ │
│  │  Save to Downloads folder   │ │
│  └─────────────────────────────┘ │
│                                   │
│  ┌─────────────────────────────┐ │
│  │  📥 Restore from Backup    │ │
│  │  Import .db file            │ │
│  └─────────────────────────────┘ │
│                                   │
│  ┌─────────────────────────────┐ │
│  │  📄 Export to CSV           │ │
│  │  Share as spreadsheet       │ │
│  └─────────────────────────────┘ │
└───────────────────────────────────┘
         │
         │ Tap "Backup Now"
         ▼
┌───────────────────────────────────┐
│  ✅ Backup Complete!             │
│                                   │
│  File: kash_cube_2026-02-24.db │
│  Location: Downloads/Kash Cube/  │
│  Size: 2.4 MB                    │
│                                   │
│  [Share] [OK]                    │
└───────────────────────────────────┘
```

---

## 4. Navigation Patterns

### 4.1 Bottom Navigation

```
┌──────────────────────────────────────────┐
│                                          │
│           (Current Screen)               │
│                                          │
│                                          │
│                                          │
│                  [+]  ←── FAB            │
├──────────┬──────────┬──────────┬─────────┤
│  🏠      │  📋      │  �      │  📊     │
│  Home    │  Trans.  │  Ledger  │ Reports │
│          │          │          │         │
└──────────┴──────────┴──────────┴─────────┘
```

**Navigation Rules:**
- Bottom nav always visible (except modals and detail screens)
- FAB visible on Home and Transactions tabs
- Tab state preserved when switching (no data loss)
- Badge on Ledger tab shows count of parties with pending amounts

### 4.2 Screen Transitions

| From | To | Transition |
|------|----|------------|
| Any Tab | Another Tab | Fade (instant) |
| List | Detail | Slide right |
| Any | Add/Edit Form | Slide up (modal) |
| Any | Search | Slide down |
| Any | Settings | Slide right |
| Detail | Edit | Slide right |

### 4.3 Back Navigation

| Screen | Back Button |
|--------|-------------|
| Home | Exit app (with confirmation) |
| Transaction Detail | → Transactions List |
| Add Transaction | → Previous screen (discard warning if unsaved) |
| Customer Detail | → Ledger Screen |
| Settings | → Previous screen |
| Search | → Previous screen |

---

## 5. State Diagrams

### 5.1 Transaction States

```
                    ┌──────────┐
     SMS Parsed ──► │  PENDING  │ ◄── Manual Entry
                    └────┬─────┘
                         │
              User confirms / auto-save
                         │
                    ┌────▼─────┐
                    │  ACTIVE   │ ◄── Normal state
                    └────┬─────┘
                         │
                    Edit / Delete
                    ┌────┴─────┐
                    │          │
               ┌────▼───┐ ┌───▼──────┐
               │ EDITED  │ │ DELETED   │
               │         │ │ (soft)    │
               └─────────┘ └──────────┘
```

### 5.2 Ledger Entry States (Derived from Transactions)

```
User lends money:
  Transaction(type: lent) created
         │
         ▼
  Ledger shows: Party X owes ₹5,000
         │
  User records settlement:
  Transaction(type: receivedBack, linkedTransactionId: original)
         │
         ▼
  ┌──────────────┐
  │ Partial?     │
  │ YES → Ledger shows reduced amount
  │ NO  → Ledger shows ₹0 (settled)
  └──────────────┘

  Overdue Detection:
  lent/borrowed txn with dueDate < today
  AND no full settlement = OVERDUE badge
```

### 5.3 App Lock States

```
┌───────────┐
│  LOCKED    │ ◄── App launch
└─────┬─────┘     App resume after 5 min
      │
  PIN / Biometric
      │
┌─────▼─────┐
│  UNLOCKED  │ ◄── Normal usage
└─────┬─────┘
      │
  App minimized > 5 min
  Screen off
      │
┌─────▼─────┐
│  LOCKED    │
└───────────┘
```

---

## 6. Empty States

### 6.1 Empty State Designs

**Home Screen (No Transactions):**
```
┌───────────────────────────────┐
│                               │
│          🧊                   │
│                               │
│   "No transactions yet"       │
│                               │
│   Your expenses will appear   │
│   here automatically from     │
│   SMS, or add them manually.  │
│                               │
│   [+ Add First Transaction]   │
│                               │
└───────────────────────────────┘
```

**Ledger Screen (No Entries):**
```
┌───────────────────────────────┐
│                               │
│          📒                   │
│                               │
│   "No ledger entries yet"     │
│                               │
│   Lend, borrow, or invest     │
│   to see summaries here.      │
│   Tap + to add a transaction. │
│                               │
│   [+ Add Transaction]         │
│                               │
└───────────────────────────────┘
```

**Reports Screen (No Data):**
```
┌───────────────────────────────┐
│                               │
│          📊                   │
│                               │
│   "Not enough data yet"       │
│                               │
│   Start adding transactions   │
│   to see your financial       │
│   reports and insights.       │
│                               │
│   [Go to Home]                │
│                               │
└───────────────────────────────┘
```

**Search (No Results):**
```
┌───────────────────────────────┐
│                               │
│          🔍                   │
│                               │
│   "No results for 'xyz'"     │
│                               │
│   Try a different search      │
│   term or adjust filters.     │
│                               │
└───────────────────────────────┘
```

---

## 7. Error States

### 7.1 Error Handling Screens

**SMS Permission Denied:**
```
┌───────────────────────────────┐
│                               │
│          📱                   │
│                               │
│   "SMS access not granted"    │
│                               │
│   You can still use Kash Cube│
│   by adding transactions      │
│   manually.                   │
│                               │
│   [Open Settings]             │
│   [Continue without SMS]      │
│                               │
└───────────────────────────────┘
```

**Database Error:**
```
┌───────────────────────────────┐
│                               │
│          ⚠️                   │
│                               │
│   "Something went wrong"      │
│                               │
│   We couldn't save your       │
│   transaction. Please try     │
│   again.                      │
│                               │
│   [Retry] [Cancel]            │
│                               │
└───────────────────────────────┘
```

**Restore Validation Failed:**
```
┌───────────────────────────────┐
│                               │
│          ❌                   │
│                               │
│   "Invalid backup file"       │
│                               │
│   The selected file is not    │
│   a valid Kash Cube backup.  │
│   Please select a .db file.   │
│                               │
│   [Try Again] [Cancel]        │
│                               │
└───────────────────────────────┘
```

---

## 8. Confirmation Dialogs

### 8.1 Destructive Actions

**Delete Transaction:**
```
┌───────────────────────────────┐
│  Delete Transaction?          │
│                               │
│  ₹450 - Swiggy (Food)        │
│  Feb 24, 2026                 │
│                               │
│  This cannot be undone.       │
│                               │
│  [Cancel]  [Delete]           │
└───────────────────────────────┘
```

**Clear All Data:**
```
┌───────────────────────────────┐
│  ⚠️ Clear ALL Data?          │
│                               │
│  This will permanently delete │
│  all transactions, credits,   │
│  and settings.                │
│                               │
│  Type "DELETE" to confirm:    │
│  [____________]               │
│                               │
│  [Cancel]  [Clear Everything] │
└───────────────────────────────┘
```

**Restore Backup (Overwrite):**
```
┌───────────────────────────────┐
│  Restore Backup?              │
│                               │
│  This will REPLACE all your   │
│  current data with the backup.│
│                               │
│  Current: 1,247 transactions  │
│  Backup:  892 transactions    │
│                               │
│  [Cancel]  [Restore]          │
└───────────────────────────────┘
```

**Discard Unsaved Changes:**
```
┌───────────────────────────────┐
│  Discard Changes?             │
│                               │
│  You have unsaved changes.    │
│  Are you sure you want to     │
│  go back?                     │
│                               │
│  [Keep Editing]  [Discard]    │
└───────────────────────────────┘
```

---

## 9. Gesture & Interaction Map

### 9.1 Touch Interactions

| Screen | Gesture | Action |
|--------|---------|--------|
| Transaction List | Tap | Open detail |
| Transaction List | Long press | Quick menu (Edit/Delete) |
| Transaction List | Swipe left | Delete (with undo snackbar) |
| Home | Pull down | Refresh / re-parse recent SMS |
| Reports | Swipe left/right | Previous/next month |
| Credits → Ledger | Tap party | Open party detail |
| Pie Chart | Tap segment | Show category detail |
| Any form | Tap outside keyboard | Dismiss keyboard |

### 9.2 Snackbar Messages

| Action | Message | Undo |
|--------|---------|------|
| Transaction added | "Transaction saved ✓" | - |
| Transaction deleted | "Transaction deleted" | [Undo] |
| Settlement linked | "Settlement linked to original ✓" | [Undo] |
| Backup saved | "Backup saved to Downloads ✓" | - |
| Category changed | "Category updated ✓" | [Undo] |

---

## 10. Screen Flow Diagrams by User Story

### 10.1 Small Business Owner - Daily Flow

```
Morning:
  Open App → PIN → Home (see yesterday's summary)
  │
  ▼
  Check Ledger tab → See who owes what, investments
  │
  ▼
Throughout Day:
  SMS arrives → Auto-captured → Shows in Home
  │
  ▼
  Customer pays back → Notification → Link as settlement
  │
  ▼
Evening:
  Open Reports → Check daily summary
  │
  ▼
  Review auto-captured transactions → Edit if needed
```

### 10.2 Freelancer - Monthly Flow

```
Week 1-3:
  SMS auto-captures payments received
  Manual entry for cash expenses
  │
  ▼
Month End:
  Open Reports → Monthly tab
  │
  ▼
  View income vs expenses → Category breakdown
  │
  ▼
  Export CSV → Send to accountant
  │
  ▼
  Backup database → Save to computer
```

### 10.3 Privacy User - Setup Flow

```
Install App
  │
  ▼
Set PIN → Skip SMS permission (manual only)
  │
  ▼
Add transactions manually
  │
  ▼
Check Reports weekly
  │
  ▼
Monthly backup to personal drive
```

---

## 11. Deep Link Map (Future)

### 11.1 Planned Deep Links

| Link | Screen | Use Case |
|------|--------|----------|
| `kashcube://add` | Add Transaction | Quick add from widget |
| `kashcube://ledger` | Ledger Screen | Notification tap |
| `kashcube://reports/monthly` | Monthly Report | Scheduled reminder |
| `kashcube://transaction/:id` | Transaction Detail | SMS notification tap |

---

## 12. Accessibility Flow

### 12.1 Screen Reader Order

Each screen follows logical reading order:
1. Screen title / AppBar
2. Summary cards (top)
3. Main content (list/form)
4. Actions (FAB, buttons)
5. Bottom navigation

### 12.2 Keyboard Navigation (Future)

| Key | Action |
|-----|--------|
| Tab | Move to next input |
| Enter | Submit form / Select item |
| Escape | Close modal / Go back |
| Ctrl+N | New transaction |
| Ctrl+S | Save |

---

**Next Steps:** Implement screens following [Technical Architecture](./TECHNICAL_ARCHITECTURE.md)
