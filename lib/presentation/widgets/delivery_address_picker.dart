import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../data/models/party_address.dart';
import '../providers/party_address_provider.dart';
import 'indian_state_dropdown.dart';

/// Reusable bottom sheet that lets the user pick a delivery address for a
/// Delivery Challan or Invoice.
///
/// Three groups are presented:
///   1. "No delivery address" — clears the snapshot (calls [onSelected] with
///      `null`).
///   2. Party's saved [PartyAddress] list — auto-populated from DB.
///   3. "Enter custom address…" — opens an inline form for ad-hoc entry.
///
/// The sheet calls [onSelected] with a [PartyAddress?]:
///   - `null`            → no delivery address
///   - address with `id` → a saved party address was chosen
///   - address without `id` → custom ad-hoc entry (snapshot only, not persisted)
Future<void> showDeliveryAddressPicker({
  required BuildContext context,
  required int? partyId,
  required PartyAddress? current,
  required void Function(PartyAddress? address) onSelected,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetCtx) => _DeliveryAddressPicker(
      partyId: partyId,
      current: current,
      onSelected: onSelected,
    ),
  );
}

// ── Private sheet widget ──────────────────────────────────────────────────────

class _DeliveryAddressPicker extends ConsumerStatefulWidget {
  const _DeliveryAddressPicker({
    required this.partyId,
    required this.current,
    required this.onSelected,
  });

  final int? partyId;
  final PartyAddress? current;
  final void Function(PartyAddress? address) onSelected;

  @override
  ConsumerState<_DeliveryAddressPicker> createState() =>
      _DeliveryAddressPickerState();
}

class _DeliveryAddressPickerState
    extends ConsumerState<_DeliveryAddressPicker> {
  /// Whether to show the inline custom address form.
  bool _showCustomForm = false;

  // Custom address form controllers
  final _labelCtrl = TextEditingController(text: 'Delivery Site');
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _gstinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // ── Drag handle ────────────────────────────────────────────────
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Delivery Address',
                    style: tt.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Scrollable content ──────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm,
              ),
              children: [
                // ── Option: None ──────────────────────────────────────────
                _AddressTile(
                  icon: Icons.location_off_outlined,
                  label: 'No delivery address',
                  sublabel: 'Leave delivery address blank',
                  isSelected: widget.current == null && !_showCustomForm,
                  onTap: () {
                    widget.onSelected(null);
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: AppSpacing.xs),

                // ── Saved addresses ───────────────────────────────────────
                if (widget.partyId != null) ...[
                  _SavedAddressList(
                    partyId: widget.partyId!,
                    current: widget.current,
                    onSelected: (addr) {
                      widget.onSelected(addr);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],

                // ── Option: Custom ────────────────────────────────────────
                _AddressTile(
                  icon: Icons.edit_location_alt_outlined,
                  label: 'Enter custom address…',
                  sublabel: 'One-time address, not saved to party',
                  isSelected: _showCustomForm,
                  onTap: () => setState(() => _showCustomForm = !_showCustomForm),
                ),

                // ── Custom address form ───────────────────────────────────
                if (_showCustomForm) ...[
                  const SizedBox(height: AppSpacing.md),
                  _CustomAddressForm(
                    labelCtrl: _labelCtrl,
                    addressCtrl: _addressCtrl,
                    cityCtrl: _cityCtrl,
                    stateCtrl: _stateCtrl,
                    pincodeCtrl: _pincodeCtrl,
                    gstinCtrl: _gstinCtrl,
                    onConfirm: () {
                      final addr = PartyAddress(
                        partyId: widget.partyId ?? 0,
                        label: _labelCtrl.text.trim().isEmpty
                            ? 'Custom'
                            : _labelCtrl.text.trim(),
                        address: _addressCtrl.text.trim().isEmpty
                            ? null
                            : _addressCtrl.text.trim(),
                        city: _cityCtrl.text.trim().isEmpty
                            ? null
                            : _cityCtrl.text.trim(),
                        state: _stateCtrl.text.trim().isEmpty
                            ? null
                            : _stateCtrl.text.trim(),
                        pincode: _pincodeCtrl.text.trim().isEmpty
                            ? null
                            : _pincodeCtrl.text.trim(),
                        gstin: _gstinCtrl.text.trim().isEmpty
                            ? null
                            : _gstinCtrl.text.trim(),
                        createdAt: DateTime.now(),
                      );
                      widget.onSelected(addr);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Saved-addresses sub-widget ────────────────────────────────────────────────

class _SavedAddressList extends ConsumerWidget {
  const _SavedAddressList({
    required this.partyId,
    required this.current,
    required this.onSelected,
  });

  final int partyId;
  final PartyAddress? current;
  final void Function(PartyAddress) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAddrs = ref.watch(partyAddressesProvider(partyId));

    return asyncAddrs.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: CircularProgressIndicator.adaptive(),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (addresses) {
        if (addresses.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                'Saved addresses',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
            ...addresses.map(
              (addr) => _AddressTile(
                icon: addr.isDefault
                    ? Icons.home_outlined
                    : Icons.location_on_outlined,
                label: addr.label,
                sublabel: addr.displayLine,
                isSelected: current?.id == addr.id,
                onTap: () => onSelected(addr),
                trailing: addr.isDefault
                    ? Chip(
                        label: const Text('Default'),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon,
            color: isSelected ? cs.primary : cs.onSurfaceVariant),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? cs.primary : null,
            fontWeight: isSelected ? FontWeight.w600 : null,
          ),
        ),
        subtitle: sublabel != null && sublabel!.isNotEmpty
            ? Text(sublabel!, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: isSelected
            ? Icon(Icons.check_circle, color: cs.primary)
            : trailing,
        onTap: onTap,
      ),
    );
  }
}

// ── Custom address form ───────────────────────────────────────────────────────

class _CustomAddressForm extends StatelessWidget {
  const _CustomAddressForm({
    required this.labelCtrl,
    required this.addressCtrl,
    required this.cityCtrl,
    required this.stateCtrl,
    required this.pincodeCtrl,
    required this.gstinCtrl,
    required this.onConfirm,
  });

  final TextEditingController labelCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController stateCtrl;
  final TextEditingController pincodeCtrl;
  final TextEditingController gstinCtrl;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: labelCtrl,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'e.g. Site Office, Warehouse',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: addressCtrl,
            decoration:
                const InputDecoration(labelText: 'Street / Area'),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(labelText: 'City'),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: pincodeCtrl,
                  decoration: const InputDecoration(labelText: 'PIN Code'),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          IndianStateDropdown(controller: stateCtrl),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: gstinCtrl,
            decoration: const InputDecoration(
              labelText: 'GSTIN (optional)',
              hintText: 'Location-specific GSTIN',
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check),
            label: const Text('Use This Address'),
          ),
        ],
      ),
    );
  }
}
