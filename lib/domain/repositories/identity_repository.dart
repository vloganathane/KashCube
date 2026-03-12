import '../../../data/models/my_identity.dart';

/// Abstract contract for reading and updating the device's permanent identity.
abstract class IdentityRepository {
  /// Returns the single `my_identity` row, or `null` when the identity has not
  /// been set up yet (fresh install before [IdentitySetupScreen]).
  Future<MyIdentity?> getMyIdentity();

  /// Creates the identity row for the first time.
  Future<void> createIdentity({
    required String identityId,
    required String displayName,
    required String publicKey,
  });

  /// Updates the user-visible display name.
  Future<void> updateDisplayName(String name);

  /// Replaces the stored public key (e.g. after importing a backup).
  Future<void> setPublicKey(String publicKeyBase64);
}
