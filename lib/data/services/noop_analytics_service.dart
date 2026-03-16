import 'analytics_service.dart';

/// Default no-op backend — used before consent is given and in debug builds.
/// Zero network calls, zero side effects.
class NoOpAnalyticsService implements AnalyticsService {
  const NoOpAnalyticsService();

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> trackScreen(String screenName) async {}

  @override
  Future<void> trackEvent(
    String event, {
    Map<String, String> properties = const {},
  }) async {}
}
