import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import '../models/parsed_sms.dart';
import 'sms_parser_service.dart';

/// Callback for when a new transaction SMS is detected.
typedef OnTransactionSmsDetected = void Function(ParsedSms parsedSms);

/// Service for reading SMS and listening for incoming financial SMS.
///
/// Uses the telephony package for Android SMS access.
/// All processing happens locally — no SMS data is ever transmitted.
class SmsService {
  /// Creates a [SmsService] with an optional [SmsParserService].
  ///
  /// In production, pass the result of `ref.read(smsParserProvider)` so that
  /// the service can be replaced with a mock in unit tests. When omitted a
  /// default [SmsParserService] instance is used.
  SmsService({SmsParserService? parser})
      : _parser = parser ?? const SmsParserService();

  final SmsParserService _parser;
  final Telephony _telephony = Telephony.instance;
  bool _isListening = false;
  OnTransactionSmsDetected? _onTransactionDetected;

  /// Whether SMS permission has been granted.
  Future<bool> get hasPermission async {
    if (kIsWeb) return false;
    final permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;
    return permissionsGranted ?? false;
  }

  /// Request SMS permission from the user.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted ?? false;
  }

  /// Start listening for incoming SMS messages.
  ///
  /// [onTransactionDetected] is called when a financial SMS is parsed.
  void startListening({required OnTransactionSmsDetected onTransactionDetected}) {
    if (kIsWeb) return;
    if (_isListening) return;

    _onTransactionDetected = onTransactionDetected;
    _isListening = true;

    _telephony.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      onBackgroundMessage: _backgroundMessageHandler,
    );

    debugPrint('SmsService: Started listening for incoming SMS');
  }

  /// Stop listening for incoming SMS.
  void stopListening() {
    if (kIsWeb) return;
    _isListening = false;
    _onTransactionDetected = null;
    debugPrint('SmsService: Stopped listening');
  }

  /// Read existing SMS messages from the inbox.
  ///
  /// [maxCount] limits how many SMS to read (default: 200).
  /// Returns only financial SMS that could be parsed.
  Future<List<ParsedSms>> readExistingSms({int maxCount = 200}) async {
    if (kIsWeb) return [];
    try {
      final messages = await _telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
        ],
        sortOrder: [
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ],
      );

      final parsedList = <ParsedSms>[];
      final limit = messages.length < maxCount ? messages.length : maxCount;

      for (var i = 0; i < limit; i++) {
        final msg = messages[i];
        final sender = msg.address ?? '';
        final body = msg.body ?? '';

        if (sender.isEmpty || body.isEmpty) continue;

        // Only try parsing if sender looks financial
        if (!_parser.isFinancialSender(sender)) continue;

        final parsed = _parser.parse(body, sender);
        if (parsed != null && parsed.confidence >= 0.40) {
          parsedList.add(parsed);
        }
      }

      debugPrint('SmsService: Parsed ${parsedList.length} financial SMS from ${messages.length} total');
      return parsedList;
    } catch (e) {
      debugPrint('SmsService: Error reading SMS: $e');
      return [];
    }
  }

  /// Handle an individual incoming SMS.
  void _handleIncomingSms(SmsMessage message) {
    final sender = message.address ?? '';
    final body = message.body ?? '';

    if (sender.isEmpty || body.isEmpty) return;

    debugPrint('SmsService: Incoming SMS from $sender');

    if (!_parser.isFinancialSender(sender)) return;

    final parsed = _parser.parse(body, sender);
    if (parsed != null && parsed.confidence >= 0.40) {
      debugPrint('SmsService: Detected transaction - ${parsed.amount} ${parsed.direction.label}');
      _onTransactionDetected?.call(parsed);
    }
  }
}

/// Background message handler (must be a top-level function).
@pragma('vm:entry-point')
void _backgroundMessageHandler(SmsMessage message) {
  // Background processing — limited capabilities
  // The main handler will pick up messages when app resumes
  debugPrint('SmsService: Background SMS from ${message.address}');
}
