// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'web_preflight_probe_stub.dart';

Future<WebPreflightProbeResult> probePhoneHealth(String wsUrl) async {
  try {
    final wsUri = Uri.parse(wsUrl);
    final healthUri = wsUri.replace(
      scheme: wsUri.scheme == 'wss' ? 'https' : 'http',
      path: '/health',
      query: '',
    );

    final response = await html.HttpRequest.request(
      healthUri.toString(),
      method: 'GET',
      requestHeaders: const {'accept': 'application/json'},
    );

    final status = response.status ?? 0;
    if (status >= 200 && status < 300) {
      return const WebPreflightProbeResult(
        reachable: true,
        errorMessage: '',
      );
    }

    return WebPreflightProbeResult(
      reachable: false,
      errorMessage:
          'Phone server check failed (HTTP $status). Keep app open and ensure both devices are on same Wi-Fi.',
    );
  } catch (_) {
    return const WebPreflightProbeResult(
      reachable: false,
      errorMessage:
          'Could not reach phone server. Check same Wi-Fi, AP isolation, and local firewall.',
    );
  }
}
