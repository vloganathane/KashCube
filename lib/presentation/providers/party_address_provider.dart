import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/party_address.dart';
import '../../data/repositories/party_address_repository_impl.dart';
import '../../domain/repositories/party_address_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final partyAddressRepositoryProvider = Provider<PartyAddressRepository>(
  (_) => PartyAddressRepositoryImpl(),
);

// ── Per-party addresses (default first) ──────────────────────────────────────

final partyAddressesProvider =
    FutureProvider.family<List<PartyAddress>, int>((ref, partyId) {
  return ref.read(partyAddressRepositoryProvider).getByPartyId(partyId);
});
