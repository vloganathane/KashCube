import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Version constant — bump this whenever you update the T&C text.
// Users who accepted an older version will be prompted to re-read and accept.
// ---------------------------------------------------------------------------

abstract final class AppTerms {
  /// Current T&C version. Bump (e.g. '1.1', '2.0') to re-prompt all users.
  static const currentVersion = '1.0';
}

// ---------------------------------------------------------------------------
// Provider — true if current version is accepted, false otherwise
// ---------------------------------------------------------------------------

/// Async state: null = loading, true = accepted, false = not yet accepted.
final termsAcceptedProvider =
    AsyncNotifierProvider<_TermsNotifier, bool>(_TermsNotifier.new);

class _TermsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final settings = ref.read(settingsRepositoryProvider);
    final accepted = await settings.get(SettingsKeys.termsAcceptedVersion);
    return accepted == AppTerms.currentVersion;
  }

  /// Persist acceptance with version + timestamp, then enable analytics.
  Future<void> accept() async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(
        SettingsKeys.termsAcceptedVersion, AppTerms.currentVersion);
    await settings.set(
        SettingsKeys.termsAcceptedAt, DateTime.now().toIso8601String());

    // Accepting T&C also constitutes analytics consent (disclosed in §6).
    await settings.set(SettingsKeys.analyticsConsent, 'true');

    state = const AsyncData(true);
  }
}
