class WebPreflightProbeResult {
  const WebPreflightProbeResult({
    required this.reachable,
    required this.errorMessage,
  });

  final bool reachable;
  final String errorMessage;
}

Future<WebPreflightProbeResult> probePhoneHealth(String wsUrl) async {
  return const WebPreflightProbeResult(
    reachable: true,
    errorMessage: '',
  );
}
