import '../../data/models/party.dart';

/// Abstract interface for party (customer / vendor / lender) data access.
abstract class PartyRepository {
  /// Insert a new party. Returns the inserted ID.
  Future<int> insert(Party party);

  /// Update an existing party.
  Future<void> update(Party party);

  /// Soft-delete a party by ID.
  Future<void> delete(int id);

  /// Get a party by ID (including soft-deleted).
  Future<Party?> getById(int id);

  /// Get all non-deleted parties ordered by name.
  Future<List<Party>> getAll();

  /// Get all parties of a specific type.
  Future<List<Party>> getByType(PartyType type);

  /// Full-text search across name and phone number.
  Future<List<Party>> search(String query);

  /// Get or create a party by name (used when importing from SMS).
  /// Creates with [PartyType.customer] if not found.
  Future<Party> getOrCreate(String name);

  /// Update [reminderSentAt] on a transaction to record when a
  /// WhatsApp / SMS / Email reminder was dispatched.
  Future<void> markReminderSent(int transactionId);

  /// Get all staff parties (partyType == staff), ordered by name.
  Future<List<Party>> getStaffMembers();
}
