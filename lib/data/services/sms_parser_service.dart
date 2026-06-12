import '../models/parsed_sms.dart';
import 'sms_parser.dart';

/// Injectable, non-static wrapper around [SmsParser].
///
/// Exposes the same operations as the static [SmsParser] class but as
/// instance methods, making it possible to mock or subclass in tests.
///
/// Register via [smsParserProvider] in Riverpod and inject it into
/// [SmsService] — no direct static calls to [SmsParser] are needed in
/// production code anymore.
class SmsParserService {
  const SmsParserService();

  /// Returns true if [sender] matches the known financial-SMS sender registry.
  bool isFinancialSender(String sender) => SmsParser.isFinancialSender(sender);

  /// Parses a financial SMS [body] from [sender].
  ///
  /// Returns [ParsedSms] on success, or `null` if the message cannot be
  /// identified as a financial transaction.
  ParsedSms? parse(String body, String sender) => SmsParser.parse(body, sender);

  /// Generates a deduplication hash for a [ParsedSms] result.
  ///
  /// Two calls with equivalent amount, direction, and reference data will
  /// produce identical hashes, allowing the repository to reject duplicates.
  String generateDedupeHash(ParsedSms parsed) =>
      SmsParser.generateDedupeHash(parsed);
}
