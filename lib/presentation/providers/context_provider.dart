import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/database_helper.dart';

// ── Active context ──────────────────────────────────────────────────────────
//
// null   → personal context (the device owner's own data)
// int N  → linked_business_sessions.id (viewing a linked business session)
//
// Set by [ContextSwitcherWidget] in the app bar.
final activeContextProvider = StateProvider<int?>((ref) => null);

// ── Linked sessions list ────────────────────────────────────────────────────

/// Lightweight summary of a linked business session for display purposes.
class LinkedSession {
  const LinkedSession({
    required this.id,
    required this.businessName,
    required this.sessionId,
    this.lastSyncAt,
    this.isReadOnly = false,
  });

  final int id;
  final String businessName;
  final String sessionId;
  final DateTime? lastSyncAt;
  final bool isReadOnly;

  static LinkedSession fromMap(Map<String, dynamic> m) => LinkedSession(
    id: m['id'] as int,
    businessName: m['business_name'] as String? ?? 'Linked Business',
    sessionId: m['session_id'] as String? ?? '',
    lastSyncAt: m['last_sync_at'] != null
        ? DateTime.tryParse(m['last_sync_at'] as String)
        : null,
    isReadOnly: (m['is_read_only_forced'] as int? ?? 0) == 1,
  );
}

/// All active (not yet unlinked) business sessions, sorted by display_order.
final linkedSessionsProvider = FutureProvider<List<LinkedSession>>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'linked_business_sessions',
    where: 'unlinked_at IS NULL',
    orderBy: 'display_order ASC, created_at ASC',
  );
  return rows.map(LinkedSession.fromMap).toList();
});
