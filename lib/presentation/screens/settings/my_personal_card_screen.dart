/// "My Personal Card" screen — lets the user set their own name, phone,
/// email, and social links, then view / share them as a vCard QR code.
/// All data stays in the local key-value settings table. No network calls.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/image_compressor.dart';
import 'package:world_countries/world_countries.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../../data/services/pincode_lookup_service.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/country_picker_field.dart';
import '../../widgets/indian_state_dropdown.dart';
import '../../widgets/vcard_qr_dialog.dart';

class MyPersonalCardScreen extends ConsumerStatefulWidget {
  const MyPersonalCardScreen({super.key});

  @override
  ConsumerState<MyPersonalCardScreen> createState() =>
      _MyPersonalCardScreenState();
}

class _MyPersonalCardScreenState extends ConsumerState<MyPersonalCardScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _website;
  late final TextEditingController _whatsapp;
  late final TextEditingController _linkedin;
  late final TextEditingController _instagram;

  String? _photoPath;
  bool _loading = true;
  bool _saving = false;
  WorldCountry? _selectedCountry; // null = India (default)
  String _dialCode = '91';
  bool _pincodeAutoFilled = false;

  @override
  void initState() {
    super.initState();
    _name      = TextEditingController();
    _phone     = TextEditingController();
    _email     = TextEditingController();
    _address   = TextEditingController();
    _city      = TextEditingController();
    _state     = TextEditingController();
    _pincode   = TextEditingController();
    _website   = TextEditingController();
    _whatsapp  = TextEditingController();
    _linkedin  = TextEditingController();
    _instagram = TextEditingController();
    PincodeLookupService.ensureLoaded();
    _pincode.addListener(_onPincodeChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _pincode.removeListener(_onPincodeChanged);
    for (final c in [
      _name, _phone, _email,
      _address, _city, _state, _pincode,
      _website, _whatsapp, _linkedin, _instagram,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPincodeChanged() {
    final pin = _pincode.text.trim();
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
      _state.text = result.state;
      _pincodeAutoFilled = true;
    });
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepositoryProvider);
    final vals = await Future.wait([
      repo.get(SettingsKeys.ownerName),
      repo.get(SettingsKeys.personalPhone),
      repo.get(SettingsKeys.personalEmail),
      repo.get(SettingsKeys.personalAddress),
      repo.get(SettingsKeys.personalCity),
      repo.get(SettingsKeys.personalState),
      repo.get(SettingsKeys.personalPincode),
      repo.get(SettingsKeys.personalWebsite),
      repo.get(SettingsKeys.personalWhatsapp),
      repo.get(SettingsKeys.personalLinkedin),
      repo.get(SettingsKeys.personalInstagram),
      repo.get(SettingsKeys.personalPhotoPath),
      repo.get(SettingsKeys.personalCountry),
      repo.get(SettingsKeys.personalDialCode),
    ]);
    if (!mounted) return;
    _name.text      = vals[0] ?? '';
    _phone.text     = vals[1] ?? '';
    _email.text     = vals[2] ?? '';
    _address.text   = vals[3] ?? '';
    _city.text      = vals[4] ?? '';
    _state.text     = vals[5] ?? '';
    _pincode.text   = vals[6] ?? '';
    _website.text   = vals[7] ?? '';
    _whatsapp.text  = vals[8] ?? '';
    _linkedin.text  = vals[9] ?? '';
    _instagram.text = vals[10] ?? '';
    _photoPath      = vals[11];
    if (vals[12] != null) _selectedCountry = countryByName(vals[12]);
    _dialCode = vals[13] ?? '91';
    setState(() => _loading = false);
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xfile != null) {
      final compressed = await compressPickedImage(xfile.path);
      if (mounted) setState(() => _photoPath = compressed);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await Future.wait([
        _saveOrRemove(repo, SettingsKeys.ownerName,          _name.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalPhone,      PhoneUtils.normalize(_phone.text) ?? ''),
        _saveOrRemove(repo, SettingsKeys.personalEmail,      _email.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalAddress,    _address.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalCity,       _city.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalState,      _state.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalPincode,    _pincode.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalCountry,    _selectedCountry?.name.common ?? ''),
        _saveOrRemove(repo, SettingsKeys.personalDialCode,   _selectedCountry != null ? _dialCode : ''),
        _saveOrRemove(repo, SettingsKeys.personalWebsite,    _website.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalWhatsapp,   _whatsapp.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalLinkedin,   _linkedin.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalInstagram,  _instagram.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalPhotoPath,  _photoPath ?? ''),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal card saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOrRemove(dynamic repo, String key, String value) {
    if (value.isEmpty) return repo.remove(key);
    return repo.set(key, value);
  }

  void _showQr() {
    final vcard = vCardFromPersonalSettings(
      name:      _name.text.trim().isEmpty ? null : _name.text.trim(),
      phone:     _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email:     _email.text.trim().isEmpty ? null : _email.text.trim(),
      address:   _address.text.trim().isEmpty ? null : _address.text.trim(),
      city:      _city.text.trim().isEmpty ? null : _city.text.trim(),
      state:     _state.text.trim().isEmpty ? null : _state.text.trim(),
      pincode:   _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      website:   _website.text.trim().isEmpty ? null : _website.text.trim(),
      whatsapp:  _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      linkedin:  _linkedin.text.trim().isEmpty ? null : _linkedin.text.trim(),
      instagram: _instagram.text.trim().isEmpty ? null : _instagram.text.trim(),
    );
    showVCardQrDialog(
      context,
      vcard: vcard,
      displayName: _name.text.trim().isEmpty ? 'My Card' : _name.text.trim(),
      subtitle: PhoneUtils.formatDisplay(_phone.text.trim(), dialCode: _dialCode) ?? _email.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Personal Card'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.qr_code_2_outlined),
              tooltip: 'Show QR',
              onPressed: _showQr,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base, AppSpacing.sm,
                    AppSpacing.base, AppSpacing.xxxl),
                children: [
                  // ── Info banner ────────────────────────────────────────────
                  _InfoBanner(),
                  const SizedBox(height: AppSpacing.base),

                  // ── Profile Photo ──────────────────────────────────────────
                  _PhotoPicker(
                    photoPath: _photoPath,
                    onPick: _pickPhoto,
                    onRemove: () => setState(() => _photoPath = null),
                  ),
                  const SizedBox(height: AppSpacing.base),

                  // ── Name ──────────────────────────────────────────────────
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Your Name *',
                      hintText: 'e.g. Arjun Kumar',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── Phone + Email (side by side) ───────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                            labelText: 'Phone',
                            hintText: '9876543210',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.phone_outlined),
                            prefixText: '+$_dialCode ',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── Street Address ─────────────────────────────────────────
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Street Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── City ──────────────────────────────────────────────────
                  TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── State + Pincode ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
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
                          decoration: InputDecoration(
                            labelText: 'Postcode',
                            border: const OutlineInputBorder(),
                            suffixIcon: _pincodeAutoFilled
                                ? const Icon(Icons.check_circle_outline,
                                    color: Colors.green, size: 18)
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── Country ────────────────────────────────────────────────
                  CountryPickerField(
                    selectedCountry: _selectedCountry,
                    onChanged: (country) {
                      setState(() {
                        _selectedCountry = country;
                        _dialCode = dialCodeFor(country);
                        if (country.name.common != 'India') _state.clear();
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── Online Presence (collapsible) ─────────────────────────
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: _website.text.isNotEmpty ||
                          _whatsapp.text.isNotEmpty ||
                          _linkedin.text.isNotEmpty ||
                          _instagram.text.isNotEmpty,
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

                  // ── Save + QR ──────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('Show QR'),
                          onPressed: _showQr,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ))
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save Card'),
                          onPressed: _saving ? null : _save,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Photo Picker ──────────────────────────────────────────────────────────────

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photoPath,
    required this.onPick,
    required this.onRemove,
  });
  final String? photoPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPhoto = photoPath != null && File(photoPath!).existsSync();

    return Row(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant, width: 1.5),
              image: hasPhoto
                  ? DecorationImage(
                      image: FileImage(File(photoPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: hasPhoto ? null : cs.surfaceContainerHighest,
            ),
            child: hasPhoto
                ? null
                : Icon(Icons.add_photo_alternate_outlined,
                    size: 32, color: cs.outline),
          ),
        ),
        const SizedBox(width: AppSpacing.base),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile Photo',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Shown in your QR card.',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: const Icon(Icons.image_outlined, size: 14),
                    label:
                        const Text('Choose', style: TextStyle(fontSize: 12)),
                    onPressed: onPick,
                  ),
                  if (hasPhoto)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor:
                              Theme.of(context).colorScheme.error),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('Remove',
                          style: TextStyle(fontSize: 12)),
                      onPressed: onRemove,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: cs.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Stored 100% on your device. Use the QR button to share your contact details.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
