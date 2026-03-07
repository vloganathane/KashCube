import '../../data/models/party_address.dart';

/// Repository interface for managing multiple addresses per party.
abstract class PartyAddressRepository {
  /// Returns all addresses for [partyId], default address first.
  Future<List<PartyAddress>> getByPartyId(int partyId);

  /// Inserts a new address and returns its generated row id.
  Future<int> insert(PartyAddress address);

  /// Updates an existing address in-place.
  Future<void> update(PartyAddress address);

  /// Permanently deletes an address by [id].
  Future<void> delete(int id);

  /// Sets address [addressId] as the default for [partyId].
  /// Clears the default flag on all other addresses for that party.
  Future<void> setDefault(int partyId, int addressId);
}
