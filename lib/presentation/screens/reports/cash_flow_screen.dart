// ---------------------------------------------------------------------------
// CashFlowScreen — P2.3 (Pillar B)
// ---------------------------------------------------------------------------
// A chronological view of ALL money movement:
//   Past (30 days) → Today divider → Upcoming (90 days) → Projected
//
// Data source: cashFlowTimelineProvider from P1.5.
//
// 100% on-device — no network calls.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/cash_flow_event.dart';
import '../../../data/models/lifecycle_info.dart';
import '../../providers/cash_flow_provider.dart';
import '../../widgets/lifecycle_tag.dart';

// ---------------------------------------------------------------------------
// Filter
// ---------------------------------------------------------------------------

enum _CashFlowFilter { all, inflow, outflow, overdue }

extension on _CashFlowFilter {
  String get label => switch (this) {
        _CashFlowFilter.all => 'All',
        _CashFlowFilter.inflow => 'Inflow',
        _CashFlowFilter.outflow => 'Outflow',
        _CashFlowFilter.overdue => 'Overdue',
      };
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  _CashFlowFilter _filter = _CashFlowFilter.all;

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(cashFlowTimelineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About Cash Flow',
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: timelineAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load timeline: $e')),
        data: (allEvents) {
          final filtered = _applyFilter(allEvents, _filter);
          return CustomScrollView(
            slivers: [
              // Summary strip
              SliverToBoxAdapter(
                child: _SummaryStrip(events: allEvents),
              ),
              // Filter chips
              SliverToBoxAdapter(
                child: _FilterChipRow(
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
              ),
              // Timeline
              if (filtered.isEmpty)
                const SliverFillRemaining(child: _EmptyState())
              else
                ..._buildTimelineSliver(context, filtered),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxxl)),
            ],
          );
        },
      ),
    );
  }

  List<CashFlowEvent> _applyFilter(
      List<CashFlowEvent> events, _CashFlowFilter filter) {
    return switch (filter) {
      _CashFlowFilter.all => events,
      _CashFlowFilter.inflow =>
        events.where((e) => e.direction == CashFlowDirection.inflow).toList(),
      _CashFlowFilter.outflow =>
        events.where((e) => e.direction == CashFlowDirection.outflow).toList(),
      _CashFlowFilter.overdue =>
        events.where((e) => e.status == CashFlowStatus.overdue).toList(),
    };
  }

  List<Widget> _buildTimelineSliver(
      BuildContext context, List<CashFlowEvent> events) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final slivers = <Widget>[];
    bool shownTodayDivider = false;
    bool shownUpcomingDivider = false;

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final eventDay =
          DateTime(event.date.year, event.date.month, event.date.day);

      // Insert "TODAY / UPCOMING" divider
      if (!shownTodayDivider && !eventDay.isBefore(today)) {
        slivers.add(SliverToBoxAdapter(
          child: _SectionDivider(
              label: 'TODAY — ${DateFormat('d MMM yy').format(today)}',
              color: context.colorScheme.primary),
        ));
        shownTodayDivider = true;
      } else if (shownTodayDivider &&
          !shownUpcomingDivider &&
          event.status == CashFlowStatus.upcoming &&
          eventDay.isAfter(today)) {
        slivers.add(SliverToBoxAdapter(
          child: _SectionDivider(
              label: 'UPCOMING',
              color: context.colorScheme.tertiary),
        ));
        shownUpcomingDivider = true;
      }

      slivers.add(SliverToBoxAdapter(
        child: _EventTile(event: event),
      ));
    }

    // If all events are in the past, still show today divider at end
    if (!shownTodayDivider) {
      slivers.add(SliverToBoxAdapter(
        child: _SectionDivider(
            label: 'TODAY — ${DateFormat('d MMM yy').format(today)}',
            color: context.colorScheme.primary),
      ));
    }

    return slivers;
  }

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cash Flow Timeline',
                style: context.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Shows all recorded, upcoming, and overdue money movements '
              'across invoices, dues, loans, bills, and bookings in one view.',
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.base),
            _InfoRow(
                icon: Icons.check_circle_outline,
                color: Colors.green,
                label: 'Recorded',
                detail: 'Past transactions from your ledger'),
            _InfoRow(
                icon: Icons.warning_amber,
                color: Colors.red,
                label: 'Overdue',
                detail: 'Past their due date, not yet settled'),
            _InfoRow(
                icon: Icons.schedule,
                color: Colors.orange,
                label: 'Upcoming',
                detail: 'Expected in the next 7–90 days'),
            _InfoRow(
                icon: Icons.autorenew,
                color: Colors.blue,
                label: 'Projected',
                detail: 'Recurring bills beyond the near-term window'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary strip
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.events});

  final List<CashFlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 30));

    double upcoming30Inflow = 0;
    double upcoming30Outflow = 0;
    int overdueCount = 0;

    for (final e in events) {
      if (e.status == CashFlowStatus.overdue) {
        overdueCount++;
      } else if (e.status == CashFlowStatus.upcoming &&
          e.date.isBefore(cutoff)) {
        if (e.direction == CashFlowDirection.inflow) {
          upcoming30Inflow += e.amount;
        } else {
          upcoming30Outflow += e.amount;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: _StatBox(
              label: '30d Inflow',
              value: CurrencyFormatter.formatCompact(upcoming30Inflow),
              color: colors.income,
              icon: Icons.arrow_downward,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatBox(
              label: '30d Outflow',
              value: CurrencyFormatter.formatCompact(upcoming30Outflow),
              color: colors.expense,
              icon: Icons.arrow_upward,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (overdueCount > 0)
            Expanded(
              child: _StatBox(
                label: 'Overdue',
                value: '$overdueCount item${overdueCount > 1 ? 's' : ''}',
                color: colors.expense,
                icon: Icons.warning_amber,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(label,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: color)),
          ]),
          Text(value,
              style: context.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip row
// ---------------------------------------------------------------------------

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.selected, required this.onSelected});

  final _CashFlowFilter selected;
  final ValueChanged<_CashFlowFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        itemCount: _CashFlowFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final filter = _CashFlowFilter.values[i];
          return FilterChip(
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) => onSelected(filter),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section divider
// ---------------------------------------------------------------------------

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      color: color.withAlpha(15),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event tile
// ---------------------------------------------------------------------------

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CashFlowEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final (icon, iconColor) = _iconFor(event, colors);
    final amountColor =
        event.direction == CashFlowDirection.inflow ? colors.income : colors.expense;
    final signedAmount = event.direction == CashFlowDirection.inflow
        ? '+${CurrencyFormatter.format(event.amount)}'
        : '-${CurrencyFormatter.format(event.amount)}';

    final statusBadge = _statusBadge(event);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.description,
              style: context.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (statusBadge != null) ...[
            const SizedBox(width: AppSpacing.xs),
            statusBadge,
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${DateFormat('d MMM').format(event.date)}'
            '${event.partyName != null ? " · ${event.partyName}" : ""}'
            '${event.categoryLabel != null ? " · ${event.categoryLabel}" : ""}',
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colorScheme.outline),
            overflow: TextOverflow.ellipsis,
          ),
          Builder(builder: (ctx) {
            final info = _lifecycleFrom(event);
            if (info == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: LifecycleTag(info: info),
            );
          }),
        ],
      ),
      trailing: Text(
        signedAmount,
        style: context.textTheme.bodyMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  (IconData, Color) _iconFor(CashFlowEvent event, KashCubeColors colors) =>
      switch (event) {
        RecordedEvent() => (Icons.check_circle_outline, colors.income),
        OverdueInvoiceEvent() => (Icons.receipt_long_outlined, colors.expense),
        UpcomingInvoiceEvent() => (Icons.receipt_long_outlined, colors.income),
        OverdueCreditEvent() => (Icons.handshake_outlined, colors.expense),
        UpcomingCreditEvent() => (Icons.handshake_outlined, colors.income),
        OverdueLoanEvent() => (Icons.account_balance_outlined, colors.expense),
        UpcomingLoanEvent() => (Icons.account_balance_outlined, colors.income),
        OverdueScheduledEvent() => (Icons.repeat_outlined, colors.expense),
        UpcomingScheduledEvent() => (Icons.repeat_outlined, colors.credit),
        ProjectedScheduledEvent() => (Icons.autorenew, Colors.blue),
        UpcomingBookingEvent() => (Icons.calendar_month_outlined, colors.income),
      };

  Widget? _statusBadge(CashFlowEvent event) {
    // OVERDUE is now shown by LifecycleTag in the subtitle (more informative: OVERDUE · Nd)
    if (event.status == CashFlowStatus.projected) {
      return _Badge(label: 'PROJECTED', color: Colors.blue);
    }
    return null;
  }

  static LifecycleInfo? _lifecycleFrom(CashFlowEvent event) {
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    return switch (event) {
      RecordedEvent()         => null,
      ProjectedScheduledEvent() => null,
      OverdueInvoiceEvent()  || OverdueCreditEvent() ||
      OverdueLoanEvent()     || OverdueScheduledEvent() => LifecycleInfo(
            stage: LifecycleStage.overdue,
            daysInStage: today0
                .difference(DateTime(
                    event.date.year, event.date.month, event.date.day))
                .inDays
                .clamp(0, 9999),
          ),
      _ => null,
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline,
              size: 64, color: context.colorScheme.outline),
          const SizedBox(height: AppSpacing.base),
          Text('No events match this filter',
              style: context.textTheme.titleMedium
                  ?.copyWith(color: context.colorScheme.outline)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info row helper
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: context.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(detail,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colorScheme.outline)),
            ],
          ),
        ],
      ),
    );
  }
}
