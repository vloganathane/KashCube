import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../providers/settings_provider.dart';

/// Screen for managing all notification and reminder preferences.
///
/// Accessible from Settings → Notifications.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          final globalEnabled =
              settings[NotificationKeys.notificationsEnabled] as bool? ?? true;

          return ListView(
            children: [
              const SizedBox(height: AppSpacing.sm),

              // ── Global toggle ─────────────────────────────────────────
              _Section(
                title: 'Push Notifications',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('Enable Notifications'),
                    subtitle: const Text(
                        'Receive reminders for payments and appointments'),
                    value: globalEnabled,
                    onChanged: (val) => ref
                        .read(notificationSettingsProvider.notifier)
                        .updateSetting(
                            NotificationKeys.notificationsEnabled, val),
                  ),
                ],
              ),

              // ── Per-feature toggles ───────────────────────────────────
              if (globalEnabled) ...[
                _Section(
                  title: 'Reminder Types',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Invoice Reminders'),
                      subtitle: const Text(
                          'Notify about overdue and upcoming invoices'),
                      value: settings[NotificationKeys.invoicesNotifications]
                              as bool? ??
                          true,
                      onChanged: (val) => ref
                          .read(notificationSettingsProvider.notifier)
                          .updateSetting(
                              NotificationKeys.invoicesNotifications, val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Booking Reminders'),
                      subtitle: const Text(
                          'Notify about upcoming appointments'),
                      value: settings[NotificationKeys.bookingsNotifications]
                              as bool? ??
                          true,
                      onChanged: (val) => ref
                          .read(notificationSettingsProvider.notifier)
                          .updateSetting(
                              NotificationKeys.bookingsNotifications, val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.handshake_outlined),
                      title: const Text('Credit & Loan Reminders'),
                      subtitle:
                          const Text('Notify about lent/borrowed due dates'),
                      value: settings[NotificationKeys.creditsNotifications]
                              as bool? ??
                          true,
                      onChanged: (val) => ref
                          .read(notificationSettingsProvider.notifier)
                          .updateSetting(
                              NotificationKeys.creditsNotifications, val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.event_repeat_outlined),
                      title: const Text('Bill Reminders'),
                      subtitle:
                          const Text('Notify before scheduled bill payments'),
                      value: settings[NotificationKeys.billsNotifications]
                              as bool? ??
                          true,
                      onChanged: (val) => ref
                          .read(notificationSettingsProvider.notifier)
                          .updateSetting(
                              NotificationKeys.billsNotifications, val),
                    ),
                  ],
                ),

                // ── Quiet hours ─────────────────────────────────────────
                _Section(
                  title: 'Quiet Hours',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.bedtime_outlined),
                      title: const Text('Do Not Disturb'),
                      subtitle: Text(
                        '${settings[NotificationKeys.quietHoursStart] ?? '22:00'} – '
                        '${settings[NotificationKeys.quietHoursEnd] ?? '08:00'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickQuietHours(context, ref, settings),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base),
                      child: Text(
                        'No push notifications will be delivered during Quiet Hours.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ],

              // ── Privacy note ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'All notifications are local. No data is sent to any server.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickQuietHours(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings,
  ) async {
    // Parse start time
    final startRaw =
        (settings[NotificationKeys.quietHoursStart] as String?) ?? '22:00';
    final startParts = startRaw.split(':');
    final startTime = TimeOfDay(
      hour: int.tryParse(startParts[0]) ?? 22,
      minute: int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
    );

    final pickedStart = await showTimePicker(
      context: context,
      initialTime: startTime,
      helpText: 'Quiet Hours Start',
    );
    if (pickedStart == null || !context.mounted) return;

    final endRaw =
        (settings[NotificationKeys.quietHoursEnd] as String?) ?? '08:00';
    final endParts = endRaw.split(':');
    final endTime = TimeOfDay(
      hour: int.tryParse(endParts[0]) ?? 8,
      minute: int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0,
    );

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: endTime,
      helpText: 'Quiet Hours End',
    );
    if (pickedEnd == null || !context.mounted) return;

    String format24(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    await ref
        .read(notificationSettingsProvider.notifier)
        .updateSetting(NotificationKeys.quietHoursStart, format24(pickedStart));
    await ref
        .read(notificationSettingsProvider.notifier)
        .updateSetting(NotificationKeys.quietHoursEnd, format24(pickedEnd));
  }
}

// ── Private section widget ────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.md,
            AppSpacing.base,
            AppSpacing.xs,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}
