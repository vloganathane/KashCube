import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Compresses an image picked from the gallery or camera.
///
/// Strategy:
///   1. Compress to 800 × 600 min dimensions, quality 70.
///   2. If result is still > 150 KB, compress again at quality 50.
///   3. Writes compressed bytes to the app's documents directory (not back to
///      the source path, which may be outside the sandbox on macOS/iOS).
///   4. Returns the path to the new file in the app sandbox.
///
/// On any error, returns [sourcePath] unchanged (graceful fallback).
///
/// All processing is local — no data leaves the device.
Future<String> compressPickedImage(String sourcePath) async {
  try {
    var bytes = await FlutterImageCompress.compressWithFile(
      sourcePath,
      minWidth: 800,
      minHeight: 600,
      quality: 70,
    );

    if (bytes == null) return sourcePath;

    // Hard cap: 150 KB — reduce quality further if still too large.
    if (bytes.length > 150 * 1024) {
      bytes = await FlutterImageCompress.compressWithFile(
            sourcePath,
            minWidth: 800,
            minHeight: 600,
            quality: 50,
          ) ??
          bytes;
    }

    // Write to the app's documents directory so the path stays accessible
    // inside the sandbox (avoids macOS/iOS permission errors on re-open).
    final dir      = await getApplicationDocumentsDirectory();
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest     = File('${dir.path}/$fileName');
    await dest.writeAsBytes(bytes);

    final kbAfter = bytes.length ~/ 1024;
    debugPrint('[ImageCompress] → $kbAfter KB after compression');

    return dest.path;
  } catch (e) {
    debugPrint('[ImageCompress] Error ($e) — using original');
    return sourcePath;
  }
}
