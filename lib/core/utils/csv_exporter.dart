import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show XFile;

/// Utility for generating GSTN-compatible CSV files and ZIP archives.
///
/// All operations are pure-Dart and run fully offline.
class CsvExporter {
  CsvExporter._();

  /// UTF-8 BOM prefix required by the GSTN offline tool.
  static const List<int> _bom = [0xEF, 0xBB, 0xBF];

  // ─── CSV ────────────────────────────────────────────────────────────────────

  /// Encodes [headers] + [rows] into UTF-8 CSV bytes with a BOM prefix.
  ///
  /// Cell values are automatically quoted when they contain a comma, a
  /// double-quote, or a newline. Null values are written as empty strings.
  static Uint8List encode(List<String> headers, List<List<dynamic>> rows) {
    final sb = StringBuffer();
    sb.writeln(_csvRow(headers));
    for (final row in rows) {
      sb.writeln(_csvRow(row.map((v) => v?.toString() ?? '').toList()));
    }
    final bodyBytes = utf8.encode(sb.toString());
    final result = Uint8List(_bom.length + bodyBytes.length)
      ..setAll(0, _bom)
      ..setAll(_bom.length, bodyBytes);
    return result;
  }

  /// Writes [bytes] to a temporary file named [fileName] and returns the
  /// resulting [File].
  static Future<File> writeToTemp(String fileName, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ─── ZIP ────────────────────────────────────────────────────────────────────

  /// Zips all [files] into a single archive named [zipName].
  ///
  /// The ZIP is written to the system temp directory and returned as an
  /// [XFile] ready to be shared via `share_plus`.
  static Future<XFile> zipFiles(String zipName, List<File> files) async {
    final encoder = ZipFileEncoder();
    final dir = await getTemporaryDirectory();
    final zipPath = '${dir.path}/$zipName';
    encoder.create(zipPath);
    for (final f in files) {
      encoder.addFile(f);
    }
    encoder.close();
    return XFile(zipPath, mimeType: 'application/zip');
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static String _csvRow(List<String> cells) {
    return cells.map(_quoteCell).join(',');
  }

  static String _quoteCell(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
