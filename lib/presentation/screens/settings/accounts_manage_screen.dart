import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/account.dart';
import '../../providers/account_provider.dart';
import '../../providers/settings_provider.dart';

/// Manage accounts — view, add, rename, archive.
class AccountsManageScreen extends ConsumerWidget {
  const AccountsManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final defaultId = ref.watch(defaultAccountIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditSheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: AppSpacing.md),
                  Text('No accounts yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: accounts.length,
            separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final account = accounts[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    _iconForType(account.accountType),
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: Text(account.accountName),
                subtitle: Text(account.accountType.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        account.id == defaultId
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: account.id == defaultId
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      tooltip: account.id == defaultId
                          ? 'Remove as default'
                          : 'Set as default',
                      onPressed: () => ref
                          .read(defaultAccountIdProvider.notifier)
                          .setDefault(
                            account.id == defaultId ? null : account.id,
                          ),
                    ),
                    Switch(
                      value: account.isActive,
                      onChanged: (val) => ref
                          .read(accountsProvider.notifier)
                          .setActive(account.id!, active: val),
                    ),
                  ],
                ),
                onTap: () => _showAddEditSheet(context, ref, account: account),
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddEditSheet(BuildContext context, WidgetRef ref,
      {Account? account}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddEditAccountSheet(
        account: account,
        onSave: (a) {
          if (account == null) {
            ref.read(accountsProvider.notifier).addAccount(a);
          } else {
            ref.read(accountsProvider.notifier).updateAccount(a);
          }
        },
      ),
    );
  }

  IconData _iconForType(AccountType type) {
    switch (type) {
      case AccountType.savings:
      case AccountType.current:
        return Icons.account_balance_outlined;
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

class _AddEditAccountSheet extends StatefulWidget {
  const _AddEditAccountSheet({this.account, required this.onSave});

  final Account? account;
  final void Function(Account) onSave;

  @override
  State<_AddEditAccountSheet> createState() => _AddEditAccountSheetState();
}

class _AddEditAccountSheetState extends State<_AddEditAccountSheet> {
  final _nameController = TextEditingController();
  late AccountType _type;
  bool _isPrimary = false;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameController.text = a?.accountName ?? '';
    _type = a?.accountType ?? AccountType.savings;
    _isPrimary = a?.isPrimary ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Edit Account' : 'Add Account',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              hintText: 'e.g. SBI Savings, PhonePe',
              prefixIcon: Icon(Icons.label_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<AccountType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Account Type',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: AccountType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _type = v);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as primary account'),
            value: _isPrimary,
            onChanged: (v) => setState(() => _isPrimary = v ?? false),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                widget.onSave(
                  (widget.account ?? const Account(accountType: AccountType.savings, accountName: ''))
                      .copyWith(
                    accountName: name,
                    accountType: _type,
                    isPrimary: _isPrimary,
                    isActive: true,
                  ),
                );
                Navigator.of(context).pop();
              },
              child: Text(_isEditing ? 'Save Changes' : 'Add Account'),
            ),
          ),
        ],
      ),
    );
  }
}
