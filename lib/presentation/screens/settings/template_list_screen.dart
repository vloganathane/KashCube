import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/document_template_record.dart';
import '../../providers/document_template_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/document_template_preview.dart';
import 'template_builder_screen.dart';

/// Lists all document templates (built-in presets + user-created).
///
/// Users can:
/// • Select the active template (applied to all new PDFs).
/// • Create new custom templates via the FAB.
/// • Edit or delete custom templates (long-press or swipe).
class TemplateListScreen extends ConsumerWidget {
  const TemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(documentTemplatesProvider);
    final activeTemplate = ref.watch(documentTemplateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('PDF Templates')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const TemplateBuilderScreen(),
          ),
        ).then((_) => ref.read(documentTemplatesProvider.notifier).reload()),
        tooltip: 'New template',
        child: const Icon(Icons.add),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load templates: $e'),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return const Center(child: Text('No templates found.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: 96, // FAB clearance
            ),
            itemCount: templates.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = templates[index];
              // Active = DB is_active OR matches current settings provider id
              final isActive = record.isActive ||
                  (record.isPreset &&
                      (record.basedOn == activeTemplate.id ||
                          'tpl_${record.id}' == activeTemplate.id));
              return _TemplateListTile(
                record: record,
                isActive: isActive,
                onTap: () => _setActive(context, ref, record),
                onEdit: record.isPreset
                    ? null
                    : () => _editTemplate(context, ref, record),
                onDelete: record.isPreset
                    ? null
                    : () => _confirmDelete(context, ref, record),
              );
            },
          );
        },
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    DocumentTemplateRecord record,
  ) async {
    await ref.read(documentTemplatesProvider.notifier).setActive(record.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${record.name}" set as active template.')),
      );
    }
  }

  Future<void> _editTemplate(
    BuildContext context,
    WidgetRef ref,
    DocumentTemplateRecord record,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateBuilderScreen(existing: record),
      ),
    );
    ref.read(documentTemplatesProvider.notifier).reload();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DocumentTemplateRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          '"${record.name}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(documentTemplatesProvider.notifier).remove(record.id);
    }
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _TemplateListTile extends StatelessWidget {
  const _TemplateListTile({
    required this.record,
    required this.isActive,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final DocumentTemplateRecord record;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final subtitle = _buildSubtitle(record);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Preview thumbnail
            DocumentTemplatePreview(record: record, width: 44, dpi: 72),
            const SizedBox(width: AppSpacing.base),

            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.name,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (record.isPreset)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Built-in',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete',
                    color: Theme.of(context).colorScheme.error,
                    onPressed: onDelete,
                  ),
                // Active indicator
                Icon(
                  isActive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _buildSubtitle(DocumentTemplateRecord r) {
    final parts = <String>[];

    switch (r.pageSizeName) {
      case 'a4':
        parts.add('A4');
      case 'a5':
        parts.add('A5');
      case 'letter':
        parts.add('Letter');
      case 'thermal58':
        parts.add('58 mm Thermal');
      case 'thermal80':
        parts.add('80 mm Thermal');
      default:
        parts.add(r.pageSizeName.toUpperCase());
    }

    if (!r.isThermal) {
      parts.add(r.headerStyleName == 'banner' ? 'Banner' : 'Minimal');
      if (r.showLogo) parts.add('Logo');
    }

    if (r.amountDecimalDigits == 2) parts.add('Paise');

    return parts.join(' · ');
  }
}
