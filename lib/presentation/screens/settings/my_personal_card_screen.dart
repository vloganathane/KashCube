/// "My Personal Card" screen — lets the user set their own name, phone,
/// email, and social links, then view / share them as a vCard QR code.
/// All data stays in the local key-value settings table. No network calls.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/utils/vcard_builder.dart';
import '../../providers/settings_provider.dart';
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
  late final TextEditingController _website;
  late final TextEditingController _whatsapp;
  late final TextEditingController _linkedin;
  late final TextEditingController _instagram;

  String? _photoPath;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name      = TextEditingController();
    _phone     = TextEditingController();
    _email     = TextEditingController();
    _website   = TextEditingController();
    _whatsapp  = TextEditingController();
    _linkedin  = TextEditingController();
    _instagram = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _phone, _email, _website, _whatsapp, _linkedin, _instagram
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepositoryProvider);
    final vals = await Future.wait([
      repo.get(SettingsKeys.ownerName),
      repo.get(SettingsKeys.personalPhone),
      repo.get(SettingsKeys.personalEmail),
      repo.get(SettingsKeys.personalWebsite),
      repo.get(SettingsKeys.personalWhatsapp),
      repo.get(SettingsKeys.personalLinkedin),
      repo.get(SettingsKeys.personalInstagram),
      repo.get(SettingsKeys.personalPhotoPath),
    ]);
    if (!mounted) return;
    _name.text      = vals[0] ?? '';
    _phone.text     = vals[1] ?? '';
    _email.text     = vals[2] ?? '';
    _website.text   = vals[3] ?? '';
    _whatsapp.text  = vals[4] ?? '';
    _linkedin.text  = vals[5] ?? '';
    _instagram.text = vals[6] ?? '';
    _photoPath      = vals[7];
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
        _saveOrRemove(repo, SettingsKeys.personalPhone,      _phone.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalEmail,      _email.text.trim()),
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
      website:   _website.text.trim().isEmpty ? null : _website.text.trim(),
      whatsapp:  _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      linkedin:  _linkedin.text.trim().isEmpty ? null : _linkedin.text.trim(),
      instagram: _instagram.text.trim().isEmpty ? null : _instagram.text.trim(),
    );
    showVCardQrDialog(
      context,
      vcard: vcard,
      displayName: _name.text.trim().isEmpty ? 'My Card' : _name.text.trim(),
      subtitle: _phone.text.trim().isEmpty ? _email.text.trim() : _phone.text.trim(),
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
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            hintText: '9876543210',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
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
