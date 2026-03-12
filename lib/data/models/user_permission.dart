import 'package:equatable/equatable.dart';

class UserPermission extends Equatable {
  const UserPermission({
    this.id,
    required this.userId,
    required this.businessId,
    required this.module,
    this.canView   = true,
    this.canCreate = false,
    this.canEdit   = false,
    this.canDelete = false,
  });

  final int? id;
  final int userId;
  /// -1 = personal data scope sentinel (matches DB DEFAULT -1)
  final int businessId;
  final String module;
  final bool canView;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  static const int kPersonalScope = -1;

  UserPermission copyWith({
    int? id,
    int? userId,
    int? businessId,
    String? module,
    bool? canView,
    bool? canCreate,
    bool? canEdit,
    bool? canDelete,
  }) =>
      UserPermission(
        id:         id         ?? this.id,
        userId:     userId     ?? this.userId,
        businessId: businessId ?? this.businessId,
        module:     module     ?? this.module,
        canView:    canView    ?? this.canView,
        canCreate:  canCreate  ?? this.canCreate,
        canEdit:    canEdit    ?? this.canEdit,
        canDelete:  canDelete  ?? this.canDelete,
      );

  factory UserPermission.fromMap(Map<String, dynamic> map) => UserPermission(
        id:         map['id']          as int?,
        userId:     map['user_id']     as int,
        businessId: map['business_id'] as int? ?? kPersonalScope,
        module:     map['module']      as String,
        canView:    (map['can_view']   as int? ?? 1) == 1,
        canCreate:  (map['can_create'] as int? ?? 0) == 1,
        canEdit:    (map['can_edit']   as int? ?? 0) == 1,
        canDelete:  (map['can_delete'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id':     userId,
        'business_id': businessId,
        'module':      module,
        'can_view':    canView    ? 1 : 0,
        'can_create':  canCreate  ? 1 : 0,
        'can_edit':    canEdit    ? 1 : 0,
        'can_delete':  canDelete  ? 1 : 0,
      };

  @override
  List<Object?> get props => [id, userId, businessId, module, canView, canCreate, canEdit, canDelete];
}
