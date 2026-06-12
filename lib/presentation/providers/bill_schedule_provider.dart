import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bill.dart';
import '../../../data/repositories/bill_schedule_repository_impl.dart';
import '../../../domain/repositories/bill_schedule_repository.dart';

/// Repository provider for scheduled bills.
final billScheduleRepositoryProvider = Provider<BillScheduleRepository>(
  (ref) => BillScheduleRepositoryImpl(),
);

/// Main list provider: all active bills.
final scheduledBillsProvider =
    StateNotifierProvider<ScheduledBillsNotifier, AsyncValue<List<Bill>>>(
      (ref) => ScheduledBillsNotifier(ref.read(billScheduleRepositoryProvider)),
    );

/// Notifier with CRUD + markPaid for scheduled bills.
class ScheduledBillsNotifier extends StateNotifier<AsyncValue<List<Bill>>> {
  ScheduledBillsNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadAll();
  }

  final BillScheduleRepository _repo;

  Future<void> loadAll() async {
    try {
      state = const AsyncValue.loading();
      final bills = await _repo.getAll();
      state = AsyncValue.data(bills);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addBill(Bill bill) async {
    await _repo.insert(bill);
    await loadAll();
  }

  Future<void> updateBill(Bill bill) async {
    await _repo.update(bill);
    await loadAll();
  }

  Future<void> deleteBill(int id) async {
    await _repo.delete(id);
    await loadAll();
  }

  Future<void> markPaid(int id) async {
    await _repo.markPaid(id);
    await loadAll();
  }

  Future<void> markUnpaid(int id) async {
    await _repo.markUnpaid(id);
    await loadAll();
  }
}

/// Single bill by id.
final scheduledBillByIdProvider = FutureProvider.family<Bill?, int>((ref, id) {
  return ref.read(billScheduleRepositoryProvider).getById(id);
});

/// Overdue bills.
final overdueBillsProvider = FutureProvider<List<Bill>>((ref) {
  return ref.read(billScheduleRepositoryProvider).getOverdue();
});

/// Upcoming bills (next 7 days).
final upcomingBillsProvider = FutureProvider<List<Bill>>((ref) {
  return ref.read(billScheduleRepositoryProvider).getUpcoming(days: 7);
});

/// Total monthly bill outflow.
final totalMonthlyBillsProvider = FutureProvider<double>((ref) {
  return ref.read(billScheduleRepositoryProvider).getTotalMonthly();
});
