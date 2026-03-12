import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/identity_repository.dart';
import '../../data/models/my_identity.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [IdentityRepository] backed by the `my_identity`
/// table (always exactly 0 or 1 row with `id = 1`).
class IdentityRepositoryImpl implements IdentityRepository {
  IdentityRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  @override
  Future<MyIdentity?> getMyIdentity() => _dbHelper.withDatabase((db) async {
        final rows = await db.query('my_identity', limit: 1);
        if (rows.isEmpty) return null;
        return MyIdentity.fromMap(Map<String, dynamic>.from(rows.first));
      });

  @override
  Future<void> createIdentity({
    required String identityId,
    required String displayName,
    required String publicKey,
  }) =>
      _dbHelper.withDatabase(
        (db) => db.insert(
          'my_identity',
          {
            'id':           1,
            'identity_id':  identityId,
            'display_name': displayName,
            'public_key':   publicKey,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        ).then((_) {}),
      );

  @override
  Future<void> updateDisplayName(String name) => _dbHelper.withDatabase(
        (db) => db.update(
          'my_identity',
          {
            'display_name': name,
            'updated_at':   DateTime.now().toIso8601String(),
          },
          where: 'id = 1',
        ).then((_) {}),
      );

  @override
  Future<void> setPublicKey(String publicKeyBase64) => _dbHelper.withDatabase(
        (db) => db.update(
          'my_identity',
          {
            'public_key': publicKeyBase64,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = 1',
        ).then((_) {}),
      );
}
