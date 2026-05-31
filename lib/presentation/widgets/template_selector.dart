import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../providers/document_template_provider.dart';
import '../screens/settings/template_list_screen.dart';

/// Dropdown to select the active PDF template.
/// Shows current active template and allows quick switching.
class TemplateSelector extends ConsumerWidget {
  const TemplateSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(documentTemplatesProvider);

    return templatesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, st) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text('Error loading templates'),
      ),
      data: (templates) {
        if (templates.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No templates found',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TemplateListScreen(),
                      ),
                    );
                  },
                  tooltip: 'Manage Templates',
                ),
              ],
            ),
          );
        }

        final active = templates.firstWhere(
          (t) => t.isActive,
          orElse: () => templates.first,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: active.id,
                  items: templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            '${t.name}${t.isPreset ? " (Built-in)" : ""}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) {
                      ref
                          .read(documentTemplatesProvider.notifier)
                          .setActive(id);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TemplateListScreen(),
                    ),
                  );
                },
                tooltip: 'Manage Templates',
              ),
            ],
          ),
        );
      },
    );
  }
}
