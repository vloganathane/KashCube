import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../providers/unit_type_provider.dart';

/// Manage item unit types (pcs, kg, hrs, …).
/// System units are read-only; custom units can be added and deleted.
class UnitTypesScreen extends ConsumerWidget {
  const UnitTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitTypesProvider);
    final systemUnits = units.where((u) => u.isSystem).toList();
    final customUnits = units.where((u) => !u.isSystem).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit Types'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add unit'),
      ),
      body: units.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(
                  top: AppSpacing.sm, bottom: AppSpacing.xxxl + AppSpacing.xl),
              children: [
                // ── System defaults ────────────────────────────────────────
                _SectionHeader(
                  title: 'System Defaults',
                  subtitle: 'Built-in units — cannot be removed',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: systemUnits
                        .map((u) => Chip(
                              label: Text(u.label),
                              avatar: Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ))
                        .toList(),
                  ),
                ),

                const Divider(indent: AppSpacing.base, endIndent: AppSpacing.base),

                // ── Custom units ───────────────────────────────────────────
                _SectionHeader(
                  title: 'Custom Units',
                  subtitle: customUnits.isEmpty
                      ? 'Tap + Add unit to create your own'
                      : 'Swipe left to delete',
                ),
                if (customUnits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No custom units yet',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ...customUnits.map(
                    (u) => Dismissible(
                      key: ValueKey(u.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.base),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      confirmDismiss: (_) => _confirmDelete(context, u.label),
                      onDismissed: (_) =>
                          ref.read(unitTypesProvider.notifier).removeUnit(u.id),
                      child: ListTile(
                        leading: const Icon(Icons.straighten_outlined),
                        title: Text(u.label),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () async {
                            final ok = await _confirmDelete(context, u.label);
                            if (ok == true) {
                              ref
                                  .read(unitTypesProvider.notifier)
                                  .removeUnit(u.id);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New unit type'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              hintText: 'e.g. roll, bundle, acre…',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a unit label' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (label == null || label.isEmpty) return;

    final ok = await ref.read(unitTypesProvider.notifier).addUnit(label);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$label" already exists')),
      );
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String label) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete unit?'),
        content: Text('"$label" will be removed. Items using it keep their saved unit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
