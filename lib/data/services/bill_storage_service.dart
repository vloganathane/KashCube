import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/bill_attachment.dart';

/// Service for managing bill files on local storage.
///
/// Copies picked files into the app-private bills directory and handles
/// cleanup when bills are deleted. All operations are local-only.
class BillStorageService {
  BillStorageService._();
  static final BillStorageService instance = BillStorageService._();

  static const String _billsDir = 'bills';

  /// Returns the app-private bills directory, creating it if needed.
  Future<Directory> get _billsDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _billsDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies a picked file into the app's bills directory.
  ///
  /// Returns a [BillAttachment] with the stored file path.
  /// The file is renamed to `bill_<transactionId>_<timestamp>.<ext>`
  /// to avoid collisions.
  Future<BillAttachment> saveFile({
    required int transactionId,
    required String sourcePath,
    required String originalFileName,
  }) async {
    final dir = await _billsDirectory;
    final ext = p.extension(originalFileName).toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storedName = 'bill_${transactionId}_$timestamp$ext';
    final destPath = p.join(dir.path, storedName);

    // Copy file to app-private directory
    final sourceFile = File(sourcePath);
    final destFile = await sourceFile.copy(destPath);
    final fileSize = await destFile.length();

    // Determine file type from extension
    final fileType = _resolveFileType(ext);

    return BillAttachment(
      transactionId: transactionId,
      filePath: destPath,
      fileName: originalFileName,
      fileType: fileType,
      fileSize: fileSize,
    );
  }

  /// Deletes the bill file from disk.
  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted bill file: $filePath');
      }
    } catch (e) {
      debugPrint('Error deleting bill file: $e');
    }
  }

  /// Checks if the bill file exists on disk.
  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Returns the file size in a human-readable format.
  static String formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  BillFileType _resolveFileType(String extension) {
    switch (extension) {
      case '.pdf':
        return BillFileType.pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.heic':
      case '.heif':
        return BillFileType.image;
      default:
        return BillFileType.image;
    }
  }
}
