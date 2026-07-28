import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../pdf_download_request.dart';

Future<void> downloadPdfBytes(Uint8List bytes, String fileName) async {
  await downloadPdfFiles([
    PdfDownloadRequest(bytes: bytes, fileName: fileName),
  ]);
}

Future<void> downloadPdfFiles(List<PdfDownloadRequest> files) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);

  for (final file in files) {
    final output = File('${dir.path}/${file.fileName}');
    await output.writeAsBytes(file.bytes, flush: true);
  }
}
