import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/account.dart';
import '../../providers/account_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';

/// Formats a double as a plain number string suitable for pre-filling a
/// currency text field (no ₹ symbol, no commas; trims trailing zeros).
String _formatBalance(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toString();
}

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
        heroTag: null,
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
                  Icon(
                    Icons.account_balance_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Icon(
                    _iconForType(account.accountType),
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: Text(account.accountName),
                subtitle: Text(_subtitleForAccount(account)),
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddEditSheet(
    BuildContext context,
    WidgetRef ref, {
    Account? account,
  }) {
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
          ref.invalidate(accountBalancesProvider);
          ref.invalidate(totalBalanceProvider);
        },
      ),
    );
  }

  String _subtitleForAccount(Account a) {
    final parts = <String>[a.accountType.label];
    if (a.openingBalance != null && a.openingBalance! != 0) {
      parts.add('Opening: ${CurrencyFormatter.format(a.openingBalance!)}');
    }
    if (a.creditLimit != null && a.creditLimit! != 0) {
      parts.add('Limit: ${CurrencyFormatter.format(a.creditLimit!)}');
    }
    return parts.join(' · ');
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

// ─── Add / Edit Account Sheet ────────────────────────────────────────────────

/// Bottom sheet for creating or editing an [Account].
///
/// Fields shown:
/// - Account Name (required)
/// - Account Type (required)
/// - Opening Balance (optional, ₹ prefix)
/// - Credit Limit (optional, only for creditCard type)
/// - Account Number Last 4 (optional, for bank/card types)
/// - Bank Name (optional, for bank/card types)
/// - Linked Bank Account (optional, for debitCard/upiWallet types)
/// - Set as primary (checkbox)
class _AddEditAccountSheet extends ConsumerStatefulWidget {
  const _AddEditAccountSheet({this.account, required this.onSave});

  final Account? account;
  final void Function(Account) onSave;

  @override
  ConsumerState<_AddEditAccountSheet> createState() =>
      _AddEditAccountSheetState();
}

class _AddEditAccountSheetState extends ConsumerState<_AddEditAccountSheet> {
  final _nameController = TextEditingController();
  final _openingBalCtrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();
  final _acctNumberCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();

  late AccountType _type;
  int? _linkedBankAccountId;
  bool _isPrimary = false;

  bool get _isEditing => widget.account != null;

  /// Account types that require a linked parent bank account (upcoming phase).
  bool get _needsLinkedBank =>
      _type == AccountType.debitCard || _type == AccountType.upiWallet;

  /// Account types where we show bank name + account number.
  bool get _showBankFields =>
      _type == AccountType.savings ||
      _type == AccountType.current ||
      _type == AccountType.debitCard ||
      _type == AccountType.creditCard;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameController.text = a?.accountName ?? '';
    _type = a?.accountType ?? AccountType.savings;
    _isPrimary = a?.isPrimary ?? false;
    _linkedBankAccountId = a?.linkedBankAccountId;
    _acctNumberCtrl.text = a?.accountNumberLast4 ?? '';
    _bankNameCtrl.text = a?.bankName ?? '';

    if (a?.openingBalance != null && a!.openingBalance! != 0) {
      _openingBalCtrl.text = _formatBalance(a.openingBalance!);
    }
    if (a?.creditLimit != null && a!.creditLimit! != 0) {
      _creditLimitCtrl.text = _formatBalance(a.creditLimit!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalCtrl.dispose();
    _creditLimitCtrl.dispose();
    _acctNumberCtrl.dispose();
    _bankNameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final openingBal = double.tryParse(_openingBalCtrl.text.trim());
    final creditLimit = double.tryParse(_creditLimitCtrl.text.trim());
    final acctNum = _acctNumberCtrl.text.trim();
    final bankName = _bankNameCtrl.text.trim();

    widget.onSave(
      (widget.account ??
              const Account(accountType: AccountType.savings, accountName: ''))
          .copyWith(
            accountName: name,
            accountType: _type,
            openingBalance: openingBal,
            creditLimit: creditLimit,
            linkedBankAccountId: _linkedBankAccountId,
            accountNumberLast4: acctNum.isEmpty ? null : acctNum,
            bankName: bankName.isEmpty ? null : bankName,
            isPrimary: _isPrimary,
            isActive: true,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final allAccounts = ref.watch(accountsProvider).valueOrNull ?? [];
    // Potential linked bank accounts: savings/current only, excluding self.
    final bankAccounts = allAccounts
        .where(
          (a) =>
              (a.accountType == AccountType.savings ||
                  a.accountType == AccountType.current) &&
              a.id != widget.account?.id,
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit Account' : 'Add Account',
              style: tt.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Account Name ──────────────────────────────────────────
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                hintText: 'e.g. HDFC Savings, PhonePe',
                prefixIcon: Icon(Icons.label_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Account Type ──────────────────────────────────────────
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Account Type *',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: AccountType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _type = v;
                    // Clear linked bank if switching to a non-linking type.
                    if (!_needsLinkedBank) _linkedBankAccountId = null;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Opening Balance ───────────────────────────────────────
            TextField(
              controller: _openingBalCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: _type == AccountType.creditCard
                    ? 'Outstanding balance (opening)'
                    : 'Opening Balance',
                hintText: '0',
                prefixIcon: const Icon(Icons.currency_rupee_outlined),
                helperText: _type == AccountType.creditCard
                    ? 'Amount already owed on this card'
                    : 'Balance at the time you set up this account',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Credit Limit (credit cards only) ──────────────────────
            if (_type == AccountType.creditCard) ...[
              TextField(
                controller: _creditLimitCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Credit Limit',
                  hintText: '0',
                  prefixIcon: Icon(Icons.credit_score_outlined),
                  helperText: 'Total approved credit limit on this card',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Bank Name + Account Number (bank/card types) ──────────
            if (_showBankFields) ...[
              TextField(
                controller: _bankNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g. HDFC Bank, SBI',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _acctNumberCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Last 4 digits of account / card number',
                  hintText: '1234',
                  prefixIcon: Icon(Icons.dialpad_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Linked Bank Account (debit card / UPI wallet) ─────────
            if (_needsLinkedBank && bankAccounts.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _linkedBankAccountId,
                decoration: const InputDecoration(
                  labelText: 'Linked Bank Account',
                  prefixIcon: Icon(Icons.link_outlined),
                  helperText:
                      'Transactions on this account deduct from the linked bank account',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('None'),
                  ),
                  ...bankAccounts.map(
                    (a) => DropdownMenuItem<int?>(
                      value: a.id,
                      child: Text(a.accountName),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _linkedBankAccountId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Primary flag ──────────────────────────────────────────
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set as primary account'),
              subtitle: const Text('Pre-selected when adding transactions'),
              value: _isPrimary,
              onChanged: (v) => setState(() => _isPrimary = v ?? false),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Save ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(_isEditing ? 'Save Changes' : 'Add Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
