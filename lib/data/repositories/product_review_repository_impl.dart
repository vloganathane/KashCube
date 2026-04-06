import '../../data/models/product_review.dart';
import '../../data/services/database_helper.dart';
import '../../domain/repositories/product_review_repository.dart';

class ProductReviewRepositoryImpl implements ProductReviewRepository {
  ProductReviewRepositoryImpl({this.contextId});

  final _dbHelper = DatabaseHelper.instance;

  /// The active context for data isolation.
  final int? contextId;

  String get _ctx => contextId == null
      ? 'context_id IS NULL'
      : 'context_id = $contextId';

  @override
  Future<List<ProductReview>> getAllForProduct(int productId) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT * FROM product_reviews
      WHERE product_id = ? AND deleted_at IS NULL AND $_ctx
      ORDER BY created_at DESC
    ''', [productId]);

    return rows.map(ProductReview.fromMap).toList();
  }

  @override
  Future<ProductReview?> getById(int id) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT * FROM product_reviews
      WHERE id = ? AND $_ctx
    ''', [id]);

    return rows.isEmpty ? null : ProductReview.fromMap(rows.first);
  }

  @override
  Future<int> insert(ProductReview review) async {
    final db = await _dbHelper.database;
    final id = await db.insert('product_reviews', review.toMap());
    _dbHelper.notifyChange('product_reviews');
    return id;
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.update(
      'product_reviews',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _dbHelper.notifyChange('product_reviews');
  }

  @override
  Future<Map<String, dynamic>> getAggregateRating(int productId) async {
    final db = await _dbHelper.database;

    final rows = await db.rawQuery('''
      SELECT
        AVG(rating) as average_rating,
        COUNT(*) as review_count
      FROM product_reviews
      WHERE product_id = ? AND deleted_at IS NULL AND $_ctx
    ''', [productId]);

    if (rows.isEmpty || rows.first['review_count'] == 0) {
      return {'averageRating': 0.0, 'reviewCount': 0};
    }

    return {
      'averageRating': (rows.first['average_rating'] as num).toDouble(),
      'reviewCount': rows.first['review_count'] as int,
    };
  }
}
