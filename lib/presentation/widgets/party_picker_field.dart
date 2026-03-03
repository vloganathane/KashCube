import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/kash_cube_colors.dart';
import '../../core/utils/contacts_helper.dart';
import '../../data/models/party.dart';
import '../providers/party_provider.dart';
import '../providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// A form field widget for selecting / entering a party name.
///
/// Features two selection paths:
/// 1. **Autocomplete**: Type to see suggestions dropdown (quick select)
/// 2. **Full Picker**: Click button to see all parties with search, contacts, add new
///
/// The user can also type freely in the text field without using either method.
class PartyPickerField extends ConsumerStatefulWidget {
  const PartyPickerField({
    super.key,
    required this.controller,
    this.labelText = 'Party (optional)',
    this.hintText,
    this.validator,
    this.onSelected,
    this.onPartySelected,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final FormFieldValidator<String>? validator;

  /// Called after a party name is chosen (e.g. to trigger suggestion fetch).
  final void Function(String name)? onSelected;
  
  /// Called after a party is selected from autocomplete - provides full Party object.
  final void Function(Party party)? onPartySelected;

  @override
  ConsumerState<PartyPickerField> createState() => _PartyPickerFieldState();
}

class _PartyPickerFieldState extends ConsumerState<PartyPickerField> {
  final FocusNode _focusNode = FocusNode();
  
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
  
  Future<void> _openPicker() async {
    _focusNode.unfocus();  // Close autocomplete dropdown
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PartyPickerSheet(initial: widget.controller.text),
    );
    if (result != null && mounted) {
      widget.controller.text = result;
      widget.onSelected?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partiesAsync = ref.watch(partiesProvider);
    final allParties = partiesAsync.valueOrNull ?? [];

    return Autocomplete<Party>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Party>.empty();
        }
        final query = textEditingValue.text.toLowerCase();
        return allParties.where((party) {
          return party.name.toLowerCase().contains(query) ||
              (party.phoneNumber?.contains(query) ?? false);
        }).take(5);  // Show max 5 suggestions
      },
      displayStringForOption: (Party party) => party.name,
      onSelected: (Party party) {
        widget.controller.text = party.name;
        widget.onSelected?.call(party.name);
        widget.onPartySelected?.call(party);  // Pass full party object
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // Sync with parent controller
        widget.controller.addListener(() {
          if (controller.text != widget.controller.text) {
            controller.text = widget.controller.text;
          }
        });
        controller.addListener(() {
          if (widget.controller.text != controller.text) {
            widget.controller.text = controller.text;
          }
        });
        
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.person_outline),
            suffixIcon: IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'Show all parties',
              onPressed: _openPicker,
            ),
          ),
          validator: widget.validator,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 350),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final party = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(
                        party.name.isNotEmpty ? party.name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(party.name),
                    subtitle: party.phoneNumber != null
                        ? Text(
                            '+91 ${party.phoneNumber}',
                            style: Theme.of(context).textTheme.labelSmall,
                          )
                        : null,
                    onTap: () => onSelected(party),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Picker bottom sheet
// ---------------------------------------------------------------------------

class _PartyPickerSheet extends ConsumerStatefulWidget {
  const _PartyPickerSheet({this.initial = ''});
  final String initial;

  @override
  ConsumerState<_PartyPickerSheet> createState() => _PartyPickerSheetState();
}

class _PartyPickerSheetState extends ConsumerState<_PartyPickerSheet> {
  late final TextEditingController _search;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initial);
    _query = widget.initial;
    _search.addListener(() {
      if (_query != _search.text) setState(() => _query = _search.text);
    });
    // Ensure parties are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(partiesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // A colour per party type (mirrors parties_screen logic)
  Color _typeColor(PartyType type, KashCubeColors colors) {
    switch (type) {
      case PartyType.personal:
        return colors.investment;
      case PartyType.customer:
        return colors.income;
      case PartyType.vendor:
        return colors.expense;
      case PartyType.lender:
        return colors.credit;
      case PartyType.borrower:
        return colors.overdue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KashCubeColors>()!;
    final partiesAsync = ref.watch(partiesProvider);
    final allParties = partiesAsync.valueOrNull ?? [];

    // Filter by query
    final filtered = _query.isEmpty
        ? allParties
        : allParties
            .where((p) =>
                p.name.toLowerCase().contains(_query.toLowerCase()) ||
                (p.phoneNumber?.contains(_query) ?? false))
            .toList();

    // Show "Add new" row only when query is non-empty and no exact name match
    final hasExactMatch = allParties
        .any((p) => p.name.toLowerCase() == _query.toLowerCase());
    final showAddNew = _query.isNotEmpty && !hasExactMatch;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
        return Column(
          children: [
            // ── Handle ───────────────────────────────────────────────────
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Title + search ───────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Party',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Search or type a name…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),

            // ── Scrollable list ──────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // ── Pick from Contacts ───────────────────────────────
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.contacts_outlined,
                          size: 20,
                          color: theme.colorScheme.onSecondaryContainer),
                    ),
                    title: const Text('Pick from Contacts'),
                    subtitle: const Text(
                        'Opens your contacts app — only selected contact is read'),
                    onTap: () async {
                      // Capture navigator before any async gap.
                      final nav = Navigator.of(context);
                      final proceed = await requestContactsPickerRationale(
                        context,
                        settingsRepository:
                            ref.read(settingsRepositoryProvider),
                      );
                      if (!proceed || !mounted) return;
                      final contact =
                          await FlutterContacts.openExternalPick();
                      if (contact == null || !mounted) return;
                      final name = contact.displayName.trim();
                      if (name.isNotEmpty) nav.pop(name);
                    },
                  ),

                  if (allParties.isNotEmpty || filtered.isNotEmpty)
                    const Divider(indent: 16, endIndent: 16),

                  // ── Saved parties ────────────────────────────────────
                  if (partiesAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filtered.isEmpty && _query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                          horizontal: AppSpacing.base),
                      child: Text('No saved parties match "$_query"',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline)),
                    )
                  else
                    ...filtered.map((party) {
                      final tc = _typeColor(party.partyType, colors);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: tc.withValues(alpha: 0.15),
                          child: Text(
                            party.name.characters.first.toUpperCase(),
                            style: TextStyle(
                                color: tc, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(party.name),
                        subtitle: party.phoneNumber != null
                            ? Text(party.phoneNumber!)
                            : null,
                        trailing: _TypeBadge(
                            label: party.partyType.label, color: tc),
                        onTap: () => Navigator.pop(context, party.name),
                      );
                    }),

                  // ── Add new party ────────────────────────────────────
                  if (showAddNew) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primaryContainer,
                        child: Icon(Icons.person_add_outlined,
                            size: 20,
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                      title: Text('Add "$_query" as new party'),
                      subtitle: const Text(
                          'Saves to your parties list as a Personal contact'),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        final name = _query.trim();
                        final newParty = Party(
                          name: name,
                          partyType: PartyType.personal,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        );
                        await ref
                            .read(partiesProvider.notifier)
                            .add(newParty);
                        if (mounted) nav.pop(name);
                      },
                    ),
                  ],

                  // ── Use as-is (typed name with no save) ──────────────
                  if (_query.isNotEmpty) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.edit_outlined, size: 20),
                      ),
                      title: Text('Use "$_query" without saving'),
                      subtitle:
                          const Text('One-off name, not added to parties'),
                      onTap: () => Navigator.pop(context, _query.trim()),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ],
        );
      },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type badge chip (local helper)
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
