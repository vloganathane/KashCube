import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/adaptive_sheet.dart';
import '../../data/models/account.dart';
import '../providers/account_provider.dart';

/// Shows a bottom sheet to pick an account. Returns the chosen [Account] or
/// null if dismissed.
Future<Account?> showAccountPicker(
  BuildContext context, {
  int? excludeId,
  String? title,
}) {
  return showAdaptiveSheet<Account>(
    context,
    builder: (_) => _AccountPickerSheet(
      excludeId: excludeId,
      title: title ?? 'Select Account',
    ),
  );
}

class _AccountPickerSheet extends ConsumerWidget {
  const _AccountPickerSheet({this.excludeId, required this.title});

  final int? excludeId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          accountsAsync.when(
            data: (accounts) {
              final filtered = accounts
                  .where((a) => a.id != excludeId && a.isActive)
                  .toList();
              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: Text('No accounts found')),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final account = filtered[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        _iconForType(account.accountType),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(account.accountName),
                    subtitle: Text(account.accountType.label),
                    trailing: account.isPrimary
                        ? Chip(label: const Text('Primary'), labelStyle: const TextStyle(fontSize: 11))
                        : null,
                    onTap: () => Navigator.of(context).pop(account),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('Error loading accounts: $e'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(AccountType type) {
    switch (type) {
      case AccountType.savings:
      case AccountType.current:
        return Icons.account_balance_outlined;
      case AccountType.cash:
        return Icons.money_outlined;
      case AccountType.creditCard:
        return Icons.credit_card_outlined;
      case AccountType.debitCard:
        return Icons.payment_outlined;
      case AccountType.upiWallet:
      case AccountType.paymentWallet:
        return Icons.account_balance_wallet_outlined;
    }
  }
}
