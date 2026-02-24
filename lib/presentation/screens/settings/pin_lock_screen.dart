import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../providers/settings_provider.dart';

/// Hashes a PIN using SHA-256.
String _hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

/// Mode for the PIN screen.
enum PinScreenMode {
  /// User is unlocking the app with their PIN.
  unlock,

  /// User is setting a new PIN.
  setup,

  /// User is confirming the new PIN (re-enter).
  confirm,

  /// User is removing the PIN (enter current PIN to confirm).
  remove,
}

/// Full-screen PIN entry for app lock.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({
    super.key,
    this.mode = PinScreenMode.unlock,
    this.onSuccess,
  });

  final PinScreenMode mode;

  /// Called when PIN is verified or set successfully.
  final VoidCallback? onSuccess;

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  static const _pinLength = 4;

  String _enteredPin = '';
  String? _firstPin; // used in setup flow for confirmation
  PinScreenMode _currentMode = PinScreenMode.unlock;
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
  }

  String get _title {
    switch (_currentMode) {
      case PinScreenMode.unlock:
        return 'Enter PIN';
      case PinScreenMode.setup:
        return 'Set a PIN';
      case PinScreenMode.confirm:
        return 'Confirm PIN';
      case PinScreenMode.remove:
        return 'Enter Current PIN';
    }
  }

  String get _subtitle {
    switch (_currentMode) {
      case PinScreenMode.unlock:
        return 'Enter your PIN to unlock Kash Cube';
      case PinScreenMode.setup:
        return 'Choose a 4-digit PIN';
      case PinScreenMode.confirm:
        return 'Re-enter your PIN to confirm';
      case PinScreenMode.remove:
        return 'Enter your current PIN to remove app lock';
    }
  }

  void _onDigit(int digit) {
    if (_enteredPin.length >= _pinLength || _isProcessing) return;

    setState(() {
      _enteredPin += digit.toString();
      _errorMessage = null;
    });

    if (_enteredPin.length == _pinLength) {
      _handlePinComplete();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty || _isProcessing) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _handlePinComplete() async {
    setState(() => _isProcessing = true);

    final settingsRepo = ref.read(settingsRepositoryProvider);

    switch (_currentMode) {
      case PinScreenMode.unlock:
      case PinScreenMode.remove:
        final storedHash = await settingsRepo.get(SettingsKeys.pinHash);
        final enteredHash = _hashPin(_enteredPin);

        if (storedHash == enteredHash) {
          if (_currentMode == PinScreenMode.remove) {
            await settingsRepo.remove(SettingsKeys.pinHash);
            await settingsRepo.set(SettingsKeys.appLockEnabled, 'false');
            await settingsRepo.set(SettingsKeys.biometricEnabled, 'false');
            ref.invalidate(appLockEnabledProvider);
            ref.invalidate(biometricEnabledProvider);
          }
          HapticFeedback.lightImpact();
          widget.onSuccess?.call();
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _enteredPin = '';
            _errorMessage = 'Incorrect PIN';
            _isProcessing = false;
          });
        }
        break;

      case PinScreenMode.setup:
        _firstPin = _enteredPin;
        setState(() {
          _enteredPin = '';
          _currentMode = PinScreenMode.confirm;
          _isProcessing = false;
        });
        break;

      case PinScreenMode.confirm:
        if (_enteredPin == _firstPin) {
          final hash = _hashPin(_enteredPin);
          await settingsRepo.set(SettingsKeys.pinHash, hash);
          await settingsRepo.set(SettingsKeys.appLockEnabled, 'true');
          ref.invalidate(appLockEnabledProvider);
          HapticFeedback.lightImpact();
          widget.onSuccess?.call();
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _enteredPin = '';
            _firstPin = null;
            _currentMode = PinScreenMode.setup;
            _errorMessage = 'PINs did not match. Try again.';
            _isProcessing = false;
          });
        }
        break;
    }

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = widget.mode != PinScreenMode.unlock;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (canPop)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ),
              const Spacer(),
              // Lock icon
              Icon(
                Icons.lock_outline,
                size: 48,
                color: context.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(_title, style: context.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _subtitle,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              // PIN dots
              _PinDots(
                length: _pinLength,
                filled: _enteredPin.length,
                hasError: _errorMessage != null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _errorMessage!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.error,
                  ),
                ),
              ],
              const Spacer(),
              // Number pad
              _NumberPad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN dots indicator
// ---------------------------------------------------------------------------

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.hasError,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final color = hasError
        ? context.colorScheme.error
        : context.colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Number pad
// ---------------------------------------------------------------------------

class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.onDigit,
    required this.onBackspace,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Column(
        children: [
          _row([1, 2, 3]),
          const SizedBox(height: AppSpacing.md),
          _row([4, 5, 6]),
          const SizedBox(height: AppSpacing.md),
          _row([7, 8, 9]),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72), // placeholder
              _DigitButton(digit: 0, onTap: onDigit),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  onPressed: onBackspace,
                  icon: const Icon(Icons.backspace_outlined),
                  iconSize: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(List<int> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _DigitButton(digit: d, onTap: onDigit)).toList(),
    );
  }
}

class _DigitButton extends StatelessWidget {
  const _DigitButton({required this.digit, required this.onTap});

  final int digit;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(digit),
          customBorder: const CircleBorder(),
          child: Center(
            child: Text(
              '$digit',
              style: context.textTheme.headlineMedium,
            ),
          ),
        ),
      ),
    );
  }
}
