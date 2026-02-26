import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../data/models/party.dart';
import '../../providers/party_provider.dart';
import 'party_detail_screen.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _searchController = TextEditingController();
  PartyType? _typeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final partiesAsync = ref.watch(partiesProvider);
    final query = ref.watch(partySearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parties'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, 0, AppSpacing.base, AppSpacing.sm),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by name or phone…',
              leading: const Icon(Icons.search, size: 20),
              trailing: query.isNotEmpty
                  ? [
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(partySearchQueryProvider.notifier)
                              .state = '';
                        },
                        icon: const Icon(Icons.close, size: 18),
                      )
                    ]
                  : null,
              onChanged: (v) =>
                  ref.read(partySearchQueryProvider.notifier).state = v,
              elevation: const WidgetStatePropertyAll(0),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Type filter chips ────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.xs),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                ),
                for (final type in PartyType.values)
                  _FilterChip(
                    label: type.label,
                    selected: _typeFilter == type,
                    color: _typeColor(type, colors),
                    onTap: () =>
                        setState(() => _typeFilter = type),
                  ),
              ].map((w) => Padding(
                    padding:
                        const EdgeInsets.only(right: AppSpacing.sm),
                    child: w,
                  )).toList(),
            ),
          ),

          // ── Party list ───────────────────────────────────────────────────
          Expanded(
            child: partiesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final filtered = all.where((p) {
                  final matchesType =
                      _typeFilter == null || p.partyType == _typeFilter;
                  final q = query.toLowerCase();
                  final matchesQuery = q.isEmpty ||
                      p.name.toLowerCase().contains(q) ||
                      (p.phoneNumber?.contains(q) ?? false);
                  return matchesType && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasQuery: query.isNotEmpty || _typeFilter != null,
                    onAdd: () => _showAddEditSheet(context),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(
                      bottom: AppSpacing.xxxl + AppSpacing.xl),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _PartyTile(
                    party: filtered[i],
                    colors: colors,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PartyDetailScreen(party: filtered[i]),
                      ),
                    ).then((_) => ref.read(partiesProvider.notifier).load()),
                    onEdit: () => _showAddEditSheet(context,
                        existing: filtered[i]),
                    onDelete: () =>
                        _confirmDelete(context, filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Party'),
      ),
    );
  }

  Color _typeColor(PartyType type, KashCubeColors colors) {
    switch (type) {
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

  void _showAddEditSheet(BuildContext context, {Party? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEditPartySheet(
        existing: existing,
        onSave: (party) {
          if (existing == null) {
            ref.read(partiesProvider.notifier).add(party);
          } else {
            ref.read(partiesProvider.notifier).update(party);
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, Party party) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove party?'),
        content: Text(
            '"${party.name}" will be removed. Existing transactions are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              if (party.id != null) {
                ref.read(partiesProvider.notifier).remove(party.id!);
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Party tile
// ---------------------------------------------------------------------------

class _PartyTile extends StatelessWidget {
  const _PartyTile({
    required this.party,
    required this.colors,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Party party;
  final KashCubeColors colors;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final netBalance = party.totalCreditGiven - party.totalCreditReceived;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor:
            _typeColor(party.partyType, colors).withValues(alpha: 0.15),
        child: Text(
          party.name.isNotEmpty ? party.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _typeColor(party.partyType, colors),
          ),
        ),
      ),
      title: Text(party.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeBadge(
                  label: party.partyType.label,
                  color: _typeColor(party.partyType, colors)),
              if (party.phoneNumber != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.phone_outlined,
                    size: 12,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 2),
                Text(party.phoneNumber!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (netBalance != 0) ...[
            Text(
              netBalance > 0
                  ? '+₹${_fmt(netBalance)}'
                  : '-₹${_fmt(netBalance.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: netBalance > 0 ? colors.income : colors.expense,
              ),
            ),
            Text('net',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                        color:
                            Theme.of(context).colorScheme.outline)),
          ],
        ],
      ),
      onLongPress: () => _showContextMenu(context),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Remove',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(PartyType type, KashCubeColors colors) {
    switch (type) {
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
}

// ---------------------------------------------------------------------------
// Add / Edit bottom sheet
// ---------------------------------------------------------------------------

class _AddEditPartySheet extends ConsumerStatefulWidget {
  const _AddEditPartySheet({this.existing, required this.onSave});

  final Party? existing;
  final void Function(Party) onSave;

  @override
  ConsumerState<_AddEditPartySheet> createState() =>
      _AddEditPartySheetState();
}

class _AddEditPartySheetState extends ConsumerState<_AddEditPartySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _gstin;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late PartyType _type;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _phone = TextEditingController(text: p?.phoneNumber ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _gstin = TextEditingController(text: p?.gstin ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _type = p?.partyType ?? PartyType.customer;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Text(isEdit ? 'Edit Party' : 'Add Party',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Pick from contacts ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickFromContacts,
                icon: const Icon(Icons.contacts_outlined, size: 18),
                label: const Text('Pick from Contacts'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Type selector ────────────────────────────────────────────
            Wrap(
              spacing: AppSpacing.sm,
              children: PartyType.values.map((t) {
                final selected = _type == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Name ─────────────────────────────────────────────────────
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name *',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Phone ─────────────────────────────────────────────────────
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '10-digit mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
                prefixText: '+91 ',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (v.length != 10) return 'Enter 10-digit number';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Email ─────────────────────────────────────────────────────
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── GSTIN ─────────────────────────────────────────────────────
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: const InputDecoration(
                labelText: 'GSTIN (optional)',
                hintText: '22AAAAA0000A1Z5',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Address ────────────────────────────────────────────────────────────
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Save ──────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(isEdit ? 'Save Changes' : 'Add ${_type.label}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromContacts() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      setState(() {
        if (contact.displayName.isNotEmpty) {
          _name.text = contact.displayName;
        }
        if (contact.phones.isNotEmpty) {
          final raw = contact.phones.first.number
              .replaceAll(RegExp(r'[^\d]'), '');
          // Strip leading country code: +91 / 91 prefix
          final phone = raw.length == 12 && raw.startsWith('91')
              ? raw.substring(2)
              : raw.length > 10
                  ? raw.substring(raw.length - 10)
                  : raw;
          _phone.text = phone;
        }
        if (contact.emails.isNotEmpty) {
          _email.text = contact.emails.first.address;
        }
      });
    } catch (_) {
      // User cancelled or permission denied — silently ignore
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final party = Party(
      id: existing?.id,
      name: _name.text.trim(),
      phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      partyType: _type,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      totalTransactions: existing?.totalTransactions ?? 0,
      totalTransactionAmount: existing?.totalTransactionAmount ?? 0,
      totalCreditGiven: existing?.totalCreditGiven ?? 0,
      totalCreditReceived: existing?.totalCreditReceived ?? 0,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );
    widget.onSave(party);
    Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: (color ?? Theme.of(context).colorScheme.primary)
          .withValues(alpha: 0.2),
      checkmarkColor: color ?? Theme.of(context).colorScheme.primary,
      side: BorderSide(
        color: selected
            ? (color ?? Theme.of(context).colorScheme.primary)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery, required this.onAdd});

  final bool hasQuery;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasQuery ? 'No parties match' : 'No parties yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!hasQuery)
            Text(
              'Add customers, vendors, or lenders\nto track your financial relationships.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!hasQuery) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add Party'),
            ),
          ],
        ],
      ),
    );
  }
}
