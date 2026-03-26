import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// ActivityLogType — what kind of event happened
// ---------------------------------------------------------------------------

enum ActivityLogType {
  statusChange,
  note,
  action,
  payment,
  reminder,
}

extension ActivityLogTypeExt on ActivityLogType {
  String get dbValue {
    switch (this) {
      case ActivityLogType.statusChange:
        return 'status_change';
      case ActivityLogType.note:
        return 'note';
      case ActivityLogType.action:
        return 'action';
      case ActivityLogType.payment:
        return 'payment';
      case ActivityLogType.reminder:
        return 'reminder';
    }
  }

  static ActivityLogType fromDb(String? v) {
    switch (v) {
      case 'status_change':
        return ActivityLogType.statusChange;
      case 'action':
        return ActivityLogType.action;
      case 'payment':
        return ActivityLogType.payment;
      case 'reminder':
        return ActivityLogType.reminder;
      default:
        return ActivityLogType.note;
    }
  }
}

// ---------------------------------------------------------------------------
// ActivityLog — generic log entry reusable across all entities
// ---------------------------------------------------------------------------

class ActivityLog extends Equatable {
  const ActivityLog({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.type,
    required this.message,
    this.meta,
    required this.createdAt,
  });

  /// The type of entity this log belongs to, e.g. 'quote', 'invoice', 'credit'.
  final String entityType;
  final int entityId;
  final ActivityLogType type;
  final String message;

  /// Optional JSON string for extra structured data (e.g. old/new status, amounts).
  final String? meta;
  final DateTime createdAt;
  final int? id;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'type': type.dbValue,
        'message': message,
        'meta': meta,
        'created_at': createdAt.toIso8601String(),
      };

  factory ActivityLog.fromMap(Map<String, dynamic> map) => ActivityLog(
        id: map['id'] as int?,
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as int,
        type: ActivityLogTypeExt.fromDb(map['type'] as String?),
        message: map['message'] as String,
        meta: map['meta'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, entityType, entityId, type, message, createdAt];
}
