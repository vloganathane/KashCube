/// Abstract analytics backend.
///
/// Call sites only depend on this interface. Swap the implementation in
/// [analyticsProvider] to change the backend (NoOp → Firebase → PostHog).
abstract interface class AnalyticsService {
  /// Enable or disable event collection at runtime (driven by consent).
  Future<void> setEnabled(bool enabled);

  /// Log a named screen view.
  Future<void> trackScreen(String screenName);

  /// Log a named feature event with optional string properties.
  ///
  /// [properties] values must be plain strings — no financial data, no names.
  Future<void> trackEvent(
    String event, {
    Map<String, String> properties = const {},
  });
}
