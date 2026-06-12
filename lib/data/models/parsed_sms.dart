import 'package:equatable/equatable.dart';

/// Direction of the financial transaction detected in an SMS.
enum TransactionDirection {
  sent,
  received;

  String get label {
    switch (this) {
      case TransactionDirection.sent:
        return 'Sent';
      case TransactionDirection.received:
        return 'Received';
    }
  }
}

/// The source type of the SMS that was parsed.
enum SmsSourceType {
  upi,
  creditCard,
  debitCard,
  bankAccount,
  neft,
  rtgs,
  imps,
  atm,
  wallet,
  unknown;

  String get label {
    switch (this) {
      case SmsSourceType.upi:
        return 'UPI';
      case SmsSourceType.creditCard:
        return 'Credit Card';
      case SmsSourceType.debitCard:
        return 'Debit Card';
      case SmsSourceType.bankAccount:
        return 'Bank Account';
      case SmsSourceType.neft:
        return 'NEFT';
      case SmsSourceType.rtgs:
        return 'RTGS';
      case SmsSourceType.imps:
        return 'IMPS';
      case SmsSourceType.atm:
        return 'ATM';
      case SmsSourceType.wallet:
        return 'Wallet';
      case SmsSourceType.unknown:
        return 'Unknown';
    }
  }
}

/// Confidence level of the parsed transaction.
enum ConfidenceLevel {
  high, // >= 0.85
  medium, // >= 0.65
  low, // >= 0.40
  veryLow; // < 0.40

  static ConfidenceLevel fromScore(double score) {
    if (score >= 0.85) return ConfidenceLevel.high;
    if (score >= 0.65) return ConfidenceLevel.medium;
    if (score >= 0.40) return ConfidenceLevel.low;
    return ConfidenceLevel.veryLow;
  }
}

/// Result of parsing a financial SMS.
class ParsedSms extends Equatable {
  const ParsedSms({
    required this.amount,
    this.partyName,
    required this.direction,
    required this.sourceType,
    this.upiApp,
    this.upiRefNo,
    this.referenceId,
    this.cardLast4,
    this.accountLast4,
    this.availableBalance,
    this.date,
    required this.confidence,
    required this.smsBody,
    required this.smsSender,
  });

  /// Transaction amount.
  final double amount;

  /// Merchant or party name.
  final String? partyName;

  /// Direction: sent (debit) or received (credit).
  final TransactionDirection direction;

  /// Source type of the transaction.
  final SmsSourceType sourceType;

  /// UPI app used (PhonePe, GPay, etc.).
  final String? upiApp;

  /// UPI reference number.
  final String? upiRefNo;

  /// Generic reference ID.
  final String? referenceId;

  /// Last 4 digits of credit/debit card.
  final String? cardLast4;

  /// Last 4 digits of bank account.
  final String? accountLast4;

  /// Available balance after transaction.
  final double? availableBalance;

  /// Transaction date extracted from SMS.
  final DateTime? date;

  /// Confidence score (0.0 to 1.0).
  final double confidence;

  /// Original SMS body.
  final String smsBody;

  /// SMS sender ID.
  final String smsSender;

  /// Confidence level derived from score.
  ConfidenceLevel get confidenceLevel => ConfidenceLevel.fromScore(confidence);

  /// Whether this is a debit transaction.
  bool get isDebit => direction == TransactionDirection.sent;

  /// Whether this is a credit transaction.
  bool get isCredit => direction == TransactionDirection.received;

  @override
  List<Object?> get props => [
    amount,
    partyName,
    direction,
    sourceType,
    smsBody,
  ];

  @override
  String toString() {
    return 'ParsedSms(amount: $amount, party: $partyName, '
        'direction: ${direction.label}, source: ${sourceType.label}, '
        'confidence: ${confidence.toStringAsFixed(2)})';
  }
}
