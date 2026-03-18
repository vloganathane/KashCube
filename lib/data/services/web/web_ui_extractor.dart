import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  /// Returns the path to the extracted web UI directory.
  /// Extracts on first call, then caches.
  Future<String> getExtractedPath() async {
    if (_extractedPath != null) return _extractedPath!;
    _extractedPath = await _extract();
    return _extractedPath!;
  }

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
      final bytes = await rootBundle.load('assets/web_ui/$relativePath');
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    }

    debugPrint('[WebUiExtractor] Extraction complete');
    return outDir.path;
  }

  /// Clears the cached path so the next call to [getExtractedPath] re-extracts.
  void invalidate() => _extractedPath = null;
}
