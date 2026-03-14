/// Non-web stub for the browser HTTP client.
/// Never called at runtime because [HttpSyncTransport] is only instantiated
/// on the web (the [WebConnectScreen] is only reachable on web).
Future<Map<String, dynamic>> httpPost(
  String url,
  Map<String, dynamic> body, {
  required String sessionToken,
}) =>
    throw UnsupportedError('httpPost is only available on web');
