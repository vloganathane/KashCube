import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_log.dart';
import '../../data/repositories/activity_log_repository_impl.dart';
import '../../domain/repositories/activity_log_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

/// Single global instance — activity_log has no context_id scoping.
final activityLogRepositoryProvider = Provider<ActivityLogRepository>(
  (_) => ActivityLogRepositoryImpl(),
);

// ── Per-entity provider ───────────────────────────────────────────────────────

/// Watches the activity log for a specific entity.
/// Usage: `ref.watch(activityLogProvider(('quote', quoteId)))`
final activityLogProvider = FutureProvider.family<List<ActivityLog>,
    (String entityType, int entityId)>(
  (ref, args) async {
    final repo = ref.read(activityLogRepositoryProvider);
    return repo.getForEntity(args.$1, args.$2);
  },
);
