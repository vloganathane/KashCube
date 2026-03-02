import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../../data/models/party.dart';
import '../../providers/party_provider.dart';
import '../../widgets/party_form_sheet.dart';
import '../../widgets/vcard_qr_dialog.dart';
import '../search/search_screen.dart';
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
  PartyType? _typeFilter;


  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final partiesAsync = ref.watch(partiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen(initialFilter: SearchFilter.parties)),
            ),
          ),
        ],
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
                final filtered = all
                    .where((p) =>
                        _typeFilter == null || p.partyType == _typeFilter)
                    .toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasQuery: _typeFilter != null,
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
                        _confirmDelete(context, filtered[i]),                    onShareQr: () => showVCardQrDialog(
                      context,
                      vcard: vCardFromParty(filtered[i]),
                      displayName: filtered[i].name,
                      subtitle: filtered[i].phoneNumber ?? filtered[i].email,
                    ),                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Contact'),
      ),
    );
  }

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

  void _showAddEditSheet(BuildContext context, {Party? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PartyFormSheet(
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
    required this.onShareQr,
  });

  final Party party;
  final KashCubeColors colors;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShareQr;

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
              // Show Personal / Business context badge for lender & borrower
              if (party.partyType == PartyType.lender ||
                  party.partyType == PartyType.borrower) ...[                
                const SizedBox(width: AppSpacing.xs),
                _TypeBadge(
                  label: party.partyContext == 'business'
                      ? 'Business'
                      : 'Personal',
                  color: party.partyContext == 'business'
                      ? colors.expense.withValues(alpha: 0.7)
                      : colors.investment.withValues(alpha: 0.7),
                ),
              ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onShareQr,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Icon(
                Icons.qr_code_2_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
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
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('Share QR'),
              onTap: () {
                Navigator.pop(context);
                onShareQr();
              },
            ),
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
}

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
            hasQuery ? 'No contacts match' : 'No contacts yet',
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
              label: const Text('Add Contact'),
            ),
          ],
        ],
      ),
    );
  }
}
