import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/user_permission.dart';
import '../../../domain/models/permission.dart';
import '../../providers/app_user_provider.dart';

/// Fine-grained CRUD toggles per module, per business scope.
/// Reached from ManageUsersScreen → "Manage Permissions".
class UserPermissionsScreen extends ConsumerStatefulWidget {
  const UserPermissionsScreen({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<UserPermissionsScreen> createState() =>
      _UserPermissionsScreenState();
}

class _UserPermissionsScreenState
    extends ConsumerState<UserPermissionsScreen> {
  // In-memory editable state: module → Permission
  // We only edit the personal scope (business_id = -1) on this screen.
  // Per-business scoping can be done in a future iteration.
  Map<String, _EditablePermission>? _perms;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref
        .read(appUserRepositoryProvider)
        .getPermissionsForUser(widget.user.id!);

    final map = <String, _EditablePermission>{};
    // Seed from existing DB rows
    for (final p in rows) {
      if (p.businessId == UserPermission.kPersonalScope) {
        map[p.module] = _EditablePermission.fromPermission(
          Permission(
            canView:   p.canView,
            canCreate: p.canCreate,
            canEdit:   p.canEdit,
            canDelete: p.canDelete,
          ),
        );
      }
    }
    // Fill any missing modules with Permission.none
    for (final module in PermissionModule.all) {
      map.putIfAbsent(module, () => _EditablePermission.fromPermission(Permission.none));
    }
    if (mounted) setState(() => _perms = map);
  }

  Future<void> _save() async {
    if (_perms == null) return;
    setState(() => _isSaving = true);
    final permissions = _perms!.entries.map((e) => UserPermission(
          userId:     widget.user.id!,
          businessId: UserPermission.kPersonalScope,
          module:     e.key,
          canView:    e.value.canView,
          canCreate:  e.value.canCreate,
          canEdit:    e.value.canEdit,
          canDelete:  e.value.canDelete,
        )).toList();
    try {
      await ref.read(appUserRepositoryProvider).setPermissions(
            userId:     widget.user.id!,
            businessId: UserPermission.kPersonalScope,
            permissions: permissions,
          );
      // Refresh the provider so ManageUsersScreen re-fetches
      ref.invalidate(userPermissionsProvider(widget.user.id!));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.user.displayName} — Permissions'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: _perms == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: PermissionModule.all
                  .map((module) => _ModuleTile(
                        module: module,
                        perm: _perms![module]!,
                        onChanged: (updated) =>
                            setState(() => _perms![module] = updated),
                      ))
                  .toList(),
            ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.perm,
    required this.onChanged,
  });

  final String module;
  final _EditablePermission perm;
  final ValueChanged<_EditablePermission> onChanged;

  String get _label => module
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(_label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: _PermissionChips(perm: perm),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Column(
            children: [
              _Toggle(
                label: 'View',
                value: perm.canView,
                onChanged: (v) => onChanged(perm.copyWith(canView: v)),
              ),
              _Toggle(
                label: 'Create',
                value: perm.canCreate,
                onChanged: (v) => onChanged(perm.copyWith(canCreate: v)),
              ),
              _Toggle(
                label: 'Edit',
                value: perm.canEdit,
                onChanged: (v) => onChanged(perm.copyWith(canEdit: v)),
              ),
              _Toggle(
                label: 'Delete',
                value: perm.canDelete,
                onChanged: (v) => onChanged(perm.copyWith(canDelete: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _PermissionChips extends StatelessWidget {
  const _PermissionChips({required this.perm});
  final _EditablePermission perm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = [
      if (perm.canView) 'View',
      if (perm.canCreate) 'Create',
      if (perm.canEdit) 'Edit',
      if (perm.canDelete) 'Delete',
    ];
    if (active.isEmpty) {
      return Text('No access',
          style: TextStyle(color: cs.error, fontSize: 12));
    }
    return Wrap(
      spacing: 4,
      children: active
          .map((l) => Chip(
                label: Text(l, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ))
          .toList(),
    );
  }
}

// ── Mutable local state model ─────────────────────────────────────────────────

class _EditablePermission {
  _EditablePermission({
    required this.canView,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });

  factory _EditablePermission.fromPermission(Permission p) =>
      _EditablePermission(
        canView:   p.canView,
        canCreate: p.canCreate,
        canEdit:   p.canEdit,
        canDelete: p.canDelete,
      );

  bool canView;
  bool canCreate;
  bool canEdit;
  bool canDelete;

  _EditablePermission copyWith({
    bool? canView,
    bool? canCreate,
    bool? canEdit,
    bool? canDelete,
  }) =>
      _EditablePermission(
        canView:   canView   ?? this.canView,
        canCreate: canCreate ?? this.canCreate,
        canEdit:   canEdit   ?? this.canEdit,
        canDelete: canDelete ?? this.canDelete,
      );
}
