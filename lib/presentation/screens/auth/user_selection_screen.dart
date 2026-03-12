import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/app_user.dart';
import '../../providers/app_user_provider.dart';
import 'staff_pin_screen.dart';

/// Shown after owner authentication when one or more app users exist.
/// Lets the device holder choose to continue as the owner (full access)
/// or switch to a staff profile (restricted access).
class UserSelectionScreen extends ConsumerWidget {
  const UserSelectionScreen({
    super.key,
    required this.onOwnerSelected,
  });

  /// Called when the owner tile is tapped (user continues as owner).
  final VoidCallback onOwnerSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(appUsersProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Who\'s using Kash Cube?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choose a profile to continue',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (users) => _UserGrid(
                  users: users,
                  onOwnerSelected: onOwnerSelected,
                  onStaffSelected: (user) => _openStaffPin(context, ref, user),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openStaffPin(BuildContext context, WidgetRef ref, AppUser user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffPinScreen(user: user),
      ),
    );
  }
}

class _UserGrid extends StatelessWidget {
  const _UserGrid({
    required this.users,
    required this.onOwnerSelected,
    required this.onStaffSelected,
  });

  final List<AppUser> users;
  final VoidCallback onOwnerSelected;
  final ValueChanged<AppUser> onStaffSelected;

  @override
  Widget build(BuildContext context) {
    final all = <Widget>[
      _ProfileTile(
        initials: 'O',
        label: 'Owner',
        sublabel: 'Full access',
        isOwner: true,
        onTap: onOwnerSelected,
      ),
      ...users.map(
        (u) => _ProfileTile(
          initials: u.initials,
          label: u.displayName,
          sublabel: u.role.label,
          isOwner: false,
          onTap: () => onStaffSelected(u),
        ),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      mainAxisSpacing: AppSpacing.base,
      crossAxisSpacing: AppSpacing.base,
      childAspectRatio: 0.85,
      children: all,
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.initials,
    required this.label,
    required this.sublabel,
    required this.isOwner,
    required this.onTap,
  });

  final String initials;
  final String label;
  final String sublabel;
  final bool isOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatarColor = isOwner ? cs.primary : cs.secondaryContainer;
    final avatarTextColor = isOwner ? cs.onPrimary : cs.onSecondaryContainer;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: avatarColor,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: avatarTextColor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  sublabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
