import '../../data/models/booking.dart';
import '../../data/models/booking_item.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/booking_repository.dart';

class BookingRepositoryImpl implements BookingRepository {
  final _db = DatabaseHelper.instance;
  static const String _table = 'bookings';

  @override
  Future<List<Booking>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(_table, 
        orderBy: 'start_datetime DESC');
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<List<Booking>> getByStatus(BookingStatus status) async {
    final db = await _db.database;
    final rows = await db.query(_table,
        where: 'status = ?',
        whereArgs: [status.dbValue],
        orderBy: 'start_datetime DESC');
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<List<Booking>> getByCustomer(int customerPartyId) async {
    final db = await _db.database;
    final rows = await db.query(_table,
        where: 'customer_party_id = ?',
        whereArgs: [customerPartyId],
        orderBy: 'start_datetime DESC');
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<List<Booking>> getByDateRange(DateTime start, DateTime end) async {
    final db = await _db.database;
    final rows = await db.query(_table,
        where: 'start_datetime >= ? AND start_datetime <= ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'start_datetime ASC');
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<List<Booking>> getUpcoming({int limit = 10}) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(_table,
        where: 'status IN (?, ?) AND start_datetime >= ?',
        whereArgs: [
          BookingStatus.confirmed.dbValue,
          BookingStatus.pending.dbValue,
          now
        ],
        orderBy: 'start_datetime ASC',
        limit: limit);
    return rows.map(Booking.fromMap).toList();
  }

  @override
  Future<Booking?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(_table,
        where: 'id = ?',
        whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Booking.fromMap(rows.first);
  }

  @override
  Future<Booking?> getByRef(String bookingRef) async {
    final db = await _db.database;
    final rows = await db.query(_table,
        where: 'booking_ref = ?',
        whereArgs: [bookingRef]);
    if (rows.isEmpty) return null;
    return Booking.fromMap(rows.first);
  }

  @override
  Future<int> insert(Booking booking) async {
    final db = await _db.database;
    
    // Generate booking reference if not provided
    String bookingRef = booking.bookingRef ?? await generateBookingRef(booking.bookingType);
    
    final bookingWithRef = booking.copyWith(bookingRef: bookingRef);
    return db.insert(_table, bookingWithRef.toMap());
  }

  @override
  Future<void> update(Booking booking) async {
    final db = await _db.database;
    final map = booking.copyWith(updatedAt: DateTime.now()).toMap();
    await db.update(_table, map, 
        where: 'id = ?', 
        whereArgs: [booking.id]);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete(_table, 
        where: 'id = ?', 
        whereArgs: [id]);
  }

  @override
  Future<String> generateBookingRef([BookingType type = BookingType.business]) async {
    final db = await _db.database;
    final year = DateTime.now().year;
    final prefix = type == BookingType.personal ? 'SC' : 'BK';

    // Get the highest number for this prefix + year
    final result = await db.rawQuery('''
      SELECT booking_ref FROM $_table 
      WHERE booking_ref LIKE '$prefix-$year-%' 
      ORDER BY booking_ref DESC 
      LIMIT 1
    ''');

    int nextNumber = 1;
    if (result.isNotEmpty) {
      final lastRef = result.first['booking_ref'] as String?;
      if (lastRef != null) {
        final parts = lastRef.split('-');
        if (parts.length == 3) {
          nextNumber = (int.tryParse(parts[2]) ?? 0) + 1;
        }
      }
    }

    // Format: BK-2026-001 or SC-2026-001
    return '$prefix-$year-${nextNumber.toString().padLeft(3, '0')}';
  }

  @override
  Future<void> markAsConfirmed(int id) async {
    final db = await _db.database;
    await db.update(_table, {
      'status': BookingStatus.confirmed.dbValue,
      'confirmed_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markAsCompleted(int id) async {
    final db = await _db.database;
    await db.update(_table, {
      'status': BookingStatus.completed.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markAsCancelled(int id) async {
    final db = await _db.database;
    await db.update(_table, {
      'status': BookingStatus.cancelled.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markAsNoShow(int id) async {
    final db = await _db.database;
    await db.update(_table, {
      'status': BookingStatus.noShow.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> linkInvoice(int bookingId, int invoiceId) async {
    final db = await _db.database;
    await db.update(_table, {
      'invoice_id': invoiceId,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [bookingId]);
  }

  @override
  Future<void> markReminderSent(int bookingId) async {
    final db = await _db.database;
    await db.update(
      _table,
      {'reminder_sent_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [bookingId],
    );
  }

  // ── Booking items ─────────────────────────────────────────────────────────

  @override
  Future<void> saveItems(int bookingId, List<BookingItem> items) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('booking_items',
          where: 'booking_id = ?', whereArgs: [bookingId]);
      for (var i = 0; i < items.length; i++) {
        final item = items[i].copyWith(bookingId: bookingId, sortOrder: i);
        await txn.insert('booking_items', item.toMap());
      }
    });
  }

  @override
  Future<List<BookingItem>> getItems(int bookingId) async {
    final db = await _db.database;
    final rows = await db.query(
      'booking_items',
      where: 'booking_id = ?',
      whereArgs: [bookingId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(BookingItem.fromMap).toList();
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  @override
  Future<void> recordPayment({
    required int bookingId,
    required double amount,
  }) async {
    final db = await _db.database;
    final booking = await getById(bookingId);
    if (booking == null) return;
    final newPaid =
        (booking.paidAmount + amount).clamp(0.0, booking.totalAmount);
    final isFullyPaid = newPaid >= booking.totalAmount;
    await db.update(
      _table,
      {
        'paid_amount': newPaid,
        'updated_at': DateTime.now().toIso8601String(),
        if (isFullyPaid && booking.status != BookingStatus.completed)
          'status': BookingStatus.completed.dbValue,
      },
      where: 'id = ?',
      whereArgs: [bookingId],
    );
  }

  @override
  Future<List<Booking>> getByPartyId(int partyId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'customer_party_id = ?',
      whereArgs: [partyId],
      orderBy: 'start_datetime DESC',
    );
    return rows.map(Booking.fromMap).toList();
  }
}
