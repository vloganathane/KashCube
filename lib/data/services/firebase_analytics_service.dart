// ignore_for_file: depend_on_referenced_packages
//
// ─── Firebase Analytics backend ──────────────────────────────────────────────
//
// Setup checklist (one-time, per developer):
//   1. Run `flutterfire configure` in the project root.
//      This generates google-services.json (Android) and
//      GoogleService-Info.plist (iOS/macOS) and updates this file.
//   2. Place google-services.json in android/app/  (already gitignored).
//   3. Apply the google-services Gradle plugin — see docs/technical/FIREBASE_SETUP.md.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_analytics/firebase_analytics.dart';

import 'analytics_service.dart';

/// Firebase Analytics backend.
///
/// Consent is applied via [setEnabled] before any events are sent.
/// No financial data (amounts, party names, balances) may appear in
/// event names or properties — callers are responsible for this.
class FirebaseAnalyticsService implements AnalyticsService {
  final _fa = FirebaseAnalytics.instance;

  @override
  Future<void> setEnabled(bool enabled) =>
      _fa.setAnalyticsCollectionEnabled(enabled);

  @override
  Future<void> trackScreen(String screenName) =>
      _fa.logScreenView(screenName: screenName);

  @override
  Future<void> trackEvent(
    String event, {
    Map<String, String> properties = const {},
  }) => _fa.logEvent(name: event, parameters: properties);
}
