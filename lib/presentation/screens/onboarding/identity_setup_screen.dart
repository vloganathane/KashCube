import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/identity_repository_impl.dart';
import '../../../data/services/database_helper.dart';
import '../../../data/services/identity_service.dart';

/// Shown once on a fresh install (when `my_identity` table is empty).
///
/// Asks the user for a display name, generates the Ed25519 identity keypair,
/// and persists the `my_identity` row.  On completion, the caller should
/// navigate to [AppShell].
class IdentitySetupScreen extends ConsumerStatefulWidget {
  const IdentitySetupScreen({required this.onComplete, super.key});

  final VoidCallback onComplete;

  @override
  ConsumerState<IdentitySetupScreen> createState() =>
      _IdentitySetupScreenState();
}

class _IdentitySetupScreenState extends ConsumerState<IdentitySetupScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final name = _nameController.text.trim();
      await DatabaseHelper.instance.withDatabase(
        (db) => IdentityService.instance.ensureIdentityInitialized(
          db,
          displayName: name,
        ),
      );
      // Confirm the row was written (handles cases where keypair was loaded
      // from secure storage but row wasn't persisted yet).
      await IdentityRepositoryImpl().updateDisplayName(name);
      if (mounted) widget.onComplete();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Icon(
                  Icons.fingerprint_rounded,
                  size: 64,
                  color: cs.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'What\'s your name?',
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This name is stored locally and shown when sharing your identity QR.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'e.g. Ravi Kumar',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    if (v.trim().length > 60) {
                      return 'Name must be 60 characters or fewer';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Your identity stays on this device. Nothing is shared.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
