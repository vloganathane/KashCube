import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/purchase_bill.dart';
import '../../data/repositories/purchase_bill_repository_impl.dart';
import '../../data/services/inventory_service.dart';
import '../../domain/repositories/purchase_bill_repository.dart';
import 'business_provider.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final purchaseBillRepositoryProvider = Provider<PurchaseBillRepository>(
  (_) => PurchaseBillRepositoryImpl(),
);

// ── Filters ───────────────────────────────────────────────────────────────────

/// null = show all statuses
final purchaseBillStatusFilterProvider =
    StateProvider<PurchaseBillStatus?>((_) => null);

/// Filter by ITC eligibility (null = show all)
final purchaseBillItcFilterProvider =
    StateProvider<ItcEligibility?>((_) => null);

// ── Bills list for active business ────────────────────────────────────────────

class PurchaseBillsNotifier
    extends StateNotifier<AsyncValue<List<PurchaseBill>>> {
  PurchaseBillsNotifier(this._repo, this._businessId)
      : super(const AsyncValue.loading()) {
    load();
  }

  final PurchaseBillRepository _repo;
  final int? _businessId;

  Future<void> load() async {
    if (_businessId == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => _repo.fetchForBusiness(_businessId));
  }

  Future<void> add(
      PurchaseBill bill, List<PurchaseBillItem> items) async {
    final id = await _repo.insert(bill, items);
    // Add stock for tracked catalog items on purchase bill save.
    for (final item in items) {
      if (item.catalogItemId != null && item.qty > 0) {
        await InventoryService.instance.addStock(
          item.catalogItemId!,
          item.qty,
          notes: 'Purchase Bill ${bill.billNo}',
          referenceId: id,
          referenceType: 'purchase_bill',
        );
      }
    }
    await load();
  }

  Future<void> edit(
      PurchaseBill bill, List<PurchaseBillItem> items) async {
    // Reverse previous stock movements then re-apply for edited items.
    if (bill.id != null) {
      await InventoryService.instance
          .reverseMovementsFor('purchase_bill', bill.id!);
    }
    await _repo.update(bill, items);
    for (final item in items) {
      if (item.catalogItemId != null && item.qty > 0) {
        await InventoryService.instance.addStock(
          item.catalogItemId!,
          item.qty,
          notes: 'Purchase Bill ${bill.billNo} (edited)',
          referenceId: bill.id,
          referenceType: 'purchase_bill',
        );
      }
    }
    await load();
  }

  Future<void> remove(int id) async {
    // Reverse stock additions before deleting.
    await InventoryService.instance.reverseMovementsFor('purchase_bill', id);
    await _repo.delete(id);
    await load();
  }

  Future<void> recordPayment({
    required int billId,
    required double amount,
    required DateTime paidAt,
  }) async {
    await _repo.recordPayment(
        billId: billId, amount: amount, paidAt: paidAt);
    await load();
  }

  Future<void> toggleItcAvailed(int billId, {required bool availed}) async {
    await _repo.markItcAvailed(billId, availed: availed);
    await load();
  }
}

final purchaseBillsProvider =
    StateNotifierProvider<PurchaseBillsNotifier, AsyncValue<List<PurchaseBill>>>(
  (ref) {
    final repo = ref.read(purchaseBillRepositoryProvider);
    final business = ref.watch(activeBusinessProvider);
    return PurchaseBillsNotifier(repo, business?.id);
  },
);

// ── Derived: filtered list ────────────────────────────────────────────────────

final filteredPurchaseBillsProvider =
    Provider<AsyncValue<List<PurchaseBill>>>((ref) {
  final all = ref.watch(purchaseBillsProvider);
  final statusFilter = ref.watch(purchaseBillStatusFilterProvider);
  final itcFilter = ref.watch(purchaseBillItcFilterProvider);

  return all.whenData((bills) {
    var result = bills;
    if (statusFilter != null) {
      result = result.where((b) => b.status == statusFilter).toList();
    }
    if (itcFilter != null) {
      result =
          result.where((b) => b.itcEligibility == itcFilter).toList();
    }
    return result;
  });
});

// ── Derived: ITC summary for active business (current FY) ────────────────────

/// Quick totals across all loaded bills for the active business.
class PurchaseItcSummary {
  const PurchaseItcSummary({
    required this.igstEligible,
    required this.cgstEligible,
    required this.sgstEligible,
    required this.igstBlocked,
    required this.cgstBlocked,
    required this.sgstBlocked,
    required this.totalBills,
  });

  final double igstEligible;
  final double cgstEligible;
  final double sgstEligible;
  final double igstBlocked;
  final double cgstBlocked;
  final double sgstBlocked;
  final int totalBills;

  double get totalEligible => igstEligible + cgstEligible + sgstEligible;
  double get totalBlocked => igstBlocked + cgstBlocked + sgstBlocked;

  static const zero = PurchaseItcSummary(
    igstEligible: 0,
    cgstEligible: 0,
    sgstEligible: 0,
    igstBlocked: 0,
    cgstBlocked: 0,
    sgstBlocked: 0,
    totalBills: 0,
  );
}

final purchaseItcSummaryProvider = Provider<PurchaseItcSummary>((ref) {
  final all = ref.watch(purchaseBillsProvider);
  return all.when(
    data: (bills) {
      double igstE = 0, cgstE = 0, sgstE = 0;
      double igstB = 0, cgstB = 0, sgstB = 0;
      for (final b in bills) {
        if (b.itcEligibility == ItcEligibility.eligible) {
          igstE += b.igstAmount;
          cgstE += b.cgstAmount;
          sgstE += b.sgstAmount;
        } else {
          igstB += b.igstAmount;
          cgstB += b.cgstAmount;
          sgstB += b.sgstAmount;
        }
      }
      return PurchaseItcSummary(
        igstEligible: igstE,
        cgstEligible: cgstE,
        sgstEligible: sgstE,
        igstBlocked: igstB,
        cgstBlocked: cgstB,
        sgstBlocked: sgstB,
        totalBills: bills.length,
      );
    },
    loading: () => PurchaseItcSummary.zero,
    error: (_, err) => PurchaseItcSummary.zero,
  );
});
