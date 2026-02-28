import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository_impl.dart';
import '../../domain/repositories/booking_repository.dart';

// ── Repository provider ──────────────────────────────────────────────────────

final bookingRepositoryProvider = Provider<BookingRepository>(
  (_) => BookingRepositoryImpl(),
);

// ── Filter ───────────────────────────────────────────────────────────────────

/// null = show all, otherwise filter by specific status
final bookingFilterProvider = StateProvider<BookingStatus?>((_) => null);

/// null = show all types, otherwise filter by business/personal
final bookingTypeFilterProvider = StateProvider<BookingType?>((_) => null);

/// Search query for filtering bookings by customer name, service, or ref
final bookingSearchQueryProvider = StateProvider<String>((_) => '');

// ── Bookings ─────────────────────────────────────────────────────────────────

class BookingsNotifier extends StateNotifier<AsyncValue<List<Booking>>> {
  BookingsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final BookingRepository _repo;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getAll());
  }

  Future<int> add(Booking booking) async {
    final id = await _repo.insert(booking);
    await load();
    return id;
  }

  Future<void> edit(Booking booking) async {
    await _repo.update(booking);
    await load();
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    await load();
  }

  Future<void> markAsConfirmed(int id) async {
    await _repo.markAsConfirmed(id);
    await load();
  }

  Future<void> markAsCompleted(int id) async {
    await _repo.markAsCompleted(id);
    await load();
  }

  Future<void> markAsCancelled(int id) async {
    await _repo.markAsCancelled(id);
    await load();
  }

  Future<void> markAsNoShow(int id) async {
    await _repo.markAsNoShow(id);
    await load();
  }

  Future<void> linkInvoice(int bookingId, int invoiceId) async {
    await _repo.linkInvoice(bookingId, invoiceId);
    await load();
  }
}

final bookingsProvider =
    StateNotifierProvider<BookingsNotifier, AsyncValue<List<Booking>>>(
  (ref) => BookingsNotifier(ref.read(bookingRepositoryProvider)),
);

// ── Single booking provider ──────────────────────────────────────────────────

/// Derives a single booking from the already-loaded [bookingsProvider] so it
/// automatically reflects any status change (confirm, complete, cancel, etc.)
/// without a separate DB fetch.
final bookingByIdProvider =
    Provider.family<AsyncValue<Booking?>, int>((ref, id) {
  final bookings = ref.watch(bookingsProvider);
  return bookings.whenData(
    (list) => list.cast<Booking?>().firstWhere(
          (b) => b?.id == id,
          orElse: () => null,
        ),
  );
});

/// Reverse-lookup: find the booking that is linked to a given invoice.
final bookingByInvoiceIdProvider =
    Provider.family<Booking?, int>((ref, invoiceId) {
  final bookings = ref.watch(bookingsProvider).valueOrNull ?? [];
  return bookings.cast<Booking?>().firstWhere(
    (b) => b?.invoiceId == invoiceId,
    orElse: () => null,
  );
});

// ── Upcoming bookings provider ───────────────────────────────────────────────

final upcomingBookingsProvider =
    FutureProvider<List<Booking>>((ref) async {
  final repo = ref.read(bookingRepositoryProvider);
  return repo.getUpcoming(limit: 10);
});

// ── Filtered bookings provider ───────────────────────────────────────────────

final filteredBookingsProvider = Provider<AsyncValue<List<Booking>>>((ref) {
  final bookings = ref.watch(bookingsProvider);
  final filter = ref.watch(bookingFilterProvider);
  final typeFilter = ref.watch(bookingTypeFilterProvider);
  final searchQuery = ref.watch(bookingSearchQueryProvider).toLowerCase();

  return bookings.whenData((list) {
    var filtered = list;

    // Apply status filter
    if (filter != null) {
      filtered = filtered.where((b) => b.status == filter).toList();
    }

    // Apply type filter (business vs personal)
    if (typeFilter != null) {
      filtered = filtered.where((b) => b.bookingType == typeFilter).toList();
    }

    // Apply search query
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((b) {
        return b.customerName.toLowerCase().contains(searchQuery) ||
            b.serviceName.toLowerCase().contains(searchQuery) ||
            (b.bookingRef?.toLowerCase().contains(searchQuery) ?? false) ||
            (b.notes?.toLowerCase().contains(searchQuery) ?? false);
      }).toList();
    }

    return filtered;
  });
});
