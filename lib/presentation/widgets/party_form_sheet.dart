import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/contacts_helper.dart';
import '../../data/models/party.dart';
import '../providers/settings_provider.dart';

/// Unified add / edit party bottom sheet.
///
/// Pass [existing] to pre-fill the form for editing;
/// leave it null to open an empty add form.
/// [onSave] is called with the resulting [Party] — caller decides
/// whether to add or update in the repository.
class PartyFormSheet extends ConsumerStatefulWidget {
  const PartyFormSheet({
    super.key,
    this.existing,
    required this.onSave,
  });

  final Party? existing;
  final void Function(Party) onSave;

  @override
  ConsumerState<PartyFormSheet> createState() => _PartyFormSheetState();
}

class _PartyFormSheetState extends ConsumerState<PartyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _gstin;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _notes;
  late PartyType _type;
  late String _partyContext;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _phone = TextEditingController(text: p?.phoneNumber ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _gstin = TextEditingController(text: p?.gstin ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _state = TextEditingController(text: p?.state ?? '');
    _pincode = TextEditingController(text: p?.pincode ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _type = p?.partyType ?? PartyType.personal;
    _partyContext = p?.partyContext ?? 'personal';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle ───────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    isEdit ? 'Edit Contact' : 'Add Contact',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Pick from contacts ───────────────────────────────────
              OutlinedButton.icon(
                onPressed: _pickFromContacts,
                icon: const Icon(Icons.contacts_outlined, size: 18),
                label: const Text('Pick from Contacts'),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Type selector ────────────────────────────────────────
              Wrap(
                spacing: AppSpacing.sm,
                children: PartyType.values.map((t) {
                  return ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      if (t == PartyType.vendor || t == PartyType.customer) {
                        _partyContext = 'business';
                      } else if (t != PartyType.lender &&
                          t != PartyType.borrower) {
                        _partyContext = 'personal';
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Context toggle (lender / borrower only) ───────────────
              if (_type == PartyType.lender || _type == PartyType.borrower) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'personal',
                      label: Text('Personal'),
                      icon: Icon(Icons.person_outline),
                    ),
                    ButtonSegment(
                      value: 'business',
                      label: Text('Business'),
                      icon: Icon(Icons.business_outlined),
                    ),
                  ],
                  selected: {_partyContext},
                  onSelectionChanged: (v) =>
                      setState(() => _partyContext = v.first),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── Name ─────────────────────────────────────────────────
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g. Ajay Kumar',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Phone + Email ─────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '+91 ',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        if (v.length != 10) return 'Enter 10-digit number';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── GSTIN (business types only) ───────────────────────────
              if (_type != PartyType.personal) ...[
                TextFormField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 15,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (optional)',
                    hintText: '22AAAAA0000A1Z5',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // ── Street Address ────────────────────────────────────────
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Street Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── City + State + Pincode ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _state,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _pincode,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Pincode',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Notes ─────────────────────────────────────────────────
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Save ──────────────────────────────────────────────────
              FilledButton(
                onPressed: _save,
                child: Text(
                  isEdit
                      ? 'Save Changes'
                      : (_type == PartyType.lender ||
                              _type == PartyType.borrower)
                          ? 'Add ${_partyContext == 'business' ? 'Business' : 'Personal'} ${_type.label}'
                          : 'Add ${_type.label}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromContacts() async {
    try {
      final proceed = await requestContactsPickerRationale(
        context,
        settingsRepository: ref.read(settingsRepositoryProvider),
      );
      if (!proceed || !mounted) return;

      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      setState(() {
        if (contact.displayName.isNotEmpty) {
          _name.text = contact.displayName;
        }
        if (contact.phones.isNotEmpty) {
          final raw =
              contact.phones.first.number.replaceAll(RegExp(r'[^\d]'), '');
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
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      state: _state.text.trim().isEmpty ? null : _state.text.trim(),
      pincode: _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      partyType: _type,
      partyContext: _partyContext,
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
