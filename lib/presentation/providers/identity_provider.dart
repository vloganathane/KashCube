import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/my_identity.dart';
import '../../data/repositories/identity_repository_impl.dart';
import '../../data/services/database_helper.dart';
import '../../data/services/identity_service.dart';
import '../../domain/repositories/identity_repository.dart';
import 'sync_provider.dart';

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

  final rows = await DatabaseHelper.instance.withDatabase(
    (db) => db.query('my_identity', limit: 1),
  );
  if (rows.isEmpty) return; // fresh install — wait for IdentitySetupScreen

  await DatabaseHelper.instance.withDatabase(
    (db) => IdentityService.instance.ensureIdentityInitialized(db),
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
