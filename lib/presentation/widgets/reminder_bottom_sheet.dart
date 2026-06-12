import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../data/models/notification_template.dart';
import '../../data/models/reminder_item.dart';
import '../../data/services/communication_service.dart';
import '../providers/settings_provider.dart';

/// A reusable bottom sheet for sending WhatsApp / SMS / Email reminders.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   useSafeArea: true,
///   builder: (_) => ReminderBottomSheet(
///     item: reminderItem,
///     onReminderSent: () { /* mark DB, refresh provider */ },
///   ),
/// );
/// ```
class ReminderBottomSheet extends ConsumerStatefulWidget {
  const ReminderBottomSheet({
    super.key,
    required this.item,
    required this.onReminderSent,
  });

  final ReminderItem item;

  /// Called after the user successfully opens a messaging app.
  /// The caller should update `reminder_sent_at` in the DB.
  final VoidCallback onReminderSent;

  @override
  ConsumerState<ReminderBottomSheet> createState() =>
      _ReminderBottomSheetState();
}

class _ReminderBottomSheetState extends ConsumerState<ReminderBottomSheet> {
  late TextEditingController _messageController;
  bool _sending = false;

  String get _generatedMessage {
    final senderName = ref.read(businessNameProvider).isNotEmpty
        ? ref.read(businessNameProvider)
        : 'Me';
    final timing = NotificationTemplate.timingFor(widget.item);
    final template = NotificationTemplate(widget.item.type, timing);
    return template.generateMessage(widget.item, senderName);
  }

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: _generatedMessage);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasPhone = item.partyPhone != null && item.partyPhone!.isNotEmpty;
    final hasEmail = item.partyEmail != null && item.partyEmail!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ──────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.notifications_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Send Reminder',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${item.type.label} · ${item.partyName}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Editable message ───────────────────────────────────────────
          TextField(
            controller: _messageController,
            maxLines: 5,
            minLines: 3,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Send via:', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),

          // ── Channel buttons ────────────────────────────────────────────
          if (!hasPhone && !hasEmail)
            Text(
              'No phone or email on record. '
              'Add contact details to the party to enable reminders.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (hasPhone) ...[
                  _ChannelChip(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    loading: _sending,
                    onTap: () => _send('whatsapp'),
                  ),
                  _ChannelChip(
                    icon: Icons.message_outlined,
                    label: 'SMS',
                    color: const Color(0xFF1976D2),
                    loading: _sending,
                    onTap: () => _send('sms'),
                  ),
                ],
                if (hasEmail)
                  _ChannelChip(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    color: const Color(0xFFD32F2F),
                    loading: _sending,
                    onTap: () => _send('email'),
                  ),
              ],
            ),

          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your messaging app will open with the message pre-filled.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Future<void> _send(String channel) async {
    if (_sending) return;
    setState(() => _sending = true);

    final msg = _messageController.text.trim();
    final comm = CommunicationService.instance;
    bool success = false;

    try {
      switch (channel) {
        case 'whatsapp':
          success = await comm.sendWhatsApp(widget.item.partyPhone!, msg);
        case 'sms':
          success = await comm.sendSMS(widget.item.partyPhone!, msg);
        case 'email':
          final subject =
              '${widget.item.type.label} Reminder — ${widget.item.title}';
          success = await comm.sendEmail(widget.item.partyEmail!, subject, msg);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }

    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      widget.onReminderSent();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder sent'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${channel == 'whatsapp'
                ? 'WhatsApp'
                : channel == 'sms'
                ? 'SMS app'
                : 'email app'}. '
            'Make sure the app is installed.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Private widget ───────────────────────────────────────────────────────────

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 16, color: color),
      label: Text(label),
      onPressed: loading ? null : onTap,
    );
  }
}
