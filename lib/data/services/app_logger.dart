import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

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

  static const int _maxRows = 1000;
  static const int _maxTextLen = 4000;

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: false,
      printEmojis: false,
      printTime: true,
    ),
  );

  Future<void> initialize() async {
    try {
      // Touch DB so logging is ready before first routed screen.
      await DatabaseHelper.instance.database;
    } catch (e) {
      debugPrint('[AppLogger] init failed: $e');
    }
  }

  Future<void> trace(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.trace,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> debug(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.debug,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> info(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.info,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> warning(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.warning,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> error(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.error,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> fatal(
    String message, {
    String category = 'app',
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    return _log(
      level: AppLogLevel.fatal,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) {
    return error(
      'Unhandled Flutter framework error',
      category: 'flutter',
      error: details.exception,
      stackTrace: details.stack,
      context: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
  }

  Future<void> _log({
    required AppLogLevel level,
    required String message,
    required String category,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) async {
    final safeMessage = _truncate(_redact(message));
    final safeError = error == null ? null : _truncate(_redact(error.toString()));
    final safeStack = stackTrace == null
        ? null
        : _truncate(_redact(stackTrace.toString()));

    switch (level) {
      case AppLogLevel.trace:
        _logger.t(safeMessage, error: safeError, stackTrace: stackTrace);
        break;
      case AppLogLevel.debug:
        _logger.d(safeMessage, error: safeError, stackTrace: stackTrace);
        break;
      case AppLogLevel.info:
        _logger.i(safeMessage, error: safeError, stackTrace: stackTrace);
        break;
      case AppLogLevel.warning:
        _logger.w(safeMessage, error: safeError, stackTrace: stackTrace);
        break;
      case AppLogLevel.error:
      case AppLogLevel.fatal:
        _logger.e(safeMessage, error: safeError, stackTrace: stackTrace);
        break;
    }

    final contextJson = context == null
        ? null
        : _truncate(_redact(jsonEncode(context)));

    try {
      await DatabaseHelper.instance.insertAppLog(
        level: level.name,
        category: category,
        message: safeMessage,
        error: safeError,
        stackTrace: safeStack,
        contextJson: contextJson,
        maxRows: _maxRows,
      );
    } catch (e) {
      // Do not recurse into logger if log persistence itself fails.
      debugPrint('[AppLogger] persist failed: $e');
    }
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
