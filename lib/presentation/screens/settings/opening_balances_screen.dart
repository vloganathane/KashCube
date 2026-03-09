import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/models/transaction.dart';
import '../../../data/repositories/settings_repository_impl.dart';
import '../../providers/dashboard_provider.dart';

/// Screen to set per-payment-method opening balances.
///
/// Opening balance = the amount in that account before any transactions
/// were recorded in Kash Cube. Combined with all-time transaction data,
/// this gives the true current balance per account.
class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState
    extends ConsumerState<OpeningBalancesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settings = SettingsRepositoryImpl();

  // One controller per PaymentMethod
  late final Map<PaymentMethod, TextEditingController> _controllers = {
    for (final m in PaymentMethod.values) m: TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSavedBalances();
  }

  Future<void> _loadSavedBalances() async {
    for (final method in PaymentMethod.values) {
      final saved =
          await _settings.get('opening_balance_${method.dbValue}');
      if (saved != null) {
        _controllers[method]!.text = saved;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      for (final method in PaymentMethod.values) {
        final raw = _controllers[method]!.text.trim();
        final value = raw.isEmpty ? '0' : raw;
        await _settings.set('opening_balance_${method.dbValue}', value);
      }
      // Invalidate balance providers so HomeScreen refreshes
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(totalBalanceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening balances saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: context.colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opening Balances'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  // Info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 18,
                              color: context.colorScheme.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Enter the amount you had in each account before '
                              'you started recording transactions in Kash Cube. '
                              'Leave blank or enter 0 if you started from zero.',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // One row per payment method
                  ...PaymentMethod.values.map((method) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _MethodBalanceField(
                          method: method,
                          controller: _controllers[method]!,
                        ),
                      )),

                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Opening Balances'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MethodBalanceField extends StatelessWidget {
  const _MethodBalanceField({
    required this.method,
    required this.controller,
  });

  final PaymentMethod method;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: method.label,
        prefixText: '₹ ',
        hintText: '0',
        prefixIcon: Icon(_methodIcon(method)),
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (double.tryParse(v.trim()) == null) {
          return 'Enter a valid amount';
        }
        return null;
      },
    );
  }

  IconData _methodIcon(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return Icons.money_outlined;
      case PaymentMethod.upi:
        return Icons.qr_code_rounded;
      case PaymentMethod.creditCard:
        return Icons.credit_card;
      case PaymentMethod.debitCard:
        return Icons.credit_card_outlined;
      case PaymentMethod.netBanking:
        return Icons.account_balance_outlined;
      case PaymentMethod.wallet:
        return Icons.account_balance_wallet_outlined;
      case PaymentMethod.cheque:
        return Icons.receipt_long_outlined;
    }
  }
}
