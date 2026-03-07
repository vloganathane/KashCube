// ---------------------------------------------------------------------------
// Business Flow Provider — P2.9 / E2 (Pillar D)
// ---------------------------------------------------------------------------
// Provides BusinessFlowChain lists per party and globally (leaking chains).
// All queries are parallel SQLite reads — no network.
// ---------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/business_flow_chain_builder.dart';
import '../../data/models/booking.dart';
import '../../data/models/business_flow_chain.dart';
import '../../data/models/delivery_challan.dart';
import '../../data/models/invoice.dart';
import '../../data/models/party_reminder.dart';
import '../../data/models/quote.dart';
import '../../data/models/transaction.dart';
import 'booking_provider.dart';
import 'delivery_challan_provider.dart';
import 'invoice_provider.dart';
import 'party_provider.dart';
import 'party_reminder_provider.dart';
import 'transaction_provider.dart';

// ---------------------------------------------------------------------------
// Per-party chains
// ---------------------------------------------------------------------------

/// All deal chains for a single party (by partyId).
/// Parameterised by party ID — key input for Party 360° Deals tab.
final businessFlowChainsProvider =
    FutureProvider.family<List<BusinessFlowChain>, int>(
        (ref, partyId) async {
  // Fetch party to get name
  final party = await ref.read(partyRepositoryProvider).getById(partyId);
  if (party == null) throw Exception('Party $partyId not found');

  // Parallel DB reads
  final results = await Future.wait([
    ref.read(quoteRepositoryProvider).getByPartyId(partyId),        // 0
    ref
        .read(deliveryChallanRepositoryProvider)
        .getByPartyId(partyId),                                     // 1
    ref.read(bookingRepositoryProvider).getByPartyId(partyId),      // 2
    ref.read(invoiceRepositoryProvider).getByPartyId(partyId),      // 3
    ref.read(transactionRepositoryProvider).getByPartyId(partyId),  // 4
    ref.read(partyReminderRepositoryProvider).getByParty(party.name), // 5
  ]);

  return BusinessFlowChainBuilder.build(
    partyId: partyId,
    partyName: party.name,
    quotes: results[0] as List<Quote>,
    challans: results[1] as List<DeliveryChallan>,
    bookings: results[2] as List<Booking>,
    invoices: results[3] as List<Invoice>,
    transactions: results[4] as List<Transaction>,
    reminders: (results[5] as List).cast<PartyReminder>(),
  );
});

// ---------------------------------------------------------------------------
// Global leaking chains (Action Center — E5)
// ---------------------------------------------------------------------------

/// All leaking chains across ALL parties.
/// A "leaking chain" = deal that is stuck with no invoice raised:
///   • Accepted quote with no invoice for ≥3 days
///   • Dispatched challan with no invoice for ≥2 days
///   • Confirmed/completed booking past service date with no invoice ≥1 day
///
/// Used by the Action Center "Leaking" urgency section (E5).
final leakingChainsProvider = FutureProvider<List<BusinessFlowChain>>((ref) async {
  // Fetch all parties via repo to guarantee async load
  final partyRepo = ref.read(partyRepositoryProvider);
  final parties = await partyRepo.getAll();

  if (parties.isEmpty) return [];

  // Build chains for each party in parallel
  final partyChainFutures = parties
      .where((p) => p.id != null)
      .map((p) => ref.read(businessFlowChainsProvider(p.id!).future))
      .toList();

  final allChainLists = await Future.wait(partyChainFutures);
  final allChains = allChainLists.expand((c) => c).toList();

  return BusinessFlowChainBuilder.filterLeaking(allChains);
});

/// Count of leaking chains — used in Action Center badge.
final leakingChainCountProvider = Provider<int>((ref) {
  return ref.watch(leakingChainsProvider).valueOrNull?.length ?? 0;
});
