import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
import '../../data/models/booking_item.dart';
import '../../data/repositories/booking_repository_impl.dart';
import '../../data/services/notification_service.dart';
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
  final _notifications = NotificationService.instance;

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
    // Schedule 24 h-ahead reminder
    final booking = await _repo.getById(id);
    if (booking != null) {
      await _notifications.scheduleBookingReminder(booking);
    }
  }

  Future<void> markAsCompleted(int id) async {
    await _repo.markAsCompleted(id);
    await load();
    await _notifications.cancelBookingReminder(id);
  }

  Future<void> markAsCancelled(int id) async {
    await _repo.markAsCancelled(id);
    await load();
    await _notifications.cancelBookingReminder(id);
  }

  Future<void> markAsNoShow(int id) async {
    await _repo.markAsNoShow(id);
    await load();
    await _notifications.cancelBookingReminder(id);
  }

  Future<void> linkInvoice(int bookingId, int invoiceId) async {
    await _repo.linkInvoice(bookingId, invoiceId);
    await load();
  }

  /// Record that a manual reminder (WhatsApp/SMS/Email) was sent for [bookingId].
  Future<void> markReminderSent(int bookingId) async {
    await _repo.markReminderSent(bookingId);
    await load();
  }

  // ── Items ──────────────────────────────────────────────────────────────────

  /// Save (create or update) a booking together with its line items.
  /// On create: inserts booking first, then saves items with the new id.
  /// On edit: updates booking, then replaces all items atomically.
  Future<int> saveWithItems(Booking booking, List<BookingItem> items) async {
    final int id;
    if (booking.id == null) {
      id = await _repo.insert(booking);
    } else {
      await _repo.update(booking);
      id = booking.id!;
    }
    await _repo.saveItems(id, items);
    await load();
    return id;
  }

  // ── Payments ─────────────────────────────────────────────────────────────

  /// Record a payment against the booking.
  /// Increments [paid_amount]; auto-completes when fully paid.
  Future<void> recordPayment({
    required int bookingId,
    required double amount,
  }) async {
    await _repo.recordPayment(bookingId: bookingId, amount: amount);
    await load();
  }
}

final bookingsProvider =
    StateNotifierProvider<BookingsNotifier, AsyncValue<List<Booking>>>(
      (ref) => BookingsNotifier(ref.read(bookingRepositoryProvider)),
    );

// ── Per-booking items ──────────────────────────────────────────────────────────

/// Loads the ordered line items for a single booking.
/// Used by booking detail screen and "Create Invoice" conversion.
final bookingItemsProvider = FutureProvider.autoDispose
    .family<List<BookingItem>, int>((ref, bookingId) async {
      final repo = ref.read(bookingRepositoryProvider);
      return repo.getItems(bookingId);
    });

// ── Single booking provider ──────────────────────────────────────────────────

/// Derives a single booking from the already-loaded [bookingsProvider] so it
/// automatically reflects any status change (confirm, complete, cancel, etc.)
/// without a separate DB fetch.
final bookingByIdProvider = Provider.family<AsyncValue<Booking?>, int>((
  ref,
  id,
) {
  final bookings = ref.watch(bookingsProvider);
  return bookings.whenData(
    (list) => list.cast<Booking?>().firstWhere(
      (b) => b?.id == id,
      orElse: () => null,
    ),
  );
});

/// Reverse-lookup: find the booking that is linked to a given invoice.
final bookingByInvoiceIdProvider = Provider.family<Booking?, int>((
  ref,
  invoiceId,
) {
  final bookings = ref.watch(bookingsProvider).valueOrNull ?? [];
  return bookings.cast<Booking?>().firstWhere(
    (b) => b?.invoiceId == invoiceId,
    orElse: () => null,
  );
});

// ── Upcoming bookings provider ───────────────────────────────────────────────

final upcomingBookingsProvider = FutureProvider<List<Booking>>((ref) async {
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

// ── Booking month stats ───────────────────────────────────────────────────────

/// Aggregated booking stats for a given calendar month (used by Reports screen).
class BookingMonthStats {
  const BookingMonthStats({
    this.completedCount = 0,
    this.completedRevenue = 0,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.noShowCount = 0,
    this.topService,
  });

  final int completedCount;
  final double completedRevenue;
  final int confirmedCount;
  final int pendingCount;
  final int noShowCount;
  final String? topService;

  bool get hasData =>
      completedCount > 0 ||
      confirmedCount > 0 ||
      pendingCount > 0 ||
      noShowCount > 0;
}

/// Derives booking stats for a given [month] from the already-loaded
/// [bookingsProvider].  Only considers business-type bookings.
final bookingMonthStatsProvider = Provider.family<BookingMonthStats, DateTime>((
  ref,
  month,
) {
  final bookings = ref.watch(bookingsProvider).valueOrNull ?? [];

  final monthStart = DateTime(month.year, month.month, 1);
  final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

  final inMonth = bookings.where((b) {
    return b.bookingType == BookingType.business &&
        !b.startDatetime.isBefore(monthStart) &&
        !b.startDatetime.isAfter(monthEnd);
  }).toList();

  final completed = inMonth
      .where((b) => b.status == BookingStatus.completed)
      .toList();
  final revenue = completed.fold<double>(0, (s, b) => s + b.totalAmount);

  final confirmed = inMonth
      .where((b) => b.status == BookingStatus.confirmed)
      .length;
  final pending = inMonth
      .where((b) => b.status == BookingStatus.pending)
      .length;
  final noShow = inMonth.where((b) => b.status == BookingStatus.noShow).length;

  // Top service by frequency across all bookings (not just this month)
  final serviceFreq = <String, int>{};
  for (final b in bookings.where(
    (b) => b.bookingType == BookingType.business,
  )) {
    serviceFreq[b.serviceName] = (serviceFreq[b.serviceName] ?? 0) + 1;
  }
  final topServiceEntry = serviceFreq.entries.isEmpty
      ? null
      : serviceFreq.entries.reduce((a, b) => a.value >= b.value ? a : b);

  return BookingMonthStats(
    completedCount: completed.length,
    completedRevenue: revenue,
    confirmedCount: confirmed,
    pendingCount: pending,
    noShowCount: noShow,
    topService: topServiceEntry?.key,
  );
});
