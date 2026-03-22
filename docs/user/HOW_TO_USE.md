# Kash Cube — How to Use

**Version:** 1.0  
**Updated:** March 2026

Welcome to **Kash Cube**, the privacy-first financial tracker built for India.  
Everything — your transactions, credits, reports, invoices — lives only on your phone.  
No cloud. No server. No data leaks.

---

## Table of Contents

1. [First-Time Setup](#1-first-time-setup)
2. [Navigation Overview](#2-navigation-overview)
3. [Adding Transactions](#3-adding-transactions)
4. [SMS Auto-Capture](#4-sms-auto-capture)
5. [Ledger — Credits & Loans](#5-ledger--credits--loans)
6. [Reports & Analytics](#6-reports--analytics)
7. [Business Mode](#7-business-mode)
8. [Invoices & Quotes](#8-invoices--quotes)
9. [GST & Purchase Bills](#9-gst--purchase-bills)
10. [Inventory & Item Catalog](#10-inventory--item-catalog)
11. [Staff Management](#11-staff-management)
12. [Bookings](#12-bookings)
13. [Search & Filter](#13-search--filter)
14. [Security — PIN & Biometrics](#14-security--pin--biometrics)
15. [Backup & Restore](#15-backup--restore)
16. [Settings Reference](#16-settings-reference)
17. [Open on Laptop (Web View)](#17-open-on-laptop-web-view)
18. [Tips & Tricks](#18-tips--tricks)
19. [FAQ](#19-faq)

---

## 1. First-Time Setup

When you open Kash Cube for the first time, a short 3-step setup runs:

### Step 1 — Set a PIN
- Choose a 4–6 digit PIN.
- Confirm it a second time.
- This PIN is required on every app open — it is stored locally and never sent anywhere.

### Step 2 — Allow SMS Access *(optional but recommended)*
- Kash Cube can read bank/UPI SMS to automatically capture your transactions.
- SMS is parsed **on-device only**. Nothing is uploaded.
- Tap **Allow SMS Access** to enable auto-capture.
- Tap **Skip** if you prefer to enter transactions manually. You can turn this on later in **Settings → Automation → SMS Parsing**.

### Step 3 — Profile (optional)
- Enter your name, phone, and business name.
- This appears on invoices and payment reminders.

After setup, you land on the **Home Screen** — ready to use.

---

## 2. Navigation Overview

The app has **four main tabs** at the bottom:

| Tab | What it does |
|-----|-------------|
| **Home** | Daily summary, recent transactions, quick actions |
| **Transactions** | Full chronological list of all transactions |
| **Ledger** | Summary view — who owes you, who you owe, investments |
| **Reports** | Charts, P&L, category breakdowns, export |

### Global Controls

| Control | Where | Action |
|---------|-------|--------|
| **+ FAB button** | Home & Transactions | Add a new transaction |
| **Search icon** | AppBar | Search across all records |
| **Settings gear** | AppBar | Open app settings |

### Business Sub-Navigation (Business Mode on)

When Business Mode is enabled, additional sections appear:
- **Invoices & Quotes** — under Business Hub
- **GST / GSTR-1 / GSTR-3B** — under Business Hub
- **Bills & Payments** — under Business Hub
- **Staff** — under Business Hub
- **Inventory** — under Business Hub
- **Bookings** — under Business Hub

---

## 3. Adding Transactions

### Quick Add (FAB)

1. Tap the **+** button on Home or Transactions.
2. Select the transaction type:

| Type | Use when… |
|------|-----------|
| **Spent** | You paid for something (expense) |
| **Earned** | You received money (income) |
| **Lent (Diya)** | You gave money to someone |
| **Borrowed (Liya)** | You took money from someone |
| **Invested** | You put money into FD / MF / stocks / gold |
| **Settlement** | Someone repaid you, or you repaid a loan |

3. Enter the **Amount** (₹).
4. Fill remaining fields — most are optional and revealed progressively:

**For Spent/Earned:**
- Category (auto-suggested from party name)
- Party name (who paid / where you paid)
- Payment method: Cash, UPI, Card, Net Banking, Wallet
- Date (defaults to today)
- Notes

**For Lent/Borrowed (adds fields):**
- Party name + phone (for reminders)
- Due date
- Interest rate & type (simple / compound)
- Repayment schedule (monthly, one-time, etc.)

**For Invested (adds fields):**
- Where (SBI FD, Zerodha, etc.)
- Category: FD, Mutual Fund, Stocks, Gold, PPF…
- Returns / interest rate
- Maturity date

5. Tap **Save**.

### Edit or Delete a Transaction

- Tap any transaction in the list → **Transaction Detail** screen.
- Tap the **pencil icon** to edit.
- Tap the **trash icon** and confirm to delete.

---

## 4. SMS Auto-Capture

When SMS permission is granted, Kash Cube watches for financial messages in the background.

### How It Works

1. An SMS arrives from a known sender (HDFC, PhonePe, GPay, SBI, Paytm, ICICI, etc.).
2. The app parses it locally — extracting amount, merchant, transaction type, UPI reference, and date.
3. The transaction is saved and appears in your Home screen and Transactions list.
4. A notification appears: **"₹450 to Swiggy (Food) — Tap to edit"**.

### Duplicate Prevention

The parser uses a hash of `(amount + date + merchant + type)` to automatically skip duplicates. You will never see the same transaction twice.

### Settlement Auto-Link

When you receive money from someone who has a pending lent amount:

1. Parser detects "₹2,000 from Ramesh Kumar via PhonePe".
2. App finds Ramesh has a pending lent entry of ₹5,000.
3. A prompt appears: *"Settlement detected? Ramesh owes ₹5,000. Link this ₹2,000 as repayment → Remaining: ₹3,000"*
4. Tap **Link as Settlement** or **Just Income** (if unrelated).

### Manage SMS Parsing

Go to **Settings → Automation → SMS Parsing** to:
- Enable/disable parsing
- Re-request SMS permission
- View which senders are recognised

---

## 5. Ledger — Credits & Loans

The **Ledger** tab is your living balance sheet, grouped by person, not by date.

### Sections

| Section | Shows |
|---------|----|
| **People** | Anyone you lent to or borrowed from (net balance per person) |
| **Investments** | All your active investment entries (FD, MF, Stocks, Gold…) |
| **Loans** | Your active loan obligations (home loan, personal loan…) |

### Give Credit (Udhar)

1. Go to Ledger → tap **Give Credit** (or use FAB → Lent).
2. Enter customer name, amount, and optional due date.
3. Transaction appears under **People** with pending amount highlighted.

### Record a Repayment

**Method 1 — Auto (via SMS):** If the customer pays via UPI, the auto-link prompt handles it.

**Method 2 — Manual:**
1. Tap the person's name in Ledger.
2. Tap **Add Settlement**.
3. Enter the repaid amount (or tap **Full** to settle in one go).
4. The ledger balance updates instantly.

### Party 360 View

Tap any person's name to open the **Party 360** screen:
- Full transaction timeline with that party
- Net balance (what they owe / you owe)
- Contact details & quick call/WhatsApp
- Documents (invoices, challans) linked to this party

---

## 6. Reports & Analytics

Go to the **Reports** tab.

### Available Reports

| Report | What you see |
|--------|-------------|
| **Cash Flow** | Monthly income vs expense bar chart |
| **Category Breakdown** | Pie chart by spending category |
| **P&L Statement** | Business profit & loss (requires Business Mode) |
| **Budget Tracker** | Spend vs budget per category |
| **Daily / Monthly / Yearly** | Trend views with drill-down |

### Export Reports

1. Open any report.
2. Tap the **Share / Export** icon in the AppBar.
3. Choose: **PDF**, **CSV (Excel)**, or **Share**.
4. The file is generated locally and sent to your chosen app (WhatsApp, email, etc.).

### Financial Year

Kash Cube uses **April 1 – March 31** (Indian FY) for all yearly summaries.  
You can change this in **Settings → General → Fiscal Year**.

---

## 7. Business Mode

Business Mode unlocks the full business toolkit.

### Enable Business Mode

1. Go to **Settings → Business Mode**.
2. Toggle it on.
3. Optionally add your GSTIN, business name, and address — these appear on invoices.

### Multiple Businesses

You can manage more than one business from a single device:

1. Go to **Settings → Businesses**.
2. Tap **Add Business**.
3. Switch between businesses from the same screen.

Each business has isolated data — transactions, invoices, and parties do not mix.

---

## 8. Invoices & Quotes

*(Requires Business Mode)*

### Create an Invoice

1. Navigate to **Business Hub → Invoices & Quotes**.
2. Tap **+** → **New Invoice**.
3. Fill in:
   - **Customer** — type to search or add a new party
   - **Invoice date** and **due date**
   - **Line items** — search your item catalog or type a new item with price and quantity
   - **GST / Tax** — applied per item (CGST + SGST or IGST auto-selected based on GSTIN state)
   - **Discount** (optional, per line or on total)
   - **Notes / Terms** — pulled from your default template
4. Tap **Save**.

### Invoice Actions

From the Invoice Detail screen:

| Action | What it does |
|--------|-------------|
| **Share PDF** | Generates a PDF and opens the share sheet |
| **Mark as Paid** | Records a payment against the invoice |
| **Convert to Delivery Challan** | Creates a linked DC for goods dispatch |
| **Send Reminder** | Opens WhatsApp / SMS with a payment reminder message |
| **Duplicate** | Clones invoice for repeat billing |

### Quotes / Estimates

- Create a quote the same way as an invoice — use the **Quotes** tab.
- Tap **Convert to Invoice** on an accepted quote to turn it into a billable invoice instantly.

### Invoice Templates

Customise the look of your PDF invoices:

1. Go to **Settings → Business → Invoice Templates**.
2. Choose a template or build your own with the **Template Builder**.
3. Add your logo, brand colours, payment bank details, and standard terms.

### Item Catalog

1. Go to **Business Hub → Item Catalog** (or tap **Manage Items** from the new invoice screen).
2. **Add Item**: name, HSN/SAC code, unit price, GST rate, unit type, and inventory tracking toggle.
3. Items auto-appear as suggestions when building invoices.

---

## 9. GST & Purchase Bills

*(Requires Business Mode)*

### GSTR-1 (Outward Supplies)

1. Go to **Business Hub → GST → GSTR-1**.
2. Select the return period (month/quarter).
3. The screen auto-populates B2B, B2C, HSN summary from your invoices.
4. Tap **Export JSON** to download the GSTN-compatible file for portal upload.

### Purchase Bills (Input Tax Credit)

1. Go to **Business Hub → GST → Purchase Bills**.
2. Tap **+** to add a purchase bill (vendor invoice).
3. Enter vendor GSTIN, bill number, date, items, and GST.
4. ITC is automatically calculated and used in **GSTR-3B offset**.

### GSTR-3B Offset

1. Go to **Business Hub → GST → GSTR-3B Offset**.
2. See your output tax liability vs ITC available.
3. The net payable amount is shown — export or note it for payment.

### Delivery Challans

- Create a DC from an invoice (for goods dispatched before billing) or standalone.
- Can be e-Way Bill (EWB) ready — a preview screen shows the EWB JSON format.

---

## 10. Inventory & Item Catalog

*(Requires Business Mode)*

### Track Stock

1. Go to **Business Hub → Inventory**.
2. Toggle **Track Inventory** on for any item in the catalog.
3. Stock levels increase when you record a purchase bill, decrease when you raise an invoice.

### Low Stock Alerts

- Set a **Minimum Stock Level** per item.
- A warning badge appears on the inventory screen when stock falls below this level.

### Unit Types

Customise units (kg, pcs, litre, box, dozen…) in **Settings → Business → Unit Types**.

---

## 11. Staff Management

*(Requires Business Mode)*

### Add a Staff Member

1. Go to **Business Hub → Staff**.
2. Tap **+** → enter name, role, phone, and joining date.
3. Assign an **app access PIN** if the staff member uses the same device (restricted access).

### Manage Roles & Permissions

1. Go to **Settings → Team → User Permissions**.
2. Define what each role can see or edit (sales only, view only, full access).

### Salaries & Attendance

Staff records include a salary field and basic attendance log. Record monthly salary payments as **Spent → Staff Salary** transactions to keep them in your P&L.

---

## 12. Bookings

*(Requires Business Mode — suited for service businesses: salons, clinics, tutors, etc.)*

### Create a Booking

1. Go to **Business Hub → Bookings**.
2. Tap **+** → fill in customer, service type, date, time, and amount.
3. Booking appears in the calendar view.

### Booking Actions

- **Mark Complete** → optionally creates a linked invoice.
- **Cancel** → marks cancelled (preserved for records).
- **Reschedule** → change date/time.

---

## 13. Search & Filter

Tap the **Search icon** in the AppBar from any screen.

### Search by

- Party / merchant name
- Amount (exact or range)
- Category
- Transaction type
- Payment method
- Date range

### Filter Transactions

On the **Transactions** screen, tap the **filter icon** to narrow the list by:
- Date range
- Type (income, expense, lent, borrowed…)
- Category
- Business / personal mode
- Payment method

---

## 14. Security — PIN & Biometrics

### PIN Lock

- Set / change PIN: **Settings → Security → App Lock**.
- The app auto-locks after a configurable inactivity period.
- The app also locks when you switch away and return.

### Biometric Unlock

1. Go to **Settings → Security → App Lock**.
2. Toggle **Use Fingerprint / Face ID**.
3. Your device's biometric is used — fingerprint data never leaves the device's secure enclave.

### Multi-User / Staff PIN

Staff members can log in with their own restricted-access PIN (see [Staff Management](#11-staff-management)).  
Each staff user sees only what their role permits.

---

## 15. Backup & Restore

All data is stored in a local SQLite database on your phone. **Backup regularly** to avoid data loss.

### Create a Backup

1. Go to **Settings → Data → Encrypted Backup**.
2. Tap **Create Backup Now**.
3. The backup file (`.kc_backup`) is saved to your phone's Downloads folder.
4. Use the **Share** button to send it to WhatsApp, Google Drive, email, or any storage you trust.

### Restore from Backup

1. Go to **Settings → Data → Encrypted Backup**.
2. Tap **Restore from File**.
3. Pick your `.kc_backup` file from storage.
4. Confirm — existing data is replaced by the backup.

> ⚠️ Restoring overwrites all current data. Make a fresh backup before restoring if you want to keep recent entries.

### Storage Health

**Settings → Data → Storage Health** shows your database size, number of records, and disk space remaining. Run a cleanup from here if the database grows very large.

---

## 16. Settings Reference

| Section | Key settings |
|---------|-------------|
| **My Profile** | Name, phone, profile photo |
| **KashCube Plan** | View your current plan; upgrade to Pro |
| **Security** | PIN lock, biometrics, auto-lock timeout |
| **Team** | Manage users, set per-role permissions |
| **Accounts** | Bank accounts, UPI IDs, credit cards tracked |
| **Opening Balances** | Enter starting balances for your accounts |
| **General** | Theme (Light / Dark / System), fiscal year, currency display |
| **Data** | Encrypted backup & restore, storage health, Tally export |
| **Notifications** | Reminder timing, payment due alerts, SMS capture alerts |
| **Automation** | SMS parsing toggle, re-request SMS permission |
| **Business Mode** | Toggle business features, GSTIN, multiple businesses |
| **Invoice Templates** | Choose / build PDF templates, add logo and bank details |
| **Unit Types** | Custom units for inventory items |
| **Document Terms** | Default payment terms on invoices |
| **Open on Laptop** | Web companion — view data on browser over local Wi-Fi |
| **About** | App version, privacy policy, terms of use |

---

## 17. Open on Laptop (Web View)

Kash Cube can serve a **local web interface** on your Wi-Fi network so you can view (read only) your data from a browser on the same network.

### How to Use

1. Go to **Settings → Open on Laptop**.
2. Tap **Start Server**.
3. The screen shows a local URL like `http://192.168.1.5:8080`.
4. Open that URL in a browser on your laptop — **on the same Wi-Fi network only**.
5. Tap **Stop Server** when you're done.

> Everything stays on your local network. No data leaves your home/office network.

---

## 18. Tips & Tricks

- **Swipe left** on any transaction to get quick-access Edit and Delete buttons.
- **Long-press** a party name in Ledger to copy the balance amount for a WhatsApp message.
- **Recurring transactions** (salary received, rent paid) — set them up once in **Transactions → Recurring** so they auto-appear every month without manual entry.
- **Categories**: Tap any category chip in the Add Transaction screen to rename it or create a custom category in **Transactions → Manage Categories**.
- **Dark Mode**: Enable in **Settings → General → Theme → Dark** to reduce eye strain and battery usage (OLED screens).
- **Backup reminder**: If you haven't backed up in 7 days, a banner appears on the Home screen. Act on it — one tap triggers a backup.
- **Indian number format**: All amounts display in Indian notation — ₹1,23,456 (not ₹123,456). Export CSVs also use this format.

---

## 19. FAQ

**Q: Does Kash Cube upload my data anywhere?**  
A: No. Everything is stored in a local SQLite database on your device. There are zero network calls. No analytics, no crash reporting, no cloud sync.

**Q: I switched to a new phone. How do I move my data?**  
A: Create an Encrypted Backup on your old phone, transfer the `.kc_backup` file to the new phone (via USB, WhatsApp, email), install Kash Cube, complete setup, then Restore from File.

**Q: Why do some SMS not get captured?**  
A: Kash Cube recognises ~100 major senders (HDFC, SBI, ICICI, PhonePe, GPay, Paytm, etc.). If your bank's sender ID is not in the list, the SMS is ignored. You can add the transaction manually.

**Q: Can I use the app for both personal and business finances?**  
A: Yes. Use the **Personal / Business / Investment** toggle on each transaction to keep them separate. Reports can be filtered to show just one mode.

**Q: My GST number changed. Where do I update it?**  
A: Go to **Settings → Business Mode → Edit Business** and update the GSTIN field. All new invoices will use the updated GSTIN.

**Q: Can my accountant see the data?**  
A: Export a PDF report or CSV from the Reports screen and share it. Alternatively, use **Tally Export** (Settings → Data → Tally Export) to generate a Tally-compatible import file.

**Q: I forgot my PIN. How do I reset it?**  
A: Uninstall and reinstall the app. This deletes all local data — so restore from a backup afterwards. In a future version, a recovery key will be available.

**Q: Is there an iOS version?**  
A: Not yet. Android is the current platform. An iOS version is on the roadmap.

**Q: What is Business Mode and do I need it?**  
A: Business Mode is optional. If you're an individual tracking personal finances, you don't need it. Turn it on if you need invoices, GST filing, staff management, or inventory tracking.

---

*Kash Cube is built with privacy as the foundation. Your financial data belongs to you.*
