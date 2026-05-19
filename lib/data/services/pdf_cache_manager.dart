import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

/// Manages ephemeral PDF files generated for invoices and quotes.
///
/// PDFs are written into a `pdfs/` subdirectory of the system temp folder.
/// Eviction policy:
///   • Files older than 24 hours are deleted on resume.
///   • At most [_maxFiles] PDFs are kept on disk (oldest deleted first).
///
/// Filenames use the FY-scoped document number, e.g.
///   `Invoice_INV-25-26-0042.pdf`
///
/// No network calls — 100% local.
class PdfCacheManager {
  PdfCacheManager._();
  static final PdfCacheManager instance = PdfCacheManager._();

  static const _subdir = 'pdfs';
  static const _maxFiles = 3;
  static const _maxAgeHours = 24;

  // ── Internal helpers ────────────────────────────────────────────────────

  Future<Directory> _cacheDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Returns the full path where [filename] should be written.
  ///
  /// Does NOT create the file — just resolves the path.
  Future<String> tempPath(String filename) async {
    final dir = await _cacheDir();
    return '${dir.path}/$filename';
  }

  /// Evict stale PDFs (> 24 h) and enforce the [_maxFiles] cap.
  ///
  /// Call on `AppLifecycleState.resumed`.
  Future<void> evict() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;

      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.pdf'))
          .cast<File>()
          .toList();

      final now = DateTime.now();
      final fresh = <File>[];

      for (final f in files) {
        final stat = await f.stat();
        if (now.difference(stat.modified).inHours >= _maxAgeHours) {
          await f.delete();
          debugPrint('[PdfCache] Evicted (stale): ${f.path}');
        } else {
          fresh.add(f);
        }
      }

      // Sort oldest-first and trim to cap.
      fresh.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      while (fresh.length > _maxFiles) {
        final oldest = fresh.removeAt(0);
        await oldest.delete();
        debugPrint('[PdfCache] Evicted (cap): ${oldest.path}');
      }
    } catch (e) {
      debugPrint('[PdfCache] Evict error (non-critical): $e');
    }
  }

  /// Delete all cached PDFs. Called from the Storage Health Dashboard.
  Future<void> clearAll() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('[PdfCache] Cleared all cached PDFs');
      }
    } catch (e) {
      debugPrint('[PdfCache] Clear error: $e');
    }
  }

  /// Total size of all cached PDFs in bytes.
  Future<int> totalSize() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.pdf')) {
          total += (await entity.stat()).size;
        }
      }
      return total;
    } catch (e) {
      AppLogger.instance.debug(
        'Failed to calculate PDF cache size',
        category: 'pdf_cache',
        error: e,
      );
      return 0;
    }
  }
}
