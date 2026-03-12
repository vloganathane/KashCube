import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/pin_hash.dart';
import '../../../data/models/app_user.dart';
import '../../providers/app_user_provider.dart';

/// 4-digit PIN entry screen for non-owner app users.
/// On success: sets [activeAppUserProvider] and pops to the main shell.
class StaffPinScreen extends ConsumerStatefulWidget {
  const StaffPinScreen({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<StaffPinScreen> createState() => _StaffPinScreenState();
}

class _StaffPinScreenState extends ConsumerState<StaffPinScreen> {
  static const int _maxAttempts = 5;
  static const int _pinLength = 4;

  String _enteredPin = '';
  int _failedAttempts = 0;
  String? _errorMessage;
  bool _isLocked = false;

  void _onDigit(String digit) {
    if (_isLocked) return;
    if (_enteredPin.length >= _pinLength) return;
    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });
    if (_enteredPin.length == _pinLength) {
      _verify();
    }
  }

  void _onBackspace() {
    if (_isLocked || _enteredPin.isEmpty) return;
    setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
  }

  Future<void> _verify() async {
    final storedHash = widget.user.pinHash;
    if (storedHash == null) {
      // No PIN set — allow entry (owner manages access)
      _onSuccess();
      return;
    }

    if (verifyPin(_enteredPin, storedHash)) {
      _onSuccess();
    } else {
      HapticFeedback.heavyImpact();
      final remaining = _maxAttempts - (_failedAttempts + 1);
      setState(() {
        _failedAttempts++;
        _enteredPin = '';
        if (_failedAttempts >= _maxAttempts) {
          _isLocked = true;
          _errorMessage = 'Too many attempts. Ask owner to unlock.';
        } else {
          _errorMessage = 'Incorrect PIN — $remaining attempt${remaining == 1 ? '' : 's'} left';
        }
      });
    }
  }

  void _onSuccess() {
    HapticFeedback.lightImpact();
    ref.read(activeAppUserProvider.notifier).state = widget.user;
    ref.read(appUserRepositoryProvider).recordLogin(widget.user.id!);
    // Pop back to whatever screen owns UserSelectionScreen (the _LockGate rebuild
    // will see activeAppUserProvider != null and show AppShell).
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            CircleAvatar(
              radius: 36,
              backgroundColor: cs.secondaryContainer,
              child: Text(
                widget.user.initials,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.user.displayName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.user.role.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isLocked
                        ? cs.error
                        : filled
                            ? cs.primary
                            : cs.outlineVariant,
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            const Spacer(),
            // Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
              child: Column(
                children: [
                  for (final row in [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ])
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: row
                          .map((d) => _KeypadButton(
                                label: d,
                                onTap: () => _onDigit(d),
                                enabled: !_isLocked,
                              ))
                          .toList(),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 72, height: 72),
                      _KeypadButton(label: '0', onTap: () => _onDigit('0'), enabled: !_isLocked),
                      _KeypadButton(
                        icon: Icons.backspace_outlined,
                        onTap: _onBackspace,
                        enabled: !_isLocked,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    this.label,
    this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          onTap: enabled ? onTap : null,
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3),
                        ),
                  )
                : Icon(
                    icon,
                    color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3),
                  ),
          ),
        ),
      ),
    );
  }
}
