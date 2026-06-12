// ---------------------------------------------------------------------------
// FlowChainTile — P2.10
// ---------------------------------------------------------------------------
// A card that summarises a single BusinessFlowChain deal pipeline:
//   [Origin badge]  Title + subtitle
//   Status chip     Outstanding / Received amounts
//   Stepper row:    Quote → Challan → Invoice → Paid
//
// Tapping the tile triggers [onTap] — typically opens the linked invoice.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/theme/kash_cube_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/lifecycle_classifier.dart';
import '../../data/models/business_flow_chain.dart';
import '../../data/models/party_reminder.dart';
import 'lifecycle_tag.dart';

class FlowChainTile extends StatelessWidget {
  const FlowChainTile({super.key, required this.chain, this.onTap});

  final BusinessFlowChain chain;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final (statusColor, statusLabel) = _statusStyle(
      context,
      colors,
      chain.status,
    );

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: origin badge + title + status chip
              Row(
                children: [
                  _OriginBadge(origin: chain.origin),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      chain.chainTitle,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _StatusChip(label: statusLabel, color: statusColor),
                ],
              ),

              const SizedBox(height: AppSpacing.xs),

              // Row 2: amount info
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total: ${CurrencyFormatter.format(chain.totalValue)}',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.outline,
                          ),
                        ),
                        if (chain.outstandingAmount > 0)
                          Text(
                            'Outstanding: ${CurrencyFormatter.format(chain.outstandingAmount)}',
                            style: context.textTheme.labelMedium?.copyWith(
                              color: colors.expense,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Days since origin
                  Text(
                    '${chain.daysSinceOrigin}d ago',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.outline,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.sm),

              // Row 3: pipeline stepper
              _PipelineStepper(chain: chain),

              // Invoice lifecycle tag (LC4) — shown when invoice exists
              if (chain.invoice != null) ...[
                const SizedBox(height: AppSpacing.xs),
                LifecycleTag(
                  info: LifecycleClassifier.forInvoice(chain.invoice!),
                ),
              ],

              // Reminder history (E6) — compact channel/date bubbles
              if (chain.reminders.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                _ReminderTimeline(reminders: chain.reminders),
              ],

              // CTA label (if action needed)
              if (chain.needsAction) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  chain.ctaLabel,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, String) _statusStyle(
    BuildContext context,
    KashCubeColors colors,
    ChainStatus status,
  ) => switch (status) {
    ChainStatus.complete => (colors.income, 'Complete'),
    ChainStatus.awaitingPayment => (colors.expense, 'Awaiting Payment'),
    ChainStatus.awaitingInvoice => (colors.credit, 'Awaiting Invoice'),
    ChainStatus.invoicedPartially => (Colors.orange, 'Partial'),
    ChainStatus.cancelled => (context.colorScheme.outline, 'Cancelled'),
  };
}

// ---------------------------------------------------------------------------
// Origin badge
// ---------------------------------------------------------------------------

class _OriginBadge extends StatelessWidget {
  const _OriginBadge({required this.origin});

  final ChainOrigin origin;

  @override
  Widget build(BuildContext context) {
    final label = switch (origin) {
      ChainOrigin.quote => 'Q',
      ChainOrigin.challan => 'C',
      ChainOrigin.booking => 'B',
      ChainOrigin.directInvoice => 'I',
    };

    final tooltip = switch (origin) {
      ChainOrigin.quote => 'Started from Quote',
      ChainOrigin.challan => 'Started from Challan',
      ChainOrigin.booking => 'Started from Booking',
      ChainOrigin.directInvoice => 'Direct Invoice',
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline stepper row
// ---------------------------------------------------------------------------

class _PipelineStepper extends StatelessWidget {
  const _PipelineStepper({required this.chain});

  final BusinessFlowChain chain;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, bool)>[
      if (chain.origin == ChainOrigin.quote || chain.quote != null)
        ('Quote', chain.quote != null),
      if (chain.origin == ChainOrigin.challan || chain.challan != null)
        ('Challan', chain.challan != null),
      if (chain.origin == ChainOrigin.booking || chain.booking != null)
        ('Booking', chain.booking != null),
      ('Invoice', chain.invoice != null),
      if (chain.reminders.isNotEmpty)
        ('Reminded ×${chain.reminders.length}', true),
      (
        'Paid',
        chain.status == ChainStatus.complete ||
            (chain.receivedAmount > 0 &&
                chain.receivedAmount >= chain.totalValue),
      ),
    ];

    if (steps.isEmpty) return const SizedBox.shrink();

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // connector
          return Expanded(
            child: Container(
              height: 2,
              color: context.colorScheme.outlineVariant,
            ),
          );
        }
        final step = steps[i ~/ 2];
        return _StepDot(label: step.$1, active: step.$2);
      }),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? context.colorScheme.primary
        : context.colorScheme.outlineVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            fontSize: 9,
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// __ Reminder Timeline (E6) ___________________________________________________

/// Compact horizontal list of reminder event bubbles.
/// Shown when [BusinessFlowChain.reminders] is non-empty.
class _ReminderTimeline extends StatelessWidget {
  const _ReminderTimeline({required this.reminders});

  final List<PartyReminder> reminders;

  @override
  Widget build(BuildContext context) {
    final sorted = [...reminders]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 2,
      children: sorted.map((r) => _ReminderBubble(reminder: r)).toList(),
    );
  }
}

class _ReminderBubble extends StatelessWidget {
  const _ReminderBubble({required this.reminder});

  final PartyReminder reminder;

  @override
  Widget build(BuildContext context) {
    final icon = switch (reminder.channel) {
      ReminderChannel.whatsapp => Icons.chat_bubble_outline_rounded,
      ReminderChannel.sms => Icons.sms_outlined,
      ReminderChannel.email => Icons.email_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.colorScheme.outlineVariant,
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: context.colorScheme.outline),
          const SizedBox(width: 3),
          Text(
            '${reminder.channel.label} · ${_short(reminder.sentAt)}',
            style: context.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: context.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _short(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }
}
