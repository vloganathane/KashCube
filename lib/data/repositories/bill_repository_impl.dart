import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/bill_repository.dart';
import '../models/bill_attachment.dart';
import '../services/database_helper.dart';

/// SQLite implementation of [BillRepository].
class BillRepositoryImpl implements BillRepository {
  final DatabaseHelper _dbHelper;

  BillRepositoryImpl({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  @override
  Future<int> insert(BillAttachment bill) async {
    final db = await _db;
    return db.insert(
      'bill_attachments',
      bill.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<BillAttachment?> getByTransactionId(int transactionId) async {
    final db = await _db;
    final rows = await db.query(
      'bill_attachments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BillAttachment.fromMap(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('bill_attachments', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteByTransactionId(int transactionId) async {
    final db = await _db;
    await db.delete(
      'bill_attachments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  @override
  Future<bool> hasAttachment(int transactionId) async {
    final db = await _db;
    final result = await db.query(
      'bill_attachments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
