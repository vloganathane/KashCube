import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app_logger.dart';

import 'database_helper.dart';

/// Context-aware feature gate.
///
/// Two modes:
/// - **Personal context** (`canDo`): reads the local `plan_features` table
///   against the subscriber's current plan.
/// - **Linked session context** (`canDoInSession`): reads the `plan_features`
///   map embedded in the session token that was issued by the primary device.
///
/// Usage:
/// ```dart
/// final gate = ref.watch(planGateProvider);
/// if (gate.canDo('lan_sync')) { /* personal plan allows it */ }
/// if (gate.canDoInSession('report_history_months', token)) { /* token allows */ }
/// ```
class PlanGate {
  const PlanGate();

  // ---------------------------------------------------------------------------
  // Personal context — reads live from DB
  // ---------------------------------------------------------------------------

  /// Returns `true` if the current local plan enables [feature].
  ///
  /// Queries `subscription` for the current plan, then `plan_features` for
  /// the feature row.  Returns `false` on any DB error or missing feature.
  Future<bool> canDo(String feature) async {
    try {
      return await DatabaseHelper.instance.withDatabase((db) async {
        return _checkLocalFeature(db, feature);
      });
    } catch (e, st) {
      AppLogger.instance.warning(
        'Failed to check plan feature',
        category: 'plan_gate',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Returns the numeric limit for [feature] in the current personal plan.
  ///
  /// Returns `0` when the feature is absent or disabled.
  Future<int> limitFor(String feature) async {
    try {
      return await DatabaseHelper.instance.withDatabase((db) async {
        return _localLimit(db, feature);
      });
    } catch (e, st) {
      AppLogger.instance.warning(
        'Failed to get plan feature limit',
        category: 'plan_gate',
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }

  /// Synchronous variant that works from a pre-loaded feature map.
  ///
  /// Useful in widgets: call `ref.watch(localPlanFeaturesProvider)` once and
  /// pass the map here for synchronous gating.
  bool canDoSync(String feature, Map<String, dynamic> features) {
    final f = features[feature] as Map<String, dynamic>?;
    if (f == null) return false;
    return f['enabled'] == true || f['enabled'] == 1;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<bool> _checkLocalFeature(Database db, String feature) async {
    final plan = await _currentPlan(db);
    final rows = await db.query(
      'plan_features',
      where: 'plan = ? AND feature = ?',
      whereArgs: [plan, feature],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['enabled'] as int? ?? 0) == 1;
  }

  Future<int> _localLimit(Database db, String feature) async {
    final plan = await _currentPlan(db);
    final rows = await db.query(
      'plan_features',
      where: 'plan = ? AND feature = ?',
      whereArgs: [plan, feature],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return rows.first['limit_value'] as int? ?? 0;
  }

  Future<String> _currentPlan(Database db) async {
    final rows = await db.query('subscription', columns: ['plan'], limit: 1);
    return rows.isNotEmpty ? (rows.first['plan'] as String? ?? 'free') : 'free';
  }

  /// Loads all personal plan features as a flat map for synchronous [canDoSync].
  ///
  /// Returns `{'feature': {'enabled': bool, 'limit': int}, ...}`.
  static Future<Map<String, dynamic>> loadLocalFeatures() async {
    try {
      return await DatabaseHelper.instance.withDatabase((db) async {
        final subRows = await db.query(
          'subscription',
          columns: ['plan'],
          limit: 1,
        );
        final plan = subRows.isNotEmpty
            ? (subRows.first['plan'] as String? ?? 'free')
            : 'free';

        final featureRows = await db.query(
          'plan_features',
          where: 'plan = ?',
          whereArgs: [plan],
        );

        final features = <String, dynamic>{};
        for (final row in featureRows) {
          features[row['feature'] as String] = {
            'enabled': (row['enabled'] as int?) == 1,
            'limit':   row['limit_value'] as int? ?? 0,
          };
        }
        return features;
      });
    } catch (e, st) {
      AppLogger.instance.warning(
        'Failed to load local plan features map',
        category: 'plan_gate',
        error: e,
        stackTrace: st,
      );
      return {};
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Singleton PlanGate instance.
final planGateProvider = Provider<PlanGate>((_) => const PlanGate());

/// Async snapshot of the local plan features map.
///
/// Use this to avoid repeated DB hits in widgets:
/// ```dart
/// final featuresAsync = ref.watch(localPlanFeaturesProvider);
/// featuresAsync.whenData((f) {
///   if (ref.read(planGateProvider).canDoSync('lan_sync', f)) { ... }
/// });
/// ```
final localPlanFeaturesProvider =
    FutureProvider<Map<String, dynamic>>((ref) => PlanGate.loadLocalFeatures());
