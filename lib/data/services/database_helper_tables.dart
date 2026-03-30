part of 'database_helper.dart';

// Per-domain schema builder helpers extracted from DatabaseHelper._onCreate.
// Each method creates the tables and indexes for one domain group.
// Called once, in order, during a fresh database installation.
extension _DatabaseTableCreators on DatabaseHelper {
  // ── 1. Transactions ───────────────────────────────────────────────────────

  Future<void> _createTransactionTables(Database db) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'personal',
        category TEXT NOT NULL,
        party_name TEXT,
        party_id INTEGER,
        phone_number TEXT,
        payment_method TEXT DEFAULT 'cash',
        account_id INTEGER,
        to_account_id INTEGER,
        sms_body TEXT,
        sms_sender TEXT,
        upi_app TEXT,
        upi_ref_no TEXT,
        reference_id TEXT,
        auto_detected INTEGER DEFAULT 0,
        verified INTEGER DEFAULT 0,
        credit_id INTEGER,
        loan_id INTEGER,
        linked_transaction_id INTEGER,
        parent_transaction_id INTEGER,
        due_date TEXT,
        interest_rate REAL,
        interest_type TEXT,
        repayment_frequency TEXT,
        total_installments INTEGER,
        emi_amount REAL,
        dedupe_hash TEXT UNIQUE,
        notes TEXT,
        tags TEXT,
        reminder_sent_at TEXT,
        linked_invoice_id INTEGER,
        linked_booking_id INTEGER,
        business_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (party_id) REFERENCES parties(id),
        FOREIGN KEY (account_id) REFERENCES accounts(id),
        FOREIGN KEY (linked_transaction_id) REFERENCES transactions(id),
        FOREIGN KEY (parent_transaction_id) REFERENCES transactions(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_transactions_date ON transactions(date DESC)');
    await db.execute('CREATE INDEX idx_transactions_party ON transactions(party_name)');
    await db.execute('CREATE INDEX idx_transactions_mode_type ON transactions(mode, type, date DESC)');
    await db.execute('CREATE INDEX idx_transactions_category ON transactions(category, date DESC)');
    await db.execute('CREATE INDEX idx_transactions_account ON transactions(account_id)');
    await db.execute('CREATE INDEX idx_transactions_to_account ON transactions(to_account_id)');
    await db.execute('CREATE INDEX idx_transactions_auto_detected ON transactions(auto_detected, verified)');
    await db.execute('CREATE INDEX idx_transactions_deleted ON transactions(deleted_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_reminder ON transactions(reminder_sent_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_linked ON transactions(linked_transaction_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_invoice ON transactions(linked_invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_booking ON transactions(linked_booking_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_business ON transactions(business_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_context ON transactions(context_id)');
  }

  // ── 2. Credits & Loans ────────────────────────────────────────────────────

  Future<void> _createCreditAndLoanTables(Database db) async {
    await db.execute('''
      CREATE TABLE credits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        customer_id INTEGER,
        phone_number TEXT,
        total_amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0,
        pending_amount REAL NOT NULL,
        direction TEXT NOT NULL DEFAULT 'given',
        credit_date TEXT NOT NULL,
        due_date TEXT,
        cleared_date TEXT,
        is_cleared INTEGER DEFAULT 0,
        is_overdue INTEGER DEFAULT 0,
        interest_rate REAL,
        interest_type TEXT,
        notes TEXT,
        tags TEXT,
        business_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES parties(id),
        FOREIGN KEY (business_id) REFERENCES businesses(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_credits_customer ON credits(customer_name)');
    await db.execute('CREATE INDEX idx_credits_status ON credits(is_cleared, is_overdue)');
    await db.execute('CREATE INDEX idx_credits_due_date ON credits(due_date)');
    await db.execute('CREATE INDEX idx_credits_pending ON credits(pending_amount DESC)');
    await db.execute('CREATE INDEX idx_credits_direction ON credits(direction)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credits_context ON credits(context_id)');

    await db.execute('''
      CREATE TABLE credit_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        credit_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        payment_method TEXT,
        transaction_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (credit_id) REFERENCES credits(id) ON DELETE CASCADE,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_credit_payments_credit ON credit_payments(credit_id)');
    await db.execute('CREATE INDEX idx_credit_payments_date ON credit_payments(payment_date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_payments_context ON credit_payments(context_id)');

    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        direction TEXT NOT NULL DEFAULT 'borrowed',
        lender_name TEXT NOT NULL,
        lender_id INTEGER,
        phone_number TEXT,
        principal_amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0,
        pending_amount REAL NOT NULL,
        loan_date TEXT NOT NULL,
        due_date TEXT,
        cleared_date TEXT,
        is_cleared INTEGER DEFAULT 0,
        is_overdue INTEGER DEFAULT 0,
        emi_amount REAL,
        total_emis INTEGER,
        paid_emis INTEGER DEFAULT 0,
        emi_day INTEGER,
        next_emi_date TEXT,
        interest_rate REAL,
        interest_type TEXT,
        total_interest REAL,
        repayment_frequency TEXT,
        notes TEXT,
        tags TEXT,
        business_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (lender_id) REFERENCES parties(id),
        FOREIGN KEY (business_id) REFERENCES businesses(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_loans_lender ON loans(lender_name)');
    await db.execute('CREATE INDEX idx_loans_status ON loans(is_cleared, is_overdue)');
    await db.execute('CREATE INDEX idx_loans_next_emi ON loans(next_emi_date)');
    await db.execute('CREATE INDEX idx_loans_direction ON loans(direction)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_context ON loans(context_id)');

    await db.execute('''
      CREATE TABLE loan_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0,
        is_paid INTEGER DEFAULT 0,
        paid_date TEXT,
        notes TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_loan_payments_loan ON loan_payments(loan_id)');
    await db.execute('CREATE INDEX idx_loan_payments_due ON loan_payments(due_date)');
    await db.execute('CREATE INDEX idx_loan_payments_status ON loan_payments(is_paid, due_date)');
  }

  // ── 3. Parties, Accounts, Categories & Budgets ───────────────────────────

  Future<void> _createPartyAndAccountTables(Database db) async {
    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone_number TEXT,
        email TEXT,
        party_type TEXT NOT NULL DEFAULT 'personal',
        party_context TEXT NOT NULL DEFAULT 'personal',
        total_transactions INTEGER DEFAULT 0,
        total_transaction_amount REAL DEFAULT 0,
        total_credit_given REAL DEFAULT 0,
        total_credit_received REAL DEFAULT 0,
        notes TEXT,
        tags TEXT,
        gstin TEXT,
        address TEXT,
        city TEXT,
        state TEXT,
        pincode TEXT,
        business_card_image_path TEXT,
        website TEXT,
        whatsapp TEXT,
        linkedin TEXT,
        instagram TEXT,
        country TEXT,
        dial_code TEXT,
        staff_role TEXT,
        staff_salary REAL,
        staff_salary_type TEXT DEFAULT 'monthly',
        staff_join_date TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_parties_name ON parties(name)');
    await db.execute('CREATE INDEX idx_parties_phone ON parties(phone_number)');
    await db.execute('CREATE INDEX idx_parties_type ON parties(party_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_parties_context ON parties(context_id)');

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_type TEXT NOT NULL,
        account_name TEXT NOT NULL,
        bank_name TEXT,
        account_number_last4 TEXT,
        current_balance REAL,
        opening_balance REAL,
        credit_limit REAL,
        linked_bank_account_id INTEGER REFERENCES accounts(id),
        is_active INTEGER DEFAULT 1,
        is_primary INTEGER DEFAULT 0,
        sms_senders TEXT,
        notes TEXT,
        color TEXT,
        icon TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_accounts_type ON accounts(account_type)');
    await db.execute('CREATE INDEX idx_accounts_active ON accounts(is_active)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_accounts_context ON accounts(context_id)');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        parent_category TEXT,
        category_type TEXT NOT NULL,
        mode TEXT DEFAULT 'both',
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0,
        is_system INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        keywords TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_categories_context ON categories(context_id)');

    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        category TEXT NOT NULL,
        budget_amount REAL NOT NULL,
        alert_at_percentage REAL NOT NULL DEFAULT 80,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        UNIQUE(year, month, category)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_budgets_context ON budgets(context_id)');
  }

  // ── 4. Scheduling (recurring, settings, bills, scheduled_payments) ────────

  Future<void> _createSchedulingTables(Database db) async {
    await db.execute('''
      CREATE TABLE recurring_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        party_name TEXT,
        payment_method TEXT,
        frequency TEXT NOT NULL,
        next_date TEXT NOT NULL,
        last_generated TEXT,
        is_active INTEGER DEFAULT 1,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at            TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_device_id TEXT,
        updated_by_device_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL UNIQUE,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL DEFAULT 'image',
        file_size INTEGER,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_bill_attachments_txn ON bill_attachments(transaction_id)');

    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL DEFAULT 'Bills & Utilities',
        frequency TEXT NOT NULL DEFAULT 'monthly',
        due_day INTEGER NOT NULL DEFAULT 1,
        is_auto_pay INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        payment_method TEXT,
        last_paid_date TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_bills_active ON bills(is_active, deleted_at)');
    await db.execute('CREATE INDEX idx_bills_due ON bills(due_day)');

    await db.execute('''
      CREATE TABLE scheduled_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense',
        category TEXT NOT NULL,
        is_one_time INTEGER NOT NULL DEFAULT 0,
        frequency TEXT,
        due_day INTEGER,
        auto_create INTEGER NOT NULL DEFAULT 0,
        is_auto_pay INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        next_date TEXT NOT NULL,
        last_paid_date TEXT,
        last_generated TEXT,
        party_name TEXT,
        payment_method TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        bill_context TEXT NOT NULL DEFAULT 'personal',
        party_id INTEGER REFERENCES parties(id),
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_sp_active ON scheduled_payments(is_active, deleted_at)');
    await db.execute('CREATE INDEX idx_sp_next ON scheduled_payments(next_date)');
    await db.execute('CREATE INDEX idx_sp_auto ON scheduled_payments(auto_create, next_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_party ON scheduled_payments(party_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_context ON scheduled_payments(context_id)');
  }

  // ── 5. Businesses & Item Catalog ──────────────────────────────────────────

  Future<void> _createBusinessAndCatalogTables(Database db) async {
    await db.execute('''
      CREATE TABLE businesses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT,
        city TEXT,
        state TEXT,
        pincode TEXT,
        phone TEXT,
        email TEXT,
        gst_no TEXT,
        logo_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 0,
        owner_name TEXT,
        website TEXT,
        whatsapp TEXT,
        linkedin TEXT,
        instagram TEXT,
        upi_id TEXT,
        country TEXT,
        dial_code TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_businesses_active ON businesses(is_active)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_businesses_context ON businesses(context_id)');

    await db.execute('''
      CREATE TABLE item_catalog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        unit TEXT DEFAULT 'pcs',
        unit_price REAL NOT NULL DEFAULT 0,
        tax_pct REAL NOT NULL DEFAULT 0,
        hsn_code TEXT,
        hsn_or_sac TEXT DEFAULT 'HSN',
        is_active INTEGER NOT NULL DEFAULT 1,
        business_id INTEGER,
        sku TEXT,
        category TEXT DEFAULT 'product',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        usage_count INTEGER NOT NULL DEFAULT 0,
        duration_minutes INTEGER DEFAULT 30,
        is_bookable INTEGER DEFAULT 0,
        track_inventory INTEGER NOT NULL DEFAULT 0,
        stock_qty REAL NOT NULL DEFAULT 0,
        low_stock_threshold REAL NOT NULL DEFAULT 5,
        mrp REAL,
        dealer_price REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_item_catalog_business ON item_catalog(business_id)');
    await db.execute('CREATE INDEX idx_item_catalog_category ON item_catalog(category)');
    await db.execute('CREATE INDEX idx_item_catalog_favorite ON item_catalog(is_favorite)');
    await db.execute('CREATE INDEX idx_item_catalog_last_used ON item_catalog(last_used_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_item_catalog_context ON item_catalog(context_id)');
  }

  // ── 6. Sales (Quotes, Invoices) ───────────────────────────────────────────

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE quotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quote_no TEXT NOT NULL UNIQUE,
        customer_party_id INTEGER,
        customer_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        valid_until TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        discount_pct REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        notes TEXT,
        business_id INTEGER,
        invoice_type TEXT NOT NULL DEFAULT 'tax_invoice',
        place_of_supply TEXT,
        reverse_charge INTEGER NOT NULL DEFAULT 0,
        customer_gstin TEXT,
        freight_amt REAL NOT NULL DEFAULT 0,
        insurance_amt REAL NOT NULL DEFAULT 0,
        packing_amt REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        pending_number_since TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_quotes_status ON quotes(status)');
    await db.execute('CREATE INDEX idx_quotes_business ON quotes(business_id)');

    await db.execute('''
      CREATE TABLE quote_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quote_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        description TEXT,
        qty REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_pct REAL NOT NULL DEFAULT 0,
        discount_pct REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        hsn_code TEXT,
        unit TEXT DEFAULT 'PCS',
        hsn_or_sac TEXT DEFAULT 'HSN',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT NOT NULL UNIQUE,
        quote_id INTEGER,
        customer_party_id INTEGER,
        customer_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        issue_date TEXT NOT NULL,
        due_date TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        discount_pct REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        notes TEXT,
        business_id INTEGER,
        paid_at TEXT,
        payment_method TEXT,
        reminder_sent_at TEXT,
        invoice_type TEXT NOT NULL DEFAULT 'tax_invoice',
        place_of_supply TEXT,
        reverse_charge INTEGER NOT NULL DEFAULT 0,
        customer_gstin TEXT,
        irn TEXT,
        irn_ack_no TEXT,
        irn_ack_date TEXT,
        qr_code_data TEXT,
        ewb_no TEXT,
        ewb_generated_at TEXT,
        ewb_valid_until TEXT,
        vehicle_no TEXT,
        transporter_name TEXT,
        transporter_gstin TEXT,
        transport_mode TEXT DEFAULT '1',
        distance_km INTEGER,
        freight_amt REAL NOT NULL DEFAULT 0,
        insurance_amt REAL NOT NULL DEFAULT 0,
        packing_amt REAL NOT NULL DEFAULT 0,
        challan_id INTEGER REFERENCES delivery_challans(id) ON DELETE SET NULL,
        delivery_address TEXT,
        delivery_city TEXT,
        delivery_state TEXT,
        delivery_pincode TEXT,
        delivery_gstin TEXT,
        original_invoice_id INTEGER,
        original_invoice_no TEXT,
        original_invoice_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        pending_number_since TEXT,
        FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_invoices_status ON invoices(status)');
    await db.execute('CREATE INDEX idx_invoices_due ON invoices(due_date)');
    await db.execute('CREATE INDEX idx_invoices_business ON invoices(business_id)');
    await db.execute('CREATE INDEX idx_invoices_reminder ON invoices(reminder_sent_at, due_date)');
    await db.execute('CREATE INDEX idx_invoices_ewb ON invoices(ewb_no)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_context ON invoices(context_id)');

    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        description TEXT,
        qty REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_pct REAL NOT NULL DEFAULT 0,
        discount_pct REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        hsn_code TEXT,
        unit TEXT DEFAULT 'PCS',
        hsn_or_sac TEXT DEFAULT 'HSN',
        catalog_item_id INTEGER,
        lot_allocation_json TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
      )
    ''');
  }

  // ── 7. Bookings ───────────────────────────────────────────────────────────

  Future<void> _createBookingTables(Database db) async {
    await db.execute('''
      CREATE TABLE bookings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_party_id INTEGER,
        customer_name TEXT NOT NULL,
        service_item_id INTEGER,
        service_name TEXT NOT NULL,
        start_datetime TEXT NOT NULL,
        end_datetime TEXT,
        duration_minutes INTEGER,
        status TEXT NOT NULL DEFAULT 'pending',
        booking_type TEXT NOT NULL DEFAULT 'business',
        total_amount REAL NOT NULL,
        advance_amount REAL DEFAULT 0,
        paid_amount REAL DEFAULT 0,
        invoice_id INTEGER,
        notes TEXT,
        notification_scheduled_at TEXT,
        confirmed_at TEXT,
        business_id INTEGER,
        booking_ref TEXT,
        reminder_sent_at TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (customer_party_id) REFERENCES parties(id),
        FOREIGN KEY (service_item_id) REFERENCES item_catalog(id),
        FOREIGN KEY (invoice_id) REFERENCES invoices(id),
        FOREIGN KEY (business_id) REFERENCES businesses(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_bookings_status ON bookings(status)');
    await db.execute('CREATE INDEX idx_bookings_start_datetime ON bookings(start_datetime)');
    await db.execute('CREATE INDEX idx_bookings_customer ON bookings(customer_party_id)');
    await db.execute('CREATE INDEX idx_bookings_business ON bookings(business_id)');
    await db.execute('CREATE INDEX idx_bookings_type ON bookings(booking_type)');
    await db.execute('CREATE INDEX idx_bookings_reminder ON bookings(reminder_sent_at, start_datetime)');

    await db.execute('''
      CREATE TABLE booking_items (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_id      INTEGER NOT NULL,
        item_name       TEXT NOT NULL,
        description     TEXT,
        qty             REAL NOT NULL DEFAULT 1,
        unit            TEXT DEFAULT 'session',
        unit_price      REAL NOT NULL DEFAULT 0,
        tax_pct         REAL NOT NULL DEFAULT 0,
        discount_pct    REAL NOT NULL DEFAULT 0,
        line_total      REAL NOT NULL DEFAULT 0,
        sac_code        TEXT,
        sort_order      INTEGER DEFAULT 0,
        service_item_id INTEGER,
        created_at      TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at      TEXT,
        FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE,
        FOREIGN KEY (service_item_id) REFERENCES item_catalog(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_booking_items_booking ON booking_items(booking_id)');
  }

  // ── 8. Lookup tables (units, transporters, HSN) ───────────────────────────

  Future<void> _createLookupTables(Database db) async {
    await db.execute('''
      CREATE TABLE unit_types (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        code        TEXT,
        label       TEXT NOT NULL UNIQUE,
        is_system   INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _seedUnitTypes(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transporters (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT NOT NULL,
        gstin        TEXT,
        last_used_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transporters_name ON transporters(name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hsn_master (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        code        TEXT NOT NULL,
        description TEXT NOT NULL,
        type        TEXT NOT NULL DEFAULT 'HSN'
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hsn_master_code ON hsn_master(code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hsn_master_type ON hsn_master(type)');
    await _seedHsnMaster(db);
  }

  // ── 9. GST & Logistics ────────────────────────────────────────────────────

  Future<void> _createGstAndLogisticsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_challans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        challan_no TEXT NOT NULL UNIQUE,
        customer_party_id INTEGER,
        customer_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        challan_date TEXT NOT NULL,
        dispatch_date TEXT,
        expected_return_date TEXT,
        purpose TEXT NOT NULL DEFAULT 'supply',
        subtotal REAL NOT NULL DEFAULT 0,
        notes TEXT,
        business_id INTEGER,
        customer_gstin TEXT,
        place_of_supply TEXT,
        vehicle_no TEXT,
        transporter_name TEXT,
        transport_mode TEXT,
        distance_km INTEGER,
        converted_invoice_id INTEGER,
        ewb_no TEXT,
        delivery_address TEXT,
        delivery_city TEXT,
        delivery_state TEXT,
        delivery_pincode TEXT,
        delivery_gstin TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL,
        updated_at            TEXT NOT NULL,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        pending_number_since TEXT,
        FOREIGN KEY (customer_party_id) REFERENCES parties(id),
        FOREIGN KEY (converted_invoice_id) REFERENCES invoices(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dc_status ON delivery_challans(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dc_date ON delivery_challans(challan_date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dc_customer ON delivery_challans(customer_party_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dc_ewb ON delivery_challans(ewb_no)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_challan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        challan_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        description TEXT,
        qty REAL NOT NULL DEFAULT 1,
        unit TEXT DEFAULT 'PCS',
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        hsn_code TEXT,
        hsn_or_sac TEXT DEFAULT 'HSN',
        catalog_item_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (challan_id) REFERENCES delivery_challans(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dci_challan ON delivery_challan_items(challan_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_templates (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        name                  TEXT NOT NULL,
        based_on              TEXT NOT NULL DEFAULT 'modern',
        accent_color_hex      TEXT NOT NULL DEFAULT '#1B5E20',
        header_style          TEXT NOT NULL DEFAULT 'minimal',
        show_logo             INTEGER NOT NULL DEFAULT 1,
        amount_decimal_digits INTEGER NOT NULL DEFAULT 0,
        page_size             TEXT NOT NULL DEFAULT 'a4',
        is_active             INTEGER NOT NULL DEFAULT 0,
        is_preset             INTEGER NOT NULL DEFAULT 0,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT
      )
    ''');
    await _seedDocumentTemplatePresets(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS party_reminders (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        party_name            TEXT NOT NULL,
        channel               TEXT NOT NULL DEFAULT 'whatsapp',
        message               TEXT NOT NULL,
        invoice_refs          TEXT,
        invoice_count         INTEGER NOT NULL DEFAULT 0,
        total_outstanding     REAL,
        business_id           INTEGER,
        sent_at               TEXT NOT NULL DEFAULT (datetime('now')),
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (business_id) REFERENCES businesses(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_party_reminders_party ON party_reminders(party_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_party_reminders_sent ON party_reminders(sent_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_party_reminders_business ON party_reminders(business_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS party_addresses (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id              INTEGER NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
        label                 TEXT    NOT NULL DEFAULT 'Address',
        address               TEXT,
        city                  TEXT,
        state                 TEXT,
        pincode               TEXT,
        country               TEXT DEFAULT 'India',
        gstin                 TEXT,
        is_default            INTEGER NOT NULL DEFAULT 0,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT    NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_party_addresses_party ON party_addresses(party_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_party_addresses_default ON party_addresses(party_id, is_default)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id INTEGER NOT NULL,
        bill_no TEXT NOT NULL,
        vendor_party_id INTEGER,
        vendor_name TEXT NOT NULL,
        vendor_gstin TEXT,
        bill_date TEXT NOT NULL,
        due_date TEXT,
        place_of_supply TEXT,
        reverse_charge INTEGER NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0,
        igst_amount REAL NOT NULL DEFAULT 0,
        cgst_amount REAL NOT NULL DEFAULT 0,
        sgst_amount REAL NOT NULL DEFAULT 0,
        cess_amount REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        itc_eligibility TEXT NOT NULL DEFAULT 'eligible',
        itc_block_reason TEXT,
        itc_availed INTEGER NOT NULL DEFAULT 0,
        itc_reversal_reason TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'unpaid',
        attachment_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_id              TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version              INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        context_id           INTEGER REFERENCES linked_business_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (vendor_party_id) REFERENCES parties(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_business ON purchase_bills(business_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_bill_date ON purchase_bills(bill_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_status ON purchase_bills(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_rc ON purchase_bills(reverse_charge)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_context ON purchase_bills(context_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_bill_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        description TEXT,
        qty REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        tax_pct REAL NOT NULL DEFAULT 0,
        discount_pct REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        igst_amount REAL NOT NULL DEFAULT 0,
        cgst_amount REAL NOT NULL DEFAULT 0,
        sgst_amount REAL NOT NULL DEFAULT 0,
        hsn_code TEXT,
        unit TEXT DEFAULT 'PCS',
        hsn_or_sac TEXT DEFAULT 'HSN',
        catalog_item_id INTEGER,
        lot_no TEXT,
        expiry_date TEXT,
        mfg_date TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        FOREIGN KEY (bill_id) REFERENCES purchase_bills(id) ON DELETE CASCADE
      )
    ''');

    // Atomic cursor table for conflict-free invoice/quote/DC numbering
    // across linked devices (added to fresh-install schema at v67).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_number_cursors (
        doc_type   TEXT PRIMARY KEY,
        prefix     TEXT NOT NULL,
        last_seq   INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // ── 10. Inventory & HR ────────────────────────────────────────────────────

  Future<void> _createInventoryAndHrTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        business_id INTEGER REFERENCES businesses(id),
        movement_type TEXT NOT NULL,
        qty REAL NOT NULL,
        stock_after REAL NOT NULL,
        reference_id INTEGER,
        reference_type TEXT,
        notes TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (item_id) REFERENCES item_catalog(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sm_item ON stock_movements(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sm_date ON stock_movements(created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sm_business ON stock_movements(business_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_stock (
        business_id         INTEGER NOT NULL REFERENCES businesses(id),
        item_id             INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE,
        stock_qty           REAL    NOT NULL DEFAULT 0,
        low_stock_threshold REAL    NOT NULL DEFAULT 5,
        track_inventory     INTEGER NOT NULL DEFAULT 0,
        last_counted_qty    REAL,
        last_counted_at     TEXT,
        created_at          TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at          TEXT,
        PRIMARY KEY (business_id, item_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_item_stock_item ON item_stock(item_id)');

    // ── Lot tracking (Phase B) ──────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_lots (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id           INTEGER NOT NULL REFERENCES businesses(id),
        item_id               INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE,
        purchase_bill_id      INTEGER REFERENCES purchase_bills(id) ON DELETE SET NULL,
        lot_no                TEXT,
        expiry_date           TEXT,
        mfg_date              TEXT,
        unit_cost             REAL NOT NULL DEFAULT 0,
        qty_in                REAL NOT NULL DEFAULT 0,
        qty_remaining         REAL NOT NULL DEFAULT 0,
        status                TEXT NOT NULL DEFAULT 'active',
        notes                 TEXT,
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_lots_item_biz ON stock_lots(business_id, item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_lots_fefo ON stock_lots(business_id, item_id, expiry_date, created_at, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_lots_bill ON stock_lots(purchase_bill_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_lots_remaining ON stock_lots(business_id, item_id, qty_remaining)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lot_movements (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        business_id       INTEGER NOT NULL REFERENCES businesses(id),
        item_id           INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE,
        lot_id            INTEGER NOT NULL REFERENCES stock_lots(id) ON DELETE CASCADE,
        movement_type     TEXT NOT NULL,
        qty               REAL NOT NULL,
        lot_qty_after     REAL NOT NULL,
        reference_type    TEXT,
        reference_id      INTEGER,
        reference_line_id INTEGER,
        notes             TEXT,
        created_at        TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lot_mov_lot ON lot_movements(lot_id, created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lot_mov_ref ON lot_movements(reference_type, reference_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lot_mov_item_biz ON lot_movements(business_id, item_id, created_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        designation TEXT,
        phone TEXT,
        email TEXT,
        department TEXT,
        salary_type TEXT NOT NULL DEFAULT 'monthly',
        base_salary REAL NOT NULL DEFAULT 0,
        join_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        bank_name TEXT,
        account_no TEXT,
        ifsc_code TEXT,
        pan TEXT,
        pf_no TEXT,
        esi_no TEXT,
        notes TEXT,
        business_id INTEGER,
        party_id INTEGER REFERENCES parties(id),
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (business_id) REFERENCES businesses(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_staff_active ON staff(is_active)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_staff_business ON staff(business_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_staff_party ON staff(party_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER NOT NULL,
        pay_period_month INTEGER NOT NULL,
        pay_period_year INTEGER NOT NULL,
        base_salary REAL NOT NULL DEFAULT 0,
        allowances REAL NOT NULL DEFAULT 0,
        deductions REAL NOT NULL DEFAULT 0,
        bonus REAL NOT NULL DEFAULT 0,
        net_salary REAL NOT NULL DEFAULT 0,
        payment_method TEXT DEFAULT 'bank_transfer',
        paid_date TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        notes TEXT,
        sync_id               TEXT UNIQUE DEFAULT (lower(hex(randomblob(16)))),
        created_at            TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at            TEXT,
        deleted_at            TEXT,
        version               INTEGER NOT NULL DEFAULT 0,
        created_by_device_id  TEXT,
        updated_by_device_id  TEXT,
        FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_salp_staff ON salary_payments(staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_salp_period ON salary_payments(pay_period_year, pay_period_month)');
  }

  // ── 11. Sync & Identity ───────────────────────────────────────────────────

  Future<void> _createSyncAndIdentityTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_users (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id         TEXT    UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))),
        display_name    TEXT    NOT NULL,
        pin_hash        TEXT,
        role            TEXT    NOT NULL DEFAULT 'custom',
        linked_party_id INTEGER,
        is_active       INTEGER NOT NULL DEFAULT 1,
        default_device_id TEXT,
        last_login_at   TEXT,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        updated_at      TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (linked_party_id) REFERENCES parties(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_users_active ON app_users(is_active)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_users_party ON app_users(linked_party_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_permissions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL,
        business_id INTEGER NOT NULL DEFAULT -1,
        module      TEXT    NOT NULL,
        can_view    INTEGER NOT NULL DEFAULT 1,
        can_create  INTEGER NOT NULL DEFAULT 0,
        can_edit    INTEGER NOT NULL DEFAULT 0,
        can_delete  INTEGER NOT NULL DEFAULT 0,
        UNIQUE (user_id, business_id, module),
        FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_user_perms_user ON user_permissions(user_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subscription (
        id              INTEGER PRIMARY KEY DEFAULT 1,
        plan            TEXT NOT NULL DEFAULT 'free',
        source          TEXT DEFAULT 'none',
        purchase_token  TEXT,
        plan_started_at TEXT,
        plan_expires_at TEXT,
        is_trial        INTEGER NOT NULL DEFAULT 0,
        trial_ends_at   TEXT,
        shareable_plan_features TEXT
      )
    ''');
    await db.execute("INSERT OR IGNORE INTO subscription (id, plan) VALUES (1, 'free')");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS plan_features (
        plan         TEXT NOT NULL,
        feature      TEXT NOT NULL,
        enabled      INTEGER NOT NULL DEFAULT 1,
        limit_value  INTEGER,
        PRIMARY KEY (plan, feature)
      )
    ''');
    await _seedPlanFeatures(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS linked_devices (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id              TEXT    UNIQUE NOT NULL DEFAULT (lower(hex(randomblob(16)))),
        device_id            TEXT    NOT NULL UNIQUE,
        device_name          TEXT    NOT NULL,
        device_type          TEXT,
        device_os            TEXT,
        secondary_public_key TEXT    NOT NULL DEFAULT '',
        user_id              INTEGER,
        linked_party_id      INTEGER,
        permission_scope     TEXT    NOT NULL DEFAULT '{}',
        business_scope       TEXT    NOT NULL DEFAULT '[]',
        offline_grace_days   INTEGER NOT NULL DEFAULT 7,
        permission_preset    TEXT    NOT NULL DEFAULT 'owner_mirror',
        last_sync_at         TEXT,
        revoked_at           TEXT,
        secondary_identity_id  TEXT,
        secondary_display_name TEXT,
        created_at           TEXT    NOT NULL DEFAULT (datetime('now')),
        updated_at           TEXT    NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (user_id)         REFERENCES app_users(id) ON DELETE SET NULL,
        FOREIGN KEY (linked_party_id) REFERENCES parties(id)   ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_linked_devices_revoked ON linked_devices(revoked_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_linked_devices_party ON linked_devices(linked_party_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_recovery (
        id               INTEGER PRIMARY KEY,
        recovery_key_hash TEXT NOT NULL,
        kdf_salt         TEXT NOT NULL,
        created_at       TEXT NOT NULL DEFAULT (datetime('now')),
        last_rotated_at  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pairing_history (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id         TEXT NOT NULL,
        device_name       TEXT NOT NULL,
        permission_preset TEXT NOT NULL DEFAULT 'custom',
        paired_at         TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pairing_history_time ON pairing_history(paired_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        target_device_id   TEXT,
        target_identity_id TEXT,
        event_type         TEXT NOT NULL,
        payload            TEXT,
        created_at         TEXT NOT NULL DEFAULT (datetime('now')),
        delivered_at       TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(delivered_at) WHERE delivered_at IS NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_target ON sync_outbox(target_device_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_session (
        id              INTEGER PRIMARY KEY DEFAULT 1,
        active_user_id  INTEGER REFERENCES app_users(id),
        active_business_id INTEGER,
        locked          INTEGER NOT NULL DEFAULT 0,
        last_activity_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute("INSERT OR IGNORE INTO device_session (id, locked) VALUES (1, 0)");

    // ── UPDATE triggers (auto-stamp updated_at) ───────────────────────────
    const p0Tables = [
      'transactions', 'credits', 'credit_payments', 'loans', 'parties',
      'accounts', 'categories', 'budgets', 'item_catalog', 'scheduled_payments',
      'businesses', 'invoices', 'purchase_bills',
    ];
    for (final tbl in p0Tables) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${tbl}_sync_updated
        AFTER UPDATE ON $tbl
        FOR EACH ROW
        WHEN NEW.updated_at = OLD.updated_at OR OLD.updated_at IS NULL
        BEGIN
          UPDATE $tbl SET updated_at = datetime('now') WHERE id = NEW.id;
        END
      ''');
    }

    // ── Unique sync_id indexes ─────────────────────────────────────────────
    for (final tbl in p0Tables) {
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tbl}_sync_id ON $tbl(sync_id)');
    }

    // ── v62: my_identity & linked_business_sessions ───────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS my_identity (
        id           INTEGER PRIMARY KEY,
        identity_id  TEXT    NOT NULL UNIQUE,
        display_name TEXT    NOT NULL,
        avatar_seed  TEXT,
        public_key   TEXT    NOT NULL,
        created_at   TEXT    DEFAULT (datetime('now')),
        updated_at   TEXT    DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS linked_business_sessions (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id           TEXT    NOT NULL UNIQUE,
        primary_identity_id  TEXT    NOT NULL,
        primary_public_key   TEXT    NOT NULL,
        primary_device_name  TEXT,
        business_name        TEXT    NOT NULL DEFAULT 'Linked Business',
        business_ids         TEXT    NOT NULL DEFAULT '[]',
        token_payload        TEXT    NOT NULL,
        token_signature      TEXT    NOT NULL,
        permission_scope     TEXT    NOT NULL DEFAULT '{}',
        offline_grace_days   INTEGER NOT NULL DEFAULT 7,
        issued_at            TEXT    NOT NULL,
        last_sync_at         TEXT,
        is_read_only_forced  INTEGER DEFAULT 0,
        display_order        INTEGER DEFAULT 0,
        unlinked_at          TEXT,
        created_at           TEXT    DEFAULT (datetime('now'))
      )
    ''');

    // ── v65: payroll_notifications ─────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payroll_notifications (
        id                     INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id        TEXT    NOT NULL UNIQUE,
        source_identity_id     TEXT    NOT NULL,
        business_name          TEXT    NOT NULL,
        amount                 REAL    NOT NULL,
        currency               TEXT    NOT NULL DEFAULT 'INR',
        reference_label        TEXT,
        paid_on                TEXT    NOT NULL,
        received_at            TEXT    DEFAULT (datetime('now')),
        status                 TEXT    NOT NULL DEFAULT 'pending',
        created_transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL
      )
    ''');

    // ── v69: P2P LAN sync tables ───────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trusted_peers (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_identity_id  TEXT NOT NULL UNIQUE,
        peer_name         TEXT,
        business_id       TEXT,
        shared_secret_enc TEXT NOT NULL,
        paired_at         TEXT NOT NULL,
        last_seen_at      TEXT,
        last_synced_at    TEXT,
        is_active         INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_trusted_peers_active ON trusted_peers(is_active)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_watermarks (
        peer_identity_id  TEXT NOT NULL,
        table_name        TEXT NOT NULL,
        last_synced_at    TEXT NOT NULL,
        last_sync_cursor  TEXT,
        PRIMARY KEY (peer_identity_id, table_name)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_table_state (
        peer_identity_id   TEXT NOT NULL,
        table_name         TEXT NOT NULL,
        sync_mode          TEXT NOT NULL,
        last_synced_at     TEXT,
        last_version       INTEGER,
        last_pk            TEXT,
        schema_fingerprint TEXT NOT NULL,
        updated_at         TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (peer_identity_id, table_name)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_table_state_table ON sync_table_state(table_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_table_state_updated ON sync_table_state(updated_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id  TEXT NOT NULL,
        event_type  TEXT NOT NULL,
        event_data  TEXT,
        occurred_at TEXT NOT NULL,
        device_id   TEXT NOT NULL,
        sync_id     TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_events_invoice ON invoice_events(invoice_id, occurred_at)',
    );
  }

  // ── Activity Log ──────────────────────────────────────────────────────────

  Future<void> _createActivityLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT    NOT NULL,
        entity_id   INTEGER NOT NULL,
        type        TEXT    NOT NULL DEFAULT 'note',
        message     TEXT    NOT NULL,
        meta        TEXT,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_log_entity ON activity_log(entity_type, entity_id, created_at DESC)',
    );
  }

  Future<void> _createAppLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_logs (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp    TEXT    NOT NULL DEFAULT (datetime('now')),
        level        TEXT    NOT NULL,
        source       TEXT    NOT NULL DEFAULT 'app',
        category     TEXT,
        event_name   TEXT,
        session_id   TEXT,
        message      TEXT    NOT NULL,
        error        TEXT,
        stack_trace  TEXT,
        context_json TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_app_logs_time ON app_logs(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_app_logs_level ON app_logs(level, timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_app_logs_session_time ON app_logs(session_id, timestamp DESC)',
    );
  }
}
