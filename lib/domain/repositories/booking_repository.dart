import '../../data/models/booking.dart';

abstract class BookingRepository {
  /// Get all bookings
  Future<List<Booking>> getAll();
  
  /// Get bookings by status
  Future<List<Booking>> getByStatus(BookingStatus status);
  
  /// Get bookings by customer party ID
  Future<List<Booking>> getByCustomer(int customerPartyId);
  
  /// Get bookings within date range
  Future<List<Booking>> getByDateRange(DateTime start, DateTime end);
  
  /// Get upcoming bookings (confirmed, not completed, future date)
  Future<List<Booking>> getUpcoming({int limit = 10});
  
  /// Get booking by ID
  Future<Booking?> getById(int id);
  
  /// Get booking by reference number
  Future<Booking?> getByRef(String bookingRef);
  
  /// Insert new booking
  Future<int> insert(Booking booking);
  
  /// Update existing booking
  Future<void> update(Booking booking);
  
  /// Delete booking (soft delete)
  Future<void> delete(int id);
  
  /// Generate next booking reference number
  /// BK-YYYY-NNN for business, SC-YYYY-NNN for personal
  Future<String> generateBookingRef([BookingType type = BookingType.business]);
  
  /// Mark booking as confirmed
  Future<void> markAsConfirmed(int id);
  
  /// Mark booking as completed
  Future<void> markAsCompleted(int id);
  
  /// Mark booking as cancelled
  Future<void> markAsCancelled(int id);
  
  /// Mark booking as no-show
  Future<void> markAsNoShow(int id);
  
  /// Link invoice to booking
  Future<void> linkInvoice(int bookingId, int invoiceId);

  /// Record that a manual reminder (WhatsApp/SMS/Email) was sent for [bookingId].
  Future<void> markReminderSent(int bookingId);
}
