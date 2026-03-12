import 'package:equatable/equatable.dart';
import '../../data/models/app_user.dart';

/// All modules that can be individually permission-gated.
class PermissionModule {
  static const String transactions  = 'transactions';
  static const String invoices      = 'invoices';
  static const String purchaseBills = 'purchase_bills';
  static const String credits       = 'credits';
  static const String loans         = 'loans';
  static const String reports       = 'reports';
  static const String settings      = 'settings';
  static const String inventory     = 'inventory';
  static const String staff         = 'staff';
  static const String accounts      = 'accounts';
  static const String budgets       = 'budgets';

  /// All modules — used when seeding full permission sets.
  static const List<String> all = [
    transactions, invoices, purchaseBills, credits, loans,
    reports, settings, inventory, staff, accounts, budgets,
  ];
}

/// Immutable permission value object for a single module.
class Permission extends Equatable {
  const Permission({
    this.canView   = false,
    this.canCreate = false,
    this.canEdit   = false,
    this.canDelete = false,
  });

  final bool canView;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  /// Full access — used for owner mode (activeAppUserProvider == null).
  static const Permission full = Permission(
    canView: true, canCreate: true, canEdit: true, canDelete: true,
  );

  /// View-only access.
  static const Permission viewOnly = Permission(canView: true);

  /// No access at all.
  static const Permission none = Permission();

  bool get hasAnyAccess => canView || canCreate || canEdit || canDelete;

  @override
  List<Object?> get props => [canView, canCreate, canEdit, canDelete];
}

/// Role presets — canonical permission sets per module per role.
/// business_id = -1 covers the personal scope sentinel.
abstract class RolePreset {
  /// Returns the default [Permission] for [module] given [role].
  static Permission forModule(AppUserRole role, String module) {
    return switch (role) {
      AppUserRole.manager  => _managerPermissions[module]  ?? Permission.viewOnly,
      AppUserRole.cashier  => _cashierPermissions[module]  ?? Permission.none,
      AppUserRole.auditor  => _auditorPermissions[module]  ?? Permission.none,
      AppUserRole.custom   => Permission.none,
    };
  }

  /// Returns a list of UserPermission seeds for all modules for [userId] scoped
  /// to [businessId] using the given [role] preset.
  static List<Map<String, dynamic>> seedRows({
    required int userId,
    required int businessId,
    required AppUserRole role,
  }) {
    return PermissionModule.all.map((module) {
      final p = forModule(role, module);
      return {
        'user_id':     userId,
        'business_id': businessId,
        'module':      module,
        'can_view':    p.canView    ? 1 : 0,
        'can_create':  p.canCreate  ? 1 : 0,
        'can_edit':    p.canEdit    ? 1 : 0,
        'can_delete':  p.canDelete  ? 1 : 0,
      };
    }).toList();
  }

  // ── Preset tables ───────────────────────────────────────────────────────────

  static const _managerPermissions = <String, Permission>{
    PermissionModule.transactions:  Permission(canView: true, canCreate: true, canEdit: true, canDelete: false),
    PermissionModule.invoices:      Permission(canView: true, canCreate: true, canEdit: true, canDelete: false),
    PermissionModule.purchaseBills: Permission(canView: true, canCreate: true, canEdit: true, canDelete: false),
    PermissionModule.credits:       Permission(canView: true, canCreate: true, canEdit: true, canDelete: false),
    PermissionModule.loans:         Permission(canView: true, canCreate: false, canEdit: false, canDelete: false),
    PermissionModule.reports:       Permission.viewOnly,
    PermissionModule.settings:      Permission.viewOnly,
    PermissionModule.inventory:     Permission(canView: true, canCreate: true, canEdit: true, canDelete: false),
    PermissionModule.staff:         Permission.viewOnly,
    PermissionModule.accounts:      Permission.viewOnly,
    PermissionModule.budgets:       Permission.viewOnly,
  };

  static const _cashierPermissions = <String, Permission>{
    PermissionModule.transactions:  Permission(canView: true, canCreate: true, canEdit: false, canDelete: false),
    PermissionModule.invoices:      Permission(canView: true, canCreate: true, canEdit: false, canDelete: false),
    PermissionModule.purchaseBills: Permission.none,
    PermissionModule.credits:       Permission.none,
    PermissionModule.loans:         Permission.none,
    PermissionModule.reports:       Permission.none,
    PermissionModule.settings:      Permission.none,
    PermissionModule.inventory:     Permission.viewOnly,
    PermissionModule.staff:         Permission.none,
    PermissionModule.accounts:      Permission.none,
    PermissionModule.budgets:       Permission.none,
  };

  static const _auditorPermissions = <String, Permission>{
    PermissionModule.transactions:  Permission.viewOnly,
    PermissionModule.invoices:      Permission.viewOnly,
    PermissionModule.purchaseBills: Permission.viewOnly,
    PermissionModule.credits:       Permission.viewOnly,
    PermissionModule.loans:         Permission.viewOnly,
    PermissionModule.reports:       Permission.viewOnly,
    PermissionModule.settings:      Permission.none,
    PermissionModule.inventory:     Permission.viewOnly,
    PermissionModule.staff:         Permission.none,
    PermissionModule.accounts:      Permission.viewOnly,
    PermissionModule.budgets:       Permission.viewOnly,
  };
}
