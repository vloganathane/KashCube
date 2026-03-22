import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/analytics_events.dart';
import '../../data/services/analytics_service.dart';
import '../../data/services/firebase_analytics_service.dart';
// ignore: unused_import — kept for easy swap in tests
import '../../data/services/noop_analytics_service.dart';

import 'settings_provider.dart';

export '../../data/services/analytics_events.dart';
export '../../data/services/analytics_service.dart';

// ---------------------------------------------------------------------------
// Backend selector
// ---------------------------------------------------------------------------

/// Switch this to [FirebaseAnalyticsService()] once you've added the
/// firebase_analytics package and run `flutterfire configure`.
///
/// The rest of the app never changes — only this one line.
AnalyticsService _buildBackend() {
  return FirebaseAnalyticsService();
  // return const NoOpAnalyticsService(); // ← use this for debug / unit tests
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provides a configured [AnalyticsService] respecting the user's consent.
///
/// - If consent is null (not asked yet) → no-op, nothing is sent.
/// - If consent is false → no-op, nothing is sent.
/// - If consent is true → backend fires events.
///
/// Use [analyticsConsentProvider] to read/update consent in Settings.
final analyticsProvider = FutureProvider<AnalyticsService>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final raw = await settings.get(SettingsKeys.analyticsConsent);
  final consented = raw == 'true';

  final service = _buildBackend();
  await service.setEnabled(consented);
  return service;
});

// ---------------------------------------------------------------------------
// Consent notifier
// ---------------------------------------------------------------------------

/// Read/toggle analytics consent. Updates the backend immediately.
final analyticsConsentProvider =
    AsyncNotifierProvider<_ConsentNotifier, bool?>(_ConsentNotifier.new);

class _ConsentNotifier extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() async {
    final raw = await ref
        .read(settingsRepositoryProvider)
        .get(SettingsKeys.analyticsConsent);
    return switch (raw) {
      'true'  => true,
      'false' => false,
      _       => null, // not yet asked
    };
  }

  Future<void> setConsent(bool value) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(SettingsKeys.analyticsConsent, value.toString());
    state = AsyncData(value);

    // Propagate immediately to the active backend.
    final analytics = await ref.read(analyticsProvider.future);
    await analytics.setEnabled(value);

    // Log the consent event itself (only fires if enabled).
    await analytics.trackEvent(
      value
          ? AnalyticsEvents.analyticsConsentGiven
          : AnalyticsEvents.analyticsConsentRevoked,
    );

    // Re-evaluate analyticsProvider.
    ref.invalidate(analyticsProvider);
  }
}

// ---------------------------------------------------------------------------
// Convenience helper
// ---------------------------------------------------------------------------

/// Tracks an event if analytics is ready and consented.
/// Safe to call without awaiting — fire-and-forget.
void trackEvent(
  WidgetRef ref,
  String event, {
  Map<String, String> properties = const {},
}) {
  ref.read(analyticsProvider).whenData(
        (svc) => svc.trackEvent(event, properties: properties),
      );
}

void trackScreen(WidgetRef ref, String screenName) {
  ref.read(analyticsProvider).whenData(
        (svc) => svc.trackScreen(screenName),
      );
}
