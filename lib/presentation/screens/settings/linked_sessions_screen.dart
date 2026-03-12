import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/device_session_token.dart';
import '../../providers/sync_provider.dart';
import 'link_device_screen.dart';

/// Shows all active linked business sessions on a SECONDARY device.
///
/// Secondary devices can be linked to multiple primary businesses.  This
/// screen lets users review and manage those connections.
class LinkedSessionsScreen extends ConsumerWidget {
  const LinkedSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(linkedSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(linkedSessionsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (_, i) => _SessionTile(session: sessions[i]),
          );
        },
      ),
      bottomNavigationBar: _LinkBusinessButton(),
    );
  }
}

// ---------------------------------------------------------------------------
// Session tile
// ---------------------------------------------------------------------------

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});
  final DeviceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final lastSync = session.lastSyncAt;
    final isRO     = session.isReadOnlyForced;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: isRO ? cs.errorContainer : cs.primaryContainer,
        child: Icon(
          Icons.business_rounded,
          color: isRO ? cs.onErrorContainer : cs.onPrimaryContainer,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              session.businessName,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (isRO)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(Icons.lock_outline_rounded,
                  size: 16, color: cs.onSurfaceVariant),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _presetLabel(session.token),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.primary),
          ),
          if (lastSync != null)
            Text(
              'Last sync: ${DateFormatter.format(lastSync)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.link_off_rounded),
        tooltip: 'Unlink',
        color: cs.error,
        onPressed: () => _confirmUnlink(context, ref),
      ),
    );
  }

  String _presetLabel(DeviceSessionToken token) {
    switch (token.preset) {
      case 'owner_mirror':
        return 'Owner Mirror';
      case 'manager':
        return 'Manager';
      case 'cashier':
        return 'Cashier';
      case 'auditor':
        return 'Auditor';
      default:
        return 'Custom';
    }
  }

  Future<void> _confirmUnlink(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unlink session?'),
        content: Text(
          'This will remove the link to "${session.businessName}". '
          'You can re-link by scanning a new QR code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(linkedSessionsProvider.notifier)
          .unlink(session.sessionId);
    }
  }
}

// ---------------------------------------------------------------------------
// Link to a business button
// ---------------------------------------------------------------------------

class _LinkBusinessButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        child: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LinkDeviceScreen(),
            ),
          ),
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Link to a Business'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_center_outlined,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No linked businesses yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "Link to a Business" to connect to a primary device over Wi-Fi. No internet needed.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
