import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/services/encrypted_backup_service.dart';
import '../../../data/services/fy_archive_service.dart';
import '../../providers/fy_provider.dart';
import 'encrypted_backup_screen.dart';

// ---------------------------------------------------------------------------
// FyCloseWizardScreen  — Phase 2 Year-End Closing Wizard
// ---------------------------------------------------------------------------
// A 3-step wizard that guides the user through:
//   Step 1 — Summary:   FY P&L, invoice counts, open credits overview.
//   Step 2 — Review:    Carry-forward acknowledgements (open invoices,
//                        uncleared credits), optional closing notes.
//   Step 3 — Archive:   Backup prompt + "Archive & Close FY" action.
//
// After archive is complete:
//   • DB is copied to kash_cube_archive_FY{YYYY}-{YY}.db.
//   • last_fy_close_date + current_fy_start are updated in settings.
//   • yearEndWarningProvider is invalidated → home banner disappears.
// ---------------------------------------------------------------------------

class FyCloseWizardScreen extends ConsumerStatefulWidget {
  const FyCloseWizardScreen({super.key});

  @override
  ConsumerState<FyCloseWizardScreen> createState() =>
      _FyCloseWizardScreenState();
}

class _FyCloseWizardScreenState extends ConsumerState<FyCloseWizardScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 3;

  // Step 2 form state
  bool _acknowledgeOpenInvoices = false;
  bool _acknowledgeOpenCredits = false;
  final _notesController = TextEditingController();

  // Async summary (loaded once)
  FYSummary? _summary;
  bool _summaryLoading = true;
  String? _summaryError;

  // Step 3 archive state
  bool _archiving = false;
  bool _archiveDone = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final s = await FyArchiveService.instance.getFYSummary();
      if (mounted) {
        setState(() {
          _summary = s;
          _summaryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = e.toString();
          _summaryLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _next() {
    if (_currentStep >= _totalSteps - 1) return;
    setState(() => _currentStep++);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _back() {
    if (_currentStep == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _currentStep--);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Step 2 validation ─────────────────────────────────────────────────────

  bool get _step2CanProceed {
    final s = _summary;
    if (s == null) return false;
    // If there are open invoices the user must acknowledge them.
    if (s.outstanding > 0 && !_acknowledgeOpenInvoices) return false;
    // If there are open credits the user must acknowledge them.
    if (s.openCreditCount > 0 && !_acknowledgeOpenCredits) return false;
    return true;
  }

  // ── Archive ───────────────────────────────────────────────────────────────

  Future<void> _archiveAndClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive & Close FY?'),
        content: Text(
          'This will create an archive copy of your database for '
          '${_summary?.fyLabel ?? 'this FY'} and reset invoice numbering '
          'for the new financial year.\n\n'
          'Your existing data is not deleted — it stays in the live database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive & Close'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _archiving = true);

    try {
      await FyArchiveService.instance.archiveCurrentFY();

      // Invalidate FY provider so home banner disappears.
      ref.invalidate(yearEndWarningProvider);

      if (!mounted) return;
      setState(() {
        _archiving = false;
        _archiveDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _archiving = false);
      context.showSnackBar('Archive failed: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Year-End Closing'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _archiveDone ? null : _back,
        ),
      ),
      body: Column(
        children: [
          // ── Step indicator ───────────────────────────────────────────
          _StepIndicator(current: _currentStep, total: _totalSteps),

          // ── Page content ─────────────────────────────────────────────
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1Summary(
                  loading: _summaryLoading,
                  error: _summaryError,
                  summary: _summary,
                ),
                _Step2Review(
                  summary: _summary,
                  acknowledgeOpenInvoices: _acknowledgeOpenInvoices,
                  acknowledgeOpenCredits: _acknowledgeOpenCredits,
                  onAcknowledgeInvoicesChanged: (v) =>
                      setState(() => _acknowledgeOpenInvoices = v),
                  onAcknowledgeCreditsChanged: (v) =>
                      setState(() => _acknowledgeOpenCredits = v),
                  notesController: _notesController,
                ),
                _Step3Archive(
                  summary: _summary,
                  archiving: _archiving,
                  archiveDone: _archiveDone,
                  onBackup: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EncryptedBackupScreen()),
                    );
                    // Re-check backup status after returning.
                    if (mounted) setState(() {});
                  },
                  onArchive: _archiveAndClose,
                  onDone: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Bottom navigation ─────────────────────────────────────────
          if (!_archiveDone)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.base),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton(
                        onPressed: _archiving ? null : _back,
                        child: const Text('Back'),
                      ),
                    const Spacer(),
                    if (_currentStep < _totalSteps - 1)
                      FilledButton(
                        onPressed: _canAdvance() ? _next : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                        child: const Text('Next'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _canAdvance() {
    if (_summaryLoading) return false;
    if (_currentStep == 1) return _step2CanProceed;
    return true;
  }
}

// ---------------------------------------------------------------------------
// Step Indicator
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  static const _labels = ['Summary', 'Review', 'Archive'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Row(
        children: List.generate(total, (i) {
          final isActive = i == current;
          final isDone = i < current;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isActive || isDone)
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _labels[i],
                        style: context.textTheme.labelSmall?.copyWith(
                          color: isActive
                              ? scheme.primary
                              : isDone
                                  ? scheme.primary.withValues(alpha: 0.7)
                                  : scheme.onSurfaceVariant,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < total - 1) const SizedBox(width: AppSpacing.xs),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Summary
// ---------------------------------------------------------------------------

class _Step1Summary extends StatelessWidget {
  const _Step1Summary({
    required this.loading,
    required this.error,
    required this.summary,
  });

  final bool loading;
  final String? error;
  final FYSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text('Error loading summary: $error',
              textAlign: TextAlign.center),
        ),
      );
    }
    final s = summary!;
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<KashCubeColors>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.fyLabel,
            style: context.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${_fmt(s.fyRange.start)} — ${_fmt(s.fyRange.end)}',
            style: context.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── P&L card ─────────────────────────────────────────────────
          _SummaryCard(
            title: 'Profit & Loss',
            children: [
              _SummaryRow(
                label: 'Income',
                value: CurrencyFormatter.format(s.income),
                valueColor: colors?.income,
              ),
              _SummaryRow(
                label: 'Expenses',
                value: CurrencyFormatter.format(s.expense),
                valueColor: colors?.expense,
              ),
              const Divider(height: AppSpacing.lg),
              _SummaryRow(
                label: 'Net P&L',
                value: CurrencyFormatter.formatSigned(s.netPnL),
                valueColor: s.netPnL >= 0 ? colors?.income : colors?.expense,
                bold: true,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Invoices card ─────────────────────────────────────────────
          _SummaryCard(
            title: 'Invoices',
            children: [
              _SummaryRow(
                label: 'Total invoices issued',
                value: s.invoiceCount.toString(),
              ),
              _SummaryRow(
                label: 'Outstanding receivables',
                value: CurrencyFormatter.format(s.outstanding),
                valueColor: s.outstanding > 0 ? colors?.expense : null,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Credits card ────────────────────────────────────────────
          _SummaryCard(
            title: 'Dues',
            children: [
              _SummaryRow(
                label: 'Open credits',
                value: s.openCreditCount.toString(),
                valueColor: s.openCreditCount > 0 ? colors?.credit : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day} ${_month(d.month)} ${d.year}';
  String _month(int m) => const [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ---------------------------------------------------------------------------
// Step 2 — Review & Carry-forward
// ---------------------------------------------------------------------------

class _Step2Review extends StatelessWidget {
  const _Step2Review({
    required this.summary,
    required this.acknowledgeOpenInvoices,
    required this.acknowledgeOpenCredits,
    required this.onAcknowledgeInvoicesChanged,
    required this.onAcknowledgeCreditsChanged,
    required this.notesController,
  });

  final FYSummary? summary;
  final bool acknowledgeOpenInvoices;
  final bool acknowledgeOpenCredits;
  final ValueChanged<bool> onAcknowledgeInvoicesChanged;
  final ValueChanged<bool> onAcknowledgeCreditsChanged;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<KashCubeColors>();
    final hasOpenInvoices = (s?.outstanding ?? 0) > 0;
    final hasOpenCredits = (s?.openCreditCount ?? 0) > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Before Closing',
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These items will carry over to the new financial year. '
            'Please review and confirm.',
            style: context.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Open invoices ─────────────────────────────────────────────
          if (hasOpenInvoices) ...[
            _AcknowledgeCard(
              icon: Icons.receipt_long_outlined,
              iconColor: colors?.expense ?? scheme.error,
              title: 'Outstanding Invoices',
              body:
                  '${CurrencyFormatter.format(s!.outstanding)} is still unpaid. '
                  'These invoices will remain open in the new FY.',
              checked: acknowledgeOpenInvoices,
              onChanged: onAcknowledgeInvoicesChanged,
              checkLabel: 'I understand and want to continue',
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Open credits ──────────────────────────────────────────────
          if (hasOpenCredits) ...[
            _AcknowledgeCard(
              icon: Icons.people_outline,
              iconColor: colors?.credit ?? scheme.tertiary,
              title: 'Open Dues',
              body:
                  '${s!.openCreditCount} credit${s.openCreditCount > 1 ? 's' : ''} '
                  'remain uncleared. They will carry forward to the new FY.',
              checked: acknowledgeOpenCredits,
              onChanged: onAcknowledgeCreditsChanged,
              checkLabel: 'I understand and want to continue',
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── No pending items ──────────────────────────────────────────
          if (!hasOpenInvoices && !hasOpenCredits)
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: (colors?.income ?? Colors.green).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (colors?.income ?? Colors.green).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: colors?.income ?? Colors.green),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'All invoices are paid and no open credits. '
                      'You\'re all set to close!',
                      style: context.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.lg),

          // ── Closing notes ─────────────────────────────────────────────
          Text(
            'Closing Notes (optional)',
            style: context.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: notesController,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              hintText:
                  'Add any notes for this FY close, e.g. key highlights…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.all(AppSpacing.md),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Archive & Close
// ---------------------------------------------------------------------------

class _Step3Archive extends StatelessWidget {
  const _Step3Archive({
    required this.summary,
    required this.archiving,
    required this.archiveDone,
    required this.onBackup,
    required this.onArchive,
    required this.onDone,
  });

  final FYSummary? summary;
  final bool archiving;
  final bool archiveDone;
  final VoidCallback onBackup;
  final VoidCallback onArchive;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<KashCubeColors>();

    if (archiveDone) {
      return _ArchiveDoneView(
        summary: summary,
        onDone: onDone,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Archive & Close',
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Before closing, we recommend taking an encrypted backup.',
            style: context.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Backup nudge ──────────────────────────────────────────────
          _BackupStatusCard(onBackup: onBackup),

          const SizedBox(height: AppSpacing.xl),

          // ── What happens card ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What happens when you close:',
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                _BulletItem(
                  icon: Icons.archive_outlined,
                  text:
                      'Current database is copied to kash_cube_archive_${summary?.fyLabel.replaceAll(' ', '_') ?? 'FY'}.db',
                ),
                _BulletItem(
                  icon: Icons.receipt_outlined,
                  text:
                      'Invoice numbering resets to 0001 for the new financial year',
                ),
                _BulletItem(
                  icon: Icons.history_outlined,
                  text:
                      'All existing transactions, invoices, and credits remain accessible',
                ),
                _BulletItem(
                  icon: Icons.notifications_outlined,
                  text: 'Year-end reminders are silenced',
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Archive button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: archiving ? null : onArchive,
              icon: archiving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.archive_outlined),
              label: Text(
                  archiving ? 'Archiving…' : 'Archive & Close FY'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    colors?.income ?? scheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Archive Done View
// ---------------------------------------------------------------------------

class _ArchiveDoneView extends StatelessWidget {
  const _ArchiveDoneView({required this.summary, required this.onDone});

  final FYSummary? summary;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 72,
            color: colors?.income ?? scheme.primary,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '${summary?.fyLabel ?? 'FY'} Closed!',
            style: context.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your database has been archived and invoice numbering '
            'will reset for the new financial year.',
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup Status Card — queries EncryptedBackupService for last backup date.
// ---------------------------------------------------------------------------

class _BackupStatusCard extends StatefulWidget {
  const _BackupStatusCard({required this.onBackup});

  final VoidCallback onBackup;

  @override
  State<_BackupStatusCard> createState() => _BackupStatusCardState();
}

class _BackupStatusCardState extends State<_BackupStatusCard> {
  DateTime? _lastBackup;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final d = await EncryptedBackupService.instance.lastBackupDate();
    if (mounted) {
      setState(() {
        _lastBackup = d;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<KashCubeColors>();

    if (_loading) {
      return const SizedBox(
          height: 64, child: Center(child: CircularProgressIndicator()));
    }

    final hasBackup = _lastBackup != null;
    final bgColor = hasBackup
        ? (colors?.income ?? Colors.green).withValues(alpha: 0.08)
        : (colors?.credit ?? scheme.tertiary).withValues(alpha: 0.1);
    final borderColor = hasBackup
        ? (colors?.income ?? Colors.green).withValues(alpha: 0.3)
        : (colors?.credit ?? scheme.tertiary).withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            hasBackup ? Icons.shield_outlined : Icons.shield_outlined,
            color: hasBackup
                ? (colors?.income ?? Colors.green)
                : (colors?.credit ?? scheme.tertiary),
            size: 28,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBackup ? 'Backup exists' : 'No encrypted backup yet',
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  hasBackup
                      ? 'Last backup: ${_fmtDate(_lastBackup!)}'
                      : 'Create an encrypted backup before archiving.',
                  style: context.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: widget.onBackup,
            child: Text(hasBackup ? 'Update' : 'Backup'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${_month(d.month)} ${d.year}';

  String _month(int m) => const [
        '',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.bodyMedium?.copyWith(
      color: valueColor,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _AcknowledgeCard extends StatelessWidget {
  const _AcknowledgeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.checked,
    required this.onChanged,
    required this.checkLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String checkLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: context.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(body,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            title: Text(checkLabel,
                style: context.textTheme.bodySmall),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
