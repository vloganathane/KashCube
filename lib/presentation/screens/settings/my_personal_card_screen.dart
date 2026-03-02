/// "My Personal Card" screen — lets the user set their own name, phone,
/// email, and social links, then view / share them as a vCard QR code.
/// All data stays in the local key-value settings table. No network calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
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
    ]);
    if (!mounted) return;
    _name.text      = vals[0] ?? '';
    _phone.text     = vals[1] ?? '';
    _email.text     = vals[2] ?? '';
    _website.text   = vals[3] ?? '';
    _whatsapp.text  = vals[4] ?? '';
    _linkedin.text  = vals[5] ?? '';
    _instagram.text = vals[6] ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await Future.wait([
        _saveOrRemove(repo, SettingsKeys.ownerName,         _name.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalPhone,     _phone.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalEmail,     _email.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalWebsite,   _website.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalWhatsapp,  _whatsapp.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalLinkedin,  _linkedin.text.trim()),
        _saveOrRemove(repo, SettingsKeys.personalInstagram, _instagram.text.trim()),
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

                  // ── Basic Info ─────────────────────────────────────────────
                  _SectionHeader(title: 'Basic Info'),
                  const SizedBox(height: AppSpacing.sm),

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

                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: '9876543210',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Online Presence ─────────────────────────────────────────
                  _SectionHeader(title: 'Online Presence'),
                  const SizedBox(height: AppSpacing.sm),

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
                  const SizedBox(height: AppSpacing.xl),

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

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
    );
  }
}

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
