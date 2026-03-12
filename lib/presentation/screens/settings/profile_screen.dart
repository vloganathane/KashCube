import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/identity_repository_impl.dart';
import '../../../data/services/identity_service.dart';
import '../../providers/identity_provider.dart';

/// Settings → My Identity
///
/// Shows the user's display name, identity QR, and public key fingerprint.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _showQr = false;
  bool _editingName = false;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await IdentityRepositoryImpl().updateDisplayName(trimmed);
    ref.invalidate(myIdentityProvider);
    if (mounted) setState(() => _editingName = false);
  }

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(myIdentityProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Identity')),
      body: identityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (identity) {
          if (identity == null) {
            return const Center(child: Text('Identity not set up'));
          }

          final fingerprint = identity.publicKey.length >= 8
              ? identity.publicKey.substring(identity.publicKey.length - 8)
              : identity.publicKey;

          String? qrPayload;
          try {
            qrPayload = IdentityService.instance.identityQrPayload();
          } catch (_) {
            // identity not yet loaded in memory
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Avatar + Name ──────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          identity.displayName.isNotEmpty
                              ? identity.displayName[0].toUpperCase()
                              : '?',
                          style: tt.headlineLarge?.copyWith(
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_editingName) ...[
                        TextField(
                          controller: _nameController
                            ..text = identity.displayName,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            border: OutlineInputBorder(),
                          ),
                          autofocus: true,
                          onSubmitted: _saveName,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _editingName = false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () =>
                                  _saveName(_nameController.text),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          identity.displayName,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _editingName = true),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit name'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Identity details ────────────────────────────────────────
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Identity ID'),
                      subtitle: Text(
                        identity.identityId,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        tooltip: 'Copy',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: identity.identityId),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Identity ID copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('Public key fingerprint'),
                      subtitle: Text(
                        '…$fingerprint',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        tooltip: 'Copy full key',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: identity.publicKey),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Public key copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Identity QR ─────────────────────────────────────────────
              if (qrPayload != null)
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.qr_code_outlined),
                        title: const Text('My Identity QR'),
                        subtitle: const Text(
                          'Scan this on another device to link your identity',
                        ),
                        trailing: TextButton(
                          onPressed: () =>
                              setState(() => _showQr = !_showQr),
                          child: Text(_showQr ? 'Hide' : 'Show QR'),
                        ),
                      ),
                      if (_showQr) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_outlined,
                                    size: 80,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'QR display available\nin Phase D2',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // ── Privacy note ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your private key is stored only on this device and is never transmitted.',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
