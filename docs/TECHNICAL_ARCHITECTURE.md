# Technical Architecture
# ExpenseOwl System Design

**Version:** 1.0  
**Date:** February 24, 2026  
**Status:** Design Phase

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    ExpenseOwl Mobile App                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │              │  │              │  │              │ │
│  │  UI Layer    │──│ Business     │──│   Data       │ │
│  │  (Flutter)   │  │ Logic        │  │   Layer      │ │
│  │              │  │ (Riverpod)   │  │  (SQLite)    │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         │                   │                │         │
│         └───────────────────┴────────────────┘         │
│                            │                           │
│                 ┌──────────┴───────────┐              │
│                 │                      │              │
│          ┌──────▼──────┐      ┌───────▼────────┐     │
│          │             │      │                │     │
│          │ SMS Service │      │  Local Storage │     │
│          │  (Android)  │      │   (Files)      │     │
│          │             │      │                │     │
│          └─────────────┘      └────────────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
               ↑
               │ SMS Broadcasts
               │ (Android System)
```

### 1.2 Design Principles

1. **Privacy-First:** All processing happens on-device
2. **Offline-First:** Works without internet connection
3. **Fast:** <2s app launch, <100ms queries
4. **Reliable:** No data loss, automatic recovery
5. **Scalable:** Handle 50k+ transactions smoothly
6. **Maintainable:** Clean architecture, testable code

---

## 2. Technology Stack

### 2.1 Core Technologies

| Layer | Technology | Reason |
|-------|------------|--------|
| **Frontend** | Flutter 3.16+ | Cross-platform, native performance, hot reload |
| **Language** | Dart 3.2+ | Type-safe, null-safe, async support |
| **State Management** | Riverpod 2.4+ | Testable, compile-safe, best practices |
| **Local Database** | SQLite (sqflite 2.3+) | Fast, reliable, standard for local data |
| **File Storage** | path_provider | Access device directories |
| **SMS Reading** | telephony 0.2.0 | Native SMS access (Android) |
| **Charts** | fl_chart 0.66+ | Beautiful, customizable charts |
| **Authentication** | local_auth 2.1+ | Biometric/PIN support |
| **Date/Time** | intl 0.19+ | Localization, formatting |

### 2.2 Development Tools

-**IDE:** VS Code with Flutter/Dart extensions
- **Version Control:** Git + GitHub
- **Testing:** Flutter test framework
- **Debugging:** Flutter DevTools
- **CI/CD:** GitHub Actions (future)
- **Code Quality:** flutter_lints, dart analyze

---

## 3. Architecture Layers

### 3.1 Presentation Layer (UI)

**Framework:** Flutter  
**Pattern:** MVVM with Riverpod

```
lib/
├── screens/              # Full-page views
│   ├── home/
│   │   ├── home_screen.dart
│   │   └── widgets/
│   ├── transactions/
│   │   ├── transactions_screen.dart
│   │   ├── add_transaction_screen.dart
│   │   └── transaction_detail_screen.dart
│   ├── credits/
│   │   ├── credits_screen.dart
│   │   ├── give_credit_screen.dart
│   │   └── customer_detail_screen.dart
│   ├── reports/
│   │   ├── reports_screen.dart
│   │   └── widgets/
│   └── settings/
│       └── settings_screen.dart
│
├── widgets/              # Reusable components
│   ├── transaction_tile.dart
│   ├── amount_input.dart
│   ├── category_selector.dart
│   ├── quick_confirm_dialog.dart
│   └── charts/
│       ├── pie_chart_widget.dart
│       └── bar_chart_widget.dart
```

**Key Responsibilities:**
- Render UI based on state
- Handle user interactions
- Navigate between screens
- Display notifications

---

### 3.2 Business Logic Layer

**Pattern:** Repository Pattern with Providers

```
lib/
├── providers/            # Riverpod providers
│   ├── transaction_provider.dart
│   ├── credit_provider.dart
│   ├── loan_provider.dart
│   ├── category_provider.dart
│   └── auth_provider.dart
│
├── services/             # Business logic services
│   ├── sms_parser_service.dart
│   ├── categorization_service.dart
│   ├── analytics_service.dart
│   ├── export_service.dart
│   └── backup_service.dart
│
├── repositories/         # Data access layer
│   ├── transaction_repository.dart
│   ├── credit_repository.dart
│   ├── loan_repository.dart
│   └── settings_repository.dart
```

**Key Responsibilities:**
- Parse SMS and extract transaction data
- Categorize transactions intelligently
- Link repayments to credits/loans
- Calculate analytics and insights
- Handle backup/export operations

---

### 3.3 Data Layer

**Database:** SQLite  
**ORM:** Custom (lightweight, specific to needs)

```
lib/
├── database/
│   ├── database_helper.dart        # DB initialization
│   ├── migrations/
│   │   ├── migration_v1.dart
│   │   └── migration_v2.dart
│   └── dao/                        # Data Access Objects
│       ├── transaction_dao.dart
│       ├── credit_dao.dart
│       └── loan_dao.dart
│
├── models/                          # Data models
│   ├── transaction.dart
│   ├── credit_record.dart
│   ├── loan_record.dart
│   ├── party.dart
│   ├── category.dart
│   └── account.dart
```

**Key Responsibilities:**
- Store and retrieve data efficiently
- Maintain data integrity
- Handle migrations
- Provide query interfaces
- Ensure data persistence

---

## 4. Core Components

### 4.1 SMS Parser Service

**Purpose:** Parse financial SMS and extract transaction data

```dart
class SmsParserService {
  // Main parsing function
  ParsedTransaction? parse(String smsBody, String sender) {
    // 1. Identify SMS type
    SmsType type = identifyType(sender, smsBody);
    
    // 2. Apply appropriate parser
    switch (type) {
      case SmsType.upi:
        return parseUpiSms(smsBody);
      case SmsType.creditCard:
        return parseCreditCardSms(smsBody);
      case SmsType.bank:
        return parseBankSms(smsBody);
      default:
        return null;
    }
  }
  
  // UPI SMS parser
  ParsedTransaction? parseUpiSms(String sms) {
    // Extract patterns:
    // - Amount: Rs. 450, Rs.450.00, ₹450
    // - Direction: "paid to", "received from"
    // - Party: name after "to/from"
    // - UPI app: PhonePe, GPay, Paytm
    // - Reference: UPI Ref No, TxnID
  }
  
  // Credit card SMS parser
  ParsedTransaction? parseCreditCardSms(String sms) {
    // Extract patterns:
    // - Amount
    // - Merchant name
    // - Card last 4 digits
    // - Date/time
    // - Available balance
  }
  
  // Confidence scoring
  double calculateConfidence(ParsedTransaction parsed) {
    // High: All fields extracted correctly
    // Medium: Some fields missing
    // Low: Ambiguous or uncertain data
  }
}
```

**SMS Pattern Database:**
```dart
class SmsPatterns {
  static final Map<String, List<RegExp>> patterns = {
    'upi_sent': [
      RegExp(r'Rs\.?\s*(\d+\.?\d*)\s*(?:paid|debited|sent)\s*to\s*(.+?)\s*(?:via|using)\s*(PhonePe|GPay|Paytm)', caseSensitive: false),
      // More patterns...
    ],
    'upi_received': [
      RegExp(r'Rs\.?\s*(\d+\.?\d*)\s*(?:received|credited)\s*from\s*(.+?)\s*(?:via|using)\s*(PhonePe|GPay|Paytm)', caseSensitive: false),
      // More patterns...
    ],
    'credit_card': [
      RegExp(r'Rs\.?\s*(\d+\.?\d*)\s*(?:spent|used|charged)\s*on\s*.+?Card\s*XX(\d{4})\s*at\s*(.+?)\s*on\s*(.+)', caseSensitive: false),
      // More patterns...
    ],
  };
}
```

---

### 4.2 Categorization Service

**Purpose:** Auto-categorize transactions based on merchant name

```dart
class CategorizationService {
  // Merchant keyword mapping
  static final Map<String, String> merchantKeywords = {
    'swiggy': 'Food & Dining',
    'zomato': 'Food & Dining',
    'uber': 'Transport',
    'ola': 'Transport',
    'amazon': 'Shopping',
    'flipkart': 'Shopping',
    'netflix': 'Entertainment',
    'electricity': 'Bills',
    // ... extensive list
  };
  
  String suggestCategory(String merchant, TransactionType type) {
    // 1. Check exact matches
    // 2. Check partial matches
    // 3. Use ML model (future)
    // 4. Default to 'Other'
  }
  
  // Learn from user corrections
  void learnFromCorrection(String merchant, String category) {
    // Update local patterns
    // Improve future suggestions
  }
}
```

---

### 4.3 Credit Linking Service

**Purpose:** Auto-link repayments to pending credits

```dart
class CreditLinkingService {
  Future<CreditSuggestion?> suggestCreditLink(
    ParsedTransaction transaction
  ) async {
    // 1. Check if transaction is "received" type
    if (transaction.type != TransactionType.income) {
      return null;
    }
    
    // 2. Find customers with pending credit
    List<CreditRecord> pending = await creditRepo
        .findPendingByCustomerName(transaction.partyName);
    
    // 3. If match found, suggest linking
    if (pending.isNotEmpty) {
      return CreditSuggestion(
        transaction: transaction,
        creditRecord: pending.first,
        confidence: calculateMatchConfidence(
          transaction.partyName,
          pending.first.customerName
        ),
      );
    }
    
    return null;
  }
  
  double calculateMatchConfidence(String name1, String name2) {
    // Exact match: 1.0
    // Similar (Levenshtein distance): 0.7-0.9
    // Partial match: 0.5-0.7
    // No match: <0.5
  }
}
```

---

### 4.4 Analytics Service

**Purpose:** Generate insights and reports

```dart
class AnalyticsService {
  // Daily summary
  DailySummary getDailySummary(DateTime date) {
    return DailySummary(
      income: totalIncome(date),
      expense: totalExpense(date),
      profit: netProfit(date),
      transactionCount: count(date),
      topCategory: mostSpentCategory(date),
    );
  }
  
  // Monthly report
  MonthlyReport getMonthlyReport(int year, int month) {
    return MonthlyReport(
      income: totalIncome(year, month),
      expense: totalExpense(year, month),
      categoryBreakdown: expenseByCategory(year, month),
      topCustomers: topPayingCustomers(year, month),
      trends: calculateTrends(year, month),
    );
  }
  
  // Insights
  List<Insight> generateInsights() {
    return [
      // "You spend 40% more on weekends"
      // "Peak spending: Friday evenings"
      // "You're trending toward ₹X this month"
    ];
  }
}
```

---

## 5. Data Models

### 5.1 Core Models

**See:** [Database Schema](./DATABASE_SCHEMA.md) for complete schema

```dart
// Transaction Model
class Transaction {
  final int? id;
  final double amount;
  final DateTime date;
  final TransactionType type;        // income, expense, credit_given, etc.
  final TransactionMode mode;        // business, personal
  final String category;
  final String? partyName;
  final String? phoneNumber;
  
  // UPI/SMS details
  final String? upiApp;
  final String? upiRefNo;
  final String? smsBody;
  final String? smsSender;
  final bool autoDetected;
  
  // Linking
  final int? creditId;
  final int? loanId;
  
  // Business
  final bool gstApplicable;
  final double? gstAmount;
  
  // Meta
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

// Credit Record Model
class CreditRecord {
  final int? id;
  final String customerName;
  final String? phoneNumber;
  final double totalAmount;
  final double paidAmount;
  final double pendingAmount;      // totalAmount - paidAmount
  
  final DateTime creditDate;
  final DateTime? dueDate;
  final bool isCleared;
  
  // Optional
  final double? interestRate;
  final double? creditLimit;
  
  // Tracking
  final List<int> transactionIds;  // Related payments
  final String? notes;
}

// Loan Record Model
class LoanRecord {
  final int? id;
  final String lenderName;
  final String? phoneNumber;
  final double principalAmount;
  final double paidAmount;
  final double pendingAmount;
  
  final DateTime loanDate;
  final DateTime? dueDate;
  final bool isCleared;
  
  // Repayment plan
  final double? emiAmount;
  final int? totalEmis;
  final int? paidEmis;
  
  // Interest
  final double? interestRate;
  final InterestType? interestType;
  
  final List<int> transactionIds;
  final String? notes;
}
```

---

## 6. State Management

### 6.1 Riverpod Architecture

```dart
// Transaction Provider
final transactionProvider = StateNotifierProvider<
  TransactionNotifier,
  AsyncValue<List<Transaction>>
>((ref) {
  return TransactionNotifier(
    ref.read(transactionRepositoryProvider),
  );
});

class TransactionNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final TransactionRepository _repository;
  
  TransactionNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadTransactions();
  }
  
  Future<void> loadTransactions() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getAllTransactions());
  }
  
  Future<void> addTransaction(Transaction transaction) async {
    await _repository.insert(transaction);
    await loadTransactions();
  }
  
  // Filtered views
  List<Transaction> get todayTransactions {
    return state.value?.where((t) => isToday(t.date)).toList() ?? [];
  }
  
  List<Transaction> get businessTransactions {
    return state.value?.where((t) => t.mode == TransactionMode.business).toList() ?? [];
  }
}
```

### 6.2 Provider Dependencies

```
App Root
├─ Database Provider (singleton)
│  └─ Repository Providers
│     ├─ Transaction Repository
│     ├─ Credit Repository
│     └─ Loan Repository
│
├─ Service Providers
│  ├─ SMS Parser Service
│  ├─ Categorization Service
│  └─ Analytics Service
│
└─ State Providers
   ├─ Transaction Provider (depends on repo)
   ├─ Credit Provider (depends on repo)
   ├─ Loan Provider (depends on repo)
   └─ Settings Provider
```

---

## 7. Security Architecture

### 7.1 App Security

```dart
class SecurityService {
  // PIN Authentication
  Future<bool> verifyPIN(String pin) async {
    String hashedPIN = await getStoredPIN();
    return hashPIN(pin) == hashedPIN;
  }
  
  // Biometric Authentication
  Future<bool> authenticateBiometric() async {
    final LocalAuthentication auth = LocalAuthentication();
    return await auth.authenticate(
      localizedReason: 'Unlock ExpenseOwl',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }
  
  // Session Management
  void startSession() {
    _lastActivityTime = DateTime.now();
    _startInactivityTimer();
  }
  
  void _startInactivityTimer() {
    Timer.periodic(Duration(minutes: 1), (timer) {
      if (DateTime.now().difference(_lastActivityTime).inMinutes >= 5) {
        lockApp();
        timer.cancel();
      }
    });
  }
}
```

### 7.2 Data Encryption (Optional)

```dart
class EncryptionService {
  // Encrypt sensitive fields
  String encrypt(String plaintext, String key) {
    // AES-256 encryption
  }
  
  String decrypt(String ciphertext, String key) {
    // AES-256 decryption
  }
  
  // Derive encryption key from PIN
  String deriveKeyFromPIN(String pin) {
    // PBKDF2 key derivation
  }
}
```

---

## 8. Performance Optimization

### 8.1 Database Optimization

```sql
-- Indexes for fast queries
CREATE INDEX idx_transactions_date ON transactions(date DESC);
CREATE INDEX idx_transactions_party ON transactions(partyName);
CREATE INDEX idx_transactions_mode ON transactions(mode, type);
CREATE INDEX idx_credits_customer ON credits(customerName);
CREATE INDEX idx_credits_pending ON credits(isCleared, dueDate);

-- Query optimization
-- Use LIMIT for pagination
SELECT * FROM transactions ORDER BY date DESC LIMIT 50 OFFSET 0;

-- Use indexed columns in WHERE clauses
SELECT * FROM transactions WHERE mode = 'business' AND date >= '2026-02-01';
```

### 8.2 UI Performance

```dart
// Pagination for large lists
class TransactionListView extends StatefulWidget {
  @override
  _TransactionListViewState createState() => _TransactionListViewState();
}

class _TransactionListViewState extends State<TransactionListView> {
  static const int pageSize = 50;
  int currentPage = 0;
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        // Load more when reaching end
        if (index == transactions.length - 1) {
          loadNextPage();
        }
        return TransactionTile(transactions[index]);
      },
    );
  }
}

// Lazy loading for images/receipts
class ReceiptImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loadImage(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(snapshot.data);
        }
        return CircularProgressIndicator();
      },
    );
  }
}
```

### 8.3 Memory Management

```dart
// Dispose controllers
@override
void dispose() {
  _amountController.dispose();
  _descriptionController.dispose();
  _scrollController.dispose();
  super.dispose();
}

// Clear caches periodically
void clearOldCaches() {
  // Clear caches older than 7 days
  final cutoff = DateTime.now().subtract(Duration(days: 7));
  _cache.removeWhere((key, value) => value.timestamp.isBefore(cutoff));
}
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

```dart
// Test SMS parser
test('Parse PhonePe UPI SMS correctly', () {
  final sms = 'Paid Rs.450.00 to Swiggy using PhonePe. UPI Ref No 405512345678';
  final parsed = SmsParserService().parse(sms, 'PHONEPE');
  
  expect(parsed?.amount, 450.00);
  expect(parsed?.partyName, 'Swiggy');
  expect(parsed?.upiApp, 'PhonePe');
  expect(parsed?.type, TransactionType.expense);
});

// Test categorization
test('Categorize Swiggy as Food & Dining', () {
  final category = CategorizationService().suggestCategory('Swiggy', TransactionType.expense);
  expect(category, 'Food & Dining');
});
```

### 9.2 Integration Tests

```dart
// Test credit linking flow
testWidgets('Link repayment to credit', (WidgetTester tester) async {
  // 1. Create a credit record
  await creditRepo.insert(CreditRecord(customerName: 'Ramesh', totalAmount: 4000));
  
  // 2. Add a repayment transaction
  await transactionRepo.insert(Transaction(
    amount: 500,
    partyName: 'Ramesh',
    type: TransactionType.income,
  ));
  
  // 3. Verify suggestion is shown
  await tester.pumpAndSettle();
  expect(find.text('Apply to Ramesh\'s credit?'), findsOneWidget);
  
  // 4. Confirm linking
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
  
  // 5. Verify credit is updated
  final credit = await creditRepo.findByCustomer('Ramesh');
  expect(credit?.pendingAmount, 3500);
});
```

### 9.3 Performance Tests

```dart
test('Handle 10,000 transactions smoothly', () async {
  // Insert 10k transactions
  for (int i = 0; i < 10000; i++) {
    await repo.insert(generateRandomTransaction());
  }
  
  // Query should complete in <100ms
  final stopwatch = Stopwatch()..start();
  final results = await repo.getAll();
  stopwatch.stop();
  
  expect(stopwatch.elapsedMilliseconds, lessThan(100));
  expect(results.length, 10000);
});
```

---

## 10. Monitoring & Debugging

### 10.1 Local Logging

```dart
class Logger {
  static void log(String message, {LogLevel level = LogLevel.info}) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] [$level] $message';
    
    // Write to local file (privacy-safe)
    _writeToFile(logMessage);
    
    // Print in debug mode
    if (kDebugMode) {
      print(logMessage);
    }
  }
  
  static void error(String message, dynamic error, StackTrace? stackTrace) {
    log('ERROR: $message\n$error\n$stackTrace', level: LogLevel.error);
  }
}
```

### 10.2 Crash Handling

```dart
void main() {
  // Catch all errors
  FlutterError.onError = (details) {
    Logger.error('Flutter Error', details.exception, details.stack);
  };
  
  runZonedGuarded(() {
    runApp(MyApp());
  }, (error, stackTrace) {
    Logger.error('Unhandled Error', error, stackTrace);
  });
}
```

---

## 11. Deployment Architecture

### 11.1 Build Configuration

```yaml
# build.yaml
android:
  minSdkVersion: 26  # Android 8.0+
  targetSdkVersion: 34  # Android 14
  compileSdkVersion: 34
  
release:
  shrinkResources: true
  minifyEnabled: true
  obfuscate: true
```

### 11.2 Release Process

1. **Version Bump:** Update pubspec.yaml version
2. **Build:** `flutter build apk --release`
3. **Sign:** Sign APK with release keystore
4. **Test:** Manual testing on multiple devices
5. **Upload:** Upload to Play Store
6. **Monitor:** Watch crash reports and reviews

---

## 12. Future Architecture Considerations

### 12.1 Cloud Sync (Optional)
```
Device A                    Encrypted Cloud              Device B
   │                              │                         │
   ├─[Encrypt]──────────────────►│                         │
   │   Local Data                 │◄───[Decrypt]───────────┤
   │                              │    Local Data           │
   │                        [End-to-End                     │
   │                       Encrypted Storage]               │
```

### 12.2 Multi-Platform
- **iOS:** Reuse 90% of Flutter code
- **Web:** Dashboard view only (no SMS)
- **Desktop:** Backup management

### 12.3 Extensibility
- Plugin architecture for custom parsers
- API for third-party integrations
- Export format extensions

---

**Next Document:** [Database Schema](./DATABASE_SCHEMA.md)
