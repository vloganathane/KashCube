// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

Future<Map<String, dynamic>> uploadMedia({
  required String wsUrl,
  required String sessionToken,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final wsUri = Uri.parse(wsUrl);
  final httpUri = wsUri.replace(
    scheme: wsUri.scheme == 'wss' ? 'https' : 'http',
    path: '/media/upload',
    query: '',
  );

  final body = jsonEncode({
    'file_name': fileName,
    'mime_type': mimeType,
    'bytes_b64': base64Encode(bytes),
  });

  final response = await html.HttpRequest.request(
    httpUri.toString(),
    method: 'POST',
    sendData: body,
    requestHeaders: {
      'content-type': 'application/json',
      'x-kash-session': sessionToken,
    },
  );

  final status = response.status ?? 0;
  final text = response.responseText ?? '{}';
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Invalid media upload response');
  }

  if (status < 200 || status >= 300 || decoded['ok'] != true) {
    throw Exception(decoded['error'] ?? 'Media upload failed ($status)');
  }

  return decoded;
}
