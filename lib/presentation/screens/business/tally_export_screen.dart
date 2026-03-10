import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/tally_xml_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/upgrade_prompt_sheet.dart' show showUpgradePromptSheet;

/// Exports transactions to Tally XML format for import into Tally ERP / Prime.
///
/// Business tier only.  All processing is 100% local — no network calls.
class TallyExportScreen extends ConsumerStatefulWidget {
  const TallyExportScreen({super.key});

  @override
  ConsumerState<TallyExportScreen> createState() => _TallyExportScreenState();
}

class _TallyExportScreenState extends ConsumerState<TallyExportScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');

  DateTime _from = DateTime(
      DateTime.now().year, DateTime.now().month - 2 < 1 ? 1 : DateTime.now().month - 2, 1);
  DateTime _to = DateTime.now();
  bool _exporting = false;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final business = ref.read(activeBusinessProvider);
      final companyName = business?.name ?? 'My Company';
      final txnRepo = ref.read(transactionRepositoryProvider);
      final transactions = await txnRepo.getByDateRange(_from, _to);

      if (!mounted) return;

      if (transactions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No transactions found for the selected period.')),
        );
        return;
      }

      final filePath = await TallyXmlService.instance.export(
        transactions,
        companyName: companyName,
      );

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/xml')],
        subject: 'Kash Cube — Tally XML Export',
        text:
            'Tally XML for ${_dateFormat.format(_from)} – ${_dateFormat.format(_to)}'
            ' (${transactions.length} vouchers)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionTierProvider);
    if (!tier.isBusiness) {
      return _GatedPlaceholder(tier: tier);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tally XML Export'),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: context.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Export your transactions as a Tally-compatible XML file. '
                        'Import it via Gateway of Tally → Import Data → Vouchers.',
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Select Date Range',
              style: context.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _DatePickerButton(
                    label: 'From',
                    date: _from,
                    dateFormat: _dateFormat,
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DatePickerButton(
                    label: 'To',
                    date: _to,
                    dateFormat: _dateFormat,
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_exporting ? 'Exporting…' : 'Export & Share XML'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "The generated XML file will be shared via your device's standard share sheet.",
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tier gate ─────────────────────────────────────────────────────────────────

class _GatedPlaceholder extends ConsumerWidget {
  const _GatedPlaceholder({required this.tier});
  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tally XML Export')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.import_export_outlined,
                  size: 64, color: context.colorScheme.outline),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Tally XML export is a\nBusiness tier feature',
                textAlign: TextAlign.center,
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () =>
                    showUpgradePromptSheet(context, featureName: 'Tally Export'),
                icon: const Icon(Icons.star_outline),
                label: const Text('Upgrade to Business'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Date picker button ────────────────────────────────────────────────────────

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.label,
    required this.date,
    required this.dateFormat,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md, horizontal: AppSpacing.base),
        alignment: Alignment.centerLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.colorScheme.outline),
          ),
          Text(
            dateFormat.format(date),
            style: context.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
