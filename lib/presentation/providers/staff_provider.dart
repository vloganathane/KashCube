import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/staff.dart';
import '../../data/repositories/staff_repository_impl.dart';
import 'inventory_provider.dart' show activeBusinessIdProvider;

final _staffRepo = StaffRepository.instance;

// ── Staff list ─────────────────────────────────────────────────────────────────

class StaffNotifier extends StateNotifier<AsyncValue<List<Staff>>> {
  StaffNotifier(this._businessId) : super(const AsyncValue.loading()) {
    load();
  }

  final int? _businessId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _staffRepo.getAll(businessId: _businessId),
    );
  }

  Future<void> add(Staff staff) async {
    await _staffRepo.insert(staff);
    await load();
  }

  Future<void> update(Staff staff) async {
    await _staffRepo.update(staff);
    await load();
  }

  Future<void> deactivate(int id) async {
    await _staffRepo.deactivate(id);
    await load();
  }
}

final staffProvider =
    StateNotifierProvider.autoDispose<StaffNotifier, AsyncValue<List<Staff>>>(
        (ref) {
  final businessId = ref.watch(activeBusinessIdProvider);
  return StaffNotifier(businessId);
});

// ── Salary payments for one staff member ───────────────────────────────────────

class SalaryPaymentNotifier
    extends StateNotifier<AsyncValue<List<SalaryPayment>>> {
  SalaryPaymentNotifier(this._staffId) : super(const AsyncValue.loading()) {
    load();
  }

  final int _staffId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _staffRepo.getPaymentsForStaff(_staffId),
    );
  }

  Future<void> record(SalaryPayment payment) async {
    await _staffRepo.insertPayment(payment);
    await load();
  }

  Future<void> update(SalaryPayment payment) async {
    await _staffRepo.updatePayment(payment);
    await load();
  }

  Future<void> remove(int id) async {
    await _staffRepo.deletePayment(id);
    await load();
  }
}

final salaryPaymentsProvider = StateNotifierProvider.autoDispose
    .family<SalaryPaymentNotifier, AsyncValue<List<SalaryPayment>>, int>(
        (ref, staffId) {
  return SalaryPaymentNotifier(staffId);
});

// activeBusinessIdProvider is imported from inventory_provider.dart
