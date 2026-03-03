import 'package:flutter/foundation.dart';

import '../models/hsn_entry.dart';
import 'database_helper.dart';

/// Provides offline HSN / SAC code search against the local `hsn_master` table.
///
/// The table is seeded from the bundled CSV assets on first install (DB v35).
/// Queries are limited to [_defaultLimit] rows to keep the autocomplete fast.
class HsnSearchService {
  HsnSearchService._();
  static final HsnSearchService instance = HsnSearchService._();

  static const int _defaultLimit = 25;

  /// Search [hsn_master] by code prefix **or** description keyword.
  ///
  /// [type] must be either 'HSN' or 'SAC'.
  /// Returns an empty list on any error (never throws).
  Future<List<HsnEntry>> search(
    String query, {
    required String type,
    int limit = _defaultLimit,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    try {
      final db = await DatabaseHelper.instance.database;
      final like = '%${q.replaceAll('%', '').replaceAll('_', '')}%';
      final rows = await db.rawQuery(
        '''
        SELECT code, description, type
        FROM hsn_master
        WHERE type = ?
          AND (code LIKE ? OR description LIKE ?)
        ORDER BY
          CASE WHEN code LIKE ? THEN 0 ELSE 1 END,
          length(code),
          code
        LIMIT ?
        ''',
        [type, like, like, '$q%', limit],
      );
      return rows.map(HsnEntry.fromMap).toList();
    } catch (e) {
      debugPrint('[HsnSearchService] search error: $e');
      return [];
    }
  }
}
