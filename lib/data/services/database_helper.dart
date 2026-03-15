import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';

part 'database_helper_tables.dart';

/// Singleton helper for SQLite database initialization and access.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  /// Returns the database instance, creating it if needed.
  ///
  /// Also re-opens the database if the cached handle was closed externally.
  ///
  /// Root cause of `database_closed 1`: workmanager 0.6.0 shares the same
  /// FlutterEngine (and therefore the same sqflite native plugin) between the
  /// main Dart isolate and WorkManager background isolates.  sqflite's default
  /// `singleInstance: true` causes background `openDatabase` calls to return
  /// the *same* native handle (same ID) as the main isolate's open connection.
  /// When the background task closes that handle, the main isolate's
  /// `_database` reference becomes a dangling pointer — `isOpen` still reports
  /// `true` on the Dart side, but the next native query throws `database_closed`.
  ///
  /// Primary fix: always pass `singleInstance: false` when opening the DB in
  /// background tasks (see [ActionCenterBackgroundService]).
  /// Defence-in-depth: if we encounter `database_closed` anyway (hot restart,
  /// unforeseen paths), reset and re-open before rethrowing.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Executes [op] with a valid database handle, recovering once from a
  /// stale-handle `database_closed` error (e.g. caused by a hot restart or
  /// an unexpected isolate interaction).
  Future<T> withDatabase<T>(Future<T> Function(Database db) op) async {
    try {
      return await op(await database);
    } on DatabaseException catch (e) {
      if (e.toString().contains('database_closed')) {
        _database = null;
        final db = await _initDatabase();
        _database = db;
        return await op(db);
      }
      rethrow;
    }
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

    await _createTransactionTables(db);

    await _createCreditAndLoanTables(db);

    await _createPartyAndAccountTables(db);

    await _createSchedulingTables(db);

    await _createBusinessAndCatalogTables(db);

    await _createSalesTables(db);

    await _createBookingTables(db);

    // -- schema_version table
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL DEFAULT (datetime('now')),
        description TEXT
      )
    ''');

    await db.insert('schema_version', {
      'version': 52,
      'description': 'Progressive schema seed (fresh install base)',
    });

    await _createLookupTables(db);

    await _createGstAndLogisticsTables(db);

    await _createInventoryAndHrTables(db);

    // Seed default categories + default accounts
    await _seedCategories(db);
    await _seedAccounts(db);
    await _seedFySettings(db);

    // ── v58: identity & sync tables ──────────────────────────────────────────
    await _createSyncAndIdentityTables(db);

    await db.insert('schema_version', {
      'version': 62,
      'description': 'Full v62 schema: sync foundation + Phase D1 my_identity + linked_business_sessions (fresh install)',
      'applied_at': DateTime.now().toIso8601String(),
    });

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
          code TEXT,
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

    if (oldVersion < 34) {
      // GST Phase C1: IRN / e-Invoice placeholder fields on invoices.
      // Only invoices carry an IRN — quotes do not (per GSTN spec).
      await db.execute('ALTER TABLE invoices ADD COLUMN irn TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN irn_ack_no TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN irn_ack_date TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN qr_code_data TEXT');
      await db.insert('schema_version', {
        'version': 34,
        'description': 'GST Phase C1: irn/irn_ack_no/irn_ack_date/qr_code_data on invoices (e-Invoice placeholders)',
      });
    }

    if (oldVersion < 35) {
      // Offline HSN + SAC code lookup master table (seeded from bundled CSVs).
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
      await db.insert('schema_version', {
        'version': 35,
        'description': 'HSN/SAC master table seeded from bundled CBIC CSVs',
      });
    }

    if (oldVersion < 36) {
      // e-Way Bill fields on invoices: transport details + EWB registry.
      await db.execute('ALTER TABLE invoices ADD COLUMN ewb_no TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN ewb_generated_at TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN ewb_valid_until TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN vehicle_no TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN transporter_name TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN transporter_gstin TEXT');
      await db.execute("ALTER TABLE invoices ADD COLUMN transport_mode TEXT DEFAULT '1'");
      await db.execute('ALTER TABLE invoices ADD COLUMN distance_km INTEGER');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_ewb ON invoices(ewb_no)');
      // Frequent transporters table for EWB autocomplete.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS transporters (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          name         TEXT NOT NULL,
          gstin        TEXT,
          last_used_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transporters_name ON transporters(name)');
      // GSP settings keys (all disabled by default — consent required to enable).
      final gspDefaults = <String, String>{
        'gsp_enabled': '0',
        'gsp_provider': 'masters_india',
        'gsp_consent_given_at': '',
      };
      for (final e in gspDefaults.entries) {
        await db.insert('settings', {
          'key': e.key,
          'value': e.value,
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await db.insert('schema_version', {
        'version': 36,
        'description': 'e-Way Bill fields on invoices + transporters table + GSP settings keys',
      });
    }

    if (oldVersion < 37) {
      // Freight, insurance, packing & forwarding charges on invoices and quotes.
      await db.execute('ALTER TABLE invoices ADD COLUMN freight_amt REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN insurance_amt REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN packing_amt REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE quotes ADD COLUMN freight_amt REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE quotes ADD COLUMN insurance_amt REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE quotes ADD COLUMN packing_amt REAL NOT NULL DEFAULT 0');
      await db.insert('schema_version', {
        'version': 37,
        'description': 'Freight, insurance, packing charges on invoices and quotes (CBIC Rule 46)',
      });
    }

    if (oldVersion < 38) {
      // Country + dial code for international party / business support.
      await db.execute('ALTER TABLE parties ADD COLUMN country TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN dial_code TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN country TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN dial_code TEXT');
      await db.insert('schema_version', {
        'version': 38,
        'description': 'Country and dial code for international customers/vendors (parties + businesses)',
      });
    }

    if (oldVersion < 39) {
      // Delivery Challan feature (GST Rule 55)
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
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
          FOREIGN KEY (challan_id) REFERENCES delivery_challans(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dci_challan ON delivery_challan_items(challan_id)');

      await db.insert('schema_version', {
        'version': 39,
        'description': 'Delivery Challan tables — GST Rule 55 (supply without tax invoice)',
      });
    }

    if (oldVersion < 40) {
      // Link invoices back to their source delivery challan
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN challan_id INTEGER REFERENCES delivery_challans(id) ON DELETE SET NULL',
      );
      await db.insert('schema_version', {
        'version': 40,
        'description': 'Add challan_id to invoices for DC → Invoice link-back',
      });
    }

    if (oldVersion < 41) {
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
          created_at            TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await _seedDocumentTemplatePresets(db);
      await db.insert('schema_version', {
        'version': 41,
        'description': 'Add document_templates table with built-in presets',
      });
    }

    if (oldVersion < 42) {
      // booking_items: multi-service line items for business bookings.
      // Schema mirrors invoice_items (minus HSN) for seamless Booking→Invoice.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS booking_items (
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
          FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE,
          FOREIGN KEY (service_item_id) REFERENCES item_catalog(id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_booking_items_booking ON booking_items(booking_id)',
      );

      // paid_amount: running total of all payments received (advance + later).
      await db.execute(
        'ALTER TABLE bookings ADD COLUMN paid_amount REAL DEFAULT 0',
      );
      // Seed existing advance amounts so legacy bookings stay correct.
      await db.execute(
        'UPDATE bookings SET paid_amount = advance_amount WHERE advance_amount > 0',
      );

      await db.insert('schema_version', {
        'version': 42,
        'description': 'Add booking_items table and paid_amount column for multi-service bookings',
      });
    }

    if (oldVersion < 43) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS party_reminders (
          id                INTEGER PRIMARY KEY AUTOINCREMENT,
          party_name        TEXT NOT NULL,
          channel           TEXT NOT NULL DEFAULT 'whatsapp',
          message           TEXT NOT NULL,
          invoice_refs      TEXT,
          invoice_count     INTEGER NOT NULL DEFAULT 0,
          total_outstanding REAL,
          sent_at           TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_party_reminders_party ON party_reminders(party_name)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_party_reminders_sent ON party_reminders(sent_at DESC)');

      await db.insert('schema_version', {
        'version': 43,
        'description': 'Add party_reminders table for reminder history tracking',
      });
    }

    if (oldVersion < 44) {
      // Add business_id to credits, loans, party_reminders for personal/business separation
      await db.execute(
          'ALTER TABLE credits ADD COLUMN business_id INTEGER REFERENCES businesses(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_credits_business ON credits(business_id)');

      await db.execute(
          'ALTER TABLE loans ADD COLUMN business_id INTEGER REFERENCES businesses(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_business ON loans(business_id)');

      await db.execute(
          'ALTER TABLE party_reminders ADD COLUMN business_id INTEGER REFERENCES businesses(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_party_reminders_business ON party_reminders(business_id)');

      await db.insert('schema_version', {
        'version': 44,
        'description': 'Add business_id to credits, loans, party_reminders for personal/business separation',
      });
    }

    if (oldVersion < 45) {
      // Add party_id FK to scheduled_payments for Party 360° aggregation
      await db.execute(
          'ALTER TABLE scheduled_payments ADD COLUMN party_id INTEGER REFERENCES parties(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sp_party ON scheduled_payments(party_id)');

      await db.insert('schema_version', {
        'version': 45,
        'description': 'Add party_id FK to scheduled_payments for Party 360° aggregation',
      });
    }

    if (oldVersion < 46) {
      // ── party_addresses — multiple named addresses per party ──────────────
      await db.execute('''
        CREATE TABLE IF NOT EXISTS party_addresses (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          party_id    INTEGER NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
          label       TEXT    NOT NULL DEFAULT 'Address',
          address     TEXT,
          city        TEXT,
          state       TEXT,
          pincode     TEXT,
          country     TEXT DEFAULT 'India',
          gstin       TEXT,
          is_default  INTEGER NOT NULL DEFAULT 0,
          created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_party_addresses_party ON party_addresses(party_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_party_addresses_default ON party_addresses(party_id, is_default)',
      );

      // ── Delivery address snapshot columns on delivery_challans ────────────
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN delivery_address TEXT',
      );
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN delivery_city TEXT',
      );
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN delivery_state TEXT',
      );
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN delivery_pincode TEXT',
      );
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN delivery_gstin TEXT',
      );

      // ── Delivery address snapshot columns on invoices ─────────────────────
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN delivery_address TEXT',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN delivery_city TEXT',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN delivery_state TEXT',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN delivery_pincode TEXT',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN delivery_gstin TEXT',
      );

      await db.insert('schema_version', {
        'version': 46,
        'description':
            'Add party_addresses table; delivery address snapshot columns on delivery_challans and invoices',
      });
    }

    if (oldVersion < 47) {
      // ── Credit/Debit Note original-invoice link columns (Phase F1) ────────
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN original_invoice_id INTEGER',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN original_invoice_no TEXT',
      );
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN original_invoice_date TEXT',
      );

      await db.insert('schema_version', {
        'version': 47,
        'description':
            'Add original_invoice_id/no/date to invoices for Credit/Debit Note linking',
      });
    }

    if (oldVersion < 48) {
      // ── Purchase Bills + ITC Tracking (Phase G1) ─────────────────────────
      await db.execute('''
        CREATE TABLE purchase_bills (
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (vendor_party_id) REFERENCES parties(id) ON DELETE SET NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_pb_business ON purchase_bills(business_id)');
      await db.execute(
          'CREATE INDEX idx_pb_bill_date ON purchase_bills(bill_date)');
      await db.execute(
          'CREATE INDEX idx_pb_status ON purchase_bills(status)');
      await db.execute(
          'CREATE INDEX idx_pb_rc ON purchase_bills(reverse_charge)');

      await db.execute('''
        CREATE TABLE purchase_bill_items (
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
          FOREIGN KEY (bill_id) REFERENCES purchase_bills(id) ON DELETE CASCADE
        )
      ''');

      await db.insert('schema_version', {
        'version': 48,
        'description':
            'Add purchase_bills + purchase_bill_items tables for ITC tracking (Phase G1)',
      });
    }

    if (oldVersion < 49) {
      await db.execute(
        'ALTER TABLE purchase_bills ADD COLUMN attachment_path TEXT',
      );
      await db.insert('schema_version', {
        'version': 49,
        'description': 'Add attachment_path to purchase_bills for vendor invoice attachment',
      });
    }

    if (oldVersion < 50) {
      await db.execute('ALTER TABLE businesses ADD COLUMN upi_id TEXT');
      await _seedDocumentTemplatePresets(db);
      await db.insert('schema_version', {
        'version': 50,
        'description': 'Add upi_id to businesses; seed industry invoice template presets',
      });
    }

    if (oldVersion < 51) {
      // Inventory tracking columns on item_catalog
      await db.execute(
          'ALTER TABLE item_catalog ADD COLUMN track_inventory INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE item_catalog ADD COLUMN stock_qty REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE item_catalog ADD COLUMN low_stock_threshold REAL NOT NULL DEFAULT 5');
      // Stock movements ledger
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          movement_type TEXT NOT NULL,
          qty REAL NOT NULL,
          stock_after REAL NOT NULL,
          reference_id INTEGER,
          reference_type TEXT,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (item_id) REFERENCES item_catalog(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sm_item ON stock_movements(item_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sm_date ON stock_movements(created_at DESC)');
      await db.insert('schema_version', {
        'version': 51,
        'description':
            'Inventory Phase A: stock tracking columns on item_catalog + stock_movements table',
      });
    }

    if (oldVersion < 52) {
      // Staff roster
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
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT,
          FOREIGN KEY (business_id) REFERENCES businesses(id)
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_staff_active ON staff(is_active)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_staff_business ON staff(business_id)');
      // Salary payment records
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
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salp_staff ON salary_payments(staff_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salp_period ON salary_payments(pay_period_year, pay_period_month)');
      await db.insert('schema_version', {
        'version': 52,
        'description': 'Staff & Payroll: staff + salary_payments tables',
      });
    }

    if (oldVersion < 53) {
      await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN catalog_item_id INTEGER');
      await db.execute(
          'ALTER TABLE delivery_challan_items ADD COLUMN catalog_item_id INTEGER');
      await db.execute(
          'ALTER TABLE purchase_bill_items ADD COLUMN catalog_item_id INTEGER');
      await db.insert('schema_version', {
        'version': 53,
        'description':
            'Link line items to item catalog: catalog_item_id on invoice_items, delivery_challan_items, purchase_bill_items',
      });
    }

    if (oldVersion < 54) {
      // Add party_id FK to staff so every staff member links to a Party (contact) record.
      await db.execute(
          'ALTER TABLE staff ADD COLUMN party_id INTEGER REFERENCES parties(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_staff_party ON staff(party_id)');

      // Backfill: create a parties row for every existing staff member.
      final existingStaff = await db.rawQuery(
          'SELECT id, name, phone, email FROM staff WHERE party_id IS NULL');
      final now = DateTime.now().toIso8601String();
      for (final row in existingStaff) {
        final partyId = await db.insert('parties', {
          'name': row['name'],
          'phone_number': row['phone'],
          'email': row['email'],
          'party_type': 'staff',
          'created_at': now,
          'updated_at': now,
        });
        await db.update(
          'staff',
          {'party_id': partyId},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await db.insert('schema_version', {
        'version': 54,
        'description':
            'Link staff to parties: party_id FK on staff, backfill party records for existing staff',
      });
    }

    if (oldVersion < 55) {
      // 1. Add business_id to stock_movements.
      await db.execute(
          'ALTER TABLE stock_movements ADD COLUMN business_id INTEGER REFERENCES businesses(id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sm_business ON stock_movements(business_id)');

      // 2. Create the item_stock per-business stock table.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_stock (
          business_id INTEGER NOT NULL REFERENCES businesses(id),
          item_id     INTEGER NOT NULL REFERENCES item_catalog(id) ON DELETE CASCADE,
          stock_qty           REAL    NOT NULL DEFAULT 0,
          low_stock_threshold REAL    NOT NULL DEFAULT 5,
          track_inventory     INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (business_id, item_id)
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_item_stock_item ON item_stock(item_id)');

      // 3. Backfill item_stock from item_catalog for the active business.
      //    Items that were already tracked get their existing qty/threshold
      //    assigned to the active business. Other businesses start at 0.
      final activeBizRows = await db
          .rawQuery('SELECT id FROM businesses WHERE is_active = 1 LIMIT 1');
      if (activeBizRows.isNotEmpty) {
        final activeBizId = activeBizRows.first['id'] as int;
        final trackedItems = await db.rawQuery(
          'SELECT id, stock_qty, low_stock_threshold '
          'FROM item_catalog WHERE track_inventory = 1',
        );
        for (final item in trackedItems) {
          await db.rawInsert(
            'INSERT OR IGNORE INTO item_stock '
            '(business_id, item_id, stock_qty, low_stock_threshold, track_inventory) '
            'VALUES (?, ?, ?, ?, 1)',
            [
              activeBizId,
              item['id'],
              item['stock_qty'],
              item['low_stock_threshold'],
            ],
          );
        }
        // 4. Back-fill stock_movements with the active business id.
        await db.rawUpdate(
          'UPDATE stock_movements SET business_id = ? WHERE business_id IS NULL',
          [activeBizId],
        );
      }

      await db.insert('schema_version', {
        'version': 55,
        'description':
            'Per-business inventory: item_stock table, business_id on stock_movements, backfill from item_catalog',
      });
    }
    if (oldVersion < 56) {
      await db.execute(
          'ALTER TABLE item_stock ADD COLUMN last_counted_qty REAL');
      await db.execute(
          'ALTER TABLE item_stock ADD COLUMN last_counted_at TEXT');
      await db.insert('schema_version', {
        'version': 56,
        'description':
            'Physical count: last_counted_qty + last_counted_at on item_stock',
      });
    }

    if (oldVersion < 57) {
      // Add staff-specific columns to parties
      await db.execute(
          'ALTER TABLE parties ADD COLUMN staff_role TEXT');
      await db.execute(
          'ALTER TABLE parties ADD COLUMN staff_salary REAL');
      await db.execute(
          "ALTER TABLE parties ADD COLUMN staff_salary_type TEXT DEFAULT 'monthly'");
      await db.execute(
          'ALTER TABLE parties ADD COLUMN staff_join_date TEXT');

      // Back-fill from old staff table (rows that were linked to a party)
      await db.execute('''
        UPDATE parties SET
          staff_role        = (SELECT designation FROM staff WHERE party_id = parties.id),
          staff_salary      = (SELECT base_salary  FROM staff WHERE party_id = parties.id),
          staff_salary_type = (SELECT salary_type  FROM staff WHERE party_id = parties.id),
          staff_join_date   = (SELECT join_date     FROM staff WHERE party_id = parties.id)
        WHERE id IN (SELECT party_id FROM staff WHERE party_id IS NOT NULL)
      ''');

      // Seed Payroll categories for existing installs (safe INSERT OR IGNORE)
      await db.rawInsert('''
        INSERT OR IGNORE INTO categories
          (name, category_type, mode, icon, color, sort_order, is_system, is_active, keywords)
        VALUES
          ('Payroll', 'expense', 'both', 'badge', '#1565C0', 100, 1, 1, 'salary,wages,payroll,staff'),
          ('Payroll Deduction', 'expense', 'both', 'remove_circle_outline', '#C62828', 101, 1, 1, 'tds,pf,esi,deduction')
      ''');

      await db.insert('schema_version', {
        'version': 57,
        'description':
            'HRMS: parties gains staff_role/salary/type/join_date; Payroll categories seeded',
      });
    }

    // ── v58: Phase 0 — Sync Foundation ───────────────────────────────────────
    // Adds sync_id + version + created_by_device_id to all P0 tables.
    // Adds updated_at / deleted_at to tables that were missing them.
    // Creates UPDATE triggers for updated_at + version maintenance.
    // Creates 9 new tables: app_users, user_permissions, subscription,
    //   plan_features, linked_devices, device_recovery, pairing_history,
    //   sync_outbox, device_session.
    // Seeds subscription (free tier) and plan_features matrix.
    if (oldVersion < 58) {
      // ── Step A: Add sync columns to existing P0 tables ─────────────────────

      // transactions: already has updated_at, deleted_at
      await db.execute('ALTER TABLE transactions ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE transactions ADD COLUMN created_by_device_id TEXT');

      // credits: already has updated_at, deleted_at
      await db.execute('ALTER TABLE credits ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE credits ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE credits ADD COLUMN created_by_device_id TEXT');

      // credit_payments: missing updated_at + deleted_at
      await db.execute('ALTER TABLE credit_payments ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE credit_payments ADD COLUMN updated_at TEXT');
      await db.execute('ALTER TABLE credit_payments ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE credit_payments ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE credit_payments ADD COLUMN created_by_device_id TEXT');

      // loans: already has updated_at, deleted_at
      await db.execute('ALTER TABLE loans ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE loans ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE loans ADD COLUMN created_by_device_id TEXT');

      // parties: already has updated_at, deleted_at
      await db.execute('ALTER TABLE parties ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE parties ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE parties ADD COLUMN created_by_device_id TEXT');

      // accounts: already has updated_at, deleted_at
      await db.execute('ALTER TABLE accounts ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE accounts ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE accounts ADD COLUMN created_by_device_id TEXT');

      // categories: missing updated_at + deleted_at
      await db.execute('ALTER TABLE categories ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE categories ADD COLUMN updated_at TEXT');
      await db.execute('ALTER TABLE categories ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE categories ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE categories ADD COLUMN created_by_device_id TEXT');

      // budgets: missing updated_at (no deleted_at — keyed by year+month+category)
      await db.execute('ALTER TABLE budgets ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE budgets ADD COLUMN updated_at TEXT');
      await db.execute('ALTER TABLE budgets ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE budgets ADD COLUMN created_by_device_id TEXT');

      // item_catalog: already has updated_at; missing deleted_at
      await db.execute('ALTER TABLE item_catalog ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE item_catalog ADD COLUMN created_by_device_id TEXT');

      // scheduled_payments: already has updated_at, deleted_at
      await db.execute('ALTER TABLE scheduled_payments ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE scheduled_payments ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE scheduled_payments ADD COLUMN created_by_device_id TEXT');

      // businesses: already has updated_at; missing deleted_at
      await db.execute('ALTER TABLE businesses ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE businesses ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE businesses ADD COLUMN created_by_device_id TEXT');

      // invoices: already has updated_at; missing deleted_at
      await db.execute('ALTER TABLE invoices ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE invoices ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN created_by_device_id TEXT');

      // purchase_bills: already has updated_at; missing deleted_at
      await db.execute('ALTER TABLE purchase_bills ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE purchase_bills ADD COLUMN deleted_at TEXT');
      await db.execute('ALTER TABLE purchase_bills ADD COLUMN version INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE purchase_bills ADD COLUMN created_by_device_id TEXT');

      // ── Step B: Backfill sync_id for all existing rows ─────────────────────
      const p0Tables = [
        'transactions', 'credits', 'credit_payments', 'loans', 'parties',
        'accounts', 'categories', 'budgets', 'item_catalog', 'scheduled_payments',
        'businesses', 'invoices', 'purchase_bills',
      ];
      for (final tbl in p0Tables) {
        await db.execute(
          "UPDATE $tbl SET sync_id = lower(hex(randomblob(16))) WHERE sync_id IS NULL",
        );
      }

      // ── Step C: Create unique indexes on sync_id ───────────────────────────
      for (final tbl in p0Tables) {
        await db.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_${tbl}_sync_id ON $tbl(sync_id)",
        );
      }

      // ── Step D: CREATE UPDATE triggers (updated_at + version) ─────────────
      // Pattern: WHEN NEW.updated_at = OLD.updated_at (or either NULL) prevents
      // the trigger from re-firing on its own UPDATE, eliminating infinite recursion.
      for (final tbl in p0Tables) {
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS trg_${tbl}_sync_updated
            AFTER UPDATE ON $tbl
            FOR EACH ROW
            WHEN NEW.updated_at = OLD.updated_at OR OLD.updated_at IS NULL
            BEGIN
              UPDATE $tbl SET
                updated_at = datetime('now'),
                version    = COALESCE(OLD.version, 0) + 1
              WHERE id = OLD.id;
            END
        ''');
      }

      // ── Step E: CREATE new tables ──────────────────────────────────────────

      // app_users — named profiles with PINs and roles (both devices)
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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_users_active ON app_users(is_active)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_app_users_party ON app_users(linked_party_id)',
      );

      // user_permissions — RBAC permission rows (both devices)
      // business_id = -1 is the sentinel for "personal data scope" (avoids NULL != NULL)
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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_perms_user ON user_permissions(user_id)',
      );

      // subscription — local subscription state, always 1 row (both devices)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subscription (
          id              INTEGER PRIMARY KEY,
          plan            TEXT NOT NULL DEFAULT 'free',
          source          TEXT DEFAULT 'none',
          purchase_token  TEXT,
          plan_started_at TEXT,
          plan_expires_at TEXT,
          is_trial        INTEGER NOT NULL DEFAULT 0,
          trial_ends_at   TEXT
        )
      ''');

      // plan_features — plan × feature capability matrix (both devices)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS plan_features (
          plan         TEXT NOT NULL,
          feature      TEXT NOT NULL,
          enabled      INTEGER NOT NULL DEFAULT 1,
          limit_value  INTEGER,
          PRIMARY KEY (plan, feature)
        )
      ''');

      // linked_devices — registry of paired secondaries (primary device only)
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
          last_sync_at         TEXT,
          revoked_at           TEXT,
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

      // device_recovery — recovery key hash for primary disaster recovery
      await db.execute('''
        CREATE TABLE IF NOT EXISTS device_recovery (
          id               INTEGER PRIMARY KEY,
          recovery_key_hash TEXT NOT NULL,
          kdf_salt         TEXT NOT NULL,
          created_at       TEXT NOT NULL DEFAULT (datetime('now')),
          last_rotated_at  TEXT
        )
      ''');

      // pairing_history — completed pairing audit log
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pairing_history (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          device_id        TEXT NOT NULL,
          device_name      TEXT NOT NULL,
          permission_preset TEXT NOT NULL DEFAULT 'custom',
          paired_at        TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pairing_history_time ON pairing_history(paired_at DESC)',
      );

      // sync_outbox — outbound event queue (primary device only)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_outbox (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          target_device_id TEXT,
          event_type       TEXT NOT NULL,
          payload          TEXT,
          created_at       TEXT NOT NULL DEFAULT (datetime('now')),
          delivered_at     TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(delivered_at) WHERE delivered_at IS NULL',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_outbox_target ON sync_outbox(target_device_id)',
      );

      // device_session — session credential on secondary (secondary device only; 1 row max)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS device_session (
          id                  INTEGER PRIMARY KEY,
          this_device_id      TEXT NOT NULL,
          primary_device_id   TEXT NOT NULL,
          primary_public_key  TEXT NOT NULL,
          token_payload       TEXT NOT NULL DEFAULT '{}',
          token_signature     TEXT NOT NULL DEFAULT '',
          permission_scope    TEXT NOT NULL DEFAULT '{}',
          business_scope      TEXT NOT NULL DEFAULT '[]',
          offline_grace_days  INTEGER NOT NULL DEFAULT 7,
          issued_at           TEXT NOT NULL DEFAULT (datetime('now')),
          last_sync_at        TEXT,
          is_read_only_forced INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // ── Step F: Seed subscription (free tier, 1 row) ───────────────────────
      await db.execute(
        "INSERT OR IGNORE INTO subscription (id, plan) VALUES (1, 'free')",
      );

      // ── Step G: Seed plan_features matrix ─────────────────────────────────
      await _seedPlanFeatures(db);

      await db.insert('schema_version', {
        'version': 58,
        'description':
            'Phase 0: sync_id + version + triggers on all P0 tables; 9 new auth/sync tables; subscription seeded',
      });
    }

    // ── v62: Phase D1 — My Identity Foundation ─────────────────────────────
    if (oldVersion < 62) {
      // my_identity — permanent per-install Ed25519 identity (1 row)
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

      // linked_business_sessions — replaces sync device_session; multi-session support
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

      // Migrate existing sync device_session → linked_business_sessions (best effort).
      // The device_session table may have either the app-management schema or the
      // sync-credential schema (token_payload etc.) — only migrate the latter.
      try {
        await db.execute('''
          INSERT OR IGNORE INTO linked_business_sessions (
            session_id, primary_identity_id, primary_public_key,
            business_name, business_ids, token_payload, token_signature,
            permission_scope, offline_grace_days, issued_at,
            last_sync_at, is_read_only_forced
          )
          SELECT
            lower(hex(randomblob(16))),
            primary_device_id,
            primary_public_key,
            'Linked Business',
            business_scope,
            token_payload,
            token_signature,
            permission_scope,
            offline_grace_days,
            issued_at,
            last_sync_at,
            is_read_only_forced
          FROM device_session
          WHERE token_payload IS NOT NULL AND token_payload != '{}'
          LIMIT 1
        ''');
      } catch (e) {
        // device_session has app-management schema only — no sync data to migrate
        debugPrint('[DB v62] device_session migration skipped: $e');
      }

      // Add identity columns to linked_devices and app_users
      try {
        await db.execute(
          'ALTER TABLE linked_devices ADD COLUMN secondary_identity_id TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE app_users ADD COLUMN identity_id TEXT',
        );
      } catch (_) {}

      await db.insert('schema_version', {
        'version': 62,
        'description':
            'Phase D1: my_identity table, linked_business_sessions (replaces sync device_session)',
      });
    }

    // ── v63: Phase D2 — Context Layer ──────────────────────────────────────
    //
    // Add context_id to all 13 syncable P0 tables.
    // context_id IS NULL  → personal (owner) data — never purged on unlink
    // context_id = N      → linked business session N — cascades on unlink
    if (oldVersion < 63) {
      const contextTables = [
        'transactions',
        'credits',
        'credit_payments',
        'loans',
        'parties',
        'accounts',
        'categories',
        'budgets',
        'item_catalog',
        'scheduled_payments',
        'businesses',
        'invoices',
        'purchase_bills',
      ];
      for (final tbl in contextTables) {
        try {
          await db.execute(
            'ALTER TABLE $tbl ADD COLUMN context_id INTEGER '
            'REFERENCES linked_business_sessions(id) ON DELETE CASCADE',
          );
        } catch (e) {
          debugPrint('[DB v63] context_id already exists on $tbl: $e');
        }
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_${tbl}_context '
            'ON $tbl(context_id)',
          );
        } catch (e) {
          debugPrint('[DB v63] context index already exists on $tbl: $e');
        }
      }
      await db.insert('schema_version', {
        'version': 63,
        'description':
            'Phase D2: context_id on all 13 syncable P0 tables for dual-primary context isolation',
      });
    }

    // ── v64: Phase D3 — Linked Sessions Upgrade ────────────────────────────
    //
    // 1. subscription.shareable_plan_features — pre-serialised plan features
    //    JSON cached on primary; embedded in session tokens and shared to
    //    secondary during pairing so it can gate features without a DB hit.
    // 2. linked_devices.secondary_display_name — human-readable name for the
    //    linked identity captured during pairing (so the UI shows "Ravi Kumar"
    //    instead of "Ravi's Galaxy S23").
    if (oldVersion < 64) {
      try {
        await db.execute(
          'ALTER TABLE subscription ADD COLUMN shareable_plan_features TEXT',
        );
      } catch (e) {
        debugPrint('[DB v64] shareable_plan_features already exists: $e');
      }
      try {
        await db.execute(
          'ALTER TABLE linked_devices ADD COLUMN secondary_display_name TEXT',
        );
      } catch (e) {
        debugPrint('[DB v64] secondary_display_name already exists: $e');
      }
      await db.insert('schema_version', {
        'version': 64,
        'description':
            'Phase D3: shareable_plan_features on subscription; secondary_display_name on linked_devices',
      });
    }

    if (oldVersion < 65) {
      // payroll_notifications — cross-context salary events delivered to secondary
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
      // Add target_identity_id to sync_outbox for privacy-filtered delivery
      try {
        await db.execute(
          'ALTER TABLE sync_outbox ADD COLUMN target_identity_id TEXT',
        );
      } catch (e) {
        debugPrint('[DB v65] target_identity_id already exists: $e');
      }
      await db.insert('schema_version', {
        'version': 65,
        'description':
            'Phase D4: payroll_notifications table + sync_outbox.target_identity_id',
      });
    }

    if (oldVersion < 66) {
      // Migrate active recurring_transactions → scheduled_payments
      // auto_create=1 so the new engine picks them up going forward.
      await db.execute('''
        INSERT INTO scheduled_payments (
          name, amount, type, category, is_one_time, frequency,
          auto_create, is_active, next_date, last_generated,
          party_name, payment_method, notes, created_at, updated_at,
          bill_context
        )
        SELECT
          COALESCE(NULLIF(party_name, ''), category),
          amount, type, category, 0, frequency,
          1, is_active, next_date, last_generated,
          party_name, payment_method, notes,
          COALESCE(created_at, datetime('now')), updated_at,
          'personal'
        FROM recurring_transactions
        WHERE is_active = 1
      ''');
      // Deactivate migrated templates so they don't auto-generate twice.
      await db.execute(
          "UPDATE recurring_transactions SET is_active = 0, "
          "updated_at = datetime('now') WHERE is_active = 1");

      // Migrate active bills → scheduled_payments
      // next_date is derived from due_day (first upcoming occurrence).
      await db.execute('''
        INSERT INTO scheduled_payments (
          name, amount, type, category, is_one_time, frequency,
          due_day, is_auto_pay, auto_create, is_active,
          next_date, last_paid_date, payment_method, notes,
          created_at, updated_at, bill_context
        )
        SELECT
          name, amount, 'expense', category, 0, frequency,
          due_day, is_auto_pay, 0, is_active,
          CASE
            WHEN CAST(strftime('%d', 'now') AS INTEGER) <= due_day
              THEN strftime('%Y-%m-', 'now')
                   || printf('%02d', due_day) || 'T00:00:00.000'
            ELSE strftime('%Y-%m-', date('now', '+1 month'))
                 || printf('%02d', due_day) || 'T00:00:00.000'
          END,
          last_paid_date, payment_method, notes,
          COALESCE(created_at, datetime('now')), updated_at, 'personal'
        FROM bills
        WHERE is_active = 1 AND deleted_at IS NULL
      ''');
      // Soft-delete migrated bill rows.
      await db.execute(
          "UPDATE bills SET deleted_at = datetime('now'), "
          "updated_at = datetime('now') "
          "WHERE is_active = 1 AND deleted_at IS NULL");

      await db.insert('schema_version', {
        'version': 66,
        'description':
            'Migrate recurring_transactions + bills into scheduled_payments; '
            'deprecate legacy tables',
      });
    }

    if (oldVersion < 67) {
      // Conflict-free multi-device invoice numbering (v67).
      // Adds an atomic cursor table and pending_number_since columns so that
      // secondary devices can save documents offline and receive real serial
      // numbers when they reconnect and upload their deltas.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_number_cursors (
          doc_type   TEXT PRIMARY KEY,
          prefix     TEXT NOT NULL,
          last_seq   INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'ALTER TABLE invoices ADD COLUMN pending_number_since TEXT',
      );
      await db.execute(
        'ALTER TABLE quotes ADD COLUMN pending_number_since TEXT',
      );
      await db.execute(
        'ALTER TABLE delivery_challans ADD COLUMN pending_number_since TEXT',
      );
      await db.insert('schema_version', {
        'version': 67,
        'description':
            'Conflict-free numbering: invoice_number_cursors table + '
            'pending_number_since columns on invoices/quotes/delivery_challans',
      });
    }
  }

  /// Seeds the [hsn_master] table from the two bundled CBIC CSV assets.
  ///
  /// Uses a single transaction with batch inserts for performance.
  /// Each CSV has columns: CODE,DESCRIPTION  (header row skipped).
  /// Re-entrant: uses [ConflictAlgorithm.ignore] so rows are never duplicated.
  Future<void> _seedHsnMaster(Database db) async {
    debugPrint('[DB] Seeding hsn_master from bundled CSVs…');
    const assets = [
      ('assets/hns_sac/HSN_SAC - HSN_MSTR.csv', 'HSN'),
      ('assets/hns_sac/HSN_SAC - SAC_MSTR.csv', 'SAC'),
    ];

    await db.transaction((txn) async {
      for (final (assetPath, type) in assets) {
        late String raw;
        try {
          raw = await rootBundle.loadString(assetPath);
        } catch (e) {
          debugPrint('[DB] Could not load $assetPath: $e');
          continue;
        }

        final lines = const LineSplitter().convert(raw);
        final batch = txn.batch();
        var inserted = 0;

        for (var i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          // Handle CSV: code is always first field; description may be quoted.
          String code;
          String desc;
          if (line.startsWith('"')) {
            // Entire line is a quoted field — malformed; skip.
            continue;
          } else if (line.contains(',')) {
            final firstComma = line.indexOf(',');
            code = line.substring(0, firstComma).trim();
            var rest = line.substring(firstComma + 1).trim();
            // Strip surrounding quotes from description if present.
            if (rest.startsWith('"') && rest.endsWith('"')) {
              rest = rest.substring(1, rest.length - 1)
                  .replaceAll('""', '"');
            }
            desc = rest;
          } else {
            continue;
          }

          if (code.isEmpty || desc.isEmpty) continue;

          batch.insert(
            'hsn_master',
            {'code': code, 'description': desc, 'type': type},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          inserted++;
        }

        await batch.commit(noResult: true);
        debugPrint('[DB] hsn_master: inserted $inserted $type rows');
      }
    });
  }

  /// Seeds the [plan_features] table with the free / pro / team capability matrix.
  /// Uses [ConflictAlgorithm.ignore] so re-running on upgrades is safe.
  Future<void> _seedPlanFeatures(Database db) async {
    final rows = <Map<String, Object?>>[
      // linked_devices
      {'plan': 'free',  'feature': 'linked_devices',          'enabled': 1, 'limit_value': 0},
      {'plan': 'pro',   'feature': 'linked_devices',          'enabled': 1, 'limit_value': 2},
      {'plan': 'team',  'feature': 'linked_devices',          'enabled': 1, 'limit_value': 10},
      // app_users
      {'plan': 'free',  'feature': 'app_users',               'enabled': 1, 'limit_value': 0},
      {'plan': 'pro',   'feature': 'app_users',               'enabled': 1, 'limit_value': 3},
      {'plan': 'team',  'feature': 'app_users',               'enabled': 1, 'limit_value': 20},
      // cashier_mode
      {'plan': 'free',  'feature': 'cashier_mode',            'enabled': 1, 'limit_value': 1},
      {'plan': 'pro',   'feature': 'cashier_mode',            'enabled': 1, 'limit_value': 1},
      {'plan': 'team',  'feature': 'cashier_mode',            'enabled': 1, 'limit_value': 1},
      // businesses
      {'plan': 'free',  'feature': 'businesses',              'enabled': 1, 'limit_value': 1},
      {'plan': 'pro',   'feature': 'businesses',              'enabled': 1, 'limit_value': 3},
      {'plan': 'team',  'feature': 'businesses',              'enabled': 1, 'limit_value': 10},
      // report_history_months (0 = unlimited)
      {'plan': 'free',  'feature': 'report_history_months',   'enabled': 1, 'limit_value': 3},
      {'plan': 'pro',   'feature': 'report_history_months',   'enabled': 1, 'limit_value': 24},
      {'plan': 'team',  'feature': 'report_history_months',   'enabled': 1, 'limit_value': 0},
      // lan_sync
      {'plan': 'free',  'feature': 'lan_sync',                'enabled': 0, 'limit_value': 0},
      {'plan': 'pro',   'feature': 'lan_sync',                'enabled': 1, 'limit_value': 1},
      {'plan': 'team',  'feature': 'lan_sync',                'enabled': 1, 'limit_value': 1},
    ];
    for (final row in rows) {
      await db.insert('plan_features', row, conflictAlgorithm: ConflictAlgorithm.ignore);
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
      // GSP (e-Way Bill Option B) \u2014 disabled by default, consent required.
      'gsp_enabled': '0',
      'gsp_provider': 'masters_india',
      'gsp_consent_given_at': '',
      // Default T&C for PDFs
      'invoice_terms':
          '1. Payment is due within the period stated on this invoice.\n'
          '2. Goods once sold will not be taken back or exchanged.\n'
          '3. Interest @ 18% p.a. will be charged on overdue amounts.\n'
          '4. Subject to local jurisdiction only.\n'
          '5. E. & O.E.',
      'quote_terms':
          '1. This quotation is valid for the period mentioned above.\n'
          '2. Prices are subject to change without prior notice after validity.\n'
          '3. Delivery timelines will be confirmed upon order placement.\n'
          '4. 50% advance required to confirm the order.\n'
          '5. Subject to local jurisdiction only.',
      'booking_terms':
          '1. Booking is confirmed only upon receipt of advance payment.\n'
          '2. Cancellations must be notified at least 48 hours in advance.\n'
          '3. No refunds for last-minute cancellations or no-shows.\n'
          '4. The management reserves the right to modify or cancel bookings.\n'
          '5. Subject to local jurisdiction only.',
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

  /// Seeds the nine built-in [document_templates] presets (4 layout + 5 industry).
  /// Safe to call multiple times — uses INSERT OR IGNORE on the preset names.
  Future<void> _seedDocumentTemplatePresets(Database db) async {
    const now = '2026-01-01T00:00:00.000';
    const presets = <Map<String, Object?>>[
      {
        'name': 'Classic',
        'based_on': 'classic',
        'accent_color_hex': '#1B5E20',
        'header_style': 'banner',
        'show_logo': 1,
        'amount_decimal_digits': 2,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Modern',
        'based_on': 'modern',
        'accent_color_hex': '#1B5E20',
        'header_style': 'minimal',
        'show_logo': 1,
        'amount_decimal_digits': 0,
        'page_size': 'a4',
        'is_active': 1, // default active
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Plain',
        'based_on': 'plain',
        'accent_color_hex': '#000000',
        'header_style': 'minimal',
        'show_logo': 0,
        'amount_decimal_digits': 0,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Thermal Receipt',
        'based_on': 'receipt',
        'accent_color_hex': '#000000',
        'header_style': 'minimal',
        'show_logo': 0,
        'amount_decimal_digits': 0,
        'page_size': 'thermal80',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      // Industry presets
      {
        'name': 'Pharmacy',
        'based_on': 'pharmacy',
        'accent_color_hex': '#006064',
        'header_style': 'banner',
        'show_logo': 1,
        'amount_decimal_digits': 2,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Restaurant',
        'based_on': 'restaurant',
        'accent_color_hex': '#5D4037',
        'header_style': 'banner',
        'show_logo': 1,
        'amount_decimal_digits': 0,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Service',
        'based_on': 'service',
        'accent_color_hex': '#1565C0',
        'header_style': 'minimal',
        'show_logo': 1,
        'amount_decimal_digits': 0,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Freelancer',
        'based_on': 'freelancer',
        'accent_color_hex': '#37474F',
        'header_style': 'minimal',
        'show_logo': 0,
        'amount_decimal_digits': 2,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
      {
        'name': 'Generic',
        'based_on': 'generic',
        'accent_color_hex': '#1B5E20',
        'header_style': 'minimal',
        'show_logo': 1,
        'amount_decimal_digits': 0,
        'page_size': 'a4',
        'is_active': 0,
        'is_preset': 1,
        'created_at': now,
      },
    ];
    for (final row in presets) {
      await db.insert(
        'document_templates',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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

    final payrollCategories = [
      {'name': 'Payroll', 'icon': 'badge', 'color': '#1565C0', 'sort_order': 100, 'keywords': 'salary,wages,payroll,staff'},
      {'name': 'Payroll Deduction', 'icon': 'remove_circle_outline', 'color': '#C62828', 'sort_order': 101, 'keywords': 'tds,pf,esi,deduction'},
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

    for (final cat in payrollCategories) {
      await db.insert('categories', {
        'name': cat['name'],
        'category_type': 'expense',
        'mode': 'both',
        'icon': cat['icon'],
        'color': cat['color'],
        'sort_order': cat['sort_order'],
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
    // Ensure the `code` column exists — it was added to the _onCreate schema
    // later than the v28 migration DDL. Silently ignored if already present.
    try {
      await db.execute('ALTER TABLE unit_types ADD COLUMN code TEXT');
    } catch (_) {
      // Column already exists — ignore.
    }
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

  // ── e-Way Bill ──────────────────────────────────────────────────────────────

  /// Updates only the EWB columns on an invoice row.
  ///
  /// Call this after a successful export/generation to persist the EWB
  /// metadata without touching invoice lines or amounts.
  Future<void> updateEwbFields(
    int invoiceId, {
    String? ewbNo,
    required DateTime ewbGeneratedAt,
    required DateTime ewbValidUntil,
    String? vehicleNo,
    String? transporterName,
    String? transporterGstin,
    required String transportMode,
    int? distanceKm,
  }) async {
    final db = await database;
    await db.update(
      'invoices',
      {
        'ewb_no': ewbNo,
        'ewb_generated_at': ewbGeneratedAt.toIso8601String(),
        'ewb_valid_until': ewbValidUntil.toIso8601String(),
        'vehicle_no': vehicleNo,
        'transporter_name': transporterName,
        'transporter_gstin': transporterGstin,
        'transport_mode': transportMode,
        'distance_km': distanceKm,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  // ── Transporters ──────────────────────────────────────────────────────────

  /// Returns all transporters ordered by most recently used.
  Future<List<Map<String, dynamic>>> getTransporters() async {
    final db = await database;
    return db.query(
      'transporters',
      orderBy: 'last_used_at DESC',
      limit: 30,
    );
  }

  /// Upsert a transporter into the `transporters` table.
  ///
  /// If a transporter with [name] already exists, updates its `last_used_at`
  /// and optionally [gstin]. Otherwise inserts a new row.
  Future<void> saveTransporter({
    required String name,
    String? gstin,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(
      'transporters',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('transporters', {
        'name': name,
        'gstin': gstin,
        'last_used_at': now,
      });
    } else {
      await db.update(
        'transporters',
        {
          'gstin': ?gstin,
          'last_used_at': now,
        },
        where: 'name = ?',
        whereArgs: [name],
      );
    }
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
