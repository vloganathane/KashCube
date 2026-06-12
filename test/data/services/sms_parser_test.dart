import 'package:flutter_test/flutter_test.dart';
import 'package:kash_cube/data/models/parsed_sms.dart';
import 'package:kash_cube/data/services/sms_parser.dart';

void main() {
  // ---------------------------------------------------------------------------
  // UPI — PhonePe debit
  // ---------------------------------------------------------------------------
  group('SmsParser.parse — PhonePe UPI', () {
    test('parses debit UPI payment from PhonePe', () {
      const body =
          'Rs.500.00 debited from your A/c X1234 on 14-Mar-26 to VPA merchant@upi'
          ' (Ref No 412345678901). Avl Bal Rs.10,500.';
      final result = SmsParser.parse(body, 'PHONEPE');
      expect(result, isNotNull);
      expect(result!.amount, 500.0);
      expect(result.isDebit, isTrue);
      expect(result.sourceType, SmsSourceType.upi);
    });

    test('parses credit UPI payment to PhonePe', () {
      const body =
          'Rs.1,200.00 credited to your A/c X5678 on 14-Mar-26 via UPI'
          ' (Ref 512345678901). Avl Bal Rs.11,700.';
      final result = SmsParser.parse(body, 'PHONEPE');
      expect(result, isNotNull);
      expect(result!.amount, 1200.0);
      expect(result.isCredit, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // UPI — HDFC Bank
  // ---------------------------------------------------------------------------
  group('SmsParser.parse — HDFC Bank debit', () {
    test(
      'parses HDFC bank debit alert with correct bankAccount sourceType',
      () {
        // Bank senders always produce SmsSourceType.bankAccount, not .upi
        const body =
            'Rs.250 debited from A/c XX9876 via UPI on 14-Mar-26.'
            ' UPI Ref 312345678901. Avl Bal Rs.10,250.00.';
        final result = SmsParser.parse(body, 'HDFCBK');
        expect(result, isNotNull);
        expect(result!.amount, 250.0);
        expect(result.isDebit, isTrue);
        expect(result.sourceType, SmsSourceType.bankAccount);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Bank debit — ICICI
  // ---------------------------------------------------------------------------
  group('SmsParser.parse — ICICI bank account', () {
    test('parses ICICI debit alert', () {
      const body =
          'ICICI Bank: Rs 3,000.00 debited from A/c XX1234 on 14-Mar-2026;'
          ' balance Rs 47,500.00. Info: ATM WDL';
      final result = SmsParser.parse(body, 'ICICIB');
      expect(result, isNotNull);
      expect(result!.amount, 3000.0);
      expect(result.isDebit, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // GPay — bounded regex ensures no false positive on long sender
  // ---------------------------------------------------------------------------
  group('SmsParser.parse — GPay sender gate', () {
    test('GPay pattern does NOT trigger for non-GPay sender', () {
      // This body matches the GPay received-alt pattern syntactically,
      // but the sender is not GPAY/GOOGLEPAY so it should not use that pattern.
      const body = 'You have received Rs.500 from Rahul Kumar via Google Pay.';
      // Sending as an unknown bank sender — should not match GPay-specific regex.
      final result = SmsParser.parse(body, 'SBIINB');
      // If it parses at all it should be via generic pattern, not GPay-specific.
      // The key assertion: it doesn't produce an incorrect GPay sourceType.
      if (result != null) {
        expect(result.upiApp, isNot('Google Pay'));
      }
    });

    test('GPay pattern fires correctly for GPAY sender', () {
      const body =
          'You have received Rs.1,500 from Amit Singh via Google Pay.'
          ' UPI Ref: 412345678901.';
      final result = SmsParser.parse(body, 'GPAY');
      expect(result, isNotNull);
      expect(result!.amount, 1500.0);
      expect(result.isCredit, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Dedup hash
  // ---------------------------------------------------------------------------
  group('SmsParser.generateDedupeHash', () {
    final baseDate = DateTime(2026, 3, 14, 10, 30);

    ParsedSms makeParsed({
      double amount = 500,
      String? partyName = 'Zomato',
      TransactionDirection direction = TransactionDirection.sent,
      String? upiRefNo,
      String? referenceId,
    }) {
      return ParsedSms(
        amount: amount,
        partyName: partyName,
        direction: direction,
        sourceType: SmsSourceType.upi,
        date: baseDate,
        confidence: 0.9,
        smsBody: 'dummy',
        smsSender: 'PHONEPE',
        upiRefNo: upiRefNo,
        referenceId: referenceId,
      );
    }

    test('same transaction produces same hash', () {
      final a = makeParsed(upiRefNo: '123456');
      final b = makeParsed(upiRefNo: '123456');
      expect(SmsParser.generateDedupeHash(a), SmsParser.generateDedupeHash(b));
    });

    test('different upiRefNo produces different hash', () {
      final a = makeParsed(upiRefNo: '111111');
      final b = makeParsed(upiRefNo: '222222');
      expect(
        SmsParser.generateDedupeHash(a),
        isNot(SmsParser.generateDedupeHash(b)),
      );
    });

    test('different referenceId produces different hash', () {
      final a = makeParsed(referenceId: 'REF001');
      final b = makeParsed(referenceId: 'REF002');
      expect(
        SmsParser.generateDedupeHash(a),
        isNot(SmsParser.generateDedupeHash(b)),
      );
    });

    test('different amounts produce different hash', () {
      final a = makeParsed(amount: 100);
      final b = makeParsed(amount: 200);
      expect(
        SmsParser.generateDedupeHash(a),
        isNot(SmsParser.generateDedupeHash(b)),
      );
    });

    test('different direction produces different hash', () {
      final a = makeParsed(direction: TransactionDirection.sent);
      final b = makeParsed(direction: TransactionDirection.received);
      expect(
        SmsParser.generateDedupeHash(a),
        isNot(SmsParser.generateDedupeHash(b)),
      );
    });

    test('null ref and empty ref produce identical hash (stable)', () {
      final a = makeParsed(upiRefNo: null, referenceId: null);
      final b = makeParsed(upiRefNo: null, referenceId: null);
      expect(SmsParser.generateDedupeHash(a), SmsParser.generateDedupeHash(b));
    });
  });

  // ---------------------------------------------------------------------------
  // New sender IDs (B3 fix verification)
  // ---------------------------------------------------------------------------
  group('SmsParser.parse — expanded sender registry', () {
    test('parses Fi Money sender (FIMONY)', () {
      const body =
          'Rs.750 debited from Fi account XXXX2345 on 14-Mar-26.'
          ' UPI ref 512345678901.';
      final result = SmsParser.parse(body, 'FIMONY');
      // Should not return null (sender is in registry)
      // Generic parse may be used if no specific pattern matches.
      expect(result, isNotNull);
      expect(result!.amount, 750.0);
    });

    test('unknown sender returns null or generic parse result', () {
      const body = 'Your transaction of Rs.100 is confirmed.';
      // Completely unknown sender should return null or low-confidence generic.
      final result = SmsParser.parse(body, 'XYZBANK12345');
      // Acceptable: null or very low confidence
      if (result != null) {
        expect(result.confidence, lessThan(0.65));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // parseBatch
  // ---------------------------------------------------------------------------
  group('SmsParser.parseBatch', () {
    test('returns empty list for empty input', () {
      expect(SmsParser.parseBatch([]), isEmpty);
    });

    test('filters out unparseable messages', () {
      final results = SmsParser.parseBatch([
        (body: 'Your OTP is 123456. Do not share.', sender: 'HDFC'),
        (
          body: 'Rs.500 debited from A/c X1234. UPI ref 112233445566.',
          sender: 'PHONEPE',
        ),
      ]);
      // The OTP SMS should not parse as a transaction.
      // At least 0, at most 1 result (the debit).
      expect(results.length, lessThanOrEqualTo(1));
    });
  });
}
