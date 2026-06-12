import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sms_provider.dart';

/// Onboarding screen explaining why Kash Cube needs SMS access.
///
/// Shown when the user first enables "Auto-detect SMS transactions" and the
/// OS permission has not yet been granted.  All processing is local — no SMS
/// data ever leaves the device.
class SmsPermissionScreen extends ConsumerStatefulWidget {
  const SmsPermissionScreen({super.key});

  @override
  ConsumerState<SmsPermissionScreen> createState() =>
      _SmsPermissionScreenState();
}

class _SmsPermissionScreenState extends ConsumerState<SmsPermissionScreen> {
  bool _requesting = false;

  Future<void> _grantPermission() async {
    setState(() => _requesting = true);

    final smsService = ref.read(smsServiceProvider);
    final granted = await smsService.requestPermission();

    if (!mounted) return;
    setState(() => _requesting = false);

    if (granted) {
      // Enable the provider so the SMS listener starts on next app-shell init.
      await ref.read(smsAutoDetectEnabledProvider.notifier).setEnabled(true);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      // Permission denied — show a brief explanation and stay on screen.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permission denied. You can grant it anytime from your device '
            'Settings → Apps → Kash Cube → Permissions.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _skip() {
    // User chose not to grant permission — disable the feature toggle so the
    // app doesn't prompt again unexpectedly.
    ref.read(smsAutoDetectEnabledProvider.notifier).setEnabled(false);
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Transactions'),
        // No leading back arrow — user must choose Grant or Skip explicitly.
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxxl),

              // ── Hero icon ─────────────────────────────────────────────────
              Icon(Icons.sms_outlined, size: 72, color: colorScheme.primary),
              const SizedBox(height: AppSpacing.xl),

              // ── Headline ──────────────────────────────────────────────────
              Text(
                'Auto-detect UPI & bank\ntransactions',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.base),

              // ── Sub-headline ──────────────────────────────────────────────
              Text(
                'Kash Cube reads financial SMS from your bank and UPI apps to '
                'automatically log transactions — so you don\'t have to.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),

              // ── Feature bullets ───────────────────────────────────────────
              ..._features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.icon, size: 22, color: colorScheme.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(f.label, style: textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ── Privacy notice ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your SMS is read locally on this device only. '
                        'Kash Cube never transmits any message content '
                        'to any server.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Grant button ──────────────────────────────────────────────
              FilledButton.icon(
                onPressed: _requesting ? null : _grantPermission,
                icon: _requesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_requesting ? 'Requesting…' : 'Grant Permission'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Skip button ───────────────────────────────────────────────
              TextButton(
                onPressed: _requesting ? null : _skip,
                child: const Text('Skip for now'),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature bullet data
// ---------------------------------------------------------------------------

class _Feature {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;
}

const _features = <_Feature>[
  _Feature(
    Icons.auto_awesome_outlined,
    'Transactions are logged instantly when a payment SMS arrives.',
  ),
  _Feature(
    Icons.category_outlined,
    'Each transaction is auto-categorised based on the merchant name.',
  ),
  _Feature(
    Icons.phonelink_lock_outlined,
    'Only financial SMS from banks and UPI apps are processed — personal messages are ignored.',
  ),
  _Feature(
    Icons.visibility_off_outlined,
    'You review and confirm each transaction before it\'s saved.',
  ),
];
