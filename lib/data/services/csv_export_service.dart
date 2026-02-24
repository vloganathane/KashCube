import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transaction.dart';

/// Service for exporting transactions to CSV format.
///
/// All processing is local — no data is transmitted.
class CsvExportService {
  CsvExportService._();
  static final CsvExportService instance = CsvExportService._();

  static const _exportDir = 'exports';
  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _timeFormat = DateFormat('hh:mm a');

  /// Export a list of transactions to a CSV file.
  ///
  /// Returns the file path on success.
  Future<String> exportTransactions(
    List<Transaction> transactions, {
    String? fileName,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(join(appDir.path, _exportDir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final name = fileName ?? 'kash_cube_transactions_$timestamp.csv';
      final filePath = join(dir.path, name);

      final csvContent = _buildCsv(transactions);
      final file = File(filePath);
      await file.writeAsString(csvContent);

      debugPrint('CSV exported: $filePath (${transactions.length} rows)');
      return filePath;
    } catch (e) {
      debugPrint('CSV export failed: $e');
      rethrow;
    }
  }

  String _buildCsv(List<Transaction> transactions) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln(
      'Date,Time,Type,Category,Amount,Party,Payment Method,'
      'UPI App,UPI Ref,Notes',
    );

    // Rows
    for (final txn in transactions) {
      final date = _dateFormat.format(txn.date);
      final time = _timeFormat.format(txn.date);
      final type = txn.type.label;
      final category = _escapeCsv(txn.category);
      final amount = txn.amount.toStringAsFixed(2);
      final party = _escapeCsv(txn.partyName ?? '');
      final paymentMethod = txn.paymentMethod.label;
      final upiApp = txn.upiApp ?? '';
      final upiRef = txn.upiRefNo ?? '';
      final notes = _escapeCsv(txn.notes ?? '');

      buffer.writeln(
        '$date,$time,$type,$category,$amount,$party,'
        '$paymentMethod,$upiApp,$upiRef,$notes',
      );
    }

    return buffer.toString();
  }

  /// Escape a CSV field: wrap in quotes if it contains commas, quotes, or newlines.
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Delete an export file.
  Future<void> deleteExport(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
