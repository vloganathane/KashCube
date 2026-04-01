import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path_provider/path_provider.dart';

/// Extracts `assets/web_ui/` from the Flutter asset bundle to a temporary
/// directory the first time it is called, then caches the path.
///
/// The extraction is lazy — it happens on the first `GET /*` request, not
/// on server startup. Subsequent calls return the cached path instantly.
class WebUiExtractor {
  WebUiExtractor._();
  static final WebUiExtractor instance = WebUiExtractor._();

  String? _extractedPath;
  bool _extracting = false;

  /// Returns the path to the extracted web UI directory.
  /// Extracts on first call, then caches.
  Future<String> getExtractedPath() async {
    if (_extractedPath != null) return _extractedPath!;
    await extractNow();
    return _extractedPath!;
  }

  /// Eagerly extracts the bundled web UI to the temp directory.
  ///
  /// Safe to call repeatedly; extraction only runs when no cached path exists.
  Future<void> extractNow() async {
    if (_extractedPath != null || _extracting) return;
    _extracting = true;
    try {
      _extractedPath = await _extract();
    } finally {
      _extracting = false;
    }
  }

  bool get isReady => _extractedPath != null;
  bool get isExtracting => _extracting;

  Future<String> _extract() async {
    final tmpDir  = await getTemporaryDirectory();
    final outDir  = Directory('${tmpDir.path}/kashcube_web_ui');

    // Always re-extract to pick up new builds (simple version-insensitive approach).
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);

    // Read the manifest to know which files to extract.
    final manifestText = await rootBundle.loadString('assets/web_ui/manifest.txt');
    final files = manifestText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    debugPrint('[WebUiExtractor] Extracting ${files.length} files to ${outDir.path}');

    for (final relativePath in files) {
      final file = File('${outDir.path}/$relativePath');
      file.parent.createSync(recursive: true);
      final bytes = await _loadAssetBytes(relativePath);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    }

    debugPrint('[WebUiExtractor] Extraction complete');
    return outDir.path;
  }

  /// Clears the cached path so the next call to [getExtractedPath] re-extracts.
  void invalidate() {
    _extractedPath = null;
    _extracting = false;
  }

  Future<ByteData> _loadAssetBytes(String relativePath) async {
    final primaryKey = 'assets/web_ui/$relativePath';
    try {
      return await rootBundle.load(primaryKey);
    } on FlutterError {
      // Some web-bundle package assets are flattened by Flutter into
      // package-style keys on mobile, e.g. packages/wakelock_plus/...
      if (relativePath.startsWith('assets/packages/')) {
        final packageKey = relativePath.replaceFirst('assets/', '');
        try {
          return await rootBundle.load(packageKey);
        } on FlutterError {
          // no_sleep.js is optional for wakelock on web UI; serve an empty
          // fallback to keep the embedded HTTP server booting.
          if (packageKey.endsWith('/no_sleep.js')) {
            debugPrint('[WebUiExtractor] Optional asset missing: $packageKey. Using empty fallback file.');
            return ByteData(0);
          }
          rethrow;
        }
      }
      rethrow;
    }
  }
}
