import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Version constant — bump this whenever you update the T&C text.
// Users who accepted an older version will be prompted to re-read and accept.
// ---------------------------------------------------------------------------

abstract final class AppTerms {
  /// Current T&C version. Bump (e.g. '1.1', '2.0') to re-prompt all users.
  /// When bumped, all users must re-accept before using the app.
  static const currentVersion = '2.2';
}

// ---------------------------------------------------------------------------
// Provider — true if current version is accepted, false otherwise
// ---------------------------------------------------------------------------

/// Async state: null = loading, true = accepted, false = not yet accepted.
final termsAcceptedProvider = AsyncNotifierProvider<_TermsNotifier, bool>(
  _TermsNotifier.new,
);

class _TermsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    debugPrint('[Terms] Checking terms acceptance...');
    final settings = ref.read(settingsRepositoryProvider);
    final accepted = await settings
        .get(SettingsKeys.termsAcceptedVersion)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint(
              '[Terms] Timeout reading acceptance version; defaulting to not accepted',
            );
            return null;
          },
        );
    debugPrint(
      '[Terms] Accepted version: $accepted (current: ${AppTerms.currentVersion})',
    );
    final result = accepted == AppTerms.currentVersion;
    debugPrint('[Terms] Result: $result');
    return result;
  }

  /// Persist acceptance with version + timestamp, then enable analytics.
  Future<void> accept() async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(
      SettingsKeys.termsAcceptedVersion,
      AppTerms.currentVersion,
    );
    await settings.set(
      SettingsKeys.termsAcceptedAt,
      DateTime.now().toIso8601String(),
    );

    // Accepting T&C also constitutes analytics consent (disclosed in §6).
    await settings.set(SettingsKeys.analyticsConsent, 'true');

    state = const AsyncData(true);
  }
}
