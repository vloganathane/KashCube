import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/kash_cube_colors.dart';
import '../../core/utils/adaptive_sheet.dart';
import '../../core/utils/contacts_helper.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/credit.dart';
import '../../data/models/party.dart';
import '../providers/credit_provider.dart';
import '../providers/loan_provider.dart';
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
    this.filterTypes,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final FormFieldValidator<String>? validator;

  /// Called after a party name is chosen (e.g. to trigger suggestion fetch).
  final void Function(String name)? onSelected;
  
  /// Called after a party is selected from autocomplete - provides full Party object.
  final void Function(Party party)? onPartySelected;

  /// When set, only parties of these types appear in suggestions and the picker.
  final List<PartyType>? filterTypes;

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
    final result = await showAdaptiveSheet<({Party? party, String? name})>(
      context,
      builder: (_) => _PartyPickerSheet(
        initial: widget.controller.text,
        filterTypes: widget.filterTypes,
      ),
    );
    if (result != null && mounted) {
      final name = result.party?.name ?? result.name ?? '';
      widget.controller.text = name;
      widget.onSelected?.call(name);
      if (result.party != null) widget.onPartySelected?.call(result.party!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final partiesAsync = ref.watch(partiesProvider);
    final allParties = partiesAsync.valueOrNull ?? [];
    // Apply type filter when provided
    final sourceParties = widget.filterTypes != null
        ? allParties.where((p) => widget.filterTypes!.contains(p.partyType)).toList()
        : allParties;

    // Build outstanding map from active credits and loans for subtitle hints.
    final credits = ref.watch(activeCreditsProvider).valueOrNull ?? [];
    final loans   = ref.watch(activeLoansProvider).valueOrNull ?? [];
    final outstandingMap = <String, double>{};
    for (final c in credits) {
      if (!c.isCleared) {
        final key = c.customerName.toLowerCase().trim();
        outstandingMap[key] = (outstandingMap[key] ?? 0) +
            (c.direction == CreditDirection.given
                ? c.pendingAmount
                : -c.pendingAmount);
      }
    }
    for (final l in loans) {
      if (!l.isCleared) {
        final key = l.lenderName.toLowerCase().trim();
        outstandingMap[key] = (outstandingMap[key] ?? 0) +
            (l.isLent ? l.pendingAmount : -l.pendingAmount);
      }
    }

    return Autocomplete<Party>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Party>.empty();
        }
        final query = textEditingValue.text.toLowerCase();
        return sourceParties.where((party) {
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
                  final key = party.name.toLowerCase().trim();
                  final outstanding = outstandingMap[key];
                  final hasBalance =
                      outstanding != null && outstanding.abs() > 0.01;
                  final balanceLabel = hasBalance
                      ? (outstanding >= 0
                          ? 'Owes ${CurrencyFormatter.format(outstanding)}'
                          : 'You owe ${CurrencyFormatter.format(-outstanding)}')
                      : null;
                  final kColors = Theme.of(context).extension<KashCubeColors>();
                  final balanceColor = hasBalance
                      ? (outstanding >= 0 ? kColors?.income : kColors?.expense)
                      : null;
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (party.phoneNumber != null)
                          Text(
                            '+91 ${party.phoneNumber}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        if (balanceLabel != null)
                          Text(
                            balanceLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: balanceColor,
                                    fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
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
  const _PartyPickerSheet({this.initial = '', this.filterTypes});
  final String initial;
  final List<PartyType>? filterTypes;

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
      case PartyType.staff:
        return colors.investment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<KashCubeColors>()!;
    final partiesAsync = ref.watch(partiesProvider);
    final allParties = partiesAsync.valueOrNull ?? [];
    // Apply type filter when provided
    final sourceParties = widget.filterTypes != null
        ? allParties.where((p) => widget.filterTypes!.contains(p.partyType)).toList()
        : allParties;

    // Filter by query
    final filtered = _query.isEmpty
        ? sourceParties
        : sourceParties
            .where((p) =>
                p.name.toLowerCase().contains(_query.toLowerCase()) ||
                (p.phoneNumber?.contains(_query) ?? false))
            .toList();

    // Show "Add new" row only when query is non-empty and no exact name match
    final hasExactMatch = sourceParties
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
                  // ── Pick from Contacts (hidden when type-filtered) ───
                  if (widget.filterTypes == null)
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
                        // Capture navigator + messenger before any async gap.
                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final proceed = await requestContactsPickerRationale(
                          context,
                          settingsRepository:
                              ref.read(settingsRepositoryProvider),
                        );
                        if (!proceed || !mounted) return;
                        final granted = await requestContactsRuntimePermission();
                        if (!granted || !mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Contacts permission denied. Enable it in '
                                'Settings to import contacts.',
                              ),
                            ),
                          );
                          return;
                        }
                        try {
                          final contact =
                              await FlutterContacts.openExternalPick();
                          if (contact == null || !mounted) return;
                          final name = contact.displayName.trim();
                          if (name.isNotEmpty) nav.pop((party: null, name: name));
                        } catch (_) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not open contacts on this device. '
                                'Type the name manually.',
                              ),
                            ),
                          );
                        }
                      },
                    ),

                  if (sourceParties.isNotEmpty || filtered.isNotEmpty)
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
                            ? Text('+91 ${party.phoneNumber!}')
                            : null,
                        trailing: _TypeBadge(
                            label: party.partyType.label, color: tc),
                        onTap: () => Navigator.pop(
                          context,
                          (party: party, name: null),
                        ),
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
                        if (mounted) nav.pop((party: null, name: name));
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
                      onTap: () => Navigator.pop(
                        context,
                        (party: null, name: _query.trim()),
                      ),
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
