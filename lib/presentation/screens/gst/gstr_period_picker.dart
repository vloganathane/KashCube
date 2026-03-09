import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';

// ─── Date range ──────────────────────────────────────────────────────────────

class GstrDateRange {
  const GstrDateRange({
    required this.from,
    required this.to,
    required this.returnPeriodLabel,
    required this.displayLabel,
  });

  /// First day of the selected period.
  final DateTime from;

  /// Last day of the selected period.
  final DateTime to;

  /// GSTN return period in "MMYYYY" format (e.g. "032026").
  final String returnPeriodLabel;

  /// Human-readable label (e.g. "March 2026" or "Q4 FY 2025-26").
  final String displayLabel;
}

// ─── Indian fiscal year helpers ───────────────────────────────────────────────

String _fyLabel(int startYear) => '$startYear-${(startYear + 1) % 100 < 10 ? '0${(startYear + 1) % 100}' : '${(startYear + 1) % 100}'}';

/// Returns the 12 months (Apr–Mar) for the FY starting in [startYear].
List<DateTime> _fyMonths(int startYear) {
  final months = <DateTime>[];
  for (int m = 4; m <= 12; m++) {
    months.add(DateTime(startYear, m));
  }
  for (int m = 1; m <= 3; m++) {
    months.add(DateTime(startYear + 1, m));
  }
  return months;
}

/// Returns the 4 quarters (Apr-Jun, Jul-Sep, Oct-Dec, Jan-Mar) for the FY.
List<_Quarter> _fyQuarters(int startYear) => [
      _Quarter('Q1 (Apr–Jun)', DateTime(startYear, 4, 1),
          DateTime(startYear, 6, 30)),
      _Quarter('Q2 (Jul–Sep)', DateTime(startYear, 7, 1),
          DateTime(startYear, 9, 30)),
      _Quarter('Q3 (Oct–Dec)', DateTime(startYear, 10, 1),
          DateTime(startYear, 12, 31)),
      _Quarter('Q4 (Jan–Mar)', DateTime(startYear + 1, 1, 1),
          DateTime(startYear + 1, 3, 31)),
    ];

class _Quarter {
  const _Quarter(this.label, this.from, this.to);
  final String label;
  final DateTime from;
  final DateTime to;
}

String _monthLabel(DateTime d) => DateFormat('MMM yyyy').format(d);
String _returnLabel(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}${d.year}';

DateTime _lastDayOf(DateTime month) =>
    DateTime(month.year, month.month + 1, 0);

// ─── Widget ───────────────────────────────────────────────────────────────────

/// Period picker for GSTR-1 export.
///
/// Allows the user to select:
///   - Fiscal Year (current FY, last FY, one before that)
///   - Mode: Monthly | Quarterly
///   - Specific month or quarter within that FY
///
/// Calls [onChanged] whenever the selection changes. The initial value is the
/// most recently completed month.
class GstrPeriodPicker extends StatefulWidget {
  const GstrPeriodPicker({
    super.key,
    required this.onChanged,
  });

  final void Function(GstrDateRange range) onChanged;

  @override
  State<GstrPeriodPicker> createState() => _GstrPeriodPickerState();
}

class _GstrPeriodPickerState extends State<GstrPeriodPicker> {
  late int _fyStartYear;
  bool _quarterly = false;

  // Monthly selection — index into the 12 FY months (0-based, 0 = April)
  int _monthIdx = 0;

  // Quarterly selection — index into quarters (0-based, 0 = Q1)
  int _quarterIdx = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fyStartYear = _fyStartYear_(now);
    _monthIdx = _defaultMonthIdx(now);
  }

  // Pick the most recently completed month within the current FY
  static int _fyStartYear_(DateTime d) =>
      d.month >= 4 ? d.year : d.year - 1;

  static int _defaultMonthIdx(DateTime now) {
    final fyStart = _fyStartYear_(now);
    final months = _fyMonths(fyStart);
    final lastCompletedMonth = now.day > 1
        ? DateTime(now.year, now.month - 1 < 1 ? 12 : now.month - 1)
        : DateTime(now.year, now.month - 2 < 1 ? 12 : now.month - 2);
    for (int i = months.length - 1; i >= 0; i--) {
      if (!months[i].isAfter(lastCompletedMonth)) return i;
    }
    return 0;
  }

  GstrDateRange _buildRange() {
    if (_quarterly) {
      final q = _fyQuarters(_fyStartYear)[_quarterIdx];
      final endMonth = q.to.month;
      final endYear = q.to.year;
      final label = '${endMonth.toString().padLeft(2, '0')}$endYear';
      return GstrDateRange(
        from: q.from,
        to: q.to,
        returnPeriodLabel: label,
        displayLabel: '${q.label}  FY ${_fyLabel(_fyStartYear)}',
      );
    } else {
      final month = _fyMonths(_fyStartYear)[_monthIdx];
      return GstrDateRange(
        from: DateTime(month.year, month.month, 1),
        to: _lastDayOf(month),
        returnPeriodLabel: _returnLabel(month),
        displayLabel: _monthLabel(month),
      );
    }
  }

  void _notify() => widget.onChanged(_buildRange());

  bool _isFuture(DateTime d) {
    final now = DateTime.now();
    return d.year > now.year ||
        (d.year == now.year && d.month > now.month);
  }

  @override
  Widget build(BuildContext context) {
    final range = _buildRange();
    final quarters = _fyQuarters(_fyStartYear);
    final months = _fyMonths(_fyStartYear);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── FY selector ────────────────────────────────────────────────
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Fiscal Year', style: context.textTheme.labelMedium),
                _FyChip(
                  label: _fyLabel(_fyStartYear_(DateTime.now())),
                  selected: _fyStartYear == _fyStartYear_(DateTime.now()),
                  onTap: () => setState(() {
                    _fyStartYear = _fyStartYear_(DateTime.now());
                    _notify();
                  }),
                ),
                _FyChip(
                  label: _fyLabel(_fyStartYear_(DateTime.now()) - 1),
                  selected:
                      _fyStartYear == _fyStartYear_(DateTime.now()) - 1,
                  onTap: () => setState(() {
                    _fyStartYear = _fyStartYear_(DateTime.now()) - 1;
                    _notify();
                  }),
                ),
                _FyChip(
                  label: _fyLabel(_fyStartYear_(DateTime.now()) - 2),
                  selected:
                      _fyStartYear == _fyStartYear_(DateTime.now()) - 2,
                  onTap: () => setState(() {
                    _fyStartYear = _fyStartYear_(DateTime.now()) - 2;
                    _notify();
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // ── Monthly / Quarterly toggle ──────────────────────────────────
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Monthly'),
                  selected: !_quarterly,
                  onSelected: (_) => setState(() {
                    _quarterly = false;
                    _notify();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: AppSpacing.xs),
                ChoiceChip(
                  label: const Text('Quarterly'),
                  selected: _quarterly,
                  onSelected: (_) => setState(() {
                    _quarterly = true;
                    _notify();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── Month / Quarter grid ────────────────────────────────────────
            if (!_quarterly) ...[
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: List.generate(12, (i) {
                  final m = months[i];
                  final future = _isFuture(m);
                  return ChoiceChip(
                    label: Text(DateFormat('MMM yy').format(m)),
                    selected: !_quarterly && _monthIdx == i,
                    onSelected: future
                        ? null
                        : (_) => setState(() {
                              _monthIdx = i;
                              _notify();
                            }),
                    visualDensity: VisualDensity.compact,
                  );
                }),
              ),
            ] else ...[
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: List.generate(4, (i) {
                  final q = quarters[i];
                  final future = _isFuture(q.to);
                  return ChoiceChip(
                    label: Text(q.label),
                    selected: _quarterly && _quarterIdx == i,
                    onSelected: future
                        ? null
                        : (_) => setState(() {
                              _quarterIdx = i;
                              _notify();
                            }),
                    visualDensity: VisualDensity.compact,
                  );
                }),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),

            // ── Selected range label ────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 14,
                    color: context.colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  range.displayLabel,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (_isFuture(_buildRange().to))
                  Chip(
                    label: const Text('Future period'),
                    labelStyle: TextStyle(
                        color: context.colorScheme.error, fontSize: 11),
                    backgroundColor:
                        context.colorScheme.errorContainer.withValues(alpha: 0.4),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FyChip extends StatelessWidget {
  const _FyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('FY $label'),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}
