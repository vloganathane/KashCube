# Auto-Generated Database Table Inventory

Generated at: `2026-05-31T13:24:20+00:00`
Source: `lib/data/services/database_helper_tables.dart`

Total tables: **61**

## Domain Summary

- **Core Finance Ledger**: 12 tables
- **Parties and Communication**: 3 tables
- **Business Docs and Revenue Flows**: 13 tables
- **Catalog, Stock, and Units**: 8 tables
- **Staff and Payroll**: 3 tables
- **Settings, Auth, Permissions, Plans**: 6 tables
- **Device Identity and Sync Infrastructure**: 11 tables
- **Ungrouped**: 5 tables

## Core Finance Ledger

### `transactions`

- Columns: **44** | Table constraints: **4** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `date` | `TEXT` | NOT NULL | Business date field |
| `type` | `TEXT` | NOT NULL | Domain-specific field |
| `mode` | `TEXT` | NOT NULL DEFAULT 'personal' | Domain-specific field |
| `category` | `TEXT` | NOT NULL | Domain-specific field |
| `party_name` | `TEXT` | — | Display name / label |
| `party_id` | `INTEGER` | — | Reference to related entity |
| `phone_number` | `TEXT` | — | Phone/contact value |
| `payment_method` | `TEXT` | DEFAULT 'cash' | Domain-specific field |
| `account_id` | `INTEGER` | — | Reference to related entity |
| `to_account_id` | `INTEGER` | — | Reference to related entity |
| `sms_body` | `TEXT` | — | Domain-specific field |
| `sms_sender` | `TEXT` | — | Domain-specific field |
| `upi_app` | `TEXT` | — | Domain-specific field |
| `upi_ref_no` | `TEXT` | — | Human-readable document/reference number |
| `reference_id` | `TEXT` | — | Reference to related entity |
| `auto_detected` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `verified` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `credit_id` | `INTEGER` | — | Reference to related entity |
| `loan_id` | `INTEGER` | — | Reference to related entity |
| `linked_transaction_id` | `INTEGER` | — | Reference to related entity |
| `parent_transaction_id` | `INTEGER` | — | Reference to related entity |
| `due_date` | `TEXT` | — | Business date field |
| `interest_rate` | `REAL` | — | Rate/percentage value |
| `interest_type` | `TEXT` | — | Domain-specific field |
| `repayment_frequency` | `TEXT` | — | Domain-specific field |
| `total_installments` | `INTEGER` | — | Domain-specific field |
| `emi_amount` | `REAL` | — | Monetary value |
| `dedupe_hash` | `TEXT` | UNIQUE | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `tags` | `TEXT` | — | Tag list / metadata |
| `reminder_sent_at` | `TEXT` | — | Timestamp field |
| `linked_invoice_id` | `INTEGER` | — | Reference to related entity |
| `linked_booking_id` | `INTEGER` | — | Reference to related entity |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `FOREIGN KEY (party_id) REFERENCES parties(id)`
- `FOREIGN KEY (account_id) REFERENCES accounts(id)`
- `FOREIGN KEY (linked_transaction_id) REFERENCES transactions(id)`
- `FOREIGN KEY (parent_transaction_id) REFERENCES transactions(id)`

### `credits`

- Columns: **26** | Table constraints: **2** | Indexes: **1**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `customer_name` | `TEXT` | NOT NULL | Display name / label |
| `customer_id` | `INTEGER` | — | Reference to related entity |
| `phone_number` | `TEXT` | — | Phone/contact value |
| `total_amount` | `REAL` | NOT NULL | Monetary value |
| `paid_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `pending_amount` | `REAL` | NOT NULL | Monetary value |
| `direction` | `TEXT` | NOT NULL DEFAULT 'given' | Domain-specific field |
| `credit_date` | `TEXT` | NOT NULL | Business date field |
| `due_date` | `TEXT` | — | Business date field |
| `cleared_date` | `TEXT` | — | Business date field |
| `is_cleared` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `is_overdue` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `interest_rate` | `REAL` | — | Rate/percentage value |
| `interest_type` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `tags` | `TEXT` | — | Tag list / metadata |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `FOREIGN KEY (customer_id) REFERENCES parties(id)`
- `FOREIGN KEY (business_id) REFERENCES businesses(id)`

**Indexes**
- `CREATE INDEX idx_credits_due_date ON credits(due_date)`

### `credit_payments`

- Columns: **15** | Table constraints: **2** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `credit_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `payment_date` | `TEXT` | NOT NULL | Business date field |
| `payment_method` | `TEXT` | — | Domain-specific field |
| `transaction_id` | `INTEGER` | — | Reference to related entity |
| `notes` | `TEXT` | — | Free-form user notes |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `FOREIGN KEY (credit_id) REFERENCES credits(id) ON DELETE CASCADE`
- `FOREIGN KEY (transaction_id) REFERENCES transactions(id)`

### `loans`

- Columns: **33** | Table constraints: **2** | Indexes: **3**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `direction` | `TEXT` | NOT NULL DEFAULT 'borrowed' | Domain-specific field |
| `lender_name` | `TEXT` | NOT NULL | Domain-specific field |
| `lender_id` | `INTEGER` | — | Reference to related entity |
| `phone_number` | `TEXT` | — | Phone/contact value |
| `principal_amount` | `REAL` | NOT NULL | Monetary value |
| `paid_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `pending_amount` | `REAL` | NOT NULL | Monetary value |
| `loan_date` | `TEXT` | NOT NULL | Business date field |
| `due_date` | `TEXT` | — | Business date field |
| `cleared_date` | `TEXT` | — | Business date field |
| `is_cleared` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `is_overdue` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `emi_amount` | `REAL` | — | Monetary value |
| `total_emis` | `INTEGER` | — | Domain-specific field |
| `paid_emis` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `emi_day` | `INTEGER` | — | Domain-specific field |
| `next_emi_date` | `TEXT` | — | Business date field |
| `interest_rate` | `REAL` | — | Rate/percentage value |
| `interest_type` | `TEXT` | — | Domain-specific field |
| `total_interest` | `REAL` | — | Domain-specific field |
| `repayment_frequency` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `tags` | `TEXT` | — | Tag list / metadata |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `FOREIGN KEY (lender_id) REFERENCES parties(id)`
- `FOREIGN KEY (business_id) REFERENCES businesses(id)`

**Indexes**
- `CREATE INDEX idx_loans_lender ON loans(lender_name)`
- `CREATE INDEX idx_loans_next_emi ON loans(next_emi_date)`
- `CREATE INDEX idx_loans_direction ON loans(direction)`

### `loan_payments`

- Columns: **16** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `loan_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `installment_number` | `INTEGER` | NOT NULL | Human-readable document/reference number |
| `due_date` | `TEXT` | NOT NULL | Business date field |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `paid_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `is_paid` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `paid_date` | `TEXT` | — | Business date field |
| `notes` | `TEXT` | — | Free-form user notes |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE`

### `accounts`

- Columns: **23** | Table constraints: **0** | Indexes: **1**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `account_type` | `TEXT` | NOT NULL | Domain-specific field |
| `account_name` | `TEXT` | NOT NULL | Domain-specific field |
| `bank_name` | `TEXT` | — | Domain-specific field |
| `account_number_last4` | `TEXT` | — | Human-readable document/reference number |
| `current_balance` | `REAL` | — | Domain-specific field |
| `opening_balance` | `REAL` | — | Domain-specific field |
| `credit_limit` | `REAL` | — | Domain-specific field |
| `linked_bank_account_id` | `INTEGER` | REFERENCES accounts(id) | Reference to related entity |
| `is_active` | `INTEGER` | DEFAULT 1 | Boolean-like flag (0/1) |
| `is_primary` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `sms_senders` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `color` | `TEXT` | — | Domain-specific field |
| `icon` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Indexes**
- `CREATE INDEX idx_accounts_active ON accounts(is_active)`

### `categories`

- Columns: **19** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL UNIQUE | Display name / label |
| `parent_category` | `TEXT` | — | Domain-specific field |
| `category_type` | `TEXT` | NOT NULL | Domain-specific field |
| `mode` | `TEXT` | DEFAULT 'both' | Domain-specific field |
| `icon` | `TEXT` | NOT NULL | Domain-specific field |
| `color` | `TEXT` | NOT NULL | Domain-specific field |
| `sort_order` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `is_system` | `INTEGER` | DEFAULT 1 | Boolean-like flag (0/1) |
| `is_active` | `INTEGER` | DEFAULT 1 | Boolean-like flag (0/1) |
| `keywords` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

### `budgets`

- Columns: **13** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `year` | `INTEGER` | NOT NULL | Domain-specific field |
| `month` | `INTEGER` | NOT NULL | Domain-specific field |
| `category` | `TEXT` | NOT NULL | Domain-specific field |
| `budget_amount` | `REAL` | NOT NULL | Monetary value |
| `alert_at_percentage` | `REAL` | NOT NULL DEFAULT 80 | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `UNIQUE(year, month, category)`

### `recurring_transactions`

- Columns: **18** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `type` | `TEXT` | NOT NULL | Domain-specific field |
| `category` | `TEXT` | NOT NULL | Domain-specific field |
| `party_name` | `TEXT` | — | Display name / label |
| `payment_method` | `TEXT` | — | Domain-specific field |
| `frequency` | `TEXT` | NOT NULL | Domain-specific field |
| `next_date` | `TEXT` | NOT NULL | Business date field |
| `last_generated` | `TEXT` | — | Domain-specific field |
| `is_active` | `INTEGER` | DEFAULT 1 | Boolean-like flag (0/1) |
| `notes` | `TEXT` | — | Free-form user notes |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

### `scheduled_payments`

- Columns: **27** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `type` | `TEXT` | NOT NULL DEFAULT 'expense' | Domain-specific field |
| `category` | `TEXT` | NOT NULL | Domain-specific field |
| `is_one_time` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `frequency` | `TEXT` | — | Domain-specific field |
| `due_day` | `INTEGER` | — | Domain-specific field |
| `auto_create` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `is_auto_pay` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `next_date` | `TEXT` | NOT NULL | Business date field |
| `last_paid_date` | `TEXT` | — | Business date field |
| `last_generated` | `TEXT` | — | Domain-specific field |
| `party_name` | `TEXT` | — | Display name / label |
| `payment_method` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `bill_context` | `TEXT` | NOT NULL DEFAULT 'personal' | Domain-specific field |
| `party_id` | `INTEGER` | REFERENCES parties(id) | Reference to related entity |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

### `bills`

- Columns: **18** | Table constraints: **0** | Indexes: **1**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `category` | `TEXT` | NOT NULL DEFAULT 'Bills & Utilities' | Domain-specific field |
| `frequency` | `TEXT` | NOT NULL DEFAULT 'monthly' | Domain-specific field |
| `due_day` | `INTEGER` | NOT NULL DEFAULT 1 | Domain-specific field |
| `is_auto_pay` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `notes` | `TEXT` | — | Free-form user notes |
| `payment_method` | `TEXT` | — | Domain-specific field |
| `last_paid_date` | `TEXT` | — | Business date field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Indexes**
- `CREATE INDEX idx_bills_due ON bills(due_day)`

### `bill_attachments`

- Columns: **13** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `transaction_id` | `INTEGER` | NOT NULL UNIQUE | Reference to related entity |
| `file_path` | `TEXT` | NOT NULL | Domain-specific field |
| `file_name` | `TEXT` | NOT NULL | Domain-specific field |
| `file_type` | `TEXT` | NOT NULL DEFAULT 'image' | Domain-specific field |
| `file_size` | `INTEGER` | — | Domain-specific field |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE`


## Parties and Communication

### `parties`

- Columns: **37** | Table constraints: **0** | Indexes: **3**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `phone_number` | `TEXT` | — | Phone/contact value |
| `email` | `TEXT` | — | Email/contact value |
| `party_type` | `TEXT` | NOT NULL DEFAULT 'personal' | Domain-specific field |
| `party_context` | `TEXT` | NOT NULL DEFAULT 'personal' | Domain-specific field |
| `total_transactions` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `total_transaction_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `total_credit_given` | `REAL` | DEFAULT 0 | Domain-specific field |
| `total_credit_received` | `REAL` | DEFAULT 0 | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `tags` | `TEXT` | — | Tag list / metadata |
| `gstin` | `TEXT` | — | Tax/compliance identifier |
| `address` | `TEXT` | — | Domain-specific field |
| `city` | `TEXT` | — | Domain-specific field |
| `state` | `TEXT` | — | Domain-specific field |
| `pincode` | `TEXT` | — | Domain-specific field |
| `business_card_image_path` | `TEXT` | — | Domain-specific field |
| `business_card_media_id` | `TEXT` | — | Reference to related entity |
| `website` | `TEXT` | — | Domain-specific field |
| `whatsapp` | `TEXT` | — | Domain-specific field |
| `linkedin` | `TEXT` | — | Domain-specific field |
| `instagram` | `TEXT` | — | Domain-specific field |
| `country` | `TEXT` | — | Domain-specific field |
| `dial_code` | `TEXT` | — | Domain-specific field |
| `staff_role` | `TEXT` | — | Domain-specific field |
| `staff_salary` | `REAL` | — | Domain-specific field |
| `staff_salary_type` | `TEXT` | DEFAULT 'monthly' | Domain-specific field |
| `staff_join_date` | `TEXT` | — | Business date field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Indexes**
- `CREATE INDEX idx_parties_name ON parties(name)`
- `CREATE INDEX idx_parties_phone ON parties(phone_number)`
- `CREATE INDEX idx_parties_type ON parties(party_type)`

### `party_addresses`

- Columns: **17** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `party_id` | `INTEGER` | NOT NULL REFERENCES parties(id) ON DELETE CASCADE | Reference to related entity |
| `label` | `TEXT` | NOT NULL DEFAULT 'Address' | Domain-specific field |
| `address` | `TEXT` | — | Domain-specific field |
| `city` | `TEXT` | — | Domain-specific field |
| `state` | `TEXT` | — | Domain-specific field |
| `pincode` | `TEXT` | — | Domain-specific field |
| `country` | `TEXT` | DEFAULT 'India' | Domain-specific field |
| `gstin` | `TEXT` | — | Tax/compliance identifier |
| `is_default` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

### `party_reminders`

- Columns: **16** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `party_name` | `TEXT` | NOT NULL | Display name / label |
| `channel` | `TEXT` | NOT NULL DEFAULT 'whatsapp' | Domain-specific field |
| `message` | `TEXT` | NOT NULL | Domain-specific field |
| `invoice_refs` | `TEXT` | — | Domain-specific field |
| `invoice_count` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `total_outstanding` | `REAL` | — | Domain-specific field |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `sent_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Timestamp field |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (business_id) REFERENCES businesses(id)`


## Business Docs and Revenue Flows

### `businesses`

- Columns: **29** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `address` | `TEXT` | — | Domain-specific field |
| `city` | `TEXT` | — | Domain-specific field |
| `state` | `TEXT` | — | Domain-specific field |
| `pincode` | `TEXT` | — | Domain-specific field |
| `phone` | `TEXT` | — | Phone/contact value |
| `phones_json` | `TEXT` | — | Phone/contact value |
| `email` | `TEXT` | — | Email/contact value |
| `gst_no` | `TEXT` | — | Human-readable document/reference number |
| `logo_path` | `TEXT` | — | Domain-specific field |
| `logo_media_id` | `TEXT` | — | Reference to related entity |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `owner_name` | `TEXT` | — | Domain-specific field |
| `website` | `TEXT` | — | Domain-specific field |
| `whatsapp` | `TEXT` | — | Domain-specific field |
| `linkedin` | `TEXT` | — | Domain-specific field |
| `instagram` | `TEXT` | — | Domain-specific field |
| `upi_id` | `TEXT` | — | Reference to related entity |
| `country` | `TEXT` | — | Domain-specific field |
| `dial_code` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

### `quotes`

- Columns: **28** | Table constraints: **0** | Indexes: **2**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `quote_no` | `TEXT` | NOT NULL UNIQUE | Human-readable document/reference number |
| `customer_party_id` | `INTEGER` | — | Reference to related entity |
| `customer_name` | `TEXT` | NOT NULL | Display name / label |
| `status` | `TEXT` | NOT NULL DEFAULT 'draft' | Current lifecycle/status state |
| `valid_until` | `TEXT` | — | Domain-specific field |
| `subtotal` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `tax_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `total` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `notes` | `TEXT` | — | Free-form user notes |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `invoice_type` | `TEXT` | NOT NULL DEFAULT 'tax_invoice' | Domain-specific field |
| `place_of_supply` | `TEXT` | — | Domain-specific field |
| `reverse_charge` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `customer_gstin` | `TEXT` | — | Tax/compliance identifier |
| `freight_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `insurance_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `packing_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `pending_number_since` | `TEXT` | — | Human-readable document/reference number |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Indexes**
- `CREATE INDEX idx_quotes_status ON quotes(status)`
- `CREATE INDEX idx_quotes_business ON quotes(business_id)`

### `quote_items`

- Columns: **14** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `quote_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `item_name` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | — | Domain-specific field |
| `qty` | `REAL` | NOT NULL DEFAULT 1 | Quantity measure |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `tax_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `line_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `hsn_code` | `TEXT` | — | Tax/compliance identifier |
| `unit` | `TEXT` | DEFAULT 'PCS' | Domain-specific field |
| `hsn_or_sac` | `TEXT` | DEFAULT 'HSN' | Tax/compliance identifier |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE`

### `invoices`

- Columns: **55** | Table constraints: **1** | Indexes: **3**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `invoice_no` | `TEXT` | NOT NULL UNIQUE | Human-readable document/reference number |
| `quote_id` | `INTEGER` | — | Reference to related entity |
| `customer_party_id` | `INTEGER` | — | Reference to related entity |
| `customer_name` | `TEXT` | NOT NULL | Display name / label |
| `status` | `TEXT` | NOT NULL DEFAULT 'draft' | Current lifecycle/status state |
| `issue_date` | `TEXT` | NOT NULL | Business date field |
| `due_date` | `TEXT` | — | Business date field |
| `subtotal` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `tax_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `total` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `paid_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `notes` | `TEXT` | — | Free-form user notes |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `paid_at` | `TEXT` | — | Timestamp field |
| `payment_method` | `TEXT` | — | Domain-specific field |
| `reminder_sent_at` | `TEXT` | — | Timestamp field |
| `invoice_type` | `TEXT` | NOT NULL DEFAULT 'tax_invoice' | Domain-specific field |
| `place_of_supply` | `TEXT` | — | Domain-specific field |
| `reverse_charge` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `customer_gstin` | `TEXT` | — | Tax/compliance identifier |
| `irn` | `TEXT` | — | Tax/compliance identifier |
| `irn_ack_no` | `TEXT` | — | Human-readable document/reference number |
| `irn_ack_date` | `TEXT` | — | Business date field |
| `qr_code_data` | `TEXT` | — | Domain-specific field |
| `ewb_no` | `TEXT` | — | Human-readable document/reference number |
| `ewb_generated_at` | `TEXT` | — | Timestamp field |
| `ewb_valid_until` | `TEXT` | — | Domain-specific field |
| `vehicle_no` | `TEXT` | — | Human-readable document/reference number |
| `transporter_name` | `TEXT` | — | Domain-specific field |
| `transporter_gstin` | `TEXT` | — | Tax/compliance identifier |
| `transport_mode` | `TEXT` | DEFAULT '1' | Domain-specific field |
| `distance_km` | `INTEGER` | — | Domain-specific field |
| `freight_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `insurance_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `packing_amt` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `challan_id` | `INTEGER` | REFERENCES delivery_challans(id) ON DELETE SET NULL | Reference to related entity |
| `delivery_address` | `TEXT` | — | Domain-specific field |
| `delivery_city` | `TEXT` | — | Domain-specific field |
| `delivery_state` | `TEXT` | — | Domain-specific field |
| `delivery_pincode` | `TEXT` | — | Domain-specific field |
| `delivery_gstin` | `TEXT` | — | Tax/compliance identifier |
| `original_invoice_id` | `INTEGER` | — | Reference to related entity |
| `original_invoice_no` | `TEXT` | — | Human-readable document/reference number |
| `original_invoice_date` | `TEXT` | — | Business date field |
| `created_at` | `TEXT` | NOT NULL | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |
| `pending_number_since` | `TEXT` | — | Human-readable document/reference number |

**Table-level constraints**
- `FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL`

**Indexes**
- `CREATE INDEX idx_invoices_status ON invoices(status)`
- `CREATE INDEX idx_invoices_due ON invoices(due_date)`
- `CREATE INDEX idx_invoices_ewb ON invoices(ewb_no)`

### `invoice_items`

- Columns: **16** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `invoice_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `item_name` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | — | Domain-specific field |
| `qty` | `REAL` | NOT NULL DEFAULT 1 | Quantity measure |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `tax_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `line_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `hsn_code` | `TEXT` | — | Tax/compliance identifier |
| `unit` | `TEXT` | DEFAULT 'PCS' | Domain-specific field |
| `hsn_or_sac` | `TEXT` | DEFAULT 'HSN' | Tax/compliance identifier |
| `catalog_item_id` | `INTEGER` | — | Reference to related entity |
| `lot_allocation_json` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE`

### `bookings`

- Columns: **27** | Table constraints: **4** | Indexes: **1**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `customer_party_id` | `INTEGER` | — | Reference to related entity |
| `customer_name` | `TEXT` | NOT NULL | Display name / label |
| `service_item_id` | `INTEGER` | — | Reference to related entity |
| `service_name` | `TEXT` | NOT NULL | Domain-specific field |
| `start_datetime` | `TEXT` | NOT NULL | Domain-specific field |
| `end_datetime` | `TEXT` | — | Domain-specific field |
| `duration_minutes` | `INTEGER` | — | Domain-specific field |
| `status` | `TEXT` | NOT NULL DEFAULT 'pending' | Current lifecycle/status state |
| `booking_type` | `TEXT` | NOT NULL DEFAULT 'business' | Domain-specific field |
| `total_amount` | `REAL` | NOT NULL | Monetary value |
| `advance_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `paid_amount` | `REAL` | DEFAULT 0 | Monetary value |
| `invoice_id` | `INTEGER` | — | Reference to related entity |
| `notes` | `TEXT` | — | Free-form user notes |
| `notification_scheduled_at` | `TEXT` | — | Timestamp field |
| `confirmed_at` | `TEXT` | — | Timestamp field |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `booking_ref` | `TEXT` | — | Domain-specific field |
| `reminder_sent_at` | `TEXT` | — | Timestamp field |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (customer_party_id) REFERENCES parties(id)`
- `FOREIGN KEY (service_item_id) REFERENCES item_catalog(id)`
- `FOREIGN KEY (invoice_id) REFERENCES invoices(id)`
- `FOREIGN KEY (business_id) REFERENCES businesses(id)`

**Indexes**
- `CREATE INDEX idx_bookings_status ON bookings(status)`

### `booking_items`

- Columns: **15** | Table constraints: **2** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `booking_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `item_name` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | — | Domain-specific field |
| `qty` | `REAL` | NOT NULL DEFAULT 1 | Quantity measure |
| `unit` | `TEXT` | DEFAULT 'session' | Domain-specific field |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `tax_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `line_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `sac_code` | `TEXT` | — | Tax/compliance identifier |
| `sort_order` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `service_item_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE`
- `FOREIGN KEY (service_item_id) REFERENCES item_catalog(id)`

### `delivery_challans`

- Columns: **33** | Table constraints: **2** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `challan_no` | `TEXT` | NOT NULL UNIQUE | Human-readable document/reference number |
| `customer_party_id` | `INTEGER` | — | Reference to related entity |
| `customer_name` | `TEXT` | NOT NULL | Display name / label |
| `status` | `TEXT` | NOT NULL DEFAULT 'draft' | Current lifecycle/status state |
| `challan_date` | `TEXT` | NOT NULL | Business date field |
| `dispatch_date` | `TEXT` | — | Business date field |
| `expected_return_date` | `TEXT` | — | Business date field |
| `purpose` | `TEXT` | NOT NULL DEFAULT 'supply' | Domain-specific field |
| `subtotal` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `notes` | `TEXT` | — | Free-form user notes |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `customer_gstin` | `TEXT` | — | Tax/compliance identifier |
| `place_of_supply` | `TEXT` | — | Domain-specific field |
| `vehicle_no` | `TEXT` | — | Human-readable document/reference number |
| `transporter_name` | `TEXT` | — | Domain-specific field |
| `transport_mode` | `TEXT` | — | Domain-specific field |
| `distance_km` | `INTEGER` | — | Domain-specific field |
| `converted_invoice_id` | `INTEGER` | — | Reference to related entity |
| `ewb_no` | `TEXT` | — | Human-readable document/reference number |
| `delivery_address` | `TEXT` | — | Domain-specific field |
| `delivery_city` | `TEXT` | — | Domain-specific field |
| `delivery_state` | `TEXT` | — | Domain-specific field |
| `delivery_pincode` | `TEXT` | — | Domain-specific field |
| `delivery_gstin` | `TEXT` | — | Tax/compliance identifier |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `pending_number_since` | `TEXT` | — | Human-readable document/reference number |

**Table-level constraints**
- `FOREIGN KEY (customer_party_id) REFERENCES parties(id)`
- `FOREIGN KEY (converted_invoice_id) REFERENCES invoices(id) ON DELETE SET NULL`

### `delivery_challan_items`

- Columns: **13** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `challan_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `item_name` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | — | Domain-specific field |
| `qty` | `REAL` | NOT NULL DEFAULT 1 | Quantity measure |
| `unit` | `TEXT` | DEFAULT 'PCS' | Domain-specific field |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `line_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `hsn_code` | `TEXT` | — | Tax/compliance identifier |
| `hsn_or_sac` | `TEXT` | DEFAULT 'HSN' | Tax/compliance identifier |
| `catalog_item_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (challan_id) REFERENCES delivery_challans(id) ON DELETE CASCADE`

### `purchase_bills`

- Columns: **33** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `business_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `bill_no` | `TEXT` | NOT NULL | Human-readable document/reference number |
| `vendor_party_id` | `INTEGER` | — | Reference to related entity |
| `vendor_name` | `TEXT` | NOT NULL | Display name / label |
| `vendor_gstin` | `TEXT` | — | Tax/compliance identifier |
| `bill_date` | `TEXT` | NOT NULL | Business date field |
| `due_date` | `TEXT` | — | Business date field |
| `place_of_supply` | `TEXT` | — | Domain-specific field |
| `reverse_charge` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `subtotal` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `igst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `cgst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `sgst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `cess_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `tax_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `total` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `paid_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `itc_eligibility` | `TEXT` | NOT NULL DEFAULT 'eligible' | Domain-specific field |
| `itc_block_reason` | `TEXT` | — | Domain-specific field |
| `itc_availed` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `itc_reversal_reason` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `status` | `TEXT` | NOT NULL DEFAULT 'unpaid' | Current lifecycle/status state |
| `attachment_path` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

**Table-level constraints**
- `FOREIGN KEY (vendor_party_id) REFERENCES parties(id) ON DELETE SET NULL`

### `purchase_bill_items`

- Columns: **21** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `bill_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `item_name` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | — | Domain-specific field |
| `qty` | `REAL` | NOT NULL DEFAULT 1 | Quantity measure |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `tax_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `discount_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `line_total` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `igst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `cgst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `sgst_amount` | `REAL` | NOT NULL DEFAULT 0 | Monetary value |
| `hsn_code` | `TEXT` | — | Tax/compliance identifier |
| `unit` | `TEXT` | DEFAULT 'PCS' | Domain-specific field |
| `hsn_or_sac` | `TEXT` | DEFAULT 'HSN' | Tax/compliance identifier |
| `catalog_item_id` | `INTEGER` | — | Reference to related entity |
| `lot_no` | `TEXT` | — | Human-readable document/reference number |
| `expiry_date` | `TEXT` | — | Business date field |
| `mfg_date` | `TEXT` | — | Business date field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (bill_id) REFERENCES purchase_bills(id) ON DELETE CASCADE`

### `invoice_number_cursors`

- Columns: **4** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `doc_type` | `TEXT` | PRIMARY KEY | Domain-specific field |
| `prefix` | `TEXT` | NOT NULL | Domain-specific field |
| `last_seq` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |

### `document_templates`

- Columns: **25** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `based_on` | `TEXT` | NOT NULL DEFAULT 'modern' | Domain-specific field |
| `accent_color_hex` | `TEXT` | NOT NULL DEFAULT '#1B5E20' | Domain-specific field |
| `header_style` | `TEXT` | NOT NULL DEFAULT 'minimal' | Domain-specific field |
| `show_logo` | `INTEGER` | NOT NULL DEFAULT 1 | Domain-specific field |
| `amount_decimal_digits` | `INTEGER` | NOT NULL DEFAULT 0 | Monetary value |
| `page_size` | `TEXT` | NOT NULL DEFAULT 'a4' | Domain-specific field |
| `font_family` | `TEXT` | NOT NULL DEFAULT 'helvetica' | Domain-specific field |
| `body_font_size` | `REAL` | NOT NULL DEFAULT 9 | Domain-specific field |
| `title_font_size` | `REAL` | NOT NULL DEFAULT 22 | Domain-specific field |
| `page_margin` | `REAL` | NOT NULL DEFAULT 32 | Domain-specific field |
| `section_spacing` | `REAL` | NOT NULL DEFAULT 20 | Domain-specific field |
| `item_column_width_pct` | `REAL` | NOT NULL DEFAULT 45 | Rate/percentage value |
| `header_alignment` | `TEXT` | NOT NULL DEFAULT 'left' | Domain-specific field |
| `builder_config_json` | `TEXT` | NOT NULL DEFAULT '{}' | Domain-specific field |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `is_preset` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |


## Catalog, Stock, and Units

### `item_catalog`

- Columns: **58** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `description` | `TEXT` | — | Domain-specific field |
| `unit` | `TEXT` | DEFAULT 'pcs' | Domain-specific field |
| `unit_price` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `tax_pct` | `REAL` | NOT NULL DEFAULT 0 | Rate/percentage value |
| `hsn_code` | `TEXT` | — | Tax/compliance identifier |
| `hsn_or_sac` | `TEXT` | DEFAULT 'HSN' | Tax/compliance identifier |
| `brand_name` | `TEXT` | — | Domain-specific field |
| `primary_image_path` | `TEXT` | — | Domain-specific field |
| `barcode` | `TEXT` | — | Domain-specific field |
| `additional_properties_json` | `TEXT` | — | Domain-specific field |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `sku` | `TEXT` | — | Domain-specific field |
| `category` | `TEXT` | DEFAULT 'product' | Domain-specific field |
| `is_favorite` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `last_used_at` | `TEXT` | — | Timestamp field |
| `usage_count` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `duration_minutes` | `INTEGER` | DEFAULT 30 | Domain-specific field |
| `is_bookable` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `track_inventory` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `stock_qty` | `REAL` | NOT NULL DEFAULT 0 | Quantity measure |
| `low_stock_threshold` | `REAL` | NOT NULL DEFAULT 5 | Domain-specific field |
| `mrp` | `REAL` | — | Domain-specific field |
| `dealer_price` | `REAL` | — | Domain-specific field |
| `mpn` | `TEXT` | — | Domain-specific field |
| `availability` | `TEXT` | DEFAULT 'InStock' | Domain-specific field |
| `price_currency` | `TEXT` | DEFAULT 'INR' | Domain-specific field |
| `price_valid_until` | `TEXT` | — | Domain-specific field |
| `manufacturer_name` | `TEXT` | — | Domain-specific field |
| `color` | `TEXT` | — | Domain-specific field |
| `size` | `TEXT` | — | Domain-specific field |
| `weight_value` | `REAL` | — | Domain-specific field |
| `weight_unit` | `TEXT` | DEFAULT 'g' | Domain-specific field |
| `width_cm` | `REAL` | — | Domain-specific field |
| `height_cm` | `REAL` | — | Domain-specific field |
| `depth_cm` | `REAL` | — | Domain-specific field |
| `material` | `TEXT` | — | Domain-specific field |
| `keywords` | `TEXT` | — | Domain-specific field |
| `country_of_origin` | `TEXT` | — | Domain-specific field |
| `release_date` | `TEXT` | — | Business date field |
| `product_id` | `TEXT` | — | Reference to related entity |
| `asin` | `TEXT` | — | Domain-specific field |
| `logo_path` | `TEXT` | — | Domain-specific field |
| `pattern` | `TEXT` | — | Domain-specific field |
| `slogan` | `TEXT` | — | Domain-specific field |
| `item_condition` | `TEXT` | DEFAULT 'NewCondition' | Domain-specific field |
| `model_number` | `TEXT` | — | Human-readable document/reference number |
| `product_group_id` | `INTEGER` | — | Reference to related entity |
| `created_at` | `TEXT` | NOT NULL | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |
| `context_id` | `INTEGER` | REFERENCES linked_business_sessions(id) ON DELETE CASCADE | Linked business session scope |

### `unit_types`

- Columns: **5** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `code` | `TEXT` | — | Domain-specific field |
| `label` | `TEXT` | NOT NULL UNIQUE | Domain-specific field |
| `is_system` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `sort_order` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |

### `stock_movements`

- Columns: **16** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `item_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `business_id` | `INTEGER` | REFERENCES businesses(id) | Reference to related entity |
| `movement_type` | `TEXT` | NOT NULL | Domain-specific field |
| `qty` | `REAL` | NOT NULL | Quantity measure |
| `stock_after` | `REAL` | NOT NULL | Domain-specific field |
| `reference_id` | `INTEGER` | — | Reference to related entity |
| `reference_type` | `TEXT` | — | Domain-specific field |
| `notes` | `TEXT` | — | Free-form user notes |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (item_id) REFERENCES item_catalog(id) ON DELETE CASCADE`

### `item_stock`

- Columns: **9** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `business_id` | `INTEGER` | NOT NULL REFERENCES businesses(id) | Reference to related entity |
| `item_id` | `INTEGER` | NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE | Reference to related entity |
| `stock_qty` | `REAL` | NOT NULL DEFAULT 0 | Quantity measure |
| `low_stock_threshold` | `REAL` | NOT NULL DEFAULT 5 | Domain-specific field |
| `track_inventory` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `last_counted_qty` | `REAL` | — | Quantity measure |
| `last_counted_at` | `TEXT` | — | Timestamp field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |

**Table-level constraints**
- `PRIMARY KEY (business_id, item_id)`

### `stock_lots`

- Columns: **19** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `business_id` | `INTEGER` | NOT NULL REFERENCES businesses(id) | Reference to related entity |
| `item_id` | `INTEGER` | NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE | Reference to related entity |
| `purchase_bill_id` | `INTEGER` | REFERENCES purchase_bills(id) ON DELETE SET NULL | Reference to related entity |
| `lot_no` | `TEXT` | — | Human-readable document/reference number |
| `expiry_date` | `TEXT` | — | Business date field |
| `mfg_date` | `TEXT` | — | Business date field |
| `unit_cost` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `qty_in` | `REAL` | NOT NULL DEFAULT 0 | Quantity measure |
| `qty_remaining` | `REAL` | NOT NULL DEFAULT 0 | Quantity measure |
| `status` | `TEXT` | NOT NULL DEFAULT 'active' | Current lifecycle/status state |
| `notes` | `TEXT` | — | Free-form user notes |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

### `lot_movements`

- Columns: **12** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `business_id` | `INTEGER` | NOT NULL REFERENCES businesses(id) | Reference to related entity |
| `item_id` | `INTEGER` | NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE | Reference to related entity |
| `lot_id` | `INTEGER` | NOT NULL REFERENCES stock_lots(id) ON DELETE CASCADE | Reference to related entity |
| `movement_type` | `TEXT` | NOT NULL | Domain-specific field |
| `qty` | `REAL` | NOT NULL | Quantity measure |
| `lot_qty_after` | `REAL` | NOT NULL | Quantity measure |
| `reference_type` | `TEXT` | — | Domain-specific field |
| `reference_id` | `INTEGER` | — | Reference to related entity |
| `reference_line_id` | `INTEGER` | — | Reference to related entity |
| `notes` | `TEXT` | — | Free-form user notes |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |

### `transporters`

- Columns: **4** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `gstin` | `TEXT` | — | Tax/compliance identifier |
| `last_used_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Timestamp field |

### `hsn_master`

- Columns: **4** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `code` | `TEXT` | NOT NULL | Domain-specific field |
| `description` | `TEXT` | NOT NULL | Domain-specific field |
| `type` | `TEXT` | NOT NULL DEFAULT 'HSN' | Domain-specific field |


## Staff and Payroll

### `staff`

- Columns: **26** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `name` | `TEXT` | NOT NULL | Display name / label |
| `designation` | `TEXT` | — | Domain-specific field |
| `phone` | `TEXT` | — | Phone/contact value |
| `email` | `TEXT` | — | Email/contact value |
| `department` | `TEXT` | — | Domain-specific field |
| `salary_type` | `TEXT` | NOT NULL DEFAULT 'monthly' | Domain-specific field |
| `base_salary` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `join_date` | `TEXT` | — | Business date field |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `bank_name` | `TEXT` | — | Domain-specific field |
| `account_no` | `TEXT` | — | Human-readable document/reference number |
| `ifsc_code` | `TEXT` | — | Domain-specific field |
| `pan` | `TEXT` | — | Domain-specific field |
| `pf_no` | `TEXT` | — | Human-readable document/reference number |
| `esi_no` | `TEXT` | — | Human-readable document/reference number |
| `notes` | `TEXT` | — | Free-form user notes |
| `business_id` | `INTEGER` | — | Reference to related entity |
| `party_id` | `INTEGER` | REFERENCES parties(id) | Reference to related entity |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (business_id) REFERENCES businesses(id)`

### `salary_payments`

- Columns: **20** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `staff_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `pay_period_month` | `INTEGER` | NOT NULL | Domain-specific field |
| `pay_period_year` | `INTEGER` | NOT NULL | Domain-specific field |
| `base_salary` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `allowances` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `deductions` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `bonus` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `net_salary` | `REAL` | NOT NULL DEFAULT 0 | Domain-specific field |
| `payment_method` | `TEXT` | DEFAULT 'bank_transfer' | Domain-specific field |
| `paid_date` | `TEXT` | — | Business date field |
| `status` | `TEXT` | NOT NULL DEFAULT 'pending' | Current lifecycle/status state |
| `notes` | `TEXT` | — | Free-form user notes |
| `sync_id` | `TEXT` | UNIQUE DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | — | Last update timestamp |
| `deleted_at` | `TEXT` | — | Soft-delete timestamp |
| `version` | `INTEGER` | NOT NULL DEFAULT 0 | Monotonic version for merge/conflict handling |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

**Table-level constraints**
- `FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE`

### `payroll_notifications`

- Columns: **11** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `notification_id` | `TEXT` | NOT NULL UNIQUE | Reference to related entity |
| `source_identity_id` | `TEXT` | NOT NULL | Reference to related entity |
| `business_name` | `TEXT` | NOT NULL | Domain-specific field |
| `amount` | `REAL` | NOT NULL | Monetary value |
| `currency` | `TEXT` | NOT NULL DEFAULT 'INR' | Domain-specific field |
| `reference_label` | `TEXT` | — | Domain-specific field |
| `paid_on` | `TEXT` | NOT NULL | Domain-specific field |
| `received_at` | `TEXT` | DEFAULT (datetime('now')) | Timestamp field |
| `status` | `TEXT` | NOT NULL DEFAULT 'pending' | Current lifecycle/status state |
| `created_transaction_id` | `INTEGER` | REFERENCES transactions(id) ON DELETE SET NULL | Reference to related entity |


## Settings, Auth, Permissions, Plans

### `settings`

- Columns: **5** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `key` | `TEXT` | PRIMARY KEY | Settings key |
| `value` | `TEXT` | NOT NULL | Settings value |
| `updated_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Last update timestamp |
| `created_by_device_id` | `TEXT` | — | Device that created the row |
| `updated_by_device_id` | `TEXT` | — | Device that last updated the row |

### `app_users`

- Columns: **11** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `sync_id` | `TEXT` | UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `display_name` | `TEXT` | NOT NULL | Display name / label |
| `pin_hash` | `TEXT` | — | Domain-specific field |
| `role` | `TEXT` | NOT NULL DEFAULT 'custom' | Domain-specific field |
| `linked_party_id` | `INTEGER` | — | Reference to related entity |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `default_device_id` | `TEXT` | — | Reference to related entity |
| `last_login_at` | `TEXT` | — | Timestamp field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (linked_party_id) REFERENCES parties(id) ON DELETE SET NULL`

### `user_permissions`

- Columns: **8** | Table constraints: **2** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `user_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `business_id` | `INTEGER` | NOT NULL DEFAULT -1 | Reference to related entity |
| `module` | `TEXT` | NOT NULL | Domain-specific field |
| `can_view` | `INTEGER` | NOT NULL DEFAULT 1 | Permission flag (0/1) |
| `can_create` | `INTEGER` | NOT NULL DEFAULT 0 | Permission flag (0/1) |
| `can_edit` | `INTEGER` | NOT NULL DEFAULT 0 | Permission flag (0/1) |
| `can_delete` | `INTEGER` | NOT NULL DEFAULT 0 | Permission flag (0/1) |

**Table-level constraints**
- `UNIQUE (user_id, business_id, module)`
- `FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE CASCADE`

### `subscription`

- Columns: **9** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY DEFAULT 1 | Primary row identifier |
| `plan` | `TEXT` | NOT NULL DEFAULT 'free' | Domain-specific field |
| `source` | `TEXT` | DEFAULT 'none' | Domain-specific field |
| `purchase_token` | `TEXT` | — | Domain-specific field |
| `plan_started_at` | `TEXT` | — | Timestamp field |
| `plan_expires_at` | `TEXT` | — | Timestamp field |
| `is_trial` | `INTEGER` | NOT NULL DEFAULT 0 | Boolean-like flag (0/1) |
| `trial_ends_at` | `TEXT` | — | Timestamp field |
| `shareable_plan_features` | `TEXT` | — | Domain-specific field |

### `plan_features`

- Columns: **4** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `plan` | `TEXT` | NOT NULL | Domain-specific field |
| `feature` | `TEXT` | NOT NULL | Domain-specific field |
| `enabled` | `INTEGER` | NOT NULL DEFAULT 1 | Domain-specific field |
| `limit_value` | `INTEGER` | — | Domain-specific field |

**Table-level constraints**
- `PRIMARY KEY (plan, feature)`

### `activity_log`

- Columns: **7** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `entity_type` | `TEXT` | NOT NULL | Domain-specific field |
| `entity_id` | `INTEGER` | NOT NULL | Reference to related entity |
| `type` | `TEXT` | NOT NULL DEFAULT 'note' | Domain-specific field |
| `message` | `TEXT` | NOT NULL | Domain-specific field |
| `meta` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |


## Device Identity and Sync Infrastructure

### `linked_devices`

- Columns: **19** | Table constraints: **2** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `sync_id` | `TEXT` | UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))) | Cross-device immutable row identity |
| `device_id` | `TEXT` | NOT NULL UNIQUE | Reference to related entity |
| `device_name` | `TEXT` | NOT NULL | Domain-specific field |
| `device_type` | `TEXT` | — | Domain-specific field |
| `device_os` | `TEXT` | — | Domain-specific field |
| `secondary_public_key` | `TEXT` | NOT NULL DEFAULT '' | Domain-specific field |
| `user_id` | `INTEGER` | — | Reference to related entity |
| `linked_party_id` | `INTEGER` | — | Reference to related entity |
| `permission_scope` | `TEXT` | NOT NULL DEFAULT '{}' | Serialized JSON/text payload |
| `business_scope` | `TEXT` | NOT NULL DEFAULT '[]' | Serialized JSON/text payload |
| `offline_grace_days` | `INTEGER` | NOT NULL DEFAULT 7 | Domain-specific field |
| `permission_preset` | `TEXT` | NOT NULL DEFAULT 'owner_mirror' | Domain-specific field |
| `last_sync_at` | `TEXT` | — | Timestamp field |
| `revoked_at` | `TEXT` | — | Timestamp field |
| `secondary_identity_id` | `TEXT` | — | Reference to related entity |
| `secondary_display_name` | `TEXT` | — | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Last update timestamp |

**Table-level constraints**
- `FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE SET NULL`
- `FOREIGN KEY (linked_party_id) REFERENCES parties(id) ON DELETE SET NULL`

### `device_recovery`

- Columns: **5** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY | Primary row identifier |
| `recovery_key_hash` | `TEXT` | NOT NULL | Domain-specific field |
| `kdf_salt` | `TEXT` | NOT NULL | Domain-specific field |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `last_rotated_at` | `TEXT` | — | Timestamp field |

### `pairing_history`

- Columns: **5** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `device_id` | `TEXT` | NOT NULL | Reference to related entity |
| `device_name` | `TEXT` | NOT NULL | Domain-specific field |
| `permission_preset` | `TEXT` | NOT NULL DEFAULT 'custom' | Domain-specific field |
| `paired_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Timestamp field |

### `device_session`

- Columns: **5** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY DEFAULT 1 | Primary row identifier |
| `active_user_id` | `INTEGER` | REFERENCES app_users(id) | Reference to related entity |
| `active_business_id` | `INTEGER` | — | Reference to related entity |
| `locked` | `INTEGER` | NOT NULL DEFAULT 0 | Domain-specific field |
| `last_activity_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Timestamp field |

### `my_identity`

- Columns: **7** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY | Primary row identifier |
| `identity_id` | `TEXT` | NOT NULL UNIQUE | Reference to related entity |
| `display_name` | `TEXT` | NOT NULL | Display name / label |
| `avatar_seed` | `TEXT` | — | Domain-specific field |
| `public_key` | `TEXT` | NOT NULL | Domain-specific field |
| `created_at` | `TEXT` | DEFAULT (datetime('now')) | Row creation timestamp |
| `updated_at` | `TEXT` | DEFAULT (datetime('now')) | Last update timestamp |

### `linked_business_sessions`

- Columns: **17** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `session_id` | `TEXT` | NOT NULL UNIQUE | Reference to related entity |
| `primary_identity_id` | `TEXT` | NOT NULL | Reference to related entity |
| `primary_public_key` | `TEXT` | NOT NULL | Domain-specific field |
| `primary_device_name` | `TEXT` | — | Domain-specific field |
| `business_name` | `TEXT` | NOT NULL DEFAULT 'Linked Business' | Domain-specific field |
| `business_ids` | `TEXT` | NOT NULL DEFAULT '[]' | Domain-specific field |
| `token_payload` | `TEXT` | NOT NULL | Serialized JSON/text payload |
| `token_signature` | `TEXT` | NOT NULL | Serialized JSON/text payload |
| `permission_scope` | `TEXT` | NOT NULL DEFAULT '{}' | Serialized JSON/text payload |
| `offline_grace_days` | `INTEGER` | NOT NULL DEFAULT 7 | Domain-specific field |
| `issued_at` | `TEXT` | NOT NULL | Timestamp field |
| `last_sync_at` | `TEXT` | — | Timestamp field |
| `is_read_only_forced` | `INTEGER` | DEFAULT 0 | Boolean-like flag (0/1) |
| `display_order` | `INTEGER` | DEFAULT 0 | Domain-specific field |
| `unlinked_at` | `TEXT` | — | Timestamp field |
| `created_at` | `TEXT` | DEFAULT (datetime('now')) | Row creation timestamp |

### `trusted_peers`

- Columns: **11** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `peer_identity_id` | `TEXT` | NOT NULL UNIQUE | Reference to related entity |
| `peer_name` | `TEXT` | — | Domain-specific field |
| `business_id` | `TEXT` | — | Reference to related entity |
| `shared_secret_enc` | `TEXT` | NOT NULL | Domain-specific field |
| `paired_at` | `TEXT` | NOT NULL | Timestamp field |
| `last_seen_at` | `TEXT` | — | Timestamp field |
| `last_synced_at` | `TEXT` | — | Timestamp field |
| `is_active` | `INTEGER` | NOT NULL DEFAULT 1 | Boolean-like flag (0/1) |
| `key_version` | `INTEGER` | NOT NULL DEFAULT 1 | Domain-specific field |
| `key_rotated_at` | `TEXT` | — | Timestamp field |

### `sync_outbox`

- Columns: **7** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `target_device_id` | `TEXT` | — | Reference to related entity |
| `target_identity_id` | `TEXT` | — | Reference to related entity |
| `event_type` | `TEXT` | NOT NULL | Domain-specific field |
| `payload` | `TEXT` | — | Serialized JSON/text payload |
| `created_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Row creation timestamp |
| `delivered_at` | `TEXT` | — | Timestamp field |

### `sync_watermarks`

- Columns: **4** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `peer_identity_id` | `TEXT` | NOT NULL | Reference to related entity |
| `table_name` | `TEXT` | NOT NULL | Domain-specific field |
| `last_synced_at` | `TEXT` | NOT NULL | Timestamp field |
| `last_sync_cursor` | `TEXT` | — | Sync progress/control metadata |

**Table-level constraints**
- `PRIMARY KEY (peer_identity_id, table_name)`

### `sync_table_state`

- Columns: **8** | Table constraints: **1** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `peer_identity_id` | `TEXT` | NOT NULL | Reference to related entity |
| `table_name` | `TEXT` | NOT NULL | Domain-specific field |
| `sync_mode` | `TEXT` | NOT NULL | Sync progress/control metadata |
| `last_synced_at` | `TEXT` | — | Timestamp field |
| `last_version` | `INTEGER` | — | Domain-specific field |
| `last_pk` | `TEXT` | — | Domain-specific field |
| `schema_fingerprint` | `TEXT` | NOT NULL | Domain-specific field |
| `updated_at` | `TEXT` | NOT NULL DEFAULT (datetime('now')) | Last update timestamp |

**Table-level constraints**
- `PRIMARY KEY (peer_identity_id, table_name)`

### `invoice_events`

- Columns: **7** | Table constraints: **0** | Indexes: **0**

| Column | Type | Constraints | Purpose |
|---|---|---|---|
| `id` | `INTEGER` | PRIMARY KEY AUTOINCREMENT | Primary row identifier |
| `invoice_id` | `TEXT` | NOT NULL | Reference to related entity |
| `event_type` | `TEXT` | NOT NULL | Domain-specific field |
| `event_data` | `TEXT` | — | Serialized JSON/text payload |
| `occurred_at` | `TEXT` | NOT NULL | Timestamp field |
| `device_id` | `TEXT` | NOT NULL | Reference to related entity |
| `sync_id` | `TEXT` | NOT NULL UNIQUE | Cross-device immutable row identity |

## Ungrouped

- `media_assets`
- `product_groups`
- `product_relationships`
- `product_reviews`
- `app_logs`
