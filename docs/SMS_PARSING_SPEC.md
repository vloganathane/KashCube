# SMS Parsing Specification
# Kash Cube SMS Parser

**Version:** 1.0  
**Date:** February 24, 2026  
**Supported:** India (UPI, Banks, Credit Cards)

---

## 1. Overview

### 1.1 Purpose
Parse financial transaction SMS from Indian banks, UPI apps, and credit cards to automatically extract:
- Transaction amount
- Merchant/party name
- Transaction type (sent/received, debit/credit)
- Date and time
- Payment method
- Reference numbers
- Account/card information

### 1.2 Scope
**Supported SMS Types:**
- UPI transactions (PhonePe, GPay, Paytm, BHIM)
- Credit card transactions
- Debit card transactions  
- Bank account debits/credits
- ATM withdrawals
- NEFT/RTGS/IMPS transfers
- Wallet transactions

**Out of Scope (MVP):**
- International transactions
- Complex investment transactions
- Bitcoin/cryptocurrency
- Cheque clearances (future)

---

## 2. Sender ID Registry

### 2.1 UPI Apps

| UPI App | Sender ID | Pattern |
|---------|-----------|---------|
| PhonePe | PHONEPE, PHPEPP | Various |
| Google Pay | GPAY, GOOGLEPAY | Various |
| Paytm | PAYTM, PYTMPS | Various |
| BHIM | UPIAPP, BHIM | Various |
| Amazon Pay | AMPAY, AZPUPI | Various |

### 2.2 Banks

| Bank | Sender ID | Accounts |
|------|-----------|----------|
| HDFC Bank | HDFCBK, HDFCCC | Savings, Credit Card |
| ICICI Bank | ICICIB, ICICIC | Savings, Credit Card |
| SBI | SBISEC, SBICRD | Savings, Credit Card |
| Axis Bank | AXISBK, AXISCC | Savings, Credit Card |
| Kotak Mahindra | KOTAKB, KOTAKC | Savings, Credit Card |
| PNB | PNBSMS, PNBCC | Savings, Credit Card |
| Bank of Baroda | BOISMS, BOBSMS | Savings, Credit Card |
| IndusInd Bank | INDBNK, INDCC | Savings, Credit Card |

### 2.3 Wallets

| Wallet | Sender ID |
|--------|-----------|
| Paytm Wallet | PAYTMW |
| Amazon Pay  | AMPAY |
| MobiKwik | MOBIKW |
| Freecharge | FREPAY |

---

## 3. SMS Patterns

### 3.1 UPI Transactions

#### 3.1.1 PhonePe - Money Sent

**Pattern:**
```
Paid Rs.{amount} to {merchant} using PhonePe. UPI Ref No {ref}
Rs.{amount} debited from PhonePe on {date}. UPI:{ref}
```

**Regex:**
```dart
RegExp(
  r'(?:Paid|debited)\s*Rs\.?\s*(\d+(?:\.\d{2})?)\s*(?:to|from)\s*([^.]+?)\s*(?:using|via)?\s*PhonePe',
  caseSensitive: false
)
```

**Extraction:**
- Group 1: Amount (450.00)
- Group 2: Merchant (Swiggy)
- Direction: SENT
- App: PhonePe

**Example SMS:**
```
Paid Rs.450.00 to Swiggy using PhonePe. 
UPI Ref No 405512345678
```

**Parsed Result:**
```dart
{
  amount: 450.00,
  partyName: "Swiggy",
  direction: TransactionDirection.sent,
  upiApp: "PhonePe",
  upiRefNo: "405512345678",
  date: DateTime.now(),
  confidence: 1.0
}
```

#### 3.1.2 PhonePe - Money Received

**Pattern:**
```
Received Rs.{amount} from {person} via PhonePe. UPI:{ref}
Rs.{amount} credited to PhonePe on {date}. UPI:{ref}
```

**Regex:**
```dart
RegExp(
  r'(?:Received|credited)\s*Rs\.?\s*(\d+(?:\.\d{2})?)\s*(?:from|to)\s*([^.]+?)\s*(?:via|using)?\s*PhonePe',
  caseSensitive: false
)
```

#### 3.1.3 Google Pay - Money Sent

**Pattern:**
```
You paid Rs. {amount} to {merchant}. Google Pay UPI ID: {upi_id}
Your payment of Rs {amount} to {merchant} was successful
```

**Example:**
```
You paid Rs. 1,250 to Reliance Digital
Google Pay UPI ID: merchant@paytm
```

#### 3.1.4 Google Pay - Money Received

**Pattern:**
```
{name} paid you Rs. {amount} via Google Pay
You received Rs {amount} from {name}
```

#### 3.1.5 Paytm UPI

**Pattern:**
```
Rs. {amount} paid to {merchant} via Paytm
Dear Customer, Rs.{amount} has been debited from your account to {merchant}
TxnID: {id}
```

**Example:**
```
Rs. 85 paid to Metro Card via Paytm
TxnID: T2024022412345678
```

---

### 3.2 Credit Card Transactions

#### 3.2.1 HDFC Credit Card

**Pattern:**
```
Rs.{amount} spent on HDFC Bank Credit Card XX{last4} at {merchant} on {date}. 
Avl bal: Rs.{balance}
```

**Regex:**
```dart
RegExp(
  r'Rs\.?\s*(\d+(?:\.\d{2})?)\s*(?:spent|used)\s*on\s*HDFC\s*Bank\s*Credit\s*Card\s*XX(\d{4})\s*at\s*([^.]+?)\s*on\s*(\d{2}-[A-Za-z]{3}-\d{2})',
  caseSensitive: false
)
```

**Example:**
```
Rs.2,450.00 spent on HDFC Bank Credit Card XX1234 
at AMAZON on 24-Feb-26. Avl bal: Rs.45,000
```

**Parsed Result:**
```dart
{
  amount: 2450.00,
  partyName: "AMAZON",
  cardLast4: "1234",
  date: DateTime(2026, 2, 24),
  availableBalance: 45000.00,
  confidence: 1.0
}
```

#### 3.2.2 ICICI Credit Card

**Pattern:**
```
ICICI Bank Credit Card XX{last4} used for Rs {amount} at {merchant} on {date}
```

**Example:**
```
ICICI Bank Credit Card XX5678 used for Rs 1,250.00 
at SWIGGY on 24-02-2026 15:30
```

#### 3.2.3 SBI Credit Card

**Pattern:**
```
Your SBI Card XX{last4} is used for INR {amount} at {merchant} {date} at {time}
```

**Example:**
```
Your SBI Card XX9012 is used for INR 850.00 
at UBER INDIA 24FEB at 14:25
```

---

### 3.3 Debit Card / Bank Account

#### 3.3.1 HDFC Bank - Debit Card

**Pattern:**
```
Rs.{amount} debited from A/c XX{last4} on {date} via Debit Card at {merchant}. 
Avl Bal: Rs.{balance}
```

**Example:**
```
Rs.3,500.00 debited from A/c XX1234 on 24-Feb-26 
via Debit Card at BIG BAZAAR. Avl Bal: Rs.45,230.50
```

#### 3.3.2 Bank - Direct Debit/Credit

**Pattern (Credit):**
```
Rs.{amount} credited to A/c XX{last4} on {date}. Info: {description}. Avl Bal: Rs.{balance}
```

**Example:**
```
Rs.75,000.00 credited to A/c XX1234 on 24-Feb-26. 
Info: SALARY FEB26. Avl Bal: Rs.1,25,450
```

**Pattern (Debit):**
```
Rs.{amount} debited from A/c XX{last4} for {description}. Ref: {ref}
```

**Example:**
```
Rs.2,350 debited from A/c XX1234 for Electricity Bill Payment. 
Ref: EB202602241234
```

---

### 3.4 NEFT/RTGS/IMPS

**Pattern:**
```
Rs.{amount} {credited|debited} via {NEFT|RTGS|IMPS} {from|to} {party} A/c XX{last4}. 
Ref: {ref}
```

**Example:**
```
Rs.15,000 credited via NEFT from RAMESH KUMAR A/c XX5678. 
Ref: N045123456789
```

---

### 3.5 ATM Withdrawal

**Pattern:**
```
Rs.{amount} withdrawn from {bank} ATM at {location} on {date} from A/c XX{last4}. 
Avl Bal: Rs.{balance}
```

**Example:**
```
Rs.5,000.00 withdrawn from HDFC ATM at KORAMANGALA 
on 24-Feb-26 from A/c XX1234. Avl Bal: Rs.40,230
```

---

### 3.6 Wallet Transactions

#### 3.6.1 Paytm Wallet

**Pattern (Load):**
```
Rs {amount} added to your Paytm Wallet via UPI{ref}
```

**Pattern (Spend):**
```
Rs {amount} paid from Paytm Wallet to {merchant}
```

**Example:**
```
Rs 250 added to your Paytm Wallet via UPI123456
Rs 85 paid from Paytm Wallet to Metro Card
```

#### 3.6.2 Amazon Pay

**Pattern:**
```
Amazon Pay balance Rs.{amount} added successfully
```

---

## 4. Parsing Logic

### 4.1 Parser Flow

```
SMS Received
    │
    ▼
Identify Sender ID ────► Not Financial? ──► Ignore
    │                        
    ▼ Financial SMS
    │
Extract SMS Type (UPI, CC, Bank, etc.)
    │
    ▼
Apply Type-Specific Regex Patterns
    │
    ▼
Extract Fields:
- Amount
- Party/Merchant
- Direction (sent/received)
- Date
- Reference
- Account/Card info
    │
    ▼
Calculate Confidence Score
    │
    ▼
Return ParsedTransaction object
```

### 4.2 Confidence Scoring

```dart
double calculateConfidence(ParsedTransaction parsed) {
  double score = 0.0;
  
  // Amount extracted correctly (required)
  if (parsed.amount != null && parsed.amount! > 0) {
    score += 0.4;
  } else {
    return 0.0;  // Must have amount
  }
  
  // Party name extracted
  if (parsed.partyName != null && parsed.partyName!.isNotEmpty) {
    score += 0.3;
  }
  
  // Direction determined
  if (parsed.direction != null) {
    score += 0.15;
  }
  
  // Reference number extracted
  if (parsed.referenceId != null) {
    score += 0.10;
  }
  
  // Date extracted
  if (parsed.date != null) {
    score += 0.05;
  }
  
  return score;  // 0.0 to 1.0
}

enum ConfidenceLevel {
  high,     // >= 0.85
  medium,   // >= 0.65
  low,      // >= 0.40
  veryLow   // < 0.40 (show warning)
}
```

### 4.3 Field Extraction Functions

```dart
class FieldExtractor {
  // Extract amount
  static double? extractAmount(String sms) {
    // Pattern: Rs. 450, Rs.450.00, ₹450, INR 450
    final patterns = [
      RegExp(r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{2})?)'),
      RegExp(r'₹\s*(\d+(?:,\d+)*(?:\.\d{2})?)'),
      RegExp(r'INR\s*(\d+(?:,\d+)*(?:\.\d{2})?)')
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        String amountStr = match.group(1)!.replaceAll(',', '');
        return double.tryParse(amountStr);
      }
    }
    return null;
  }
  
  // Extract merchant/party name
  static String? extractParty(String sms, TransactionDirection direction) {
    if (direction == TransactionDirection.sent) {
      // Look for "to {name}"
      final pattern = RegExp(r'(?:to|at)\s+([A-Z][A-Za-z0-9\s]+?)(?:\s+(?:using|via|on|UPI)|$)');
      final match = pattern.firstMatch(sms);
      return match?.group(1)?.trim();
    } else {
      // Look for "from {name}"
      final pattern = RegExp(r'from\s+([A-Z][A-Za-z\s]+?)(?:\s+(?:via|using|A/c)|$)');
      final match = pattern.firstMatch(sms);
      return match?.group(1)?.trim();
    }
  }
  
  // Extract UPI reference number
  static String? extractUpiRef(String sms) {
    final patterns = [
      RegExp(r'UPI\s*Ref\s*No\.?\s*(\w+)'),
      RegExp(r'UPI:\s*(\w+)'),
      RegExp(r'TxnID:\s*(\w+)'),
      RegExp(r'Ref:\s*([A-Z0-9]+)')
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
  
  // Extract date
  static DateTime? extractDate(String sms) {
    // Pattern: 24-Feb-26, 24-02-2026, 24FEB
    final patterns = [
      RegExp(r'(\d{2})-([A-Za-z]{3})-(\d{2})'),  // 24-Feb-26
      RegExp(r'(\d{2})-(\d{2})-(\d{4})'),        // 24-02-2026
      RegExp(r'(\d{2})([A-Z]{3})'),              // 24FEB
    ];
    
    // Try to parse, fallback to current date if not found
    // (Most SMS are received immediately after transaction)
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        // Parse logic here
        return parseDateFromMatch(match);
      }
    }
    
    return DateTime.now();  // Default to now
  }
  
  // Extract card/account last 4 digits
  static String? extractLast4(String sms) {
    final pattern = RegExp(r'XX(\d{4})');
    final match = pattern.firstMatch(sms);
    return match?.group(1);
  }
  
  // Extract balance
  static double? extractBalance(String sms) {
    final pattern = RegExp(r'(?:Avl\s*Bal|Available\s*[Bb]alance|Bal):\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{2})?)');
    final match = pattern.firstMatch(sms);
    if (match != null) {
      String balStr = match.group(1)!.replaceAll(',', '');
      return double.tryParse(balStr);
    }
    return null;
  }
}
```

---

## 5. Edge Cases & Error Handling

### 5.1 Common Edge Cases

1. **Multiple amounts in one SMS**
   ```
   Rs.450 spent, GST Rs.45, Total: Rs.495
   ```
   **Solution:** Extract the largest amount or use context

2. **Ambiguous party names**
   ```
   Paid to A
   ```
   **Solution:** Mark as low confidence, ask user

3. **Foreign transactions**
   ```
   $50.00 spent at AMAZON US
   ```
   **Solution:** Ignore or convert (future)

4. **Similar SMS for pending and completed**
   ```
   SMS 1: "Transaction pending"
   SMS 2: "Transaction successful"
   ```
   **Solution:** Deduplicate based on amount + date + merchant

5. **Merchant name variations**
   ```
   SWIGGY BANGALORE
   SWIGGY*DELIVE
   Swiggy Food Pvt Ltd
   ```
   **Solution:** Fuzzy matching, normalize names

### 5.2 Error Handling

```dart
class SmsParsingException implements Exception {
  final String message;
  final String sms;
  final String? sender;
  
  SmsParsingException(this.message, this.sms, [this.sender]);
}

ParsedTransaction? parseSafely(String sms, String sender) {
  try {
    return parse(sms, sender);
  } on SmsParsingException catch (e) {
    Logger.error('SMS parsing failed', e, StackTrace.current);
    return null;
  } catch (e) {
    Logger.error('Unexpected error parsing SMS', e, StackTrace.current);
    return null;
  }
}
```

---

## 6. Deduplication Strategy

### 6.1 Duplicate Detection

**Problem:** Same transaction might generate multiple SMS:
- UPI app SMS
- Bank account debit SMS
- Both within seconds

**Solution:**
```dart
String generateDedupeHash(ParsedTransaction parsed) {
  // Combine: amount + date (to minute) + merchant + direction
  final dateKey = '${parsed.date.year}-${parsed.date.month}-${parsed.date.day}-${parsed.date.hour}-${parsed.date.minute}';
  final merchantKey = parsed.partyName?.toLowerCase().replaceAll(RegExp(r'\W'), '') ?? '';
  final key = '${parsed.amount}-$dateKey-$merchantKey-${parsed.direction}';
  
  return sha256.convert(utf8.encode(key)).toString();
}

Future<bool> isDuplicate(ParsedTransaction parsed) async {
  final hash = generateDedupeHash(parsed);
  final existing = await db.query(
    'transactions',
    where: 'dedupe_hash = ? AND created_at > datetime("now", "-5 minutes")',
    whereArgs: [hash],
  );
  return existing.isNotEmpty;
}
```

### 6.2 Merge Duplicates

```dart
Transaction mergeDuplicates(Transaction t1, Transaction t2) {
  return Transaction(
    // Use more complete data
    amount: t1.amount,
    partyName: t1.partyName ?? t2.partyName,
    upiRefNo: t1.upiRefNo ?? t2.upiRefNo,
    smsBody: '${t1.smsBody}\n---\n${t2.smsBody}',  // Keep both
    referenceId: '${t1.referenceId}, ${t2.referenceId}',
    confidence: max(t1.confidence, t2.confidence),
  );
}
```

---

## 7. Pattern Database Extensibility

### 7.1 User-Contributed Patterns

```dart
class PatternDatabase {
  // Community-contributed patterns
  static Future<void> submitNewPattern({
    required String bankName,
    required String senderID,
    required String sampleSMS,
    required String regex,
  }) async {
    // Submit to community database
    // After review, add to app in next update
  }
  
  // Download updated patterns
  static Future<void> updatePatterns() async {
    // Download from GitHub/server
    // Merge with built-in patterns
  }
}
```

### 7.2 Custom Parser (Advanced Users)

```yaml
# custom_parsers.yaml
- name: My Bank Custom
  sender: MYBANK
  patterns:
    - regex: 'Rs\.(\d+\.\d{2}) paid to (.+) on (\d{2}-\d{2}-\d{4})'
      amount: 1
      merchant: 2
      date: 3
```

---

## 8. Testing

### 8.1 Unit Tests

```dart
group('SMS Parser Tests', () {
  test('Parse PhonePe sent transaction', () {
    final sms = 'Paid Rs.450.00 to Swiggy using PhonePe. UPI Ref No 405512345678';
    final result = SmsParser().parse(sms, 'PHONEPE');
    
    expect(result?.amount, 450.00);
    expect(result?.partyName, 'Swiggy');
    expect(result?.direction, TransactionDirection.sent);
    expect(result?.upiApp, 'PhonePe');
    expect(result?.confidence, greaterThanOrEqualTo(0.85));
  });
  
  test('Parse HDFC credit card transaction', () {
    final sms = 'Rs.2,450.00 spent on HDFC Bank Credit Card XX1234 at AMAZON on 24-Feb-26';
    final result = SmsParser().parse(sms, 'HDFCCC');
    
    expect(result?.amount, 2450.00);
    expect(result?.partyName, 'AMAZON');
    expect(result?.cardLast4, '1234');
  });
  
  test('Handle malformed SMS gracefully', () {
    final sms = 'This is not a transaction SMS';
    final result = SmsParser().parse(sms, 'UNKNOWN');
    
    expect(result, isNull);
  });
});
```

### 8.2 Real SMS Test Suite

```dart
class RealSmsTests {
  // Collection of 100+ real SMS samples
  static List<TestCase> getTestCases() {
    return [
      TestCase(
        sms: 'Actual SMS from user 1',
        expectedAmount: 450.00,
        expectedMerchant: 'Swiggy',
      ),
      // ... 100+ cases
    ];
  }
  
  static Future<TestReport> runAllTests() async {
    // Run parser against all real SMS
    // Report accuracy, failures, edge cases
  }
}
```

---

## 9. Performance Considerations

### 9.1 Optimization

- **Regex compilation:** Pre-compile all regex patterns at app start
- **Parallel processing:** Parse multiple buffered SMS concurrently
- **Caching:** Cache extracted data to avoid re-parsing
- **Lazy patterns:** Load bank-specific patterns only when needed

```dart
class OptimizedParser {
  // Pre-compiled patterns
  static final Map<String, List<RegExp>> _compiledPatterns = {};
  
  static Future<void> precompilePatterns() async {
    // Compile all patterns once at app start
    for (var bank in supportedBanks) {
      _compiledPatterns[bank] = compilePatterns(bank);
    }
  }
  
  // Fast lookup
  ParsedTransaction? parse(String sms, String sender) {
    final patterns = _compiledPatterns[sender];
    if (patterns == null) return null;
    
    for (var pattern in patterns) {
      // Try each pattern
      final match = pattern.firstMatch(sms);
      if (match != null) {
        return extractFromMatch(match);
      }
    }
    return null;
  }
}
```

### 9.2 Target Performance

- Parse SMS: <100ms
- Handle batch of 100 SMS: <5 seconds
- Memory usage: <10 MB for parser

---

## 10. Roadmap

### Phase 1 (MVP) - Covered in this spec
- UPI (top 4 apps)
- Credit cards (top 5 banks)
- Basic bank transactions

### Phase 2
- More banks (20+ total)
- Wallet transactions
- Investment transactions (MF, stocks)
- Bill payments

### Phase 3
- ML-based parsing
- OCR for receipt SMS images
- Multi-language SMS support
- International transactions

---

**Next Document:** [MVP Scope](./MVP_SCOPE.md)
