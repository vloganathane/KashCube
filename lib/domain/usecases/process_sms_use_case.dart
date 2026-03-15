import '../../data/models/parsed_sms.dart';
import '../../data/models/transaction.dart';
import '../../data/services/sms_parser_service.dart';
import '../repositories/transaction_repository.dart';

/// Encapsulates the flow for processing a single incoming SMS transaction.
///
/// Checks whether the transaction already exists in the database via the
/// deduplication hash, and if not, returns it as a [Transaction] ready to
/// be confirmed and saved by the presentation layer.
///
/// Centralises the dedup logic currently spread across [AppShell] and
/// [sms_provider.dart] into a single testable entry point.
class ProcessSmsUseCase {
  const ProcessSmsUseCase({
    required TransactionRepository transactionRepository,
    required SmsParserService smsParserService,
  })  : _txnRepo = transactionRepository,
        _parser = smsParserService;

  final TransactionRepository _txnRepo;
  final SmsParserService _parser;

  /// Processes [parsed] SMS and indicates whether it is a new transaction.
  ///
  /// Returns the deduplication hash so the caller can pass it to the
  /// confirmation sheet / save flow.
  ///
  /// Returns `null` if a transaction with the same hash already exists in
  /// the database, meaning it can safely be ignored.
  Future<ProcessedSms?> call(ParsedSms parsed) async {
    final hash = _parser.generateDedupeHash(parsed);
    final alreadyExists = await _txnRepo.existsByDedupeHash(hash);
    if (alreadyExists) return null;
    return ProcessedSms(parsed: parsed, dedupeHash: hash);
  }
}

/// Result value returned by [ProcessSmsUseCase] for a new (non-duplicate)
/// transaction.
class ProcessedSms {
  const ProcessedSms({required this.parsed, required this.dedupeHash});

  final ParsedSms parsed;

  /// Stable hash to pass to [TransactionRepository.existsByDedupeHash] on
  /// the save step, preventing race-condition duplicates.
  final String dedupeHash;
}
