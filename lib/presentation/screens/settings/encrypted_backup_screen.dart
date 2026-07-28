import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/encrypted_backup_service.dart';

/// Screen for creating and restoring AES-256-GCM encrypted `.kashcube` backups.
///
/// Export tab: enter passphrase → encrypt → share via OS sheet.
/// Import tab: pick file → enter passphrase → decrypt → restore.
///
/// All crypto is local — no network calls.
class EncryptedBackupScreen extends StatefulWidget {
  const EncryptedBackupScreen({super.key});

  @override
  State<EncryptedBackupScreen> createState() => _EncryptedBackupScreenState();
}

class _EncryptedBackupScreenState extends State<EncryptedBackupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypted Backup'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Export'),
            Tab(text: 'Import & Restore'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ExportTab(), _ImportTab()],
      ),
    );
  }
}

// ── Export Tab ────────────────────────────────────────────────────────────────

class _ExportTab extends StatefulWidget {
  const _ExportTab();

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _exporting = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _exporting = true);
    try {
      final file = await EncryptedBackupService.instance.exportEncrypted(
        _passCtrl.text.trim(),
      );

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Kash Cube Encrypted Backup',
        text: 'My Kash Cube encrypted backup file.',
      );

      if (mounted) {
        context.showSnackBar('Backup exported — keep your passphrase safe!');
        _passCtrl.clear();
        _confirmCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Export failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.security_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'AES-256-GCM Encrypted',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your Kash Cube data is encrypted with your passphrase before export. '
                      'The file cannot be read without it — not even by us. '
                      'Store your passphrase safely.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Passphrase',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Enter a strong passphrase',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a passphrase';
                }
                if (v.trim().length < 8) {
                  return 'Passphrase must be at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.base),

            Text(
              'Confirm passphrase',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _exporting ? null : _export(),
              decoration: InputDecoration(
                hintText: 'Re-enter your passphrase',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v != _passCtrl.text) return 'Passphrases do not match';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outlined),
                label: Text(_exporting ? 'Encrypting…' : 'Encrypt & Export'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

// ── Import Tab ────────────────────────────────────────────────────────────────

class _ImportTab extends StatefulWidget {
  const _ImportTab();

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _importing = false;
  String? _selectedPath;
  String? _selectedName;
  int? _attemptsRemaining;
  bool _lockedOut = false;
  int _lockoutMins = 0;

  @override
  void initState() {
    super.initState();
    _refreshLockStatus();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLockStatus() async {
    final locked = await EncryptedBackupService.instance.isLockedOut();
    final attempts = await EncryptedBackupService.instance.attemptsRemaining();
    final mins = await EncryptedBackupService.instance
        .lockoutMinutesRemaining();
    if (mounted) {
      setState(() {
        _lockedOut = locked;
        _attemptsRemaining = attempts;
        _lockoutMins = mins;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowedExtensions: null,
    );
    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.first;
      if (picked.path != null) {
        setState(() {
          _selectedPath = picked.path;
          _selectedName = picked.name;
        });
      }
    }
  }

  Future<void> _import() async {
    if (_selectedPath == null) {
      context.showSnackBar(
        'Please select a .kashcube file first',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await _showConfirmDialog();
    if (!confirmed) return;

    setState(() => _importing = true);
    try {
      final manifest = await EncryptedBackupService.instance.importEncrypted(
        _selectedPath!,
        _passCtrl.text.trim(),
      );

      if (!mounted) return;

      final createdAt = manifest['created_at'] as String? ?? 'unknown';
      final version = manifest['app_version'] as String? ?? '?';
      await _showSuccessDialog(createdAt, version);
    } on BackupLockoutException catch (e) {
      await _refreshLockStatus();
      if (mounted) context.showSnackBar(e.toString(), isError: true);
    } on BackupAuthException {
      await _refreshLockStatus();
      final rem = await EncryptedBackupService.instance.attemptsRemaining();
      if (!mounted) return;
      context.showSnackBar(
        'Incorrect passphrase. $rem attempt${rem == 1 ? '' : 's'} remaining.',
        isError: true,
      );
    } on BackupFormatException catch (e) {
      if (mounted) context.showSnackBar(e.toString(), isError: true);
    } catch (e) {
      if (mounted) context.showSnackBar('Restore failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Backup?'),
            content: const Text(
              'This will replace all current data with the backup. '
              'A pre-restore snapshot will be saved to kash_cube_before_restore.db '
              'in case you need to undo.\n\nAre you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showSuccessDialog(String createdAt, String version) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup date: $createdAt'),
            Text('App version: $version'),
            const SizedBox(height: AppSpacing.base),
            const Text(
              'Please restart the app to complete the restore.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Pop back to settings — user restarts manually
              Navigator.of(context).pop();
            },
            child: const Text('OK, close app'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lockout warning
            if (_lockedOut) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outlined),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Too many failed attempts. '
                          'Locked for $_lockoutMins more minute${_lockoutMins == 1 ? '' : 's'}.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
            ],

            // File picker
            Text(
              'Backup file',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _selectedName ?? 'Tap to choose .kashcube file',
                        style: _selectedName == null
                            ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              )
                            : null,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_selectedName != null)
                      Icon(
                        Icons.check_circle_outline,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),

            // Passphrase
            Text(
              'Passphrase',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              enabled: !_lockedOut,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) =>
                  (_importing || _lockedOut) ? null : _import(),
              decoration: InputDecoration(
                hintText: 'Enter your backup passphrase',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            if (!_lockedOut &&
                _attemptsRemaining != null &&
                _attemptsRemaining! < _maxAttempts) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$_attemptsRemaining attempt${_attemptsRemaining == 1 ? '' : 's'} remaining before lockout',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_importing || _lockedOut) ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.restore_outlined),
                label: Text(_importing ? 'Decrypting…' : 'Decrypt & Restore'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

const _maxAttempts = 5; // mirrors service constant for display only

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Text(
      '🔒 All encryption is performed on your device. '
      'No data is sent to any server. '
      'Your passphrase is never stored.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
