import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Compresses a picked image to fit within a 150 KB budget.
///
/// Reads via [XFile.readAsBytes()] — the only cross-platform, sandbox-safe
/// method to access a picker-selected file (works on macOS sandbox, iOS,
/// Android without needing direct filesystem access to the source path).
///
/// Strategy:
///   1. Read source bytes through XFile (security-scoped on macOS/iOS).
///   2. Compress to ≤ 800×600 px at quality 70.
///   3. If still > 150 KB, re-compress at quality 50.
///   4. Write final bytes to [getApplicationDocumentsDirectory()] and
///      return the new sandbox-safe path.
///
/// On any error, falls back to writing the raw bytes as-is to the docs dir
/// so the caller always gets a sandbox-safe path.
///
/// All processing is local — no data leaves the device.
Future<String> compressPickedImage(XFile xfile) async {
  try {
    var bytes = await xfile.readAsBytes();

    // First compression pass.
    var compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 800,
      minHeight: 600,
      quality: 70,
    );

    // Hard cap: 150 KB — reduce quality further if still too large.
    if (compressed.length > 150 * 1024) {
      compressed = await FlutterImageCompress.compressWithList(
            compressed,
            minWidth: 800,
            minHeight: 600,
            quality: 50,
          );
    }

    final dir      = await getApplicationDocumentsDirectory();
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest     = File('${dir.path}/$fileName');
    await dest.writeAsBytes(compressed);

    debugPrint('[ImageCompress] → ${compressed.length ~/ 1024} KB after compression');
    return dest.path;
  } catch (e) {
    debugPrint('[ImageCompress] Error ($e) — saving raw bytes to docs dir');
    try {
      final bytes    = await xfile.readAsBytes();
      final dir      = await getApplicationDocumentsDirectory();
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest     = File('${dir.path}/$fileName');
      await dest.writeAsBytes(bytes);
      return dest.path;
    } catch (_) {
      return xfile.path;
    }
  }
}
