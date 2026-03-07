import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/contacts_helper.dart';
import '../../core/utils/gstin_validator.dart';
import 'package:world_countries/world_countries.dart';

import '../../core/utils/phone_utils.dart';
import '../../core/utils/image_compressor.dart';
import '../../data/models/party.dart';
import '../../data/models/party_address.dart';
import '../../data/services/pincode_lookup_service.dart';
import '../providers/party_address_provider.dart';
import '../providers/settings_provider.dart';
import 'country_picker_field.dart';
import 'indian_state_dropdown.dart';
import 'qr_scanner_sheet.dart';

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
  late final TextEditingController _website;
  late final TextEditingController _whatsapp;
  late final TextEditingController _linkedin;
  late final TextEditingController _instagram;
  late PartyType _type;
  late String _partyContext;
  String? _businessCardImagePath;
  bool _onlineExpanded = false;
  WorldCountry? _selectedCountry; // null = India (default)
  String _dialCode = '91';
  bool _pincodeAutoFilled = false;

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
    _notes     = TextEditingController(text: p?.notes ?? '');
    _website   = TextEditingController(text: p?.website ?? '');
    _whatsapp  = TextEditingController(text: p?.whatsapp ?? '');
    _linkedin  = TextEditingController(text: p?.linkedin ?? '');
    _instagram = TextEditingController(text: p?.instagram ?? '');
    _type = p?.partyType ?? PartyType.personal;
    _partyContext = p?.partyContext ?? 'personal';
    _businessCardImagePath = p?.businessCardImagePath;
    // Country & dial code — load from existing party if set
    if (p?.country != null) {
      _selectedCountry = countryByName(p!.country);
    }
    _dialCode = p?.dialCode ?? '91';
    _onlineExpanded = (p?.website ?? '').isNotEmpty ||
        (p?.whatsapp ?? '').isNotEmpty ||
        (p?.linkedin ?? '').isNotEmpty ||
        (p?.instagram ?? '').isNotEmpty;
    // Warm up pincode lookup (India only) in the background
    PincodeLookupService.ensureLoaded();
    _pincode.addListener(_onPincodeChanged);
  }

  @override
  void dispose() {
    _pincode.removeListener(_onPincodeChanged);
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _notes.dispose();
    _website.dispose();
    _whatsapp.dispose();
    _linkedin.dispose();
    _instagram.dispose();
    super.dispose();
  }

  void _onPincodeChanged() {
    final pin = _pincode.text.trim();
    // Only auto-fill for India and exactly 6 digits
    final isIndia = _selectedCountry == null || _selectedCountry!.name.common == 'India';
    if (!isIndia || pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      if (_pincodeAutoFilled) setState(() => _pincodeAutoFilled = false);
      return;
    }
    final result = PincodeLookupService.lookup(pin);
    if (result == null) {
      if (_pincodeAutoFilled) setState(() => _pincodeAutoFilled = false);
      return;
    }
    setState(() {
      if (_city.text.isEmpty) _city.text = result.city;
      _state.text = result.state; // always sync state (drives GST)
      _pincodeAutoFilled = true;
    });
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

              // ── Pick from contacts / Scan QR ─────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromContacts,
                      icon: const Icon(Icons.contacts_outlined, size: 18),
                      label: const Text('Contacts'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
                      label: const Text('Scan QR'),
                    ),
                  ),
                ],
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
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone_outlined),
                        prefixText: '+$_dialCode ',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        // India requires exactly 10 digits; allow 7-15 for other countries
                        final isIndia = _selectedCountry == null ||
                            _selectedCountry!.name.common == 'India';
                        if (isIndia && v.length != 10) {
                          return 'Enter 10-digit number';
                        }
                        if (!isIndia && (v.length < 7 || v.length > 15)) {
                          return 'Enter a valid phone number';
                        }
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
                  validator: (v) => GstinValidator.validateWithState(
                    v,
                    selectedState: _state.text,
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

              // ── City ─────────────────────────────────────────────────
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── State + Pincode ───────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    // Show IndianStateDropdown only for India; plain text for other countries
                    child: (_selectedCountry == null ||
                            _selectedCountry!.name.common == 'India')
                        ? IndianStateDropdown(controller: _state)
                        : TextFormField(
                            controller: _state,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'State / Province',
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
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: 'Postcode',
                        border: const OutlineInputBorder(),
                        counterText: '',
                        suffixIcon: _pincodeAutoFilled
                            ? const Icon(Icons.check_circle_outline,
                                color: Colors.green, size: 18)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Country ───────────────────────────────────────────────
              CountryPickerField(
                selectedCountry: _selectedCountry,
                onChanged: (country) {
                  setState(() {
                    _selectedCountry = country;
                    _dialCode = dialCodeFor(country);
                    // Clear state field when switching away from India
                    if (country.name.common != 'India') {
                      _state.clear();
                    }
                  });
                },
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
              const SizedBox(height: AppSpacing.md),

              // ── Saved Addresses ───────────────────────────────────────
              if (widget.existing?.id != null)
                _PartyAddressesSection(
                  partyId: widget.existing!.id!,
                ),
              if (widget.existing?.id != null)
                const SizedBox(height: AppSpacing.sm),

              // ── Online Presence ───────────────────────────────────────
              Theme(
                data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _onlineExpanded,
                  leading: const Icon(Icons.language_outlined),
                  title: const Text('Online Presence'),
                  subtitle: const Text(
                    'Website, WhatsApp, LinkedIn, Instagram',
                    style: TextStyle(fontSize: 11),
                  ),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    TextFormField(
                      controller: _website,
                      decoration: const InputDecoration(
                        labelText: 'Website',
                        hintText: 'https://example.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language_outlined),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _whatsapp,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp Number',
                        hintText: '9876543210',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.chat_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _linkedin,
                      decoration: const InputDecoration(
                        labelText: 'LinkedIn',
                        hintText: 'linkedin.com/in/username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _instagram,
                      decoration: const InputDecoration(
                        labelText: 'Instagram',
                        hintText: '@username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Business Card ─────────────────────────────────────────
              _BusinessCardPicker(
                imagePath: _businessCardImagePath,
                onPick: _pickBusinessCard,
                onRemove: () => setState(() => _businessCardImagePath = null),
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

  Future<void> _pickBusinessCard() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null && mounted) {
      final compressed = await compressPickedImage(picked.path);
      setState(() => _businessCardImagePath = compressed);
    }
  }

  Future<void> _scanQr() async {
    final parsed = await showQrScannerSheet(context);
    if (parsed == null || !mounted) return;
    setState(() {
      if (parsed['name'] != null) _name.text = parsed['name']!;
      if (parsed['phone'] != null) {
        // Normalize phone using current dial code (strips leading country prefix)
        _phone.text = PhoneUtils.normalize(parsed['phone'], dialCode: _dialCode) ?? parsed['phone']!;
      }
      if (parsed['email'] != null) _email.text = parsed['email']!;
      if (parsed['address'] != null) _address.text = parsed['address']!;
      if (parsed['city'] != null) _city.text = parsed['city']!;
      if (parsed['state'] != null) _state.text = parsed['state']!;
      if (parsed['pincode'] != null) _pincode.text = parsed['pincode']!;
      if (parsed['gstin'] != null) _gstin.text = parsed['gstin']!;
      if (parsed['website'] != null) _website.text = parsed['website']!;
      if (parsed['whatsapp'] != null) _whatsapp.text = parsed['whatsapp']!;
      if (parsed['linkedin'] != null) _linkedin.text = parsed['linkedin']!;
      if (parsed['instagram'] != null) _instagram.text = parsed['instagram']!;
      // Auto-expand online presence if any social field was populated
      if ((parsed['website'] ?? '').isNotEmpty ||
          (parsed['whatsapp'] ?? '').isNotEmpty ||
          (parsed['linkedin'] ?? '').isNotEmpty ||
          (parsed['instagram'] ?? '').isNotEmpty) {
        _onlineExpanded = true;
      }
    });
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
      phoneNumber: PhoneUtils.normalize(_phone.text),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      state: _state.text.trim().isEmpty ? null : _state.text.trim(),
      pincode: _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      country: _selectedCountry?.name.common,
      dialCode: _selectedCountry != null ? _dialCode : null,
      partyType: _type,
      partyContext: _partyContext,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      website: _website.text.trim().isEmpty ? null : _website.text.trim(),
      whatsapp: _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      linkedin: _linkedin.text.trim().isEmpty ? null : _linkedin.text.trim(),
      instagram: _instagram.text.trim().isEmpty ? null : _instagram.text.trim(),
      businessCardImagePath: _businessCardImagePath,
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

// ── Party Addresses Section ───────────────────────────────────────────────────

class _PartyAddressesSection extends ConsumerStatefulWidget {
  const _PartyAddressesSection({required this.partyId});

  final int partyId;

  @override
  ConsumerState<_PartyAddressesSection> createState() =>
      _PartyAddressesSectionState();
}

class _PartyAddressesSectionState
    extends ConsumerState<_PartyAddressesSection> {
  Future<void> _showAddressDialog({PartyAddress? editing}) async {
    final labelCtrl =
        TextEditingController(text: editing?.label ?? '');
    final addrCtrl =
        TextEditingController(text: editing?.address ?? '');
    final cityCtrl =
        TextEditingController(text: editing?.city ?? '');
    final stateCtrl =
        TextEditingController(text: editing?.state ?? '');
    final pincodeCtrl =
        TextEditingController(text: editing?.pincode ?? '');
    final gstinCtrl =
        TextEditingController(text: editing?.gstin ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing == null ? 'Add Address' : 'Edit Address'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label *',
                  hintText: 'e.g. Head Office, Warehouse',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Street / Area',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: cityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: pincodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'PIN Code',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
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
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              if (label.isEmpty) return;
              final repo = ref.read(partyAddressRepositoryProvider);
              if (editing == null) {
                await repo.insert(PartyAddress(
                  partyId: widget.partyId,
                  label: label,
                  address: addrCtrl.text.trim().isEmpty
                      ? null
                      : addrCtrl.text.trim(),
                  city: cityCtrl.text.trim().isEmpty
                      ? null
                      : cityCtrl.text.trim(),
                  state: stateCtrl.text.trim().isEmpty
                      ? null
                      : stateCtrl.text.trim(),
                  pincode: pincodeCtrl.text.trim().isEmpty
                      ? null
                      : pincodeCtrl.text.trim(),
                  gstin: gstinCtrl.text.trim().isEmpty
                      ? null
                      : gstinCtrl.text.trim(),
                  createdAt: DateTime.now(),
                ));
              } else {
                await repo.update(editing.copyWith(
                  label: label,
                  address: addrCtrl.text.trim().isEmpty
                      ? null
                      : addrCtrl.text.trim(),
                  city: cityCtrl.text.trim().isEmpty
                      ? null
                      : cityCtrl.text.trim(),
                  state: stateCtrl.text.trim().isEmpty
                      ? null
                      : stateCtrl.text.trim(),
                  pincode: pincodeCtrl.text.trim().isEmpty
                      ? null
                      : pincodeCtrl.text.trim(),
                  gstin: gstinCtrl.text.trim().isEmpty
                      ? null
                      : gstinCtrl.text.trim(),
                ));
              }
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(partyAddressesProvider(widget.partyId));
            },
            child: Text(editing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    labelCtrl.dispose();
    addrCtrl.dispose();
    cityCtrl.dispose();
    stateCtrl.dispose();
    pincodeCtrl.dispose();
    gstinCtrl.dispose();
  }

  Future<void> _deleteAddress(PartyAddress addr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text('Delete "${addr.label}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(partyAddressRepositoryProvider).delete(addr.id!);
    ref.invalidate(partyAddressesProvider(widget.partyId));
  }

  @override
  Widget build(BuildContext context) {
    final asyncAddrs = ref.watch(partyAddressesProvider(widget.partyId));
    final cs = Theme.of(context).colorScheme;

    final addresses = asyncAddrs.valueOrNull ?? [];

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: const Icon(Icons.location_on_outlined),
        title: const Text('Saved Addresses'),
        subtitle: Text(
          addresses.isEmpty
              ? 'Add delivery / branch addresses'
              : '${addresses.length} address${addresses.length == 1 ? '' : 'es'}',
          style: const TextStyle(fontSize: 11),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        children: [
          ...addresses.map(
            (addr) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
              ),
              leading: Icon(
                addr.isDefault
                    ? Icons.home_outlined
                    : Icons.location_on_outlined,
                color: addr.isDefault ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Row(
                children: [
                  Expanded(child: Text(addr.label)),
                  if (addr.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Default',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                addr.displayLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!addr.isDefault)
                    IconButton(
                      icon: const Icon(Icons.star_outline, size: 20),
                      tooltip: 'Set as default',
                      onPressed: () async {
                        await ref
                            .read(partyAddressRepositoryProvider)
                            .setDefault(widget.partyId, addr.id!);
                        ref.invalidate(
                            partyAddressesProvider(widget.partyId));
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit',
                    onPressed: () => _showAddressDialog(editing: addr),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: cs.error),
                    tooltip: 'Delete',
                    onPressed: () => _deleteAddress(addr),
                  ),
                ],
              ),
            ),
          ),
          // ── Add Address button ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: TextButton.icon(
              onPressed: () => _showAddressDialog(),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Add Address'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

// ── Business Card Picker ──────────────────────────────────────────────────────

class _BusinessCardPicker extends StatelessWidget {
  const _BusinessCardPicker({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String? imagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.badge_outlined, size: 18, color: cs.outline),
            const SizedBox(width: 8),
            Text(
              'Business Card',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.outline),
            ),
            const Spacer(),
            if (imagePath != null)
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath!),
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (ctx, error, stack) => _placeholder(context, cs),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retake / Replace'),
          ),
        ] else
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(
                    color: cs.outlineVariant, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 32, color: cs.primary),
                  const SizedBox(height: 6),
                  Text('Tap to add business card',
                      style: TextStyle(color: cs.primary, fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(BuildContext context, ColorScheme cs) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: cs.error),
        ),
      );
}
