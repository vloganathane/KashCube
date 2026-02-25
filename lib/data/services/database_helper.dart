import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
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

    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
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
        sms_body TEXT,
        sms_sender TEXT,
        upi_app TEXT,
        upi_ref_no TEXT,
        reference_id TEXT,
        auto_detected INTEGER DEFAULT 0,
        verified INTEGER DEFAULT 0,
        credit_id INTEGER,
        loan_id INTEGER,
        parent_transaction_id INTEGER,
        dedupe_hash TEXT UNIQUE,
        notes TEXT,
        tags TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY (party_id) REFERENCES parties(id),
        FOREIGN KEY (account_id) REFERENCES accounts(id),
        FOREIGN KEY (credit_id) REFERENCES credits(id),
        FOREIGN KEY (parent_transaction_id) REFERENCES transactions(id)
      )
    ''');

    await db.execute('CREATE INDEX idx_transactions_date ON transactions(date DESC)');
    await db.execute('CREATE INDEX idx_transactions_party ON transactions(party_name)');
    await db.execute('CREATE INDEX idx_transactions_mode_type ON transactions(mode, type, date DESC)');
    await db.execute('CREATE INDEX idx_transactions_category ON transactions(category, date DESC)');
    await db.execute('CREATE INDEX idx_transactions_auto_detected ON transactions(auto_detected, verified)');
    await db.execute('CREATE INDEX idx_transactions_deleted ON transactions(deleted_at)');

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

    // -- loans table
    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        party_type TEXT NOT NULL DEFAULT 'customer',
        total_transactions INTEGER DEFAULT 0,
        total_transaction_amount REAL DEFAULT 0,
        total_credit_given REAL DEFAULT 0,
        total_credit_received REAL DEFAULT 0,
        notes TEXT,
        tags TEXT,
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
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        period TEXT NOT NULL DEFAULT 'monthly',
        start_date TEXT NOT NULL,
        end_date TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT
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

    // -- schema_version table
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL DEFAULT (datetime('now')),
        description TEXT
      )
    ''');

    await db.insert('schema_version', {
      'version': 5,
      'description': 'Add bills table for scheduled payments',
    });

    // Seed default categories
    await _seedCategories(db);

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
  }

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

  /// Close the database connection.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
