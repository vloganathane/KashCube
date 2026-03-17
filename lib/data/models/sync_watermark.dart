/// Tracks the last successful sync position for a specific (peer, table) pair.
///
/// Used as a cursor: the next pull request asks for rows where
/// `updated_at > lastSyncedAt` for the given table.
class SyncWatermark {
  const SyncWatermark({
    required this.peerIdentityId,
    required this.tableName,
    required this.lastSyncedAt,
    this.lastSyncCursor,
  });

  final String peerIdentityId;
  final String tableName;

  /// The `updated_at` high-water mark from the last successful sync.
  final DateTime lastSyncedAt;

  /// Optional opaque cursor for resuming a large batch mid-flight
  /// (e.g. the last `sync_id` received in a paginated response).
  final String? lastSyncCursor;

  factory SyncWatermark.fromMap(Map<String, dynamic> map) => SyncWatermark(
        peerIdentityId: map['peer_identity_id'] as String,
        tableName:      map['table_name'] as String,
        lastSyncedAt:   DateTime.parse(map['last_synced_at'] as String),
        lastSyncCursor: map['last_sync_cursor'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'peer_identity_id': peerIdentityId,
        'table_name':       tableName,
        'last_synced_at':   lastSyncedAt.toIso8601String(),
        if (lastSyncCursor != null) 'last_sync_cursor': lastSyncCursor,
      };

  SyncWatermark copyWith({
    DateTime? lastSyncedAt,
    String? lastSyncCursor,
  }) =>
      SyncWatermark(
        peerIdentityId: peerIdentityId,
        tableName:      tableName,
        lastSyncedAt:   lastSyncedAt ?? this.lastSyncedAt,
        lastSyncCursor: lastSyncCursor ?? this.lastSyncCursor,
      );

  @override
  String toString() =>
      'SyncWatermark($peerIdentityId/$tableName @ $lastSyncedAt)';
}
