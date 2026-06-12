import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/fiscal_year_service.dart';
import '../../providers/settings_provider.dart';

/// Loads document numbering settings in one shot.
final _documentNumberingProvider =
    FutureProvider<
      ({
        String invoiceFormat,
        String quoteFormat,
        String challanFormat,
        String invoiceStartSeq,
        String quoteStartSeq,
        String challanStartSeq,
      })
    >((ref) async {
      final repo = ref.read(settingsRepositoryProvider);
      final results = await Future.wait([
        repo.get(SettingsKeys.invoiceNoFormat),
        repo.get(SettingsKeys.quoteNoFormat),
        repo.get(SettingsKeys.challanNoFormat),
        repo.get(SettingsKeys.invoiceNoStartSeq),
        repo.get(SettingsKeys.quoteNoStartSeq),
        repo.get(SettingsKeys.challanNoStartSeq),
      ]);
      return (
        invoiceFormat: results[0] ?? '',
        quoteFormat: results[1] ?? '',
        challanFormat: results[2] ?? '',
        invoiceStartSeq: results[3] ?? '',
        quoteStartSeq: results[4] ?? '',
        challanStartSeq: results[5] ?? '',
      );
    });

class DocumentNumberingScreen extends ConsumerStatefulWidget {
  const DocumentNumberingScreen({super.key});

  @override
  ConsumerState<DocumentNumberingScreen> createState() =>
      _DocumentNumberingScreenState();
}

class _DocumentNumberingScreenState
    extends ConsumerState<DocumentNumberingScreen> {
  final _invoiceFormatController = TextEditingController();
  final _quoteFormatController = TextEditingController();
  final _challanFormatController = TextEditingController();
  final _invoiceStartController = TextEditingController();
  final _quoteStartController = TextEditingController();
  final _challanStartController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _invoiceFormatController.dispose();
    _quoteFormatController.dispose();
    _challanFormatController.dispose();
    _invoiceStartController.dispose();
    _quoteStartController.dispose();
    _challanStartController.dispose();
    super.dispose();
  }

  void _populate(
    ({
      String invoiceFormat,
      String quoteFormat,
      String challanFormat,
      String invoiceStartSeq,
      String quoteStartSeq,
      String challanStartSeq,
    })
    data,
  ) {
    if (_loaded) return;

    final isFirstTime =
        data.invoiceFormat.isEmpty &&
        data.quoteFormat.isEmpty &&
        data.challanFormat.isEmpty &&
        data.invoiceStartSeq.isEmpty &&
        data.quoteStartSeq.isEmpty &&
        data.challanStartSeq.isEmpty;

    _invoiceFormatController.text = data.invoiceFormat.isEmpty
        ? SettingsKeys.defaultInvoiceNoFormat
        : data.invoiceFormat;
    _quoteFormatController.text = data.quoteFormat.isEmpty
        ? SettingsKeys.defaultQuoteNoFormat
        : data.quoteFormat;
    _challanFormatController.text = data.challanFormat.isEmpty
        ? SettingsKeys.defaultChallanNoFormat
        : data.challanFormat;
    _invoiceStartController.text = data.invoiceStartSeq.isEmpty
        ? SettingsKeys.defaultInvoiceNoStartSeq
        : data.invoiceStartSeq;
    _quoteStartController.text = data.quoteStartSeq.isEmpty
        ? SettingsKeys.defaultQuoteNoStartSeq
        : data.quoteStartSeq;
    _challanStartController.text = data.challanStartSeq.isEmpty
        ? SettingsKeys.defaultChallanNoStartSeq
        : data.challanStartSeq;
    _loaded = true;

    if (isFirstTime) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _save(silent: true));
    }
  }

  Future<void> _save({bool silent = false}) async {
    final form = _formKey.currentState;
    if (form != null && !form.validate()) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await Future.wait([
        repo.set(
          SettingsKeys.invoiceNoFormat,
          _invoiceFormatController.text.trim(),
        ),
        repo.set(
          SettingsKeys.quoteNoFormat,
          _quoteFormatController.text.trim(),
        ),
        repo.set(
          SettingsKeys.challanNoFormat,
          _challanFormatController.text.trim(),
        ),
        repo.set(
          SettingsKeys.invoiceNoStartSeq,
          _invoiceStartController.text.trim(),
        ),
        repo.set(
          SettingsKeys.quoteNoStartSeq,
          _quoteStartController.text.trim(),
        ),
        repo.set(
          SettingsKeys.challanNoStartSeq,
          _challanStartController.text.trim(),
        ),
      ]);

      await Future.wait([
        FiscalYearService.instance.syncDocumentCursor(docType: 'invoice'),
        FiscalYearService.instance.syncDocumentCursor(docType: 'quote'),
        FiscalYearService.instance.syncDocumentCursor(docType: 'dc'),
      ]);

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document numbering saved')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(_documentNumberingProvider);
    dataAsync.whenData(_populate);

    return Scaffold(
      appBar: AppBar(title: const Text('Document Numbering')),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (_) => FutureBuilder<DateRange>(
          future: FiscalYearService.instance.currentFiscalYear,
          builder: (context, snapshot) {
            final fy =
                snapshot.data ??
                DateRange(
                  start: DateTime(2026, 4, 1),
                  end: DateTime(2027, 3, 31),
                );

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Use {YY}, {YY+1}, {YYYY}, and {SEQ} in the pattern. '
                            'The starting number is applied when the FY prefix changes.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _DocumentNumberingSection(
                    title: 'Invoice Numbers',
                    icon: Icons.receipt_long_outlined,
                    formatController: _invoiceFormatController,
                    startSeqController: _invoiceStartController,
                    fy: fy,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _DocumentNumberingSection(
                    title: 'Quotation Numbers',
                    icon: Icons.request_quote_outlined,
                    formatController: _quoteFormatController,
                    startSeqController: _quoteStartController,
                    fy: fy,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _DocumentNumberingSection(
                    title: 'Delivery Challan Numbers',
                    icon: Icons.local_shipping_outlined,
                    formatController: _challanFormatController,
                    startSeqController: _challanStartController,
                    fy: fy,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DocumentNumberingSection extends StatelessWidget {
  const _DocumentNumberingSection({
    required this.title,
    required this.icon,
    required this.formatController,
    required this.startSeqController,
    required this.fy,
  });

  final String title;
  final IconData icon;
  final TextEditingController formatController;
  final TextEditingController startSeqController;
  final DateRange fy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: formatController,
            decoration: const InputDecoration(
              labelText: 'Pattern',
              hintText: 'INV-{YY}-{YY+1}-{SEQ}',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Pattern is required';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: startSeqController,
            decoration: const InputDecoration(
              labelText: 'Starting number',
              hintText: '1',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a positive number';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedBuilder(
            animation: Listenable.merge([formatController, startSeqController]),
            builder: (context, _) {
              final format = formatController.text.trim();
              final startSeq =
                  int.tryParse(startSeqController.text.trim()) ?? 1;
              final preview = FiscalYearService.instance.formatDocumentNumber(
                format,
                fy,
                startSeq > 0 ? startSeq : 1,
              );

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preview',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      preview,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
