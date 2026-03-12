import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/pin_hash.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/party.dart';
import '../../../data/models/user_permission.dart';
import '../../providers/app_user_provider.dart';
import '../../providers/party_provider.dart';
import 'user_permissions_screen.dart';

/// Settings → Team — lists all active app users; FAB adds a new one.
class ManageUsersScreen extends ConsumerWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(appUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(context, ref, null),
        child: const Icon(Icons.person_add_outlined),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) => users.isEmpty
            ? _EmptyState(onAdd: () => _openSheet(context, ref, null))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: users.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (ctx, i) => _UserTile(
                  user: users[i],
                  onEdit: () => _openSheet(context, ref, users[i]),
                  onPermissions: () => _openPermissions(context, ref, users[i]),
                  onDeactivate: () => _confirmDeactivate(context, ref, users[i]),
                ),
              ),
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, AppUser? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddEditUserSheet(existing: existing),
    );
  }

  void _openPermissions(BuildContext context, WidgetRef ref, AppUser user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserPermissionsScreen(user: user),
      ),
    );
  }

  Future<void> _confirmDeactivate(
      BuildContext context, WidgetRef ref, AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Access'),
        content: Text(
            'Remove app access for ${user.displayName}? Their records will be kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appUsersProvider.notifier).deactivate(user.id!);
    }
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onPermissions,
    required this.onDeactivate,
  });

  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onPermissions;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.secondaryContainer,
        child: Text(
          user.initials,
          style: TextStyle(
              fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
        ),
      ),
      title: Text(user.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(user.role.label),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'perms') onPermissions();
          if (v == 'revoke') onDeactivate();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'perms', child: Text('Manage Permissions')),
          PopupMenuItem(value: 'revoke', child: Text('Revoke Access')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 64,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: AppSpacing.base),
          Text('No team members yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('Add a cashier, manager, or auditor',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  )),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add Member'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

// ── AddEditUserSheet ──────────────────────────────────────────────────────────

/// Bottom sheet for creating or editing an app user.
class AddEditUserSheet extends ConsumerStatefulWidget {
  const AddEditUserSheet({super.key, this.existing});

  final AppUser? existing;

  @override
  ConsumerState<AddEditUserSheet> createState() => _AddEditUserSheetState();
}

class _AddEditUserSheetState extends ConsumerState<AddEditUserSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  late AppUserRole _role;
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.displayName ?? '');
    _pinCtrl = TextEditingController();
    _pinConfirmCtrl = TextEditingController();
    _role = widget.existing?.role ?? AppUserRole.cashier;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final pinHash = pin.isNotEmpty ? hashPin(pin) : widget.existing?.pinHash;

    try {
      if (_isEdit) {
        await ref.read(appUsersProvider.notifier).save(
              widget.existing!.copyWith(
                displayName: name,
                role: _role,
                pinHash: pinHash,
              ),
            );
        // Keep the linked Party name in sync when the display name changes.
        final linkedPartyId = widget.existing!.linkedPartyId;
        if (name != widget.existing!.displayName && linkedPartyId != null) {
          final partyRepo = ref.read(partyRepositoryProvider);
          final linked = await partyRepo.getById(linkedPartyId);
          if (linked != null) {
            await partyRepo.update(linked.copyWith(name: name));
            ref.read(partiesProvider.notifier).load();
          }
        }
      } else {
        // Generate a sync_id on insert (the DB DEFAULT handles it but we use
        // a placeholder so toMap() can omit it — DB generates via DEFAULT).
        const tempSyncId = '';
        final newUser = AppUser(
          syncId: tempSyncId,
          displayName: name,
          role: _role,
          pinHash: pinHash,
        );
        final userId = await ref.read(appUsersProvider.notifier).add(newUser);

        // Auto-create a Party(type: staff) so salary payments, advances, and
        // payslips can all link to this person without any extra owner steps.
        final partyRepo = ref.read(partyRepositoryProvider);
        final staffParty = Party(name: name, partyType: PartyType.staff);
        final partyId = await partyRepo.insert(staffParty);

        // Backfill linked_party_id on the app_user row.
        await ref.read(appUserRepositoryProvider).update(
          newUser.copyWith(id: userId, linkedPartyId: partyId),
        );

        // Push the new party into the in-memory list without a full reload.
        ref.read(partiesProvider.notifier).addToState(
          staffParty.copyWith(id: partyId, createdAt: DateTime.now()),
        );

        // Seed role-preset permissions for the personal scope.
        await ref.read(appUserRepositoryProvider).seedRolePreset(
              userId: userId,
              businessId: UserPermission.kPersonalScope,
              role: _role,
            );
      }
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
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              _isEdit ? 'Edit Member' : 'Add Team Member',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.base),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name required' : null,
            ),
            const SizedBox(height: AppSpacing.base),
            DropdownButtonFormField<AppUserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: AppUserRole.values
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (v) => setState(() => _role = v!),
            ),
            const SizedBox(height: AppSpacing.base),
            TextFormField(
              controller: _pinCtrl,
              decoration: InputDecoration(
                  labelText:
                      _isEdit ? 'New PIN (leave blank to keep)' : 'PIN (4 digits)'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              validator: (v) {
                if (!_isEdit && (v == null || v.isEmpty)) return 'PIN required';
                if (v != null && v.isNotEmpty && v.length != 4) return 'PIN must be 4 digits';
                return null;
              },
            ),
            TextFormField(
              controller: _pinConfirmCtrl,
              decoration:
                  const InputDecoration(labelText: 'Confirm PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              validator: (v) {
                if (_pinCtrl.text.isEmpty) return null;
                if (v != _pinCtrl.text) return 'PINs do not match';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save Changes' : 'Add Member'),
            ),
          ],
        ),
      ),
    );
  }
}
