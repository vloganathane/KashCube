import 'dart:typed_data';

class PdfDownloadRequest {
  const PdfDownloadRequest({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}
