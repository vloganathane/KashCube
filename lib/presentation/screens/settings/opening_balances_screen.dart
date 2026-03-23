import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/models/account.dart';
import '../../../data/repositories/settings_repository_impl.dart';
import '../../providers/account_provider.dart';
import '../../providers/dashboard_provider.dart';

// ── Internal state object for a single editable account entry ────────────────

class _AccountEntry {
  _AccountEntry({this.existingId})
      : nameCtrl = TextEditingController(),
        bankNameCtrl = TextEditingController(),
        balanceCtrl = TextEditingController(),
        creditLimitCtrl = TextEditingController();

  final int? existingId;
  final TextEditingController nameCtrl;
  final TextEditingController bankNameCtrl;
  final TextEditingController balanceCtrl;
  final TextEditingController creditLimitCtrl;

  void dispose() {
    nameCtrl.dispose();
    bankNameCtrl.dispose();
    balanceCtrl.dispose();
    creditLimitCtrl.dispose();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Opening Balances — grouped by account type.
///
/// Sections:
///  • Bank Accounts (savings/current) — multiple named accounts supported
///  • Wallets (UPI wallet / payment wallet)
///  • Credit Cards — credit limit + opening outstanding
///  • Cash
///
/// Data is saved to the [Account] repository (Option B).
/// On first open with no saved accounts, the screen auto-migrates from the
/// legacy per-[PaymentMethod] settings keys (Option A backward compat).
class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState
    extends ConsumerState<OpeningBalancesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _legacySettings = SettingsRepositoryImpl();

  final List<_AccountEntry> _bankEntries = [];
  final List<_AccountEntry> _walletEntries = [];
  final List<_AccountEntry> _ccEntries = [];
  final _cashEntry = _AccountEntry();
  int? _cashAccountId;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final repo = ref.read(accountRepositoryProvider);
    final accounts = await repo.getAll(activeOnly: false);
    final active = accounts.where((a) => a.deletedAt == null).toList();

    for (final acct in active) {
      final type = acct.accountType;
      if (type == AccountType.savings || type == AccountType.current) {
        final e = _AccountEntry(existingId: acct.id);
        e.nameCtrl.text = acct.accountName;
        e.bankNameCtrl.text = acct.bankName ?? '';
        e.balanceCtrl.text = _fmtBalance(acct.currentBalance);
        _bankEntries.add(e);
      } else if (type == AccountType.cash) {
        _cashAccountId = acct.id;
        _cashEntry.balanceCtrl.text = _fmtBalance(acct.currentBalance);
      } else if (type == AccountType.upiWallet ||
          type == AccountType.paymentWallet) {
        final e = _AccountEntry(existingId: acct.id);
        e.nameCtrl.text = acct.accountName;
        e.balanceCtrl.text = _fmtBalance(acct.currentBalance);
        _walletEntries.add(e);
      } else if (type == AccountType.creditCard) {
        final e = _AccountEntry(existingId: acct.id);
        e.nameCtrl.text = acct.accountName;
        e.balanceCtrl.text = _fmtBalance(acct.currentBalance);
        e.creditLimitCtrl.text = _fmtBalance(acct.creditLimit);
        _ccEntries.add(e);
      }
    }

    // Auto-migrate from legacy settings when no accounts exist yet.
    if (active.isEmpty) await _migrateFromSettings();

    // Always ensure at least one blank bank entry for UX.
    if (_bankEntries.isEmpty) _bankEntries.add(_AccountEntry());

    if (mounted) setState(() => _loading = false);
  }

  String _fmtBalance(double? v) =>
      (v != null && v != 0) ? v.toStringAsFixed(2) : '';

  Future<void> _migrateFromSettings() async {
    // Bank balance was stored under opening_balance_upi in the old system.
    final upiStr = await _legacySettings.get('opening_balance_upi');
    if (upiStr != null && upiStr != '0') {
      final e = _AccountEntry();
      e.nameCtrl.text = 'My Bank Account';
      e.balanceCtrl.text = upiStr;
      _bankEntries.add(e);
    }

    final cashStr = await _legacySettings.get('opening_balance_cash');
    if (cashStr != null && cashStr != '0') {
      _cashEntry.balanceCtrl.text = cashStr;
    }

    final walletStr = await _legacySettings.get('opening_balance_wallet');
    if (walletStr != null && walletStr != '0') {
      final e = _AccountEntry();
      e.nameCtrl.text = 'My Wallet';
      e.balanceCtrl.text = walletStr;
      _walletEntries.add(e);
    }

    final ccStr = await _legacySettings.get('opening_balance_creditCard');
    final ccLimitStr =
        await _legacySettings.get('opening_balance_creditCard_limit');
    if ((ccStr != null && ccStr != '0') ||
        (ccLimitStr != null && ccLimitStr != '0')) {
      final e = _AccountEntry();
      e.nameCtrl.text = 'My Credit Card';
      e.balanceCtrl.text = ccStr ?? '';
      e.creditLimitCtrl.text = ccLimitStr ?? '';
      _ccEntries.add(e);
    }
  }

  @override
  void dispose() {
    for (final e in [..._bankEntries, ..._walletEntries, ..._ccEntries]) {
      e.dispose();
    }
    _cashEntry.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(accountRepositoryProvider);

      // ── Bank accounts ──────────────────────────────────────────────────
      for (final e in _bankEntries) {
        final name = e.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        final balance = double.tryParse(e.balanceCtrl.text.trim()) ?? 0.0;
        final bankName = e.bankNameCtrl.text.trim();
        if (e.existingId != null) {
          final existing = await repo.getById(e.existingId!);
          if (existing != null) {
            await repo.update(existing.copyWith(
              accountName: name,
              bankName: bankName.isEmpty ? null : bankName,
              currentBalance: balance,
              updatedAt: DateTime.now(),
            ));
          }
        } else {
          await repo.insert(Account(
            accountName: name,
            accountType: AccountType.savings,
            bankName: bankName.isEmpty ? null : bankName,
            currentBalance: balance,
            isActive: true,
            isPrimary: _bankEntries.indexOf(e) == 0,
          ));
        }
      }

      // ── Cash ───────────────────────────────────────────────────────────
      final cashBalance =
          double.tryParse(_cashEntry.balanceCtrl.text.trim()) ?? 0.0;
      if (_cashAccountId != null) {
        final existing = await repo.getById(_cashAccountId!);
        if (existing != null) {
          await repo.update(
              existing.copyWith(currentBalance: cashBalance, updatedAt: DateTime.now()));
        }
      } else if (cashBalance > 0) {
        _cashAccountId = await repo.insert(Account(
          accountName: 'Cash',
          accountType: AccountType.cash,
          currentBalance: cashBalance,
          isActive: true,
          isPrimary: false,
        ));
      }

      // ── Wallet accounts ────────────────────────────────────────────────
      for (final e in _walletEntries) {
        final name = e.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        final balance = double.tryParse(e.balanceCtrl.text.trim()) ?? 0.0;
        if (e.existingId != null) {
          final existing = await repo.getById(e.existingId!);
          if (existing != null) {
            await repo.update(existing.copyWith(
              accountName: name,
              currentBalance: balance,
              updatedAt: DateTime.now(),
            ));
          }
        } else {
          await repo.insert(Account(
            accountName: name,
            accountType: AccountType.paymentWallet,
            currentBalance: balance,
            isActive: true,
            isPrimary: false,
          ));
        }
      }

      // ── Credit cards ───────────────────────────────────────────────────
      for (final e in _ccEntries) {
        final name = e.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        final outstanding =
            double.tryParse(e.balanceCtrl.text.trim()) ?? 0.0;
        final limit =
            double.tryParse(e.creditLimitCtrl.text.trim()) ?? 0.0;
        if (e.existingId != null) {
          final existing = await repo.getById(e.existingId!);
          if (existing != null) {
            await repo.update(existing.copyWith(
              accountName: name,
              currentBalance: outstanding,
              creditLimit: limit,
              updatedAt: DateTime.now(),
            ));
          }
        } else {
          await repo.insert(Account(
            accountName: name,
            accountType: AccountType.creditCard,
            currentBalance: outstanding,
            creditLimit: limit,
            isActive: true,
            isPrimary: false,
          ));
        }
      }

      ref.invalidate(accountBalancesProvider);
      ref.invalidate(totalBalanceProvider);
      ref.invalidate(accountsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Opening balances saved')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: context.colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Opening Balances')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  // Info card
                  _InfoCard(
                    'Enter the amounts you held before you started recording '
                    'transactions in Kash Cube. Leave blank or enter 0 to start from zero.',
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Bank Accounts ──────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.account_balance_outlined,
                    label: 'Bank Accounts',
                    note: 'Covers UPI, Debit Card, Net Banking & Cheque payments.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._bankEntries.asMap().entries.map((e) => _BankAccountEntry(
                        entry: e.value,
                        index: e.key,
                        canRemove: _bankEntries.length > 1,
                        onRemove: () => setState(() => _bankEntries.removeAt(e.key)),
                      )),
                  _AddTile(
                    label: 'Add Bank Account',
                    onTap: () => setState(() => _bankEntries.add(_AccountEntry())),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Wallets ────────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallets',
                    note: 'Paytm, PhonePe Wallet, or any stored-value wallet.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._walletEntries.asMap().entries.map((e) => _SimpleAccountEntry(
                        entry: e.value,
                        label: 'Wallet name',
                        icon: Icons.account_balance_wallet_outlined,
                        canRemove: true,
                        onRemove: () => setState(() => _walletEntries.removeAt(e.key)),
                      )),
                  _AddTile(
                    label: 'Add Wallet',
                    onTap: () => setState(() => _walletEntries.add(_AccountEntry())),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Credit Cards ───────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.credit_card,
                    label: 'Credit Cards',
                    note:
                        'Credit Limit is the total approved limit. '
                        'Opening Outstanding is what you already owed before using Kash Cube.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._ccEntries.asMap().entries.map((e) => _CreditCardEntry(
                        entry: e.value,
                        canRemove: true,
                        onRemove: () => setState(() => _ccEntries.removeAt(e.key)),
                      )),
                  _AddTile(
                    label: 'Add Credit Card',
                    onTap: () => setState(() => _ccEntries.add(_AccountEntry())),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Cash ───────────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.money_outlined,
                    label: 'Cash',
                    note: 'Physical cash in hand.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _AmountField(
                    controller: _cashEntry.balanceCtrl,
                    label: 'Cash in hand',
                    icon: Icons.money_outlined,
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Opening Balances'),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 18, color: context.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.note});
  final IconData icon;
  final String label;
  final String? note;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: context.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: context.textTheme.titleSmall
                  ?.copyWith(color: context.colorScheme.primary)),
        ]),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note!,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: AppSpacing.xs),
        Divider(color: context.colorScheme.outlineVariant, height: 1),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(children: [
          Icon(Icons.add_circle_outline,
              size: 18, color: context.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colorScheme.primary)),
        ]),
      ),
    );
  }
}

class _BankAccountEntry extends StatelessWidget {
  const _BankAccountEntry({
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });
  final _AccountEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: entry.nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Account name',
                    hintText: 'e.g. HDFC Savings',
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter account name' : null,
                ),
              ),
              if (canRemove) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ]),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: entry.bankNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Bank name (optional)',
                hintText: 'e.g. HDFC Bank',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _AmountField(
              controller: entry.balanceCtrl,
              label: 'Opening balance',
              icon: Icons.currency_rupee,
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleAccountEntry extends StatelessWidget {
  const _SimpleAccountEntry({
    required this.entry,
    required this.label,
    required this.icon,
    required this.canRemove,
    required this.onRemove,
  });
  final _AccountEntry entry;
  final String label;
  final IconData icon;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: entry.nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: label,
                  prefixIcon: Icon(icon),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter name' : null,
              ),
            ),
            if (canRemove) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: onRemove),
            ],
          ]),
          const SizedBox(height: AppSpacing.sm),
          _AmountField(
            controller: entry.balanceCtrl,
            label: 'Opening balance',
            icon: Icons.currency_rupee,
          ),
        ]),
      ),
    );
  }
}

class _CreditCardEntry extends StatelessWidget {
  const _CreditCardEntry({
    required this.entry,
    required this.canRemove,
    required this.onRemove,
  });
  final _AccountEntry entry;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: entry.nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Card name',
                  hintText: 'e.g. HDFC Regalia',
                  prefixIcon: Icon(Icons.credit_card),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter card name' : null,
              ),
            ),
            if (canRemove) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: onRemove),
            ],
          ]),
          const SizedBox(height: AppSpacing.sm),
          _AmountField(
            controller: entry.creditLimitCtrl,
            label: 'Credit Limit',
            icon: Icons.credit_score_outlined,
          ),
          const SizedBox(height: AppSpacing.sm),
          _AmountField(
            controller: entry.balanceCtrl,
            label: 'Opening Outstanding',
            icon: Icons.currency_rupee,
            helperText: 'Leave 0 if fully paid before using Kash Cube',
          ),
        ]),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.icon,
    this.helperText,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        hintText: '0',
        prefixIcon: Icon(icon),
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (double.tryParse(v.trim()) == null) return 'Enter a valid amount';
        return null;
      },
    );
  }
}
