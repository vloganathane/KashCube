import 'dart:typed_data';

Future<Map<String, dynamic>> uploadMedia({
  required String wsUrl,
  required String sessionToken,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError('Media upload is supported only on web runtime');
}
