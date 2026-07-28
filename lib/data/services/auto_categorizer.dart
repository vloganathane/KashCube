import '../models/parsed_sms.dart';

/// Auto-categorizes transactions based on merchant/party name keywords.
///
/// Maps parsed SMS merchant names to pre-defined categories using
/// keyword matching from the seed category data.
class AutoCategorizer {
  AutoCategorizer._();

  /// Category keyword mappings for expenses.
  static const Map<String, List<String>> _expenseKeywords = {
    'Food & Dining': [
      'swiggy',
      'zomato',
      'restaurant',
      'food',
      'cafe',
      'hotel',
      'dining',
      'dominos',
      'pizza',
      'mcdonalds',
      'kfc',
      'subway',
      'burger',
      'biryani',
      'dine',
      'eat',
      'kitchen',
      'dhaba',
      'canteen',
      'mess',
      'bakery',
      'starbucks',
      'chaayos',
      'chai',
    ],
    'Transportation': [
      'uber',
      'ola',
      'rapido',
      'metro',
      'fuel',
      'petrol',
      'diesel',
      'parking',
      'toll',
      'fastag',
      'irctc',
      'railway',
      'redbus',
      'bus',
      'cab',
      'taxi',
      'auto',
      'rickshaw',
      'flight',
      'makemytrip',
      'goibibo',
      'cleartrip',
      'indigo',
      'spicejet',
      'air india',
    ],
    'Shopping': [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'shopping',
      'meesho',
      'nykaa',
      'tatacliq',
      'reliance',
      'croma',
      'vijay sales',
      'decathlon',
      'fashion',
      'clothing',
      'shoes',
      'electronics',
    ],
    'Bills & Utilities': [
      'electricity',
      'water',
      'gas',
      'internet',
      'broadband',
      'mobile',
      'recharge',
      'airtel',
      'jio',
      'vi ',
      'bsnl',
      'bill',
      'emi',
      'insurance',
      'lic',
      'premium',
      'rent',
      'maintenance',
      'society',
      'housing',
      'loan',
      'tata power',
      'bescom',
      'torrent',
      'adani',
    ],
    'Healthcare': [
      'hospital',
      'pharmacy',
      'medical',
      'doctor',
      'medicine',
      'apollo',
      'medplus',
      'netmeds',
      'pharmeasy',
      '1mg',
      'diagnostic',
      'lab',
      'clinic',
      'health',
      'dental',
      'eye',
      'fortis',
      'max hospital',
    ],
    'Entertainment': [
      'netflix',
      'hotstar',
      'spotify',
      'movie',
      'game',
      'amazon prime',
      'zee5',
      'sonyliv',
      'jiocinema',
      'youtube',
      'inox',
      'pvr',
      'bookmyshow',
      'concert',
      'event',
      'ticket',
      'subscription',
    ],
    'Groceries': [
      'bigbasket',
      'blinkit',
      'zepto',
      'grocery',
      'supermarket',
      'dmart',
      'more',
      'reliance fresh',
      'spar',
      'nature basket',
      'jiomart',
      'swiggy instamart',
      'dunzo',
      'vegetables',
      'fruits',
    ],
    'Education': [
      'school',
      'college',
      'course',
      'book',
      'tuition',
      'udemy',
      'coursera',
      'unacademy',
      'byju',
      'whitehat',
      'coaching',
      'exam',
      'fee',
      'library',
      'stationery',
      'university',
    ],
    'Business Expense': [
      'office',
      'business',
      'supply',
      'vendor',
      'wholesale',
      'trade',
      'stock',
      'inventory',
      'material',
      'equipment',
      'printing',
      'courier',
      'logistics',
      'shipping',
    ],
  };

  /// Keywords for income categories.
  static const Map<String, List<String>> _incomeKeywords = {
    'Salary': ['salary', 'wage', 'pay', 'stipend', 'compensation'],
    'Business Income': [
      'business',
      'revenue',
      'sale',
      'customer',
      'payment received',
    ],
    'Freelance': ['freelance', 'consulting', 'project', 'contract'],
    'Investment': [
      'dividend',
      'interest',
      'mutual fund',
      'stock',
      'fd',
      'rd',
      'sip',
    ],
    'Refund': ['refund', 'return', 'cashback', 'reversal', 'chargeback'],
  };

  /// Categorize a parsed SMS transaction.
  ///
  /// Returns the best-matching category name, or 'Other' / 'Other Income'
  /// as fallback.
  static String categorize(ParsedSms parsed) {
    final partyName = parsed.partyName?.toLowerCase() ?? '';
    final smsBody = parsed.smsBody.toLowerCase();
    final searchText = '$partyName $smsBody';

    if (parsed.isCredit) {
      // Check income keywords
      String bestMatch = 'Other Income';
      int bestScore = 0;
      for (final entry in _incomeKeywords.entries) {
        final score = _matchScore(searchText, entry.value);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = entry.key;
        }
      }
      if (bestScore > 0) return bestMatch;

      // Check for salary-like amounts (common Indian salary ranges on fixed dates)
      if (parsed.sourceType == SmsSourceType.bankAccount ||
          parsed.sourceType == SmsSourceType.neft ||
          parsed.sourceType == SmsSourceType.imps) {
        if (smsBody.contains('salary') || smsBody.contains('sal ')) {
          return 'Salary';
        }
      }

      return 'Other Income';
    } else {
      // Check expense keywords
      String bestMatch = 'Other';
      int bestScore = 0;
      for (final entry in _expenseKeywords.entries) {
        final score = _matchScore(searchText, entry.value);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = entry.key;
        }
      }

      // ATM withdrawals → default to "Other" (cash withdrawal, not a spend)
      if (parsed.sourceType == SmsSourceType.atm) {
        return 'Other';
      }

      return bestMatch;
    }
  }

  /// Score a text against a list of keywords.
  /// Returns the number of keyword matches.
  static int _matchScore(String text, List<String> keywords) {
    int score = 0;
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        score++;
      }
    }
    return score;
  }

  /// Suggest the most likely payment method based on the parsed SMS.
  static String suggestPaymentMethod(ParsedSms parsed) {
    switch (parsed.sourceType) {
      case SmsSourceType.upi:
        return 'UPI';
      case SmsSourceType.creditCard:
        return 'Credit Card';
      case SmsSourceType.debitCard:
        return 'Debit Card';
      case SmsSourceType.atm:
        return 'Cash';
      case SmsSourceType.wallet:
        return 'Wallet';
      case SmsSourceType.neft:
      case SmsSourceType.rtgs:
      case SmsSourceType.imps:
      case SmsSourceType.bankAccount:
        return 'Net Banking';
      case SmsSourceType.unknown:
        return 'UPI'; // Most common in India
    }
  }
}
