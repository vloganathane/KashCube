// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import '../pdf_download_request.dart';

Future<void> downloadPdfBytes(Uint8List bytes, String fileName) async {
  await downloadPdfFiles([
    PdfDownloadRequest(bytes: bytes, fileName: fileName),
  ]);
}

Future<void> downloadPdfFiles(List<PdfDownloadRequest> files) async {
  for (final file in files) {
    final blob = html.Blob([file.bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      final anchor = html.AnchorElement(href: url)
        ..download = file.fileName
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }
}
