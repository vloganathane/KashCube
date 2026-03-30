import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/my_identity.dart';
import '../../data/repositories/identity_repository_impl.dart';
import '../../data/services/app_logger.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/identity_service.dart';
import '../../domain/repositories/identity_repository.dart';
import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Identity service provider (moved here from deleted sync_provider)
// ---------------------------------------------------------------------------

/// Initialises [IdentityService] on first access (async).
final identityServiceProvider = FutureProvider<IdentityService>((ref) async {
  final settings = ref.read(settingsRepositoryProvider);
  await IdentityService.instance.ensureInitialized(settings);
  return IdentityService.instance;
});

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final identityRepositoryProvider = Provider<IdentityRepository>(
  (_) => IdentityRepositoryImpl(),
);

// ---------------------------------------------------------------------------
// Identity initialisation — runs silently on upgrade (if row already exists)
// ---------------------------------------------------------------------------

/// Ensures [IdentityService.ensureIdentityInitialized] is called at startup.
///
/// For fresh installs (no `my_identity` row) this is a no-op; the setup
/// screen calls it explicitly after the user enters a display name.
///
/// For upgrades the `my_identity` row was created during the v62 DB migration
/// (populated with the identity public key) so we just load the keypair into
/// memory here.
final identityInitProvider = FutureProvider<void>((ref) async {
  // Ensure device signing key is loaded first
  await ref.watch(identityServiceProvider.future);

  // Auto-initialize on fresh install using device hostname.
  // The user can update their display name later from Settings → My Identity.
  String defaultName;
  try {
    defaultName = kIsWeb ? 'KashCube Web' : Platform.localHostname;
  } catch (e, st) {
    AppLogger.instance.debug(
      'Failed to get device hostname for identity init',
      category: 'identity_provider',
      error: e,
    );
    defaultName = 'Me';
  }
  await DatabaseHelper.instance.withDatabase(
    (db) => IdentityService.instance
        .ensureIdentityInitialized(db, displayName: defaultName),
  );
});

// ---------------------------------------------------------------------------
// My identity
// ---------------------------------------------------------------------------

/// The single `my_identity` row, or `null` when not yet set up.
final myIdentityProvider = FutureProvider<MyIdentity?>((ref) async {
  // Re-fetch after initialization
  await ref.watch(identityInitProvider.future);
  return ref.read(identityRepositoryProvider).getMyIdentity();
});

/// `true` once the user has completed identity setup (name entered).
final hasIdentityProvider = FutureProvider<bool>((ref) async {
  final identity = await ref.watch(myIdentityProvider.future);
  return identity != null;
});
