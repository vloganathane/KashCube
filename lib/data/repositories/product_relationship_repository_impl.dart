import '../../data/models/product_relationship.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/product_relationship_repository.dart';

class ProductRelationshipRepositoryImpl
    implements ProductRelationshipRepository {
  ProductRelationshipRepositoryImpl({this.contextId});

  final _dbHelper = DatabaseHelper.instance;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx => contextId == null
      ? 'context_id IS NULL'
      : 'context_id = $contextId';

  @override
  Future<List<ProductRelationship>> getAllForProduct(int productId) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT * FROM product_relationships
      WHERE product_id = ? AND deleted_at IS NULL AND $_ctx
      ORDER BY created_at DESC
    ''', [productId]);

    return rows.map(ProductRelationship.fromMap).toList();
  }

  @override
  Future<ProductRelationship?> getById(int id) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT * FROM product_relationships
      WHERE id = ? AND $_ctx
    ''', [id]);

    return rows.isEmpty ? null : ProductRelationship.fromMap(rows.first);
  }

  @override
  Future<int> insert(ProductRelationship relationship) async {
    final db = await _dbHelper.database;
    final id = await db.insert('product_relationships', relationship.toMap());
    _dbHelper.notifyChange('product_relationships');
    return id;
  }

  @override
  Future<void> update(ProductRelationship relationship) async {
    final db = await _dbHelper.database;
    await db.update(
      'product_relationships',
      relationship.toMap(),
      where: 'id = ?',
      whereArgs: [relationship.id],
    );
    _dbHelper.notifyChange('product_relationships');
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.update(
      'product_relationships',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _dbHelper.notifyChange('product_relationships');
  }
}
