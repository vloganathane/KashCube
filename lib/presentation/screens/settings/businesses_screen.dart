import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/gstin_validator.dart';
import '../../../core/utils/image_compressor.dart';
import 'package:world_countries/world_countries.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../../data/models/business.dart';
import '../../../data/services/pincode_lookup_service.dart';
import '../../providers/business_provider.dart';
import '../../providers/web_sync_provider.dart';
import '../../widgets/country_picker_field.dart';
import '../../widgets/indian_state_dropdown.dart';
import '../../widgets/vcard_qr_dialog.dart';

class BusinessesScreen extends ConsumerWidget {
  const BusinessesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessesAsync = ref.watch(businessesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Profiles'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'businesses_fab',
        onPressed: () => _showForm(context, ref),
        tooltip: 'Add Business',
        child: const Icon(Icons.add),
      ),
      body: businessesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (businesses) => businesses.isEmpty
            ? _EmptyState(onAdd: () => _showForm(context, ref))
            : ListView.builder(
                padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    left: AppSpacing.base,
                    right: AppSpacing.base,
                    bottom: 80),
                itemCount: businesses.length,
                itemBuilder: (_, i) => _BusinessTile(
                  business: businesses[i],
                  onActivate: () => ref
                      .read(businessesProvider.notifier)
                      .activate(businesses[i].id!),
                  onEdit: () => _showForm(context, ref, business: businesses[i]),
                  onDelete: () =>
                      _confirmDelete(context, ref, businesses[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref,
      {Business? business}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BusinessFormSheet(
        business: business,
        onSave: (b, setActive) async {
          if (business == null) {
            await ref
                .read(businessesProvider.notifier)
                .add(b, setActive: setActive);
          } else {
            await ref.read(businessesProvider.notifier).edit(b);
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Business b) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text('Delete Business?'),
        content: Text(
            '"${b.name}" will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(businessesProvider.notifier).remove(b.id!);
    }
  }
}

// ── Business Tile ─────────────────────────────────────────────────────────────

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.business,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final Business business;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: business.isActive
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onActivate,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        leading: _LogoAvatar(logoPath: business.logoPath, name: business.name),
        title: Row(
          children: [
            Expanded(
              child: Text(
                business.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (business.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (business.formattedAddress.isNotEmpty)
              Text(business.formattedAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final p in (business.phones ?? (business.phone == null ? [] : [business.phone!])))
                  if (p.isNotEmpty)
                    _Badge(
                        icon: Icons.phone_outlined,
                        label: PhoneUtils.formatDisplay(p, dialCode: business.dialCode ?? '91') ?? p),
                if (business.gstNo != null && business.gstNo!.isNotEmpty)
                  _Badge(
                      icon: Icons.receipt_outlined,
                      label: 'GST: ${business.gstNo}'),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.qr_code_2_outlined),
              tooltip: 'Show QR',
              onPressed: () => showVCardQrDialog(
              context,
              vcard: vCardFromBusiness(business),
              displayName:
                (business.ownerName?.isNotEmpty ?? false)
                  ? business.ownerName!
                  : business.name,
              subtitle: PhoneUtils.formatDisplay(
                  (business.phones != null && business.phones!.isNotEmpty)
                    ? business.phones!.first
                    : business.phone,
                  dialCode: business.dialCode ?? '91') ?? business.email,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoAvatar extends StatelessWidget {
  const _LogoAvatar({required this.logoPath, required this.name});
  final String? logoPath;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && logoPath != null && File(logoPath!).existsSync()) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(logoPath!)),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor:
          Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'B',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11,
            color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

// ── Business Form Sheet ───────────────────────────────────────────────────────

class _BusinessFormSheet extends ConsumerStatefulWidget {
  const _BusinessFormSheet({this.business, required this.onSave});
  final Business? business;
  final Future<void> Function(Business, bool setActive) onSave;

  @override
  ConsumerState<_BusinessFormSheet> createState() => _BusinessFormSheetState();
}

class _BusinessFormSheetState extends ConsumerState<_BusinessFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _ownerName;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late List<TextEditingController> _phoneControllers;
  late final TextEditingController _email;
  late final TextEditingController _gst;
  late final TextEditingController _website;
  late final TextEditingController _whatsapp;
  late final TextEditingController _linkedin;
  late final TextEditingController _instagram;
  late final TextEditingController _upiId;
  String? _logoPath;
  String? _logoMediaId;
  bool _setActive = false;
  bool _saving = false;
  bool _onlineExpanded = false;
  WorldCountry? _selectedCountry; // null = India (default)
  String _dialCode = '91';
  bool _pincodeAutoFilled = false;

  @override
  void initState() {
    super.initState();
    final b = widget.business;
    _name      = TextEditingController(text: b?.name ?? '');
    _ownerName = TextEditingController(text: b?.ownerName ?? '');
    _address   = TextEditingController(text: b?.address ?? '');
    _city      = TextEditingController(text: b?.city ?? '');
    _state     = TextEditingController(text: b?.state ?? '');
    _pincode   = TextEditingController(text: b?.pincode ?? '');
    // Initialize dynamic phone controllers. Prefer `phones` list if present,
    // otherwise fall back to legacy `phone` column.
    final phoneList = <String>[];
    if (b?.phones != null && b!.phones!.isNotEmpty) {
      phoneList.addAll(b.phones!);
    } else if (b?.phone != null && b!.phone!.isNotEmpty) {
      phoneList.add(b.phone!);
    }
    if (phoneList.isEmpty) phoneList.add('');
    _phoneControllers = phoneList.map((p) => TextEditingController(text: p)).toList();
    _email     = TextEditingController(text: b?.email ?? '');
    _gst       = TextEditingController(text: b?.gstNo ?? '');
    _website   = TextEditingController(text: b?.website ?? '');
    _whatsapp  = TextEditingController(text: b?.whatsapp ?? '');
    _linkedin  = TextEditingController(text: b?.linkedin ?? '');
    _instagram = TextEditingController(text: b?.instagram ?? '');
    _upiId     = TextEditingController(text: b?.upiId ?? '');
    _logoPath = b?.logoPath;
    _logoMediaId = b?.logoMediaId;
    _setActive = b?.isActive ?? false;
    // Country & dial code — load from existing business if set
    if (b?.country != null) _selectedCountry = countryByName(b!.country);
    _dialCode = b?.dialCode ?? '91';
    // Expand online presence if any field is pre-populated
    _onlineExpanded = (b?.website ?? '').isNotEmpty ||
        (b?.whatsapp ?? '').isNotEmpty ||
        (b?.linkedin ?? '').isNotEmpty ||
        (b?.instagram ?? '').isNotEmpty;
    PincodeLookupService.ensureLoaded();
    _pincode.addListener(_onPincodeChanged);
  }

  @override
  void dispose() {
    _pincode.removeListener(_onPincodeChanged);
    for (final c in [
      _name, _ownerName, _address, _city, _state,
      _pincode, _email, _gst,
      _website, _whatsapp, _linkedin, _instagram, _upiId,
    ]) {
      c.dispose();
    }
    for (final pc in _phoneControllers) {
      pc.dispose();
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

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (xfile != null) {
      if (kIsWeb) {
        try {
          final bytes = await xfile.readAsBytes();
          final mediaId = await ref.read(webSyncProvider.notifier).uploadMediaBytes(
                bytes: bytes,
                fileName: xfile.name,
                mimeType: xfile.mimeType ?? 'image/jpeg',
              );
          if (mediaId == null) {
            throw Exception('No active web-companion session for media upload');
          }
          setState(() {
            _logoMediaId = mediaId;
            _logoPath = null;
          });
          return;
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logo upload failed: $e')),
          );
          return;
        }
      }

      final compressed = await compressPickedImage(xfile);
      setState(() {
        _logoPath = compressed;
        _logoMediaId = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    String? nullIfEmpty(TextEditingController c) {
      final s = c.text.trim();
      return s.isEmpty ? null : s;
    }

    final business = Business(
      id: widget.business?.id,
      name: _name.text.trim(),
      ownerName: nullIfEmpty(_ownerName),
      address: nullIfEmpty(_address),
      city: nullIfEmpty(_city),
      state: nullIfEmpty(_state),
      pincode: nullIfEmpty(_pincode),
      country: _selectedCountry?.name.common,
      dialCode: _selectedCountry != null ? _dialCode : null,
      // Collect phones from controllers. First non-empty is primary.
      phones: (() {
        final parts = _phoneControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
        if (parts.isEmpty) return null;
        return parts.map((p) => PhoneUtils.normalize(p, dialCode: _dialCode) ?? p).toList();
      })(),
      phone: (() {
        final first = _phoneControllers.map((c) => c.text.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');
        return first.isEmpty ? null : PhoneUtils.normalize(first, dialCode: _dialCode);
      })(),
      email: nullIfEmpty(_email),
      gstNo: nullIfEmpty(_gst)?.toUpperCase(),
      logoPath: _logoPath,
      logoMediaId: _logoMediaId,
      website: nullIfEmpty(_website),
      whatsapp: nullIfEmpty(_whatsapp),
      linkedin: nullIfEmpty(_linkedin),
      instagram: nullIfEmpty(_instagram),
      upiId: nullIfEmpty(_upiId),
      isActive: _setActive,
      createdAt: widget.business?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.onSave(business, _setActive && widget.business == null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.business != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.base),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? 'Edit Business' : 'New Business Profile',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.base),

              // Logo picker
              _LogoPicker(
                logoPath: _logoPath,
                onPick: _pickLogo,
                onRemove: () => setState(() {
                  _logoPath = null;
                  _logoMediaId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.base),

              // Business Name
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Business Name *',
                  hintText: 'e.g. Kash Cube Enterprises',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),

              // Owner / Contact Name
              TextFormField(
                controller: _ownerName,
                decoration: const InputDecoration(
                  labelText: 'Owner / Contact Name',
                  hintText: 'e.g. Arjun Kumar',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.sm),

              // GST
              TextFormField(
                controller: _gst,
                decoration: const InputDecoration(
                  labelText: 'GST Number',
                  hintText: '22AAAAA0000A1Z5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: GstinValidator.validate,
              ),
              const SizedBox(height: AppSpacing.sm),

              // UPI ID (used to generate a payment QR code on invoices)
              TextFormField(
                controller: _upiId,
                decoration: const InputDecoration(
                  labelText: 'UPI ID (payment QR on invoices)',
                  hintText: 'yourname@upi',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.sm),

              // Phone(s)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _phoneControllers.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneControllers[i],
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: i == 0 ? 'Phone (primary)' : 'Additional phone',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.phone_outlined),
                                prefixText: '+$_dialCode ',
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          if (i > 0) ...[
                            const SizedBox(width: AppSpacing.sm),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Remove',
                              onPressed: () {
                                setState(() {
                                  final c = _phoneControllers.removeAt(i);
                                  c.dispose();
                                });
                              },
                            ),
                          ]
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add phone'),
                      onPressed: () {
                        setState(() {
                          _phoneControllers.add(TextEditingController());
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Email
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Address
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

              // City
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.sm),

              // State + Pincode
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

              // Country
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

              // Online Presence (collapsible)
              const SizedBox(height: AppSpacing.sm),
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
                        hintText: 'linkedin.com/company/name',
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
                        hintText: '@handle',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Set as active toggle (only for new business or inactive one)
              if (widget.business == null || !widget.business!.isActive)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set as active business'),
                  subtitle:
                      const Text('Use for all new invoices & quotes'),
                  value: _setActive,
                  onChanged: (v) => setState(() => _setActive = v),
                ),
              const SizedBox(height: AppSpacing.base),

              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Save Changes' : 'Add Business'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logo Picker ───────────────────────────────────────────────────────────────

class _LogoPicker extends StatelessWidget {
  const _LogoPicker(
      {required this.logoPath,
      required this.onPick,
      required this.onRemove});
  final String? logoPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasLogo = !kIsWeb && logoPath != null && File(logoPath!).existsSync();

    return Row(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              image: hasLogo
                  ? DecorationImage(
                      image: FileImage(File(logoPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: hasLogo ? null : cs.surfaceContainerHighest,
            ),
            child: hasLogo
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
              Text('Business Logo',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Appears on invoices and quotes.',
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
                    label: const Text('Choose', style: TextStyle(fontSize: 12)),
                    onPressed: onPick,
                  ),
                  if (hasLogo)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor:
                              Theme.of(context).colorScheme.error),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('Remove', style: TextStyle(fontSize: 12)),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.base),
            Text('No business profiles yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add your business details to print them on invoices & quotes.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Business'),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
