import 'package:equatable/equatable.dart';

/// Represents one row change sent over LAN sync.
/// Used in both `delta_request` responses and `delta_upload` uploads.
class DeltaRow extends Equatable {
  const DeltaRow({
    required this.table,
    required this.syncId,
    required this.version,
    required this.updatedAt,
    required this.operation,
    this.payload,
  });

  /// The SQLite table name (e.g. 'transactions', 'credits').
  final String table;

  /// The row's `sync_id` UUID.
  final String syncId;

  /// The row's version counter (incremented on each modification).
  final int version;

  /// ISO-8601 timestamp of the last update.
  final String updatedAt;

  /// 'upsert' or 'delete'.
  final String operation;

  /// Full row data for upsert; null for delete.
  final Map<String, dynamic>? payload;

  bool get isUpsert => operation == 'upsert';
  bool get isDelete => operation == 'delete';

  factory DeltaRow.fromJson(Map<String, dynamic> json) => DeltaRow(
        table:     json['table'] as String,
        syncId:    json['sync_id'] as String,
        version:   json['version'] as int,
        updatedAt: json['updated_at'] as String,
        operation: json['operation'] as String,
        payload:   json['payload'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'table':      table,
        'sync_id':    syncId,
        'version':    version,
        'updated_at': updatedAt,
        'operation':  operation,
        if (payload != null) 'payload': payload,
      };

  @override
  List<Object?> get props => [table, syncId, version, operation];
}
