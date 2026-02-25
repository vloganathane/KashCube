# Database Schema
# Kash Cube Data Model

**Version:** 2.0  
**Date:** February 25, 2026  
**Database:** SQLite 3.x

---

## 1. Schema Overview

### 1.1 Entity Relationship Diagram

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│ transactions│◄───────►│   parties    │         │  categories  │
└─────────────┘         └──────────────┘         └──────────────┘
       │                       │                         │
       │                       │                         │
       ▼                       ▼                        ▼
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│   accounts  │         │   budgets    │         │recurring_txns│
└─────────────┘         └──────────────┘         └──────────────┘
```

**Note:** Credits and loans are no longer separate tables. All financial events (income, expense, lending, borrowing, investments, settlements) are stored in the unified `transactions` table with expanded type values.

### 1.2 Design Principles

1. **Normalization:** Avoid duplication, maintain referential integrity
2. **Performance:** Indexed columns for fast queries
3. **Flexibility:** JSON columns for extensible data
4. **Privacy:** No PII transmitted, all local
5. **Audit Trail:** Track creation and modification times

---

## 2. Core Tables

### 2.1 `transactions` Table

**Primary table for all financial transactions**

```sql
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Amount & Date
  amount REAL NOT NULL,
  date TEXT NOT NULL,  -- ISO 8601 format
  
  -- Classification
  type TEXT NOT NULL,  -- 'income', 'expense', 'lent', 'borrowed', 'invested',
                       -- 'received_back', 'paid_back', 'redeemed'
  mode TEXT NOT NULL,  -- 'personal', 'business', 'investment'
  category TEXT NOT NULL,
  
  -- Party Information
  party_name TEXT,
  party_id INTEGER,  -- FK to parties table
  phone_number TEXT,
  
  -- Payment Method
  payment_method TEXT,  -- 'upi', 'credit_card', 'debit_card', 'cash', 'bank_transfer', 'cheque', 'wallet'
  account_id INTEGER,  -- FK to accounts table
  
  -- Source/SMS Details
  sms_body TEXT,
  sms_sender TEXT,
  upi_app TEXT,  -- 'PhonePe', 'GPay', 'Paytm', 'BHIM', etc.
  upi_ref_no TEXT,
  reference_id TEXT,
  auto_detected BOOLEAN DEFAULT 0,
  verified BOOLEAN DEFAULT 0,
  
  -- Linking
  linked_transaction_id INTEGER,  -- For settlements → points to original lent/borrowed
  parent_transaction_id INTEGER,  -- For refunds/reversals
  
  -- Lending/Borrowing extras (nullable — only used for lent/borrowed types)
  due_date TEXT,              -- When repayment is expected
  interest_rate REAL,         -- % per period
  interest_type TEXT,         -- 'simple', 'compound', 'flat', 'none'
  repayment_frequency TEXT,   -- 'daily', 'weekly', 'monthly'
  total_installments INTEGER, -- Total number of installments
  emi_amount REAL,            -- Per-installment amount
  
  -- Business/Tax
  gst_applicable BOOLEAN DEFAULT 0,
  gst_rate REAL,
  gst_amount REAL,
  is_tax_deductible BOOLEAN DEFAULT 0,
  
  -- Receipt
  receipt_path TEXT,  -- Local file path
  receipt_url TEXT,  -- Future: Cloud URL
  
  -- Deduplication
  dedupe_hash TEXT UNIQUE,  -- Hash for duplicate detection
  
  -- Meta
  notes TEXT,
  tags TEXT,  -- JSON array: ["work", "client_a"]
  metadata TEXT,  -- JSON object for extensibility
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT,  -- Soft delete
  
  -- Foreign Keys
  FOREIGN KEY (party_id) REFERENCES parties(id),
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (linked_transaction_id) REFERENCES transactions(id),
  FOREIGN KEY (parent_transaction_id) REFERENCES transactions(id)
);

-- Indexes for performance
CREATE INDEX idx_transactions_date ON transactions(date DESC);
CREATE INDEX idx_transactions_party ON transactions(party_name);
CREATE INDEX idx_transactions_mode_type ON transactions(mode, type, date DESC);
CREATE INDEX idx_transactions_category ON transactions(category, date DESC);
CREATE INDEX idx_transactions_auto_detected ON transactions(auto_detected, verified);
CREATE INDEX idx_transactions_dedupe ON transactions(dedupe_hash);
CREATE INDEX idx_transactions_deleted ON transactions(deleted_at);
```

**Sample Data:**
```sql
INSERT INTO transactions (
  amount, date, type, mode, category, party_name,
  payment_method, upi_app, upi_ref_no, auto_detected, verified
) VALUES (
  450.00,
  '2026-02-24T14:30:00',
  'expense',
  'personal',
  'Food &Dining',
  'Swiggy',
  'upi',
  'PhonePe',
  '405512345678',
  1,
  1
);
```

---

### 2.2 `credits` Table

**Track money lent to customers (udhar/khata)**

```sql
CREATE TABLE credits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Customer Information
  customer_name TEXT NOT NULL,
  customer_id INTEGER,  -- FK to parties table
  phone_number TEXT,
  
  -- Amount Tracking
  total_amount REAL NOT NULL,  -- Total credit given
  paid_amount REAL DEFAULT 0,  -- Amount repaid so far
  pending_amount REAL NOT NULL,  -- total_amount - paid_amount
  
  -- Dates
  credit_date TEXT NOT NULL,
  due_date TEXT,
  cleared_date TEXT,
  
  -- Status
  is_cleared BOOLEAN DEFAULT 0,
  is_overdue BOOLEAN DEFAULT 0,
  
  -- Terms
  interest_rate REAL,  -- % per month
  interest_type TEXT,  -- 'simple', 'compound', 'flat'
  credit_limit REAL,  -- Max credit for this customer
  
  -- Reminders
  last_reminder_sent TEXT,
  reminder_count INTEGER DEFAULT 0,
  
  -- Related Transactions
  transaction_ids TEXT,  -- JSON array of transaction IDs
  
  -- Meta
  notes TEXT,
  tags TEXT,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT,
  
  -- Foreign Key
  FOREIGN KEY (customer_id) REFERENCES parties(id)
);

-- Indexes
CREATE INDEX idx_credits_customer ON credits(customer_name);
CREATE INDEX idx_credits_status ON credits(is_cleared, is_overdue);
CREATE INDEX idx_credits_due_date ON credits(due_date);
CREATE INDEX idx_credits_pending ON credits(pending_amount DESC);
```

**Sample Data:**
```sql
INSERT INTO credits (
  customer_name, total_amount, paid_amount, pending_amount,
  credit_date, due_date, is_cleared
) VALUES (
  'Ramesh Kumar',
  5000.00,
  1500.00,
  3500.00,
  '2026-02-01',
  '2026-02-28',
  0
);
```

---

### 2.3 `loans` Table

**Track money borrowed**

```sql
CREATE TABLE loans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Lender Information
  lender_name TEXT NOT NULL,
  lender_id INTEGER,  -- FK to parties table
  phone_number TEXT,
  
  -- Amount Tracking
  principal_amount REAL NOT NULL,
  paid_amount REAL DEFAULT 0,
  pending_amount REAL NOT NULL,
  
  -- Dates
  loan_date TEXT NOT NULL,
  due_date TEXT,
  cleared_date TEXT,
  
  -- Status
  is_cleared BOOLEAN DEFAULT 0,
  is_overdue BOOLEAN DEFAULT 0,
  
  -- Repayment Plan
  emi_amount REAL,
  total_emis INTEGER,
  paid_emis INTEGER DEFAULT 0,
  emi_day INTEGER,  -- Day of month (1-31)
  next_emi_date TEXT,
  
  -- Interest
  interest_rate REAL,
  interest_type TEXT,  -- 'simple', 'compound', 'flat'
  total_interest REAL,
  
  -- Related Transactions
  transaction_ids TEXT,  -- JSON array
  
  -- Meta
  notes TEXT,
  tags TEXT,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT,
  
  -- Foreign Key
  FOREIGN KEY (lender_id) REFERENCES parties(id)
);

-- Indexes
CREATE INDEX idx_loans_lender ON loans(lender_name);
CREATE INDEX idx_loans_status ON loans(is_cleared, is_overdue);
CREATE INDEX idx_loans_next_emi ON loans(next_emi_date);
```

---

### 2.4 `parties` Table

**Unified table for customers, vendors, lenders**

```sql
CREATE TABLE parties (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Identity
  name TEXT NOT NULL,
  phone_number TEXT,
  email TEXT,
  
  -- Type
  party_type TEXT NOT NULL,  -- 'customer', 'vendor', 'lender', 'borrower'
  
  -- Statistics
  total_transactions INTEGER DEFAULT 0,
  total_transaction_amount REAL DEFAULT 0,
  total_credit_given REAL DEFAULT 0,
  total_credit_received REAL DEFAULT 0,
  
  -- Credit Worthiness
  credit_limit REAL,
  default_count INTEGER DEFAULT 0,  -- Times payment was late
  average_payment_delay INTEGER,  -- Days
  
  -- Contact
  address TEXT,
  notes TEXT,
  tags TEXT,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT
);

-- Indexes
CREATE INDEX idx_parties_name ON parties(name);
CREATE INDEX idx_parties_phone ON parties(phone_number);
CREATE INDEX idx_parties_type ON parties(party_type);
```

---

### 2.5 `accounts` Table

**Track different payment accounts/cards**

```sql
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Account Details
  account_type TEXT NOT NULL,  -- 'savings', 'current', 'credit_card', 'debit_card', 'upi_wallet', 'payment_wallet'
  account_name TEXT NOT NULL,  -- "HDFC Credit Card", "PhonePe Wallet"
  bank_name TEXT,
  account_number_last4 TEXT,  -- Masked: XX1234
  
  -- Balance
  current_balance REAL,
  last_synced TEXT,  -- Last time balance was updated from SMS
  
  -- Credit Card Specific
  credit_limit REAL,
  available_credit REAL,
  billing_date INTEGER,  -- Day of month
  due_date INTEGER,
  
  -- Status
  is_active BOOLEAN DEFAULT 1,
  is_primary BOOLEAN DEFAULT 0,
  
  -- Sender IDs (for SMS matching)
  sms_senders TEXT,  -- JSON array: ["HDFCBK", "HDFCCC"]
  
  -- Meta
  notes TEXT,
  color TEXT,  -- UI color for this account
  icon TEXT,  -- UI icon identifier
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT
);

-- Indexes
CREATE INDEX idx_accounts_type ON accounts(account_type);
CREATE INDEX idx_accounts_active ON accounts(is_active);
```

---

### 2.6 `categories` Table

**Category definitions and metadata**

```sql
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Category Details
  name TEXT NOT NULL UNIQUE,
  parent_category TEXT,  -- For subcategories
  category_type TEXT NOT NULL,  -- 'income', 'expense'
  mode TEXT,  -- 'business', 'personal', 'both'
  
  -- UI
  icon TEXT NOT NULL,
  color TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  
  -- Keywords for auto-categorization
  keywords TEXT,  -- JSON array: ["swiggy", "zomato", "food"]
  
  -- Budgeting
  default_budget REAL,
  
  -- Status
  is_active BOOLEAN DEFAULT 1,
  is_custom BOOLEAN DEFAULT 0,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT
);

-- Indexes
CREATE INDEX idx_categories_type ON categories(category_type, mode);
CREATE INDEX idx_categories_active ON categories(is_active);
```

**Sample Data:**
```sql
-- Expense Categories
INSERT INTO categories (name, category_type, mode, icon, color, keywords) VALUES
('Food & Dining', 'expense', 'both', 'restaurant', '#FF6B35', '["swiggy", "zomato", "food", "restaurant"]'),
('Transport', 'expense', 'both', 'directions_car', '#2196F3', '["uber", "ola", "petrol", "metro"]'),
('Shopping', 'expense', 'both', 'shopping_bag', '#E91E63', '["amazon", "flipkart", "myntra"]');

-- Income Categories
INSERT INTO categories (name, category_type, mode, icon, color, keywords) VALUES
('Salary', 'income', 'personal', 'account_balance_wallet', '#4CAF50', '["salary", "wages"]'),
('Business Income', 'income', 'business', 'business', '#00BCD4', '["sales", "revenue"]');
```

---

## 3. Supporting Tables

### 3.1 `budgets` Table

**Monthly budgets per category**

```sql
CREATE TABLE budgets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Period
  year INTEGER NOT NULL,
  month INTEGER NOT NULL,
  
  -- Category
  category TEXT NOT NULL,
  
  -- Budget
  budget_amount REAL NOT NULL,
  spent_amount REAL DEFAULT 0,
  remaining_amount REAL,
  
  -- Alerts
  alert_at_percentage INTEGER DEFAULT 80,  -- Alert at 80%
  alerted BOOLEAN DEFAULT 0,
  
  -- Status
  is_active BOOLEAN DEFAULT 1,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  
  -- Unique constraint
  UNIQUE(year, month, category)
);

-- Indexes
CREATE INDEX idx_budgets_period ON budgets(year, month);
CREATE INDEX idx_budgets_category ON budgets(category);
```

---

### 3.2 `recurring_transactions` Table

**Template for recurring income/expenses**

```sql
CREATE TABLE recurring_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  
  -- Transaction Template
  amount REAL NOT NULL,
  type TEXT NOT NULL,
  mode TEXT NOT NULL,
  category TEXT NOT NULL,
  party_name TEXT,
  payment_method TEXT,
  
  -- Recurrence
  frequency TEXT NOT NULL,  -- 'daily', 'weekly', 'monthly', 'yearly'
  interval INTEGER DEFAULT 1,  -- Every X days/weeks/months
  day_of_month INTEGER,  -- For monthly (1-31)
  day_of_week INTEGER,  -- For weekly (1-7)
  
  -- Schedule
  start_date TEXT NOT NULL,
  end_date TEXT,  -- NULL = indefinite
  next_occurrence TEXT NOT NULL,
  
  -- Execution
  last_executed TEXT,
  execution_count INTEGER DEFAULT 0,
  
  -- Auto-add
  auto_add BOOLEAN DEFAULT 1,  -- Automatically add transaction
  notify_before_days INTEGER DEFAULT 0,  -- Notify N days before
  
  -- Status
  is_active BOOLEAN DEFAULT 1,
  
  -- Meta
  notes TEXT,
  
  -- Timestamps
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  deleted_at TEXT
);

-- Indexes
CREATE INDEX idx_recurring_next ON recurring_transactions(next_occurrence);
CREATE INDEX idx_recurring_active ON recurring_transactions(is_active);
```

---

### 3.3 `settings` Table

**App-wide settings and preferences**

```sql
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  value_type TEXT NOT NULL,  -- 'string', 'number', 'boolean', 'json'
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Sample settings
INSERT INTO settings (key, value, value_type) VALUES
('app_version', '1.0.0', 'string'),
('pin_enabled', 'true', 'boolean'),
('biometric_enabled', 'false', 'boolean'),
('default_mode', 'business', 'string'),
('currency_symbol', '₹', 'string'),
('date_format', 'dd-MM-yyyy', 'string'),
('sms_parsing_enabled', 'true', 'boolean'),
('auto_categorization_enabled', 'true', 'boolean'),
('onboarding_completed', 'false', 'boolean');
```

---

## 4. Views

### 4.1 `v_daily_summary` View

**Daily aggregated summary**

```sql
CREATE VIEW v_daily_summary AS
SELECT 
  DATE(date) as day,
  mode,
  SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE 0 END) as total_income,
  SUM(CASE WHEN type IN ('expense', 'lent', 'invested', 'paid_back') THEN amount ELSE 0 END) as total_expense,
  SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE -amount END) as net,
  COUNT(*) as transaction_count
FROM transactions
WHERE deleted_at IS NULL
GROUP BY DATE(date), mode;
```

### 4.2 `v_ledger_party_summary` View

**Ledger: net position per party (grouped summary)**

```sql
CREATE VIEW v_ledger_party_summary AS
SELECT 
  party_name,
  SUM(CASE WHEN type = 'lent' THEN amount ELSE 0 END) as total_lent,
  SUM(CASE WHEN type = 'received_back' THEN amount ELSE 0 END) as total_received_back,
  SUM(CASE WHEN type = 'borrowed' THEN amount ELSE 0 END) as total_borrowed,
  SUM(CASE WHEN type = 'paid_back' THEN amount ELSE 0 END) as total_paid_back,
  SUM(CASE WHEN type = 'lent' THEN amount ELSE 0 END) - 
    SUM(CASE WHEN type = 'received_back' THEN amount ELSE 0 END) as pending_receivable,
  SUM(CASE WHEN type = 'borrowed' THEN amount ELSE 0 END) - 
    SUM(CASE WHEN type = 'paid_back' THEN amount ELSE 0 END) as pending_payable,
  COUNT(*) as transaction_count
FROM transactions
WHERE type IN ('lent', 'received_back', 'borrowed', 'paid_back')
  AND deleted_at IS NULL
  AND party_name IS NOT NULL
GROUP BY party_name;
```

### 4.3 `v_investment_summary` View

**Ledger: net investment position per instrument**

```sql
CREATE VIEW v_investment_summary AS
SELECT 
  party_name as instrument,
  category,
  SUM(CASE WHEN type = 'invested' THEN amount ELSE 0 END) as total_invested,
  SUM(CASE WHEN type = 'redeemed' THEN amount ELSE 0 END) as total_redeemed,
  SUM(CASE WHEN type = 'invested' THEN amount ELSE 0 END) - 
    SUM(CASE WHEN type = 'redeemed' THEN amount ELSE 0 END) as current_value,
  COUNT(*) as transaction_count
FROM transactions
WHERE type IN ('invested', 'redeemed')
  AND deleted_at IS NULL
GROUP BY party_name, category;
```
ORDER BY c.is_overdue DESC, c.due_date ASC;
```

### 4.3 `v_monthly_category_totals` View

**Monthly spending by category**

```sql
CREATE VIEW v_monthly_category_totals AS
SELECT 
  strftime('%Y-%m', date) as month,
  mode,
  category,
  type,
  SUM(amount) as total,
  COUNT(*) as count
FROM transactions
WHERE deleted_at IS NULL
GROUP BY strftime('%Y-%m', date), mode, category, type;
```

---

## 5. Triggers

### 5.1 Update Credit Pending Amount

```sql
CREATE TRIGGER trg_update_credit_pending
AFTER UPDATE ON credits
FOR EACH ROW
BEGIN
  UPDATE credits
  SET pending_amount = total_amount - paid_amount,
      is_cleared = CASE WHEN paid_amount >= total_amount THEN 1 ELSE 0 END
  WHERE id = NEW.id;
END;
```

### 5.2 Update Timestamps

```sql
CREATE TRIGGER trg_transactions_updated
AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
  UPDATE transactions
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = NEW.id;
END;

CREATE TRIGGER trg_credits_updated
AFTER UPDATE ON credits
FOR EACH ROW
BEGIN
  UPDATE credits
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = NEW.id;
END;

CREATE TRIGGER trg_loans_updated
AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
  UPDATE loans
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = NEW.id;
END;
```

---

## 6. Migration Strategy

### 6.1 Version 1 → Version 2 (Example)

```sql
-- Add receipt_path column to transactions
ALTER TABLE transactions ADD COLUMN receipt_path TEXT;

-- Add is_tax_deductible column
ALTER TABLE transactions ADD COLUMN is_tax_deductible BOOLEAN DEFAULT 0;

-- Update schema version
UPDATE settings SET value = '2' WHERE key = 'schema_version';
```

### 6.2 Migration Manager

```dart
class DatabaseMigrations {
  static Future<void> migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    // ... more migrations
  }
  
  static Future<void> _migrateToV2(Database db) async {
    await db.execute('ALTER TABLE transactions ADD COLUMN receipt_path TEXT');
  }
}
```

---

## 7. Data Integrity

### 7.1 Foreign Key Constraints

```sql
-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- Verify integrity
PRAGMA foreign_key_check;
```

### 7.2 Check Constraints

```sql
-- Ensure amounts are positive
ALTER TABLE transactions ADD CONSTRAINT chk_amount_positive CHECK (amount > 0);

-- Ensure valid transaction types
ALTER TABLE transactions ADD CONSTRAINT chk_valid_type 
  CHECK (type IN ('income', 'expense', 'lent', 'borrowed', 'invested',
                  'received_back', 'paid_back', 'redeemed'));

-- Ensure valid modes
ALTER TABLE transactions ADD CONSTRAINT chk_valid_mode 
  CHECK (mode IN ('personal', 'business', 'investment'));
```

---

## 8. Backup & Export Queries

### 8.1 Full Export (CSV Format)

```sql
-- Export all transactions
.mode csv
.output transactions_export.csv
SELECT 
  date,
  amount,
  type,
  mode,
  category,
  party_name,
  payment_method,
  notes
FROM transactions
WHERE deleted_at IS NULL
ORDER BY date DESC;
.output stdout
```

### 8.2 Business Summary Export

```sql
SELECT 
  strftime('%Y-%m', date) as month,
  SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE 0 END) as income,
  SUM(CASE WHEN type IN ('expense', 'lent', 'invested', 'paid_back') THEN amount ELSE 0 END) as expense,
  SUM(CASE WHEN type IN ('income', 'received_back', 'redeemed') THEN amount ELSE -amount END) as profit
FROM transactions
WHERE mode = 'business'
  AND deleted_at IS NULL
GROUP BY strftime('%Y-%m', date)
ORDER BY month DESC;
```

---

## 9. Performance Considerations

### 9.1 Index Strategy
- Index on date columns (DESC for recent-first queries)
- Index on frequent WHERE conditions
- Composite indexes for multi-column filters
- Avoid over-indexing (impacts INSERT performance)

### 9.2 Query Optimization
- Use LIMIT for pagination
- Use indexes in WHERE clauses
- Avoid SELECT * (specify columns)
- Use prepared statements
- Batch INSERTs in transactions

### 9.3 Data Archival
```sql
-- Archive old data (optional, after 2+ years)
CREATE TABLE transactions_archive AS
SELECT * FROM transactions
WHERE date < date('now', '-2 years');

DELETE FROM transactions
WHERE date < date('now', '-2 years');

VACUUM;  -- Reclaim space
```

---

## 10. Schema Version Control

```sql
CREATE TABLE schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  description TEXT
);

INSERT INTO schema_version (version, description) VALUES
(1, 'Initial schema with transactions, credits, loans');
```

---

**Next Document:** [SMS Parsing Specification](./SMS_PARSING_SPEC.md)
