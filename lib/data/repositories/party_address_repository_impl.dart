import '../models/party_address.dart';
import '../services/database_helper.dart';
import '../../domain/repositories/party_address_repository.dart';

class PartyAddressRepositoryImpl implements PartyAddressRepository {
  PartyAddressRepositoryImpl([DatabaseHelper? helper])
      : _db = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  @override
  Future<List<PartyAddress>> getByPartyId(int partyId) async {
    final db = await _db.database;
    final rows = await db.query(
      'party_addresses',
      where: 'party_id = ?',
      whereArgs: [partyId],
      // default address first, then by creation date
      orderBy: 'is_default DESC, created_at ASC',
    );
    return rows.map(PartyAddress.fromMap).toList();
  }

  @override
  Future<int> insert(PartyAddress address) async {
    final db = await _db.database;
    // If this is the first address for the party, force it to be default.
    final existing = await db.query(
      'party_addresses',
      columns: ['id'],
      where: 'party_id = ?',
      whereArgs: [address.partyId],
      limit: 1,
    );
    final forceDefault = existing.isEmpty;
    return db.insert(
      'party_addresses',
      address.copyWith(isDefault: forceDefault || address.isDefault).toMap(),
    );
  }

  @override
  Future<void> update(PartyAddress address) async {
    final db = await _db.database;
    await db.update(
      'party_addresses',
      address.toMap(),
      where: 'id = ?',
      whereArgs: [address.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    // Check if this was the default address
    final rows = await db.query(
      'party_addresses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final wasDefault = rows.isNotEmpty && (rows.first['is_default'] as int?) == 1;
    final partyId = rows.isNotEmpty ? rows.first['party_id'] as int? : null;

    await db.delete('party_addresses', where: 'id = ?', whereArgs: [id]);

    // If we deleted the default, promote the oldest remaining address.
    if (wasDefault && partyId != null) {
      final remaining = await db.query(
        'party_addresses',
        columns: ['id'],
        where: 'party_id = ?',
        whereArgs: [partyId],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (remaining.isNotEmpty) {
        await db.update(
          'party_addresses',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [remaining.first['id']],
        );
      }
    }
  }

  @override
  Future<void> setDefault(int partyId, int addressId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Clear all defaults for this party
      await txn.update(
        'party_addresses',
        {'is_default': 0},
        where: 'party_id = ?',
        whereArgs: [partyId],
      );
      // Set the chosen address as default
      await txn.update(
        'party_addresses',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: [addressId],
      );
    });
  }
}
