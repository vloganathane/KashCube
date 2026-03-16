// ignore_for_file: depend_on_referenced_packages
//
// ─── Firebase Analytics backend ──────────────────────────────────────────────
//
// HOW TO ACTIVATE
// ───────────────
// 1. Add to pubspec.yaml:
//      firebase_core: ^3.x.x
//      firebase_analytics: ^11.x.x
//
// 2. Run `flutterfire configure` once to generate google-services.json
//    and add it to android/app/ (gitignored).
//
// 3. In lib/presentation/providers/analytics_provider.dart change:
//      Analytics.backend = const NoOpAnalyticsService();
//    to:
//      Analytics.backend = FirebaseAnalyticsService();
//
// 4. Remove the conditional import stub below once the package is present.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'analytics_service.dart';

// Conditional import: resolves to the real Firebase impl when the package
// exists; falls back to the no-op stub otherwise.
//
// Replace this file with the real implementation below once
// `firebase_analytics` is in pubspec.yaml:
//
// import 'package:firebase_analytics/firebase_analytics.dart';
//
// class FirebaseAnalyticsService implements AnalyticsService {
//   final _fa = FirebaseAnalytics.instance;
//
//   @override
//   Future<void> setEnabled(bool enabled) =>
//       _fa.setAnalyticsCollectionEnabled(enabled);
//
//   @override
//   Future<void> trackScreen(String screenName) =>
//       _fa.logScreenView(screenName: screenName);
//
//   @override
//   Future<void> trackEvent(
//     String event, {
//     Map<String, String> properties = const {},
//   }) =>
//       _fa.logEvent(name: event, parameters: properties);
// }

/// Placeholder class — replace this file when firebase_analytics is added.
class FirebaseAnalyticsService implements AnalyticsService {
  @override
  Future<void> setEnabled(bool enabled) async {
    throw UnimplementedError(
      'Add firebase_analytics to pubspec.yaml and replace '
      'lib/data/services/firebase_analytics_service.dart with the real impl.',
    );
  }

  @override
  Future<void> trackScreen(String screenName) async {}

  @override
  Future<void> trackEvent(
    String event, {
    Map<String, String> properties = const {},
  }) async {}
}
