import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/parsed_sms.dart';
import 'app_logger.dart';

/// Parses financial SMS from Indian banks and UPI apps.
///
/// Supports:
/// - UPI apps: PhonePe, Google Pay, Paytm, BHIM, Amazon Pay
/// - Banks: HDFC, ICICI, SBI, Axis, Kotak, PNB, BOB, IndusInd
/// - Credit/Debit card transactions
/// - NEFT/RTGS/IMPS transfers
/// - ATM withdrawals
/// - Wallet transactions
class SmsParser {
  SmsParser._();

  // ---------------------------------------------------------------------------
  // Sender ID Registry
  // ---------------------------------------------------------------------------

  /// Known financial SMS sender IDs mapped to their institution.
  static const Map<String, String> _senderRegistry = {
    // UPI Apps
    'PHONEPE': 'PhonePe',
    'PHPEPP': 'PhonePe',
    'GPAY': 'Google Pay',
    'GOOGLEPAY': 'Google Pay',
    'PAYTM': 'Paytm',
    'PYTMPS': 'Paytm',
    'UPIAPP': 'BHIM',
    'BHIM': 'BHIM',
    'AMPAY': 'Amazon Pay',
    'AZPUPI': 'Amazon Pay',
    // Banks - Savings
    'HDFCBK': 'HDFC Bank',
    'ICICIB': 'ICICI Bank',
    'SBISEC': 'SBI',
    'SBIBNK': 'SBI',
    'AXISBK': 'Axis Bank',
    'KOTAKB': 'Kotak Bank',
    'PNBSMS': 'PNB',
    'BOISMS': 'Bank of Baroda',
    'BOBSMS': 'Bank of Baroda',
    'INDBNK': 'IndusInd Bank',
    // Banks - Credit Card
    'HDFCCC': 'HDFC Credit Card',
    'ICICIC': 'ICICI Credit Card',
    'SBICRD': 'SBI Credit Card',
    'AXISCC': 'Axis Credit Card',
    'KOTAKC': 'Kotak Credit Card',
    'PNBCC': 'PNB Credit Card',
    'INDCC': 'IndusInd Credit Card',
    // Wallets
    'PAYTMW': 'Paytm Wallet',
    'MOBIKW': 'MobiKwik',
    'FREPAY': 'Freecharge',
    // Neo-banks & modern UPI apps
    'FIMONY': 'Fi Money',
    'FIMNBY': 'Fi Money',
    'SLICEP': 'Slice',
    'SLICEB': 'Slice',
    'JUPBNK': 'Jupiter',
    'JUPITE': 'Jupiter',
    'ONECRD': 'OneCard',
    'ONECRD1': 'OneCard',
    'IDFCBK': 'IDFC First Bank',
    'IDFCFB': 'IDFC First Bank',
    'YESBNK': 'Yes Bank',
    'YESBK': 'Yes Bank',
    'RBLBNK': 'RBL Bank',
    'CENTBK': 'Central Bank of India',
    'CANBNK': 'Canara Bank',
    'UNIONB': 'Union Bank',
    'BANDAN': 'Bandhan Bank',
  };

  // ---------------------------------------------------------------------------
  // Pre-compiled Regex Patterns
  // ---------------------------------------------------------------------------

  // Amount extraction patterns
  static final _amountPatterns = [
    RegExp(r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)', caseSensitive: false),
    RegExp(r'₹\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)', caseSensitive: false),
    RegExp(r'INR\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)', caseSensitive: false),
  ];

  // UPI reference patterns
  static final _upiRefPatterns = [
    RegExp(r'UPI\s*Ref\s*(?:No\.?|:)\s*(\w+)', caseSensitive: false),
    RegExp(r'UPI:\s*(\w+)', caseSensitive: false),
    RegExp(r'TxnID:\s*(\w+)', caseSensitive: false),
    RegExp(r'Txn\s*ID\s*:\s*(\w+)', caseSensitive: false),
  ];

  // Generic reference patterns
  static final _refPatterns = [
    ...(_upiRefPatterns),
    RegExp(r'Ref:\s*([A-Z0-9]+)', caseSensitive: false),
    RegExp(r'Ref\s*No\.?\s*:\s*([A-Z0-9]+)', caseSensitive: false),
  ];

  // Card / Account last 4
  static final _last4Pattern = RegExp(r'XX(\d{4})');

  // Available balance
  static final _balancePattern = RegExp(
    r'(?:Avl\s*Bal|Available\s*[Bb]alance|Bal|A/c\s*bal)[\s:]*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Date patterns
  static final _datePatterns = [
    RegExp(r'(\d{2})-([A-Za-z]{3})-(\d{2,4})'),  // 24-Feb-26 or 24-Feb-2026
    RegExp(r'(\d{2})-(\d{2})-(\d{4})'),           // 24-02-2026
    RegExp(r'(\d{2})/(\d{2})/(\d{4})'),           // 24/02/2026
    RegExp(r'(\d{2})([A-Z]{3})\b'),               // 24FEB
  ];

  // ----------- UPI Patterns -----------

  // PhonePe Sent
  static final _phonePeSent = RegExp(
    r'(?:Paid|debited)\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:to|from)\s+(.+?)\s*(?:using|via)\s*PhonePe',
    caseSensitive: false,
  );

  // PhonePe Received
  static final _phonePeReceived = RegExp(
    r'(?:Received|credited)\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:from|to)\s+(.+?)\s*(?:via|using)\s*PhonePe',
    caseSensitive: false,
  );

  // Google Pay Sent
  static final _gpaySent = RegExp(
    r'(?:You\s+paid|paid)\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*to\s+(.+?)(?:\.\s*Google\s*Pay|$)',
    caseSensitive: false,
  );

  // Google Pay Received
  static final _gpayReceived = RegExp(
    r'(.+?)\s*paid\s+you\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:via|through)\s*Google\s*Pay',
    caseSensitive: false,
  );

  // Google Pay Received (alternate) — only matched when dispatched from a known
  // Google Pay sender ID (GPAY / GOOGLEPAY). The pattern is intentionally NOT
  // used in the generic fallback to avoid false positives on non-financial SMS.
  static final _gpayReceivedAlt = RegExp(
    r'(?:You\s+)?received\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*from\s+([A-Za-z][A-Za-z0-9 .&\-]{1,40}?)(?:\s*(?:via|through|on|\.|\n)|$)',
    caseSensitive: false,
  );

  // Paytm Sent
  static final _paytmSent = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:paid|debited)\s*(?:to|from)\s+(.+?)\s*(?:via|using)\s*Paytm',
    caseSensitive: false,
  );

  // BHIM Sent
  static final _bhimSent = RegExp(
    r'(?:Paid|Sent)\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*to\s+(.+?)\s*(?:via|using)\s*(?:BHIM|UPI)',
    caseSensitive: false,
  );

  // Generic UPI Sent
  static final _genericUpiSent = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:debited|sent|paid)\s*(?:from|to)\s+(.+?)\s*(?:via\s*UPI|UPI)',
    caseSensitive: false,
  );

  // Generic UPI Received
  static final _genericUpiReceived = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:credited|received)\s*(?:to|from)\s+(.+?)\s*(?:via\s*UPI|UPI)',
    caseSensitive: false,
  );

  // ----------- Credit Card Patterns -----------

  // HDFC Credit Card
  static final _hdfcCc = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:spent|used)\s*on\s*HDFC\s*Bank\s*Credit\s*Card\s*XX(\d{4})\s*at\s+(.+?)\s*on\s*(\d{2}-[A-Za-z]{3}-\d{2,4})',
    caseSensitive: false,
  );

  // ICICI Credit Card
  static final _iciciCc = RegExp(
    r'ICICI\s*Bank\s*Credit\s*Card\s*XX(\d{4})\s*used\s*for\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*at\s+(.+?)\s*on\s*(\d{2}-\d{2}-\d{4})',
    caseSensitive: false,
  );

  // SBI Credit Card
  static final _sbiCc = RegExp(
    r'(?:Your\s+)?SBI\s*Card\s*XX(\d{4})\s*(?:is\s*)?used\s*for\s*(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*at\s+(.+?)(?:\s+\d{2}[A-Z]{3}|\s+on)',
    caseSensitive: false,
  );

  // Generic Credit Card spend
  static final _genericCcSpend = RegExp(
    r'(?:Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:spent|used|charged)\s*on\s*.*?Credit\s*Card\s*XX(\d{4})\s*(?:at)?\s+(.+?)(?:\s+on\s+|$))',
    caseSensitive: false,
  );

  // ----------- Bank Account Patterns -----------

  // Debit from account
  static final _bankDebit = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:debited|withdrawn)\s*from\s*(?:A/c|(?:your\s+)?account|Acct)\s*(?:XX)?(\d{4})\s*(?:on\s+\S+\s*)?(?:via\s+\w+\s+(?:Card\s+)?at\s+(.+?)|for\s+(.+?))(?:\.\s*|$)',
    caseSensitive: false,
  );

  // Credit to account
  static final _bankCredit = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*credited\s*to\s*(?:A/c|(?:your\s+)?account|Acct)\s*(?:XX)?(\d{4})\s*(?:on\s+\S+)?(?:\.\s*Info:\s*(.+?))?\.',
    caseSensitive: false,
  );

  // Simpler bank debit pattern
  static final _bankDebitSimple = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*debited\s*from\s*(?:A/c|account)\s*XX(\d{4})',
    caseSensitive: false,
  );

  // Simpler bank credit pattern
  static final _bankCreditSimple = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*credited\s*to\s*(?:A/c|account)\s*XX(\d{4})',
    caseSensitive: false,
  );

  // ----------- NEFT/RTGS/IMPS Patterns -----------

  static final _neftImps = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(credited|debited)\s*(?:via|through)\s*(NEFT|RTGS|IMPS)\s*(?:from|to)\s+(.+?)\s*(?:A/c|$)',
    caseSensitive: false,
  );

  // ----------- ATM Withdrawal -----------

  static final _atmWithdrawal = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*withdrawn\s*(?:from\s+\w+\s+ATM\s+at\s+(.+?)\s+on|at\s*ATM)',
    caseSensitive: false,
  );

  // ----------- Wallet Patterns -----------

  // Wallet spend
  static final _walletSpend = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*(?:paid|spent)\s*from\s+(\w+)\s*Wallet\s*to\s+(.+?)$',
    caseSensitive: false,
  );

  // Wallet load/add
  static final _walletLoad = RegExp(
    r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s*added\s*to\s*(?:your\s+)?(\w+)\s*(?:Wallet|Pay)',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Checks if a sender ID is a known financial SMS sender.
  static bool isFinancialSender(String sender) {
    final normalized = _normalizeSender(sender);
    return _senderRegistry.containsKey(normalized);
  }

  /// Parses an SMS body from a known sender. Returns null if not parseable.
  static ParsedSms? parse(String smsBody, String sender) {
    try {
      final normalizedSender = _normalizeSender(sender);

      if (!_senderRegistry.containsKey(normalizedSender)) {
        return _tryGenericParse(smsBody, sender);
      }

      final institution = _senderRegistry[normalizedSender]!;

      // Try UPI patterns first
      final upiResult = _tryParseUpi(smsBody, sender, institution);
      if (upiResult != null) return upiResult;

      // Try credit card patterns
      final ccResult = _tryParseCreditCard(smsBody, sender, normalizedSender);
      if (ccResult != null) return ccResult;

      // Try bank account patterns
      final bankResult = _tryParseBankAccount(smsBody, sender);
      if (bankResult != null) return bankResult;

      // Try NEFT/RTGS/IMPS
      final neftResult = _tryParseNeftImps(smsBody, sender);
      if (neftResult != null) return neftResult;

      // Try ATM withdrawal
      final atmResult = _tryParseAtm(smsBody, sender);
      if (atmResult != null) return atmResult;

      // Try wallet
      final walletResult = _tryParseWallet(smsBody, sender);
      if (walletResult != null) return walletResult;

      // Fallback: try generic debit/credit
      return _tryGenericParse(smsBody, sender);
    } catch (e) {
      debugPrint('SMS parsing error: $e');
      return null;
    }
  }

  /// Parses a batch of SMS messages.
  static List<ParsedSms> parseBatch(List<({String body, String sender})> messages) {
    final results = <ParsedSms>[];
    for (final msg in messages) {
      final parsed = parse(msg.body, msg.sender);
      if (parsed != null) {
        results.add(parsed);
      }
    }
    return results;
  }

  /// Generates a deduplication hash for a parsed transaction.
  static String generateDedupeHash(ParsedSms parsed) {
    final date = parsed.date ?? DateTime.now();
    final dateKey = '${date.year}-${date.month}-${date.day}-${date.hour}-${date.minute}';
    final merchantKey = parsed.partyName?.toLowerCase().replaceAll(RegExp(r'\W'), '') ?? '';
    // Include UPI/bank reference numbers so two transactions with the same
    // amount + party + minute but different refs are NOT treated as duplicates.
    final refKey = parsed.upiRefNo ?? parsed.referenceId ?? '';
    final key = '${parsed.amount}-$dateKey-$merchantKey-${parsed.direction.name}-$refKey';
    return sha256.convert(utf8.encode(key)).toString();
  }

  // ---------------------------------------------------------------------------
  // UPI Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseUpi(String sms, String sender, String institution) {
    // PhonePe Sent
    var match = _phonePeSent.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(2)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.upi,
        upiApp: 'PhonePe',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // PhonePe Received
    match = _phonePeReceived.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(2)),
        direction: TransactionDirection.received,
        sourceType: SmsSourceType.upi,
        upiApp: 'PhonePe',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // Google Pay Sent
    match = _gpaySent.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(2)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.upi,
        upiApp: 'Google Pay',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // Google Pay Received
    match = _gpayReceived.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(2)!),
        partyName: _cleanPartyName(match.group(1)),
        direction: TransactionDirection.received,
        sourceType: SmsSourceType.upi,
        upiApp: 'Google Pay',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // Google Pay Received (alternate) — only for known GPay sender IDs to prevent
    // false positives on generic SMS containing "received" and "Rs."
    final normalizedSender = _normalizeSender(sender);
    if (normalizedSender == 'GPAY' || normalizedSender == 'GOOGLEPAY') {
      match = _gpayReceivedAlt.firstMatch(sms);
      if (match != null) {
        return _buildParsed(
          sms: sms,
          sender: sender,
          amount: _parseAmount(match.group(1)!),
          partyName: _cleanPartyName(match.group(2)),
          direction: TransactionDirection.received,
          sourceType: SmsSourceType.upi,
          upiApp: 'Google Pay',
          upiRefNo: _extractUpiRef(sms),
          date: _extractDate(sms),
        );
      }
    }

    // Paytm Sent
    match = _paytmSent.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(2)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.upi,
        upiApp: 'Paytm',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // BHIM Sent
    match = _bhimSent.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(2)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.upi,
        upiApp: 'BHIM',
        upiRefNo: _extractUpiRef(sms),
        date: _extractDate(sms),
      );
    }

    // Generic UPI — only if institution suggests UPI
    if (_isUpiApp(institution)) {
      // Try generic sent
      match = _genericUpiSent.firstMatch(sms);
      if (match != null) {
        return _buildParsed(
          sms: sms,
          sender: sender,
          amount: _parseAmount(match.group(1)!),
          partyName: _cleanPartyName(match.group(2)),
          direction: TransactionDirection.sent,
          sourceType: SmsSourceType.upi,
          upiApp: institution,
          upiRefNo: _extractUpiRef(sms),
          date: _extractDate(sms),
        );
      }

      // Try generic received
      match = _genericUpiReceived.firstMatch(sms);
      if (match != null) {
        return _buildParsed(
          sms: sms,
          sender: sender,
          amount: _parseAmount(match.group(1)!),
          partyName: _cleanPartyName(match.group(2)),
          direction: TransactionDirection.received,
          sourceType: SmsSourceType.upi,
          upiApp: institution,
          upiRefNo: _extractUpiRef(sms),
          date: _extractDate(sms),
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Credit Card Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseCreditCard(String sms, String sender, String normalizedSender) {
    // HDFC Credit Card
    var match = _hdfcCc.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.creditCard,
        cardLast4: match.group(2),
        date: _parseDateString(match.group(4)),
      );
    }

    // ICICI Credit Card
    match = _iciciCc.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(2)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.creditCard,
        cardLast4: match.group(1),
        date: _parseDateString(match.group(4)),
      );
    }

    // SBI Credit Card
    match = _sbiCc.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(2)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.creditCard,
        cardLast4: match.group(1),
        date: _extractDate(sms),
      );
    }

    // Generic credit card
    match = _genericCcSpend.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.creditCard,
        cardLast4: match.group(2),
        date: _extractDate(sms),
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Bank Account Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseBankAccount(String sms, String sender) {
    // Bank debit
    var match = _bankDebit.firstMatch(sms);
    if (match != null) {
      final partyName = match.group(3) ?? match.group(4);
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(partyName),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.bankAccount,
        accountLast4: match.group(2),
        date: _extractDate(sms),
        availableBalance: _extractBalance(sms),
      );
    }

    // Bank credit
    match = _bankCredit.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.received,
        sourceType: SmsSourceType.bankAccount,
        accountLast4: match.group(2),
        date: _extractDate(sms),
        availableBalance: _extractBalance(sms),
      );
    }

    // Simpler bank debit
    match = _bankDebitSimple.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _extractPartyFromGeneric(sms, TransactionDirection.sent),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.bankAccount,
        accountLast4: match.group(2),
        date: _extractDate(sms),
        availableBalance: _extractBalance(sms),
      );
    }

    // Simpler bank credit
    match = _bankCreditSimple.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _extractPartyFromGeneric(sms, TransactionDirection.received),
        direction: TransactionDirection.received,
        sourceType: SmsSourceType.bankAccount,
        accountLast4: match.group(2),
        date: _extractDate(sms),
        availableBalance: _extractBalance(sms),
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // NEFT/RTGS/IMPS Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseNeftImps(String sms, String sender) {
    final match = _neftImps.firstMatch(sms);
    if (match == null) return null;

    final direction = match.group(2)!.toLowerCase() == 'credited'
        ? TransactionDirection.received
        : TransactionDirection.sent;

    final transferType = match.group(3)!.toUpperCase();
    final sourceType = switch (transferType) {
      'NEFT' => SmsSourceType.neft,
      'RTGS' => SmsSourceType.rtgs,
      'IMPS' => SmsSourceType.imps,
      _ => SmsSourceType.bankAccount,
    };

    return _buildParsed(
      sms: sms,
      sender: sender,
      amount: _parseAmount(match.group(1)!),
      partyName: _cleanPartyName(match.group(4)),
      direction: direction,
      sourceType: sourceType,
      referenceId: _extractRef(sms),
      date: _extractDate(sms),
      availableBalance: _extractBalance(sms),
    );
  }

  // ---------------------------------------------------------------------------
  // ATM Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseAtm(String sms, String sender) {
    final match = _atmWithdrawal.firstMatch(sms);
    if (match == null) return null;

    return _buildParsed(
      sms: sms,
      sender: sender,
      amount: _parseAmount(match.group(1)!),
      partyName: match.group(2) != null ? 'ATM ${_cleanPartyName(match.group(2))}' : 'ATM Withdrawal',
      direction: TransactionDirection.sent,
      sourceType: SmsSourceType.atm,
      accountLast4: _extractLast4(sms),
      date: _extractDate(sms),
      availableBalance: _extractBalance(sms),
    );
  }

  // ---------------------------------------------------------------------------
  // Wallet Parsing
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryParseWallet(String sms, String sender) {
    // Wallet spend
    var match = _walletSpend.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: _cleanPartyName(match.group(3)),
        direction: TransactionDirection.sent,
        sourceType: SmsSourceType.wallet,
        upiApp: match.group(2),
        date: _extractDate(sms),
      );
    }

    // Wallet load
    match = _walletLoad.firstMatch(sms);
    if (match != null) {
      return _buildParsed(
        sms: sms,
        sender: sender,
        amount: _parseAmount(match.group(1)!),
        partyName: '${match.group(2)} Wallet',
        direction: TransactionDirection.sent, // Loading wallet is still a debit
        sourceType: SmsSourceType.wallet,
        upiApp: match.group(2),
        date: _extractDate(sms),
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Generic Fallback
  // ---------------------------------------------------------------------------

  static ParsedSms? _tryGenericParse(String sms, String sender) {
    final amount = _extractFirstAmount(sms);
    if (amount == null || amount <= 0) return null;

    // Determine direction from keywords
    final lowerSms = sms.toLowerCase();
    TransactionDirection direction;
    if (lowerSms.contains('debited') ||
        lowerSms.contains('spent') ||
        lowerSms.contains('paid') ||
        lowerSms.contains('withdrawn') ||
        lowerSms.contains('sent')) {
      direction = TransactionDirection.sent;
    } else if (lowerSms.contains('credited') ||
        lowerSms.contains('received') ||
        lowerSms.contains('refund')) {
      direction = TransactionDirection.received;
    } else {
      return null; // Can't determine direction
    }

    return _buildParsed(
      sms: sms,
      sender: sender,
      amount: amount,
      partyName: _extractPartyFromGeneric(sms, direction),
      direction: direction,
      sourceType: SmsSourceType.unknown,
      accountLast4: _extractLast4(sms),
      date: _extractDate(sms),
      availableBalance: _extractBalance(sms),
    );
  }

  // ---------------------------------------------------------------------------
  // Field Extractors
  // ---------------------------------------------------------------------------

  /// Parse amount string (removes commas).
  static double _parseAmount(String amountStr) {
    return double.tryParse(amountStr.replaceAll(',', '')) ?? 0;
  }

  /// Extract the first amount found in the SMS.
  static double? _extractFirstAmount(String sms) {
    for (final pattern in _amountPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        return _parseAmount(match.group(1)!);
      }
    }
    return null;
  }

  /// Extract UPI reference number.
  static String? _extractUpiRef(String sms) {
    for (final pattern in _upiRefPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Extract any reference number.
  static String? _extractRef(String sms) {
    for (final pattern in _refPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Extract last 4 digits of card/account.
  static String? _extractLast4(String sms) {
    final match = _last4Pattern.firstMatch(sms);
    return match?.group(1);
  }

  /// Extract available balance.
  static double? _extractBalance(String sms) {
    final match = _balancePattern.firstMatch(sms);
    if (match != null) {
      return _parseAmount(match.group(1)!);
    }
    return null;
  }

  /// Extract date from SMS body.
  static DateTime? _extractDate(String sms) {
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        return _parseDateMatch(match, pattern);
      }
    }
    return null; // Will default to SMS receive time
  }

  /// Parse specific date string.
  static DateTime? _parseDateString(String? dateStr) {
    if (dateStr == null) return null;
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(dateStr);
      if (match != null) {
        return _parseDateMatch(match, pattern);
      }
    }
    return null;
  }

  static DateTime? _parseDateMatch(RegExpMatch match, RegExp pattern) {
    try {
      final patternStr = pattern.pattern;

      // dd-MMM-yy or dd-MMM-yyyy pattern
      if (patternStr.contains('[A-Za-z]{3}')) {
        final day = int.parse(match.group(1)!);
        final monthStr = match.group(2)!;
        var yearStr = match.group(3);

        if (yearStr == null) {
          // Short pattern like 24FEB — use current year
          final month = _monthFromAbbrev(monthStr);
          if (month == null) return null;
          return DateTime(DateTime.now().year, month, day);
        }

        final month = _monthFromAbbrev(monthStr);
        if (month == null) return null;

        var year = int.parse(yearStr);
        if (year < 100) year += 2000; // 26 → 2026

        return DateTime(year, month, day);
      }

      // dd-mm-yyyy or dd/mm/yyyy
      if (match.groupCount >= 3) {
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final year = int.parse(match.group(3)!);
        return DateTime(year, month, day);
      }
    } catch (e, st) {
      // Date parsing error — fall through
      AppLogger.instance.debug(
        'Failed to parse SMS date',
        category: 'sms_parser',
        error: e,
      );
    }
    return null;
  }

  static int? _monthFromAbbrev(String abbrev) {
    const months = {
      'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
      'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
    };
    return months[abbrev.toUpperCase()];
  }

  /// Extract party name from generic SMS using "to" / "from" / "at" keywords.
  static String? _extractPartyFromGeneric(String sms, TransactionDirection direction) {
    if (direction == TransactionDirection.sent) {
      // Look for "to {name}" or "at {name}"
      final pattern = RegExp(
        r'(?:to|at)\s+([A-Z][A-Za-z0-9\s&\-\.]+?)(?:\s+(?:using|via|on|UPI|Ref|from)|[.\n]|$)',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(sms);
      return _cleanPartyName(match?.group(1));
    } else {
      // Look for "from {name}"
      final pattern = RegExp(
        r'from\s+([A-Z][A-Za-z\s&\-\.]+?)(?:\s+(?:via|using|A/c|Ref)|[.\n]|$)',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(sms);
      return _cleanPartyName(match?.group(1));
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Normalize sender ID (strip prefix like AD-, VM-, etc.).
  static String _normalizeSender(String sender) {
    // Remove common prefixes: AD-HDFCBK, VM-ICICI, etc.
    final cleaned = sender.toUpperCase().replaceAll(RegExp(r'^[A-Z]{2}-'), '');
    return cleaned.trim();
  }

  /// Clean up extracted party name.
  static String? _cleanPartyName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    var cleaned = name.trim();
    // Remove trailing dots, commas
    cleaned = cleaned.replaceAll(RegExp(r'[.,;:]+$'), '').trim();
    // Remove "Pvt Ltd", "Private Limited" etc.
    cleaned = cleaned.replaceAll(RegExp(r'\s+(?:Pvt|Private|Ltd|Limited|Inc)\s*\.?\s*$', caseSensitive: false), '').trim();
    // Normalize whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    // Don't return very short names or names that look like codes
    if (cleaned.length < 2) return null;
    if (RegExp(r'^\d+$').hasMatch(cleaned)) return null;
    return cleaned;
  }

  /// Check if institution is a UPI app (used to gate generic UPI pattern matching).
  static bool _isUpiApp(String institution) {
    return const {
      'PhonePe', 'Google Pay', 'Paytm', 'BHIM', 'Amazon Pay',
      'Fi Money', 'Slice', 'Jupiter',
    }.contains(institution);
  }

  /// Calculate confidence score for a parsed result.
  static double _calculateConfidence({
    required double amount,
    String? partyName,
    required TransactionDirection direction,
    String? referenceId,
    DateTime? date,
    String? cardLast4,
    String? accountLast4,
  }) {
    double score = 0.0;

    // Amount extracted (required) — 40%
    if (amount > 0) {
      score += 0.4;
    } else {
      return 0.0;
    }

    // Party name extracted — 30%
    if (partyName != null && partyName.isNotEmpty) {
      score += 0.3;
    }

    // Direction determined — 15% (always true if we got here)
    score += 0.15;

    // Reference number — 10%
    if (referenceId != null && referenceId.isNotEmpty) {
      score += 0.10;
    }

    // Date extracted — 5%
    if (date != null) {
      score += 0.05;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Build a ParsedSms with confidence calculated.
  static ParsedSms _buildParsed({
    required String sms,
    required String sender,
    required double amount,
    String? partyName,
    required TransactionDirection direction,
    required SmsSourceType sourceType,
    String? upiApp,
    String? upiRefNo,
    String? referenceId,
    String? cardLast4,
    String? accountLast4,
    DateTime? date,
    double? availableBalance,
  }) {
    final confidence = _calculateConfidence(
      amount: amount,
      partyName: partyName,
      direction: direction,
      referenceId: upiRefNo ?? referenceId,
      date: date,
      cardLast4: cardLast4,
      accountLast4: accountLast4,
    );

    return ParsedSms(
      amount: amount,
      partyName: partyName,
      direction: direction,
      sourceType: sourceType,
      upiApp: upiApp,
      upiRefNo: upiRefNo,
      referenceId: referenceId ?? upiRefNo,
      cardLast4: cardLast4,
      accountLast4: accountLast4,
      availableBalance: availableBalance,
      date: date,
      confidence: confidence,
      smsBody: sms,
      smsSender: sender,
    );
  }
}
