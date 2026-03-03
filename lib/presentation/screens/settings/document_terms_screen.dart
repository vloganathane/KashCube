import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../providers/settings_provider.dart';

/// Loads all three terms strings from settings in one shot.
final _termsProvider =
    FutureProvider<({String invoice, String quote, String booking})>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final results = await Future.wait([
    repo.get(SettingsKeys.invoiceTerms),
    repo.get(SettingsKeys.quoteTerms),
    repo.get(SettingsKeys.bookingTerms),
  ]);
  return (
    invoice: results[0] ?? '',
    quote: results[1] ?? '',
    booking: results[2] ?? '',
  );
});

/// Screen to edit the default terms & conditions that appear in generated PDFs.
/// Changes are saved on tapping "Save".
class DocumentTermsScreen extends ConsumerStatefulWidget {
  const DocumentTermsScreen({super.key});

  @override
  ConsumerState<DocumentTermsScreen> createState() =>
      _DocumentTermsScreenState();
}

class _DocumentTermsScreenState extends ConsumerState<DocumentTermsScreen> {
  final _invoiceCtrl  = TextEditingController();
  final _quoteCtrl    = TextEditingController();
  final _bookingCtrl  = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _quoteCtrl.dispose();
    _bookingCtrl.dispose();
    super.dispose();
  }

  void _populate(({String invoice, String quote, String booking}) data) {
    if (_loaded) return;
    _invoiceCtrl.text  = data.invoice;
    _quoteCtrl.text    = data.quote;
    _bookingCtrl.text  = data.booking;
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await Future.wait([
        repo.set(SettingsKeys.invoiceTerms, _invoiceCtrl.text.trim()),
        repo.set(SettingsKeys.quoteTerms,   _quoteCtrl.text.trim()),
        repo.set(SettingsKeys.bookingTerms, _bookingCtrl.text.trim()),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terms & conditions saved')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final termsAsync = ref.watch(_termsProvider);
    termsAsync.whenData(_populate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Default Terms & Conditions'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: termsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            // ── Info banner ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
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
                      'These terms appear at the bottom of every PDF you generate.'
                      ' Leave blank to omit the section.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Invoice ──────────────────────────────────────────────────
            _TermsField(
              label: 'Invoice Terms & Conditions',
              icon: Icons.receipt_long_outlined,
              controller: _invoiceCtrl,
              hint: 'e.g. Payment due within stated period…',
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Quote ────────────────────────────────────────────────────
            _TermsField(
              label: 'Quotation Terms & Conditions',
              icon: Icons.request_quote_outlined,
              controller: _quoteCtrl,
              hint: 'e.g. This quote is valid for the stated period…',
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Booking ──────────────────────────────────────────────────
            _TermsField(
              label: 'Booking Terms & Conditions',
              icon: Icons.event_note_outlined,
              controller: _bookingCtrl,
              hint: 'e.g. Cancellations require 48 hours notice…',
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ── Save button (bottom) ─────────────────────────────────────
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save All'),
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable editable terms field
// ---------------------------------------------------------------------------

class _TermsField extends StatelessWidget {
  const _TermsField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          maxLines: 6,
          minLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(AppSpacing.md),
          ),
        ),
      ],
    );
  }
}
