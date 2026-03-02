import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';

/// Singleton helper for SQLite database initialization and access.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  /// Returns the database instance, creating it if needed.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);

    final db = await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );

    // Enable WAL mode. Must use rawQuery (not execute) because
    // PRAGMA journal_mode returns a result set — sqflite on Android
    // rejects execute() for any statement that produces output rows.
    await db.rawQuery('PRAGMA journal_mode=WAL');

    await _runIntegrityCheck(db);
    // Rolling daily snapshot — only if integrity passed.
    if (!_integrityFailed) {
      await _maybeSnapshot(db, path);
    }
    // Periodic VACUUM — runs at most once every 30 days (background op).
    await _maybeVacuum(db);
    return db;
  }

  // ── Integrity & Snapshot ──────────────────────────────────────────────────

  bool _integrityFailed = false;

  /// True if the most recent startup integrity check detected corruption.
  /// The UI can read this to offer a restore flow.
  bool get integrityFailed => _integrityFailed;

  Future<void> _runIntegrityCheck(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA integrity_check');
      final ok = result.isNotEmpty && result.first.values.first == 'ok';
      _integrityFailed = !ok;
      if (!ok) {
        debugPrint('[DB] ⚠️ Integrity check FAILED — restore from snapshot recommended');
      } else {
        debugPrint('[DB] Integrity check passed');
      }
    } catch (e) {
      debugPrint('[DB] Integrity check error: $e');
      _integrityFailed = true;
    }
  }

  /// Copies the database to a `_prev.db` file once per calendar day,
  /// after a passed integrity check. Used as a last-resort recovery snapshot.
  Future<void> _maybeSnapshot(Database db, String dbPath) async {
    try {
      final stem = dbPath.substring(0, dbPath.lastIndexOf('.'));
      final prevPath = '${stem}_prev.db';
      final prevFile = File(prevPath);
      final today = DateTime.now();

      if (await prevFile.exists()) {
        final lastMod = await prevFile.lastModified();
        if (lastMod.year == today.year &&
            lastMod.month == today.month &&
            lastMod.day == today.day) {
          return; // Already snapshotted today.
        }
      }

      // Flush WAL pages into the main DB file before copying.
      await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');

      final sourceFile = File(dbPath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(prevPath);
        debugPrint('[DB] Daily snapshot saved → $prevPath');
      }
    } catch (e) {
      debugPrint('[DB] Snapshot skipped (non-critical): $e');
    }
  }

  // ── Periodic VACUUM ───────────────────────────────────────────────────────

  static const _prefKeyLastVacuum = 'db_last_vacuum_date';
  static const _vacuumIntervalDays = 30;

  /// Runs `PRAGMA VACUUM` at most once every [_vacuumIntervalDays] days.
  ///
  /// VACUUM reclaims free pages left by deleted rows, keeping the DB compact.
  /// It runs synchronously here but is fast enough on a typical KashCube DB
  /// (< 10 MB); if it becomes a concern, move to a background Isolate.
  Future<void> _maybeVacuum(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastStr = prefs.getString(_prefKeyLastVacuum);
      final now = DateTime.now();

      if (lastStr != null) {
        final last = DateTime.tryParse(lastStr);
        if (last != null && now.difference(last).inDays < _vacuumIntervalDays) {
          return; // Too soon — skip.
        }
      }

      final sw = Stopwatch()..start();
      await db.rawQuery('VACUUM');
      sw.stop();
      debugPrint('[DB] VACUUM completed in ${sw.elapsedMilliseconds} ms');

      await prefs.setString(_prefKeyLastVacuum, now.toIso8601String());
    } catch (e) {
      debugPrint('[DB] VACUUM skipped (non-critical): $e');
    }
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign key constraints.  Note: journal_mode=WAL is set after
    // openDatabase() returns because sqflite on Android disallows execute()
    // in the onConfigure callback (only rawQuery/query are permitted there).
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('Creating database v$version...');

    // -- transactions table
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

    // -- credits table
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
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES parties(id)
      )
    ''');

    await db.execute('CREATE INDEX idx_credits_customer ON credits(customer_name)');
    await db.execute('CREATE INDEX idx_credits_status ON credits(is_cleared, is_overdue)');
    await db.execute('CREATE INDEX idx_credits_due_date ON credits(due_date)');
    await db.execute('CREATE INDEX idx_credits_pending ON credits(pending_amount DESC)');
    await db.execute('CREATE INDEX idx_credits_direction ON credits(direction)');

    // -- credit_payments table
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
        FOREIGN KEY (credit_id) REFERENCES credits(id) ON DELETE CASCADE,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id)
      )
    ''');

    await db.execute('CREATE INDEX idx_credit_payments_credit ON credit_payments(credit_id)');
    await db.execute('CREATE INDEX idx_credit_payments_date ON credit_payments(payment_date DESC)');

    // -- loans table (also stores credits / udhar)
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
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY (lender_id) REFERENCES parties(id)
      )
    ''');

    await db.execute('CREATE INDEX idx_loans_lender ON loans(lender_name)');
    await db.execute('CREATE INDEX idx_loans_status ON loans(is_cleared, is_overdue)');
    await db.execute('CREATE INDEX idx_loans_next_emi ON loans(next_emi_date)');
    await db.execute('CREATE INDEX idx_loans_direction ON loans(direction)');

    // -- loan_payments table
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
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_loan_payments_loan ON loan_payments(loan_id)');
    await db.execute('CREATE INDEX idx_loan_payments_due ON loan_payments(due_date)');
    await db.execute('CREATE INDEX idx_loan_payments_status ON loan_payments(is_paid, due_date)');

    // -- parties table
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
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_parties_name ON parties(name)');
    await db.execute('CREATE INDEX idx_parties_phone ON parties(phone_number)');
    await db.execute('CREATE INDEX idx_parties_type ON parties(party_type)');

    // -- accounts table
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_type TEXT NOT NULL,
        account_name TEXT NOT NULL,
        bank_name TEXT,
        account_number_last4 TEXT,
        current_balance REAL,
        is_active INTEGER DEFAULT 1,
        is_primary INTEGER DEFAULT 0,
        sms_senders TEXT,
        notes TEXT,
        color TEXT,
        icon TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_accounts_type ON accounts(account_type)');
    await db.execute('CREATE INDEX idx_accounts_active ON accounts(is_active)');

    // -- categories table
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
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // -- budgets table
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        category TEXT NOT NULL,
        budget_amount REAL NOT NULL,
        alert_at_percentage REAL NOT NULL DEFAULT 80,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(year, month, category)
      )
    ''');

    // -- recurring_transactions table
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
        updated_at TEXT
      )
    ''');

    // -- settings table
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // -- bill_attachments table
    await db.execute('''
      CREATE TABLE bill_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL UNIQUE,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL DEFAULT 'image',
        file_size INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_bill_attachments_txn ON bill_attachments(transaction_id)');

    // -- bills table (scheduled / recurring bill payments)
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
        deleted_at TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_bills_active ON bills(is_active, deleted_at)');
    await db.execute('CREATE INDEX idx_bills_due ON bills(due_day)');

    // -- scheduled_payments table (unified bills + recurring replacement)
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
        bill_context TEXT NOT NULL DEFAULT 'personal'
      )
    ''');

    await db.execute('CREATE INDEX idx_sp_active ON scheduled_payments(is_active, deleted_at)');
    await db.execute('CREATE INDEX idx_sp_next ON scheduled_payments(next_date)');
    await db.execute('CREATE INDEX idx_sp_auto ON scheduled_payments(auto_create, next_date)');

    // -- businesses table (multiple business profiles, v14)
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
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX idx_businesses_active ON businesses(is_active)');

    // -- item_catalog table (v13 + v15 + v19 columns)
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_item_catalog_business ON item_catalog(business_id)');
    await db.execute('CREATE INDEX idx_item_catalog_category ON item_catalog(category)');
    await db.execute('CREATE INDEX idx_item_catalog_favorite ON item_catalog(is_favorite)');
    await db.execute('CREATE INDEX idx_item_catalog_last_used ON item_catalog(last_used_at)');

    // -- quotes table (v13 + v16)
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_quotes_status ON quotes(status)');
    await db.execute('CREATE INDEX idx_quotes_business ON quotes(business_id)');

    // -- quote_items table (v13)
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
        FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE
      )
    ''');

    // -- invoices table (v13 + v16 + v18 + v21)
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_invoices_status ON invoices(status)');
    await db.execute('CREATE INDEX idx_invoices_due ON invoices(due_date)');
    await db.execute('CREATE INDEX idx_invoices_business ON invoices(business_id)');
    await db.execute('CREATE INDEX idx_invoices_reminder ON invoices(reminder_sent_at, due_date)');

    // -- invoice_items table (v13)
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
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
      )
    ''');

    // -- bookings table (v19 + v20 booking_type + v21 reminder_sent_at)
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
        invoice_id INTEGER,
        notes TEXT,
        notification_scheduled_at TEXT,
        confirmed_at TEXT,
        business_id INTEGER,
        booking_ref TEXT,
        reminder_sent_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
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

    // -- schema_version table
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL DEFAULT (datetime('now')),
        description TEXT
      )
    ''');

    await db.insert('schema_version', {
      'version': 24,
      'description': 'Full v22 schema (fresh install)',
    });

    // -- unit_types table
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

    // Seed default categories + default accounts
    await _seedCategories(db);
    await _seedAccounts(db);
    await _seedFySettings(db);

    debugPrint('Database created successfully.');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from v$oldVersion to v$newVersion...');

    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bill_attachments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_id INTEGER NOT NULL UNIQUE,
          file_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          file_type TEXT NOT NULL DEFAULT 'image',
          file_size INTEGER,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_bill_attachments_txn ON bill_attachments(transaction_id)');

      await db.insert('schema_version', {
        'version': 2,
        'description': 'Add bill_attachments table',
      });
    }

    if (oldVersion < 3) {
      // Add direction column to credits
      await db.execute("ALTER TABLE credits ADD COLUMN direction TEXT NOT NULL DEFAULT 'given'");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_credits_direction ON credits(direction)');

      // Create credit_payments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS credit_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          credit_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          payment_date TEXT NOT NULL,
          payment_method TEXT,
          transaction_id INTEGER,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (credit_id) REFERENCES credits(id) ON DELETE CASCADE,
          FOREIGN KEY (transaction_id) REFERENCES transactions(id)
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_payments_credit ON credit_payments(credit_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_payments_date ON credit_payments(payment_date DESC)');

      await db.insert('schema_version', {
        'version': 3,
        'description': 'Add credit_payments table and direction column',
      });
    }

    if (oldVersion < 4) {
      // Add repayment_frequency column to loans
      await db.execute(
          "ALTER TABLE loans ADD COLUMN repayment_frequency TEXT");

      // Create loan_payments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS loan_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          loan_id INTEGER NOT NULL,
          installment_number INTEGER NOT NULL,
          due_date TEXT NOT NULL,
          amount REAL NOT NULL,
          paid_amount REAL DEFAULT 0,
          is_paid INTEGER DEFAULT 0,
          paid_date TEXT,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loan_payments_loan ON loan_payments(loan_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loan_payments_due ON loan_payments(due_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loan_payments_status ON loan_payments(is_paid, due_date)');

      await db.insert('schema_version', {
        'version': 4,
        'description': 'Add loan_payments table and repayment_frequency',
      });
    }

    if (oldVersion < 5) {
      // Add bills table for scheduled/recurring bill payments
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bills (
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
          deleted_at TEXT
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bills_active ON bills(is_active, deleted_at)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bills_due ON bills(due_day)');

      await db.insert('schema_version', {
        'version': 5,
        'description': 'Add bills table for scheduled payments',
      });
    }

    if (oldVersion < 6) {
      // Add direction column to loans table
      await db.execute(
          "ALTER TABLE loans ADD COLUMN direction TEXT NOT NULL DEFAULT 'borrowed'");
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_direction ON loans(direction)');

      // Migrate credits into loans table
      await db.execute('''
        INSERT INTO loans (
          lender_name, lender_id, phone_number,
          principal_amount, paid_amount, pending_amount,
          direction, loan_date, due_date, cleared_date,
          is_cleared, is_overdue,
          interest_rate, interest_type,
          notes, tags, created_at, updated_at, deleted_at
        )
        SELECT
          customer_name, customer_id, phone_number,
          total_amount, paid_amount, pending_amount,
          CASE WHEN direction = 'given' THEN 'lent' ELSE 'borrowed' END,
          credit_date, due_date, cleared_date,
          is_cleared, is_overdue,
          interest_rate, interest_type,
          notes, tags, created_at, updated_at, deleted_at
        FROM credits
      ''');

      await db.insert('schema_version', {
        'version': 6,
        'description': 'Merge credits into loans (Ledger)',
      });
    }
    if (oldVersion < 7) {
      // Add new unified transaction columns
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN linked_transaction_id INTEGER');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN due_date TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN interest_rate REAL');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN interest_type TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN repayment_frequency TEXT');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN total_installments INTEGER');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN emi_amount REAL');

      // Create index for settlement linking
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_linked ON transactions(linked_transaction_id)');

      // Migrate old type values in transactions table
      await db.execute(
          "UPDATE transactions SET type = 'lent' WHERE type = 'credit_given'");
      await db.execute(
          "UPDATE transactions SET type = 'borrowed' WHERE type = 'credit_received'");
      await db.execute(
          "UPDATE transactions SET type = 'borrowed' WHERE type = 'loan_taken'");
      await db.execute(
          "UPDATE transactions SET type = 'paid_back' WHERE type = 'loan_repayment'");

      // Migrate active loans into transactions table (lent/borrowed)
      await db.execute('''
        INSERT INTO transactions (
          amount, date, type, mode, category,
          party_name, due_date, interest_rate, interest_type,
          repayment_frequency, total_installments, emi_amount,
          notes, created_at, updated_at
        )
        SELECT
          principal_amount,
          loan_date,
          CASE WHEN direction = 'lent' THEN 'lent' ELSE 'borrowed' END,
          'personal',
          CASE WHEN direction = 'lent' THEN 'Lent' ELSE 'Borrowed' END,
          lender_name,
          due_date,
          interest_rate,
          interest_type,
          repayment_frequency,
          total_emis,
          emi_amount,
          notes,
          created_at,
          updated_at
        FROM loans
        WHERE deleted_at IS NULL AND is_cleared = 0
      ''');

      await db.insert('schema_version', {
        'version': 7,
        'description': 'Unified transaction model: new types + lending fields',
      });
    }
    if (oldVersion < 8) {
      // Add to_account_id for Transfer type
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN to_account_id INTEGER');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_to_account ON transactions(to_account_id)');

      // Pre-seed default accounts if none exist
      final existing = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM accounts WHERE deleted_at IS NULL');
      final count = (existing.first['cnt'] as int? ?? 0);
      if (count == 0) {
        await _seedAccounts(db);
      }

      await db.insert('schema_version', {
        'version': 8,
        'description': 'Add to_account_id + pre-seed accounts + Transfer type',
      });
    }

    if (oldVersion < 9) {
      // Create the unified scheduled_payments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS scheduled_payments (
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
          deleted_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_active ON scheduled_payments(is_active, deleted_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_next ON scheduled_payments(next_date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_auto ON scheduled_payments(auto_create, next_date)');

      // Migrate legacy bills → scheduled_payments (reminder mode, no auto-create)
      await db.execute('''
        INSERT INTO scheduled_payments
          (name, amount, type, category, is_one_time, frequency, due_day,
           auto_create, is_auto_pay, is_active, next_date,
           last_paid_date, payment_method, notes, created_at, updated_at, deleted_at)
        SELECT
          name, amount, 'expense', category, 0, frequency, due_day,
          0, is_auto_pay, is_active,
          datetime('now', '+7 days'),
          last_paid_date, payment_method, notes, created_at, updated_at, deleted_at
        FROM bills
        WHERE deleted_at IS NULL
      ''');

      // Migrate recurring_transactions → scheduled_payments (auto-create mode)
      await db.execute('''
        INSERT INTO scheduled_payments
          (name, amount, type, category, is_one_time, frequency, due_day,
           auto_create, is_auto_pay, is_active, next_date,
           last_paid_date, last_generated, party_name, payment_method, notes,
           created_at, updated_at)
        SELECT
          category, amount, type, category, 0, frequency, NULL,
          1, 0, is_active, next_date,
          last_generated, last_generated, party_name, payment_method, notes,
          created_at, updated_at
        FROM recurring_transactions
      ''');

      await db.insert('schema_version', {
        'version': 9,
        'description': 'Unified scheduled_payments: merge bills + recurring',
      });
    }

    if (oldVersion < 10) {
      // Safety re-run: ensures scheduled_payments exists on devices that were
      // already at v9 before the table was added (e.g. dev builds).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS scheduled_payments (
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
          deleted_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_active ON scheduled_payments(is_active, deleted_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_next ON scheduled_payments(next_date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sp_auto ON scheduled_payments(auto_create, next_date)');
      await db.insert('schema_version', {
        'version': 10,
        'description': 'Ensure scheduled_payments table exists (v9 safety)',
      });
    }

    if (oldVersion < 11) {
      // Add GSTIN to parties (stored locally, never validated via network)
      await db.execute('ALTER TABLE parties ADD COLUMN gstin TEXT');

      // Add reminder_sent_at to transactions (tracks last WhatsApp/SMS/Email
      // reminder sent for lent/borrowed transactions)
      await db.execute('ALTER TABLE transactions ADD COLUMN reminder_sent_at TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_reminder ON transactions(reminder_sent_at)');

      await db.insert('schema_version', {
        'version': 11,
        'description': 'Add gstin to parties, reminder_sent_at to transactions',
      });
    }

    if (oldVersion < 12) {
      // Add address to parties (stored locally, never transmitted)
      await db.execute('ALTER TABLE parties ADD COLUMN address TEXT');

      await db.insert('schema_version', {
        'version': 12,
        'description': 'Add address to parties',
      });
    }

    if (oldVersion < 13) {
      // Business Mode — Billing & Invoicing (all local, never transmitted)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_catalog (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          unit TEXT DEFAULT 'pcs',
          unit_price REAL NOT NULL DEFAULT 0,
          tax_pct REAL NOT NULL DEFAULT 0,
          hsn_code TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS quotes (
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS quote_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quote_id INTEGER NOT NULL,
          item_name TEXT NOT NULL,
          description TEXT,
          qty REAL NOT NULL DEFAULT 1,
          unit_price REAL NOT NULL DEFAULT 0,
          tax_pct REAL NOT NULL DEFAULT 0,
          discount_pct REAL NOT NULL DEFAULT 0,
          line_total REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoices (
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          item_name TEXT NOT NULL,
          description TEXT,
          qty REAL NOT NULL DEFAULT 1,
          unit_price REAL NOT NULL DEFAULT 0,
          tax_pct REAL NOT NULL DEFAULT 0,
          discount_pct REAL NOT NULL DEFAULT 0,
          line_total REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_due ON invoices(due_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_status ON quotes(status)');

      await db.insert('schema_version', {
        'version': 13,
        'description': 'Business mode: item_catalog, quotes, quote_items, invoices, invoice_items',
      });
    }

    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS businesses (
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
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_businesses_active ON businesses(is_active)');
      await db.insert('schema_version', {
        'version': 14,
        'description': 'Add businesses table (multiple business profiles)',
      });
    }

    if (oldVersion < 15) {
      // Enhanced item catalog with categories, SKU, favorites, usage tracking, and business linkage
      await db.execute('ALTER TABLE item_catalog ADD COLUMN business_id INTEGER');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN sku TEXT');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN category TEXT DEFAULT "product"');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN last_used_at TEXT');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN usage_count INTEGER NOT NULL DEFAULT 0');
      
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_item_catalog_business ON item_catalog(business_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_item_catalog_category ON item_catalog(category)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_item_catalog_favorite ON item_catalog(is_favorite)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_item_catalog_last_used ON item_catalog(last_used_at)');
      
      await db.insert('schema_version', {
        'version': 15,
        'description': 'Enhanced item catalog: business_id, categories, SKU, favorites, usage tracking',
      });
    }

    if (oldVersion < 16) {
      // Add business_id to invoices and quotes for multi-business support
      await db.execute('ALTER TABLE invoices ADD COLUMN business_id INTEGER');
      await db.execute('ALTER TABLE quotes ADD COLUMN business_id INTEGER');
      
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_business ON invoices(business_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_business ON quotes(business_id)');
      
      await db.insert('schema_version', {
        'version': 16,
        'description': 'Add business_id to invoices and quotes for multi-business support',
      });
    }

    if (oldVersion < 17) {
      // Split address into city, state, pincode for parties (like business addresses)
      await db.execute('ALTER TABLE parties ADD COLUMN city TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN state TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN pincode TEXT');
      
      await db.insert('schema_version', {
        'version': 17,
        'description': 'Add city, state, pincode to parties for structured addresses',
      });
    }

    if (oldVersion < 18) {
      // Automatic transaction creation: link transactions to invoices/bookings
      await db.execute('ALTER TABLE transactions ADD COLUMN linked_invoice_id INTEGER');
      await db.execute('ALTER TABLE transactions ADD COLUMN linked_booking_id INTEGER');
      await db.execute('ALTER TABLE transactions ADD COLUMN business_id INTEGER');
      
      // Track invoice payment details
      await db.execute('ALTER TABLE invoices ADD COLUMN paid_at TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN payment_method TEXT');
      
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_invoice ON transactions(linked_invoice_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_booking ON transactions(linked_booking_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transactions_business ON transactions(business_id)');
      
      await db.insert('schema_version', {
        'version': 18,
        'description': 'Automatic transaction creation: link transactions to invoices/bookings, track payment details',
      });
    }

    if (oldVersion < 19) {
      // Week 25-27: Bookings feature
      
      // Create bookings table
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
          
          invoice_id INTEGER,
          
          notes TEXT,
          notification_scheduled_at TEXT,
          confirmed_at TEXT,
          
          business_id INTEGER,
          booking_ref TEXT,
          
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT,
          
          FOREIGN KEY (customer_party_id) REFERENCES parties(id),
          FOREIGN KEY (service_item_id) REFERENCES item_catalog(id),
          FOREIGN KEY (invoice_id) REFERENCES invoices(id),
          FOREIGN KEY (business_id) REFERENCES businesses(id)
        )
      ''');
      
      // Create indexes for bookings
      await db.execute('CREATE INDEX idx_bookings_status ON bookings(status)');
      await db.execute('CREATE INDEX idx_bookings_start_datetime ON bookings(start_datetime)');
      await db.execute('CREATE INDEX idx_bookings_customer ON bookings(customer_party_id)');
      await db.execute('CREATE INDEX idx_bookings_business ON bookings(business_id)');
      
      // Extend item_catalog for bookable services
      await db.execute('ALTER TABLE item_catalog ADD COLUMN duration_minutes INTEGER DEFAULT 30');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN is_bookable INTEGER DEFAULT 0');
      
      await db.insert('schema_version', {
        'version': 19,
        'description': 'Add bookings table and extend item_catalog for bookable services',
      });
    }

    if (oldVersion < 20) {
      // Business + Personal schedule: add booking_type column
      await db.execute(
        "ALTER TABLE bookings ADD COLUMN booking_type TEXT NOT NULL DEFAULT 'business'",
      );
      await db.execute(
        'CREATE INDEX idx_bookings_type ON bookings(booking_type)',
      );
      await db.insert('schema_version', {
        'version': 20,
        'description': 'Add booking_type column (business/personal) to bookings table',
      });
    }

    if (oldVersion < 21) {
      // Unified Notifications — track last manual reminder timestamp per record
      await db.execute('ALTER TABLE invoices ADD COLUMN reminder_sent_at TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_reminder ON invoices(reminder_sent_at, due_date)');
      await db.execute('ALTER TABLE bookings ADD COLUMN reminder_sent_at TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bookings_reminder ON bookings(reminder_sent_at, start_datetime)');
      await db.insert('schema_version', {
        'version': 21,
        'description': 'Add reminder_sent_at to invoices and bookings (Unified Notifications)',
      });
    }

    if (oldVersion < 22) {
      // Budget feature — drop old schema (category/amount/period/start_date) and
      // recreate with the new per-month schema (year, month, category, budget_amount).
      // Old table had no valuable data to migrate.
      await db.execute('DROP TABLE IF EXISTS budgets');
      await db.execute('''
        CREATE TABLE budgets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          category TEXT NOT NULL,
          budget_amount REAL NOT NULL,
          alert_at_percentage REAL NOT NULL DEFAULT 80,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          UNIQUE(year, month, category)
        )
      ''');
      await db.insert('schema_version', {
        'version': 22,
        'description': 'Recreate budgets table with year/month/category/budget_amount schema',
      });
    }

    if (oldVersion < 23) {
      // Add bill_context column to separate personal Bills Payable from
      // business Payables (supplier/vendor dues).
      await db.execute(
        "ALTER TABLE scheduled_payments ADD COLUMN bill_context TEXT NOT NULL DEFAULT 'personal'",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sp_context ON scheduled_payments(bill_context)',
      );
      await db.insert('schema_version', {
        'version': 23,
        'description': 'Add bill_context column to scheduled_payments (personal/business split)',
      });
    }

    if (oldVersion < 24) {
      // Add party_context to distinguish personal vs business lenders/borrowers.
      await db.execute(
        "ALTER TABLE parties ADD COLUMN party_context TEXT NOT NULL DEFAULT 'personal'",
      );
      await db.insert('schema_version', {
        'version': 24,
        'description': 'Add party_context to parties table (personal/business for lender/borrower)',
      });
    }

    if (oldVersion < 25) {
      // Store local file path for a scanned/photographed business card.
      await db.execute(
        'ALTER TABLE parties ADD COLUMN business_card_image_path TEXT',
      );
      await db.insert('schema_version', {
        'version': 25,
        'description': 'Add business_card_image_path to parties table',
      });
    }

    if (oldVersion < 26) {
      // Social/web presence on parties.
      await db.execute('ALTER TABLE parties ADD COLUMN website TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN whatsapp TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN linkedin TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN instagram TEXT');
      // Social/web presence + owner name on businesses.
      await db.execute('ALTER TABLE businesses ADD COLUMN owner_name TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN website TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN whatsapp TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN linkedin TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN instagram TEXT');
      await db.insert('schema_version', {
        'version': 26,
        'description': 'Add website, social fields to parties & businesses',
      });
    }

    if (oldVersion < 27) {
      // Fiscal year management settings.
      // ConflictAlgorithm.ignore ensures user-configured values are not clobbered
      // if somehow these keys already exist.
      await _seedFySettings(db);
      await db.insert('schema_version', {
        'version': 27,
        'description': 'FY settings: invoice_no_format, fiscal_year_start_month/day, auto_reset_invoice_no, current_fy_start',
      });
    }

    if (oldVersion < 28) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS unit_types (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          label TEXT NOT NULL UNIQUE,
          is_system INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await _seedUnitTypes(db);
      await db.insert('schema_version', {
        'version': 28,
        'description': 'Add unit_types table with seeded defaults',
      });
    }

    if (oldVersion < 29) {
      // Add software/digital service units to existing installs.
      // ConflictAlgorithm.ignore makes this safe to re-run.
      await _seedUnitTypes(db);
      await db.insert('schema_version', {
        'version': 29,
        'description': 'Seed software/digital unit types (week, year, license, seat, user, project, task, sprint, feature, screen, page, report, API call, request, token, deployment, instance, GB, MB, TB)',
      });
    }

    if (oldVersion < 30) {
      // Add nos / nos. (Indian formal unit for Numbers).
      await _seedUnitTypes(db);
      await db.insert('schema_version', {
        'version': 30,
        'description': 'Seed nos / nos. unit types',
      });
    }

    if (oldVersion < 32) {
      // GST Phase A: add HSN/unit to line items; add invoice_type/place_of_supply/
      // reverse_charge/customer_gstin to invoice+quote headers.
      await db.execute('ALTER TABLE invoice_items ADD COLUMN hsn_code TEXT');
      await db.execute("ALTER TABLE invoice_items ADD COLUMN unit TEXT DEFAULT 'PCS'");
      await db.execute("ALTER TABLE invoice_items ADD COLUMN hsn_or_sac TEXT DEFAULT 'HSN'");
      await db.execute('ALTER TABLE quote_items ADD COLUMN hsn_code TEXT');
      await db.execute("ALTER TABLE quote_items ADD COLUMN unit TEXT DEFAULT 'PCS'");
      await db.execute("ALTER TABLE quote_items ADD COLUMN hsn_or_sac TEXT DEFAULT 'HSN'");
      await db.execute("ALTER TABLE invoices ADD COLUMN invoice_type TEXT NOT NULL DEFAULT 'tax_invoice'");
      await db.execute('ALTER TABLE invoices ADD COLUMN place_of_supply TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN reverse_charge INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN customer_gstin TEXT');
      await db.execute("ALTER TABLE quotes ADD COLUMN invoice_type TEXT NOT NULL DEFAULT 'tax_invoice'");
      await db.execute('ALTER TABLE quotes ADD COLUMN place_of_supply TEXT');
      await db.execute('ALTER TABLE quotes ADD COLUMN reverse_charge INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE quotes ADD COLUMN customer_gstin TEXT');
      await db.insert('schema_version', {
        'version': 32,
        'description': 'GST Phase A: hsn_code/unit/hsn_or_sac on invoice_items+quote_items; invoice_type/place_of_supply/reverse_charge/customer_gstin on invoices+quotes',
      });
    }

    if (oldVersion < 33) {
      // GST Phase A4: store HSN/SAC type on item catalog so the form toggle is persisted.
      await db.execute("ALTER TABLE item_catalog ADD COLUMN hsn_or_sac TEXT DEFAULT 'HSN'");
      await db.insert('schema_version', {
        'version': 33,
        'description': 'GST Phase A4: hsn_or_sac column on item_catalog',
      });
    }
  }

  /// Inserts fiscal-year defaults into the settings table.
  /// Uses [ConflictAlgorithm.ignore] so existing values are never overwritten.
  Future<void> _seedFySettings(Database db) async {
    final fyStart = _currentFyStart();
    final defaults = <String, String>{
      'fiscal_year_start_month': '4',
      'fiscal_year_start_day': '1',
      'invoice_no_format': 'INV-{YY}-{YY+1}-{SEQ}',
      'quote_no_format': 'QT-{YY}-{YY+1}-{SEQ}',
      'auto_reset_invoice_no': '1',
      'last_fy_close_date': '',
      'current_fy_start': fyStart,
    };
    for (final entry in defaults.entries) {
      await db.insert(
        'settings',
        {
          'key': entry.key,
          'value': entry.value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Returns the ISO8601 date (YYYY-MM-DD) of the April 1 that began the
  /// current Indian fiscal year.
  String _currentFyStart() {
    final now = DateTime.now();
    final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
    return DateTime(fyStartYear, 4, 1).toIso8601String().substring(0, 10);
  }

  Future<void> _seedAccounts(Database db) async {
    final accounts = [
      {'account_type': 'savings', 'account_name': 'Bank', 'is_primary': 1},
      {'account_type': 'upiWallet', 'account_name': 'UPI / Wallet', 'is_primary': 0},
      {'account_type': 'savings', 'account_name': 'Cash', 'is_primary': 0},
    ];
    for (final a in accounts) {
      await db.insert('accounts', {
        ...a,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Seed default expense and income categories.
  Future<void> _seedCategories(Database db) async {
    final expenseCategories = [
      {'name': 'Food & Dining', 'icon': 'restaurant', 'color': '#FF5722', 'keywords': 'swiggy,zomato,restaurant,food,cafe,hotel,dining'},
      {'name': 'Transportation', 'icon': 'directions_car', 'color': '#2196F3', 'keywords': 'uber,ola,rapido,metro,fuel,petrol,diesel'},
      {'name': 'Shopping', 'icon': 'shopping_bag', 'color': '#9C27B0', 'keywords': 'amazon,flipkart,myntra,ajio,shopping'},
      {'name': 'Bills & Utilities', 'icon': 'receipt_long', 'color': '#607D8B', 'keywords': 'electricity,water,gas,internet,broadband,mobile,recharge'},
      {'name': 'Healthcare', 'icon': 'local_hospital', 'color': '#F44336', 'keywords': 'hospital,pharmacy,medical,doctor,medicine'},
      {'name': 'Entertainment', 'icon': 'movie', 'color': '#E91E63', 'keywords': 'netflix,hotstar,spotify,movie,game'},
      {'name': 'Groceries', 'icon': 'local_grocery_store', 'color': '#4CAF50', 'keywords': 'bigbasket,blinkit,zepto,grocery,supermarket'},
      {'name': 'Education', 'icon': 'school', 'color': '#3F51B5', 'keywords': 'school,college,course,book,tuition'},
      {'name': 'Business Expense', 'icon': 'business_center', 'color': '#795548', 'keywords': 'office,business,supply'},
      {'name': 'Other', 'icon': 'more_horiz', 'color': '#9E9E9E', 'keywords': ''},
    ];

    final incomeCategories = [
      {'name': 'Salary', 'icon': 'account_balance_wallet', 'color': '#2E7D32', 'keywords': 'salary,wage,pay'},
      {'name': 'Business Income', 'icon': 'store', 'color': '#1B5E20', 'keywords': 'business,revenue,sale'},
      {'name': 'Freelance', 'icon': 'laptop_mac', 'color': '#00695C', 'keywords': 'freelance,consulting,project'},
      {'name': 'Investment', 'icon': 'trending_up', 'color': '#0D47A1', 'keywords': 'dividend,interest,mutual fund,stock'},
      {'name': 'Refund', 'icon': 'replay', 'color': '#FF6F00', 'keywords': 'refund,return,cashback'},
      {'name': 'Other Income', 'icon': 'attach_money', 'color': '#388E3C', 'keywords': ''},
    ];

    for (var i = 0; i < expenseCategories.length; i++) {
      final cat = expenseCategories[i];
      await db.insert('categories', {
        'name': cat['name'],
        'category_type': 'expense',
        'mode': 'both',
        'icon': cat['icon'],
        'color': cat['color'],
        'sort_order': i,
        'is_system': 1,
        'is_active': 1,
        'keywords': cat['keywords'],
      });
    }

    for (var i = 0; i < incomeCategories.length; i++) {
      final cat = incomeCategories[i];
      await db.insert('categories', {
        'name': cat['name'],
        'category_type': 'income',
        'mode': 'both',
        'icon': cat['icon'],
        'color': cat['color'],
        'sort_order': i,
        'is_system': 1,
        'is_active': 1,
        'keywords': cat['keywords'],
      });
    }
  }

  // ── Custom categories ──────────────────────────────────────────────────────

  /// Returns all user-created (non-system) categories ordered by name.
  Future<List<Map<String, dynamic>>> getCustomCategories() async {
    final db = await database;
    return db.query(
      'categories',
      where: 'is_system = 0 AND is_active = 1',
      orderBy: 'name ASC',
    );
  }

  /// Inserts a user-created category and returns its new row id.
  /// Soft-deletes a user-created category by name. Returns rows affected.
  Future<int> deleteCustomCategory(String name) async {
    final db = await database;
    return db.update(
      'categories',
      {'is_active': 0},
      where: 'name = ? AND is_system = 0',
      whereArgs: [name],
    );
  }

  /// Returns the number of transactions using [category].
  Future<int> countTransactionsByCategory(String category) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE category = ?',
      [category],
    );
    return result.first['c'] as int? ?? 0;
  }

  /// Silently ignores duplicates (returns -1).
  Future<int> insertCustomCategory({
    required String name,
    required String categoryType, // 'expense' | 'income'
  }) async {
    final db = await database;
    try {
      return await db.insert('categories', {
        'name': name,
        'category_type': categoryType,
        'mode': 'both',
        'icon': 'label_outline',
        'color': '#607D8B',
        'sort_order': 999,
        'is_system': 0,
        'is_active': 1,
      });
    } on Exception {
      return -1; // duplicate name — UNIQUE constraint
    }
  }

  /// Seeds the default system unit types.
  /// GST-coded units: official e-Way Bill UOM codes from GSTN master list.
  /// Non-GST units: software / time / specialty (use OTH on e-way bill).
  /// Uses [ConflictAlgorithm.ignore] so re-running on upgrades is safe.
  Future<void> _seedUnitTypes(Database db) async {
    // [code, label, sortOrder] — code is null for non-GST units
    const units = <List<Object?>>[
      // ── Count / Quantity ────────────────────────────────
      ['NOS', 'Numbers',            0],
      ['PCS', 'Pieces',             1],
      ['UNT', 'Units',              2],
      ['DOZ', 'Dozens',             3],
      ['PAC', 'Packs',              4],
      ['BOX', 'Box',                5],
      ['SET', 'Sets',               6],
      ['PRS', 'Pairs',              7],
      // ── Packaging ──────────────────────────────────────
      ['BAG', 'Bags',               8],
      ['BTL', 'Bottles',            9],
      ['CTN', 'Cartons',           10],
      ['ROL', 'Rolls',             11],
      ['BDL', 'Bundles',           12],
      ['BUN', 'Bunches',           13],
      ['CAN', 'Cans',              14],
      ['DRM', 'Drums',             15],
      ['TUB', 'Tubes',             16],
      ['TBS', 'Tablets',           17],
      ['BAL', 'Bale',              18],
      ['BKL', 'Buckles',           19],
      // ── Bulk counts ────────────────────────────────────
      ['GRS', 'Gross',             20],
      ['GGK', 'Great Gross',       21],
      ['TGM', 'Ten Gross',         22],
      ['THD', 'Thousands',         23],
      ['BOU', 'Billion of Units',  24],
      // ── Weight ─────────────────────────────────────────
      ['GMS', 'Grammes',           25],
      ['KGS', 'Kilograms',         26],
      ['QTL', 'Quintal',           27],
      ['MTS', 'Metric Ton',        28],
      ['TON', 'Tonnes',            29],
      // ── Volume ─────────────────────────────────────────
      ['MLT', 'Mililitre',         30],
      ['LTR', 'Litres',            31],
      ['KLR', 'Kilolitre',         32],
      ['UGS', 'US Gallons',        33],
      // ── Length ─────────────────────────────────────────
      ['CMS', 'Centi Meters',      34],
      ['MTR', 'Meters',            35],
      ['KME', 'Kilometre',         36],
      ['YDS', 'Yards',             37],
      ['GYD', 'Gross Yards',       38],
      // ── Area / Volume (3-D) ────────────────────────────
      ['SQF', 'Square Feet',       39],
      ['SQM', 'Square Meters',     40],
      ['SQY', 'Square Yards',      41],
      ['CBM', 'Cubic Meters',      42],
      ['CCM', 'Cubic Centimeters', 43],
      // ── Catch-all ──────────────────────────────────────
      ['OTH', 'Others',            44],
      // ── Non-GST: specialty physical ────────────────────
      [null,  'mg',                50],
      [null,  'acre',              51],
      // ── Non-GST: time ──────────────────────────────────
      [null,  'hrs',               52],
      [null,  'days',              53],
      [null,  'week',              54],
      [null,  'month',             55],
      [null,  'year',              56],
      // ── Non-GST: software / digital services ───────────
      [null,  'license',           57],
      [null,  'seat',              58],
      [null,  'user',              59],
      [null,  'project',           60],
      [null,  'task',              61],
      [null,  'sprint',            62],
      [null,  'feature',           63],
      [null,  'screen',            64],
      [null,  'page',              65],
      [null,  'report',            66],
      [null,  'API call',          67],
      [null,  'request',           68],
      [null,  'token',             69],
      [null,  'deployment',        70],
      [null,  'instance',          71],
      [null,  'GB',                72],
      [null,  'MB',                73],
      [null,  'TB',                74],
    ];
    for (final u in units) {
      await db.insert(
        'unit_types',
        {'code': u[0], 'label': u[1], 'is_system': 1, 'sort_order': u[2]},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Returns all active unit types ordered by sort_order then label.
  Future<List<Map<String, dynamic>>> getUnitTypes() async {
    final db = await database;
    return db.rawQuery(
        'SELECT id, code, label, is_system FROM unit_types ORDER BY sort_order, label');
  }

  /// Inserts a custom unit type. Returns the new id, or -1 if duplicate.
  Future<int> insertUnitType(String label) async {
    final db = await database;
    try {
      return await db.insert('unit_types', {
        'label': label.trim(),
        'is_system': 0,
        'sort_order': 999,
      });
    } on Exception {
      return -1;
    }
  }

  /// Deletes a custom (non-system) unit type by id.
  /// No-op if the unit is a system unit.
  Future<void> deleteUnitType(int id) async {
    final db = await database;
    await db.delete(
      'unit_types',
      where: 'id = ? AND is_system = 0',
      whereArgs: [id],
    );
  }

  // ── Close ─────────────────────────────────────────────────────────────────

  /// Close the database connection.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
