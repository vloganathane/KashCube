import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:talker/talker.dart';

import 'database_helper.dart';

enum AppLogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal,
}

class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();
  static const _internalConsoleZoneKey = #appLoggerInternalConsole;

  static const int _maxRows = 1000;
  static const int _maxTextLen = 4000;
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  // Talker is used as runtime logging backend (console output + formatting).
  // SQLite persistence remains the source of truth for Diagnostics Logs UI.
  final Talker _talker = Talker(
    settings: TalkerSettings(
      useConsoleLogs: true,
      useHistory: false,
      timeFormat: TimeFormat.timeAndSeconds,
    ),
  );

  String get sessionId => _sessionId;

  static bool shouldSkipTerminalCapture([Zone? zone]) {
    final effectiveZone = zone ?? Zone.current;
    return effectiveZone[_internalConsoleZoneKey] == true;
  }

  Future<void> initialize() async {
    try {
      // Touch DB so logging is ready before first routed screen.
      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.ensureAppLogSchema(db: db);
    } catch (e) {
      debugPrint('[AppLogger] init failed: $e');
    }
  }

  Future<void> trace(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.trace,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> debug(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.debug,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> info(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.info,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> warning(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.warning,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> error(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.error,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> fatal(
    String message, {
    String source = 'app',
    String category = 'app',
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.fatal,
      message: message,
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) {
    return error(
      'Unhandled Flutter framework error',
      category: 'flutter',
      context: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
      stackTrace: details.stack,
      error: details.exception,
      eventName: 'flutter_error',
    );
  }

  Future<void> event(
    String eventName, {
    AppLogLevel level = AppLogLevel.info,
    String category = 'app',
    String? message,
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: level,
      message: message ?? _humanizeEventName(eventName),
      source: source,
      category: category,
      eventName: eventName,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> recordTerminalLine(
    String line, {
    String source = 'terminal',
  }) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    await _persistLog(
      level: AppLogLevel.info,
      source: source,
      category: 'terminal',
      eventName: 'terminal_line',
      message: _truncate(_redact(trimmed)),
      error: null,
      stackTrace: null,
      contextJson: null,
    );
  }

  Future<void> _log({
    required AppLogLevel level,
    required String message,
    String source = 'app',
    required String category,
    String? eventName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) async {
    final safeMessage = _truncate(_redact(message));
    final safeError = error == null ? null : _truncate(_redact(error.toString()));
    final safeStack = stackTrace == null
        ? null
        : _truncate(_redact(stackTrace.toString()));

    runZoned(
      () {
        switch (level) {
          case AppLogLevel.trace:
            _talker.verbose(safeMessage, safeError, stackTrace);
            break;
          case AppLogLevel.debug:
            _talker.debug(safeMessage, safeError, stackTrace);
            break;
          case AppLogLevel.info:
            _talker.info(safeMessage, safeError, stackTrace);
            break;
          case AppLogLevel.warning:
            _talker.warning(safeMessage, safeError, stackTrace);
            break;
          case AppLogLevel.error:
            _talker.error(safeMessage, safeError, stackTrace);
            break;
          case AppLogLevel.fatal:
            _talker.critical(safeMessage, safeError, stackTrace);
            break;
        }
      },
      zoneValues: {_internalConsoleZoneKey: true},
    );

    final contextJson = context == null
        ? null
        : _truncate(_redact(jsonEncode(context)));

    await _persistLog(
      level: level,
      source: source,
      category: category,
      eventName: eventName,
      message: safeMessage,
      error: safeError,
      stackTrace: safeStack,
      contextJson: contextJson,
    );
  }

  Future<void> _persistLog({
    required AppLogLevel level,
    required String source,
    required String category,
    required String message,
    String? eventName,
    String? error,
    String? stackTrace,
    String? contextJson,
  }) async {
    try {
      await DatabaseHelper.instance.insertAppLog(
        level: level.name,
        source: source,
        category: category,
        eventName: eventName,
        sessionId: _sessionId,
        message: message,
        error: error,
        stackTrace: stackTrace,
        contextJson: contextJson,
        maxRows: _maxRows,
      );
    } catch (e) {
      // Do not recurse into logger if log persistence itself fails.
      runZoned(
        () => debugPrintSynchronously('[AppLogger] persist failed: $e'),
        zoneValues: {_internalConsoleZoneKey: true},
      );
    }
  }

  String _humanizeEventName(String eventName) {
    final words = eventName.split('_').where((word) => word.isNotEmpty);
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _truncate(String input) {
    if (input.length <= _maxTextLen) return input;
    return '${input.substring(0, _maxTextLen)}...';
  }

  String _redact(String input) {
    // Mask long digit sequences that may include account/phone/reference values.
    final maskedDigits = input.replaceAllMapped(
      RegExp(r'\b\d{8,}\b'),
      (m) => '${m.group(0)!.substring(0, 2)}******${m.group(0)!.substring(m.group(0)!.length - 2)}',
    );
    return maskedDigits;
  }
}
