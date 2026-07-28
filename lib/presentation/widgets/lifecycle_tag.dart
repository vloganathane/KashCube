// ---------------------------------------------------------------------------
// Lifecycle Layer — LC3
// ---------------------------------------------------------------------------
// LifecycleTag widget — renders a compact stage pill such as:
//   [ SENT · 14d ]   [ OVERDUE · 7d ]   [ REMINDED · 2d ]
//
// Usage:
//   LifecycleTag(info: LifecycleClassifier.forInvoice(invoice))
//   LifecycleTag(info: info, expanded: true)   // shows stage dots
//
// Colour-coded:
//   overdue     → error red
//   reminded    → orange
//   sent        → primary
//   partiallyPaid → amber/credit
//   paying      → income green
//   active/draft → outline (neutral)
//   paid/cleared → muted (not shown in compact mode by default)
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../data/models/lifecycle_info.dart';

/// Compact lifecycle stage chip.
///
/// Pass [expandedMode] = true to additionally render stage progress dots.
/// Returns [SizedBox.shrink()] for terminal stages (paid / cleared) unless
/// [showTerminal] is explicitly set to true.
class LifecycleTag extends StatelessWidget {
  const LifecycleTag({
    super.key,
    required this.info,
    this.expandedMode = false,
    this.showTerminal = false,
  });

  final LifecycleInfo info;

  /// When true, renders an additional row of stage progress dots below the pill.
  final bool expandedMode;

  /// When false (default), terminal stages (paid/cleared) are hidden.
  final bool showTerminal;

  @override
  Widget build(BuildContext context) {
    if (info.stage.isTerminal && !showTerminal) return const SizedBox.shrink();

    final (color, bgAlpha) = _stageColor(context, info.stage);
    final label = info.stage.label;
    final days = info.daysInStage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagPill(label: label, days: days, color: color, bgAlpha: bgAlpha),
        if (expandedMode) ...[
          const SizedBox(height: AppSpacing.xs),
          _StageProgressDots(currentStage: info.stage),
        ],
      ],
    );
  }

  /// Returns (foreground Color, background alpha 0-255) for a stage.
  static (Color, int) _stageColor(BuildContext context, LifecycleStage stage) {
    final cs = context.colorScheme;
    final kash = context.kashColors;
    return switch (stage) {
      LifecycleStage.overdue => (cs.error, 30),
      LifecycleStage.reminded => (const Color(0xFFE65100), 28),
      LifecycleStage.sent => (cs.primary, 28),
      LifecycleStage.partiallyPaid => (kash.credit, 28),
      LifecycleStage.paying => (kash.income, 28),
      LifecycleStage.paid => (kash.income, 22),
      LifecycleStage.cleared => (cs.outline, 20),
      LifecycleStage.active => (cs.outline, 20),
      LifecycleStage.draft => (cs.outline, 20),
    };
  }
}

// ── Tag Pill ──────────────────────────────────────────────────────────────────

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    required this.days,
    required this.color,
    required this.bgAlpha,
  });

  final String label;
  final int days;
  final Color color;
  final int bgAlpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(bgAlpha),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (days > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '·',
                style: context.textTheme.labelSmall?.copyWith(
                  color: color.withAlpha(160),
                ),
              ),
            ),
            Text(
              '${days}d',
              style: context.textTheme.labelSmall?.copyWith(
                color: color.withAlpha(200),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stage Progress Dots (expanded mode) ──────────────────────────────────────

/// Horizontal dot row showing progress through the lifecycle stages.
/// Stages: active → sent → reminded → partiallyPaid → paid
class _StageProgressDots extends StatelessWidget {
  const _StageProgressDots({required this.currentStage});

  final LifecycleStage currentStage;

  static const _stages = [
    LifecycleStage.active,
    LifecycleStage.sent,
    LifecycleStage.reminded,
    LifecycleStage.partiallyPaid,
    LifecycleStage.paid,
  ];

  @override
  Widget build(BuildContext context) {
    // Determine position index of currentStage in the simplified chain
    int currentIdx = _stages.indexOf(currentStage);
    if (currentStage == LifecycleStage.overdue) {
      // Show between sent and reminded
      currentIdx = 1;
    } else if (currentStage == LifecycleStage.paying) {
      currentIdx = 3;
    } else if (currentIdx < 0) {
      currentIdx = 0;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_stages.length, (i) {
        final isActive = i <= currentIdx;
        final isCurrent = i == currentIdx;
        final color = isActive
            ? context.colorScheme.primary
            : context.colorScheme.outline.withAlpha(80);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isCurrent ? 10 : 6,
              height: isCurrent ? 10 : 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            if (i < _stages.length - 1)
              Container(
                width: 12,
                height: 1,
                color: isActive
                    ? context.colorScheme.primary.withAlpha(120)
                    : context.colorScheme.outline.withAlpha(60),
                margin: const EdgeInsets.symmetric(horizontal: 2),
              ),
          ],
        );
      }),
    );
  }
}
