import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/kash_cube_colors.dart';
import '../../../data/models/party.dart';
import '../../../data/models/transaction.dart';
import '../../providers/party_provider.dart';
import '../../providers/transaction_provider.dart';

// ---------------------------------------------------------------------------
// FutureProvider — loads transactions for a given party name
// ---------------------------------------------------------------------------

final _partyTransactionsFutureProvider =
    FutureProvider.family<List<Transaction>, String>((ref, partyName) {
  final repo = ref.read(transactionRepositoryProvider);
  return repo.getTransactionsByParty(partyName);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PartyDetailScreen extends ConsumerWidget {
  const PartyDetailScreen({super.key, required this.party});

  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KashCubeColors>()!;
    final txnAsync =
        ref.watch(_partyTransactionsFutureProvider(party.name));

    return Scaffold(
      appBar: AppBar(
        title: Text(party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _showEditSheet(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
        children: [
          // ── Header card ────────────────────────────────────────────────
          _HeaderCard(party: party, colors: colors),

          // ── Summary row ────────────────────────────────────────────────
          _SummaryRow(party: party, colors: colors),

          // ── Contact actions ────────────────────────────────────────────
          if (party.phoneNumber != null || party.email != null)
            _ContactActions(party: party),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: Text('Transaction History',
                style: Theme.of(context).textTheme.titleMedium),
          ),

          // ── Transaction list ───────────────────────────────────────────
          txnAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (txns) {
              if (txns.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: Text('No transactions with ${party.name} yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                );
              }
              return Column(
                children: txns
                    .map((t) => _TransactionTile(txn: t, colors: colors))
                    .toList(),
              );
            },
          ),
        ],
      ),

      // ── Send Reminder FAB (only if phone + has lending) ─────────────
      floatingActionButton: party.phoneNumber != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send Reminder'),
              onPressed: () => _showReminderSheet(context, ref),
            )
          : null,
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditPartySheet(
        existing: party,
        onSave: (updated) =>
            ref.read(partiesProvider.notifier).update(updated),
      ),
    );
  }

  void _showReminderSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SendReminderSheet(
        party: party,
        onReminderSent: (transactionId) {
          ref
              .read(partiesProvider.notifier)
              .markReminderSent(transactionId);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.party, required this.colors});

  final Party party;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(party.partyType, colors);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: typeColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: typeColor.withValues(alpha: 0.2),
            child: Text(
              party.name.isNotEmpty
                  ? party.name[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: typeColor),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(party.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                _InfoRow(
                  icon: Icons.label_outline,
                  text: party.partyType.label,
                  color: typeColor,
                ),
                if (party.phoneNumber != null)
                  _InfoRow(
                      icon: Icons.phone_outlined,
                      text: '+91 ${party.phoneNumber!}'),
                if (party.email != null)
                  _InfoRow(
                      icon: Icons.email_outlined, text: party.email!),
                if (party.gstin != null)
                  _InfoRow(
                      icon: Icons.receipt_long_outlined,
                      text: party.gstin!),
                if (party.address != null)
                  _InfoRow(
                      icon: Icons.location_on_outlined,
                      text: party.address!),
                if (party.notes != null)
                  _InfoRow(
                      icon: Icons.notes_outlined, text: party.notes!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(PartyType type, KashCubeColors colors) {
    switch (type) {
      case PartyType.customer:
        return colors.income;
      case PartyType.vendor:
        return colors.expense;
      case PartyType.lender:
        return colors.credit;
      case PartyType.borrower:
        return colors.overdue;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: effectiveColor)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary row
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.party, required this.colors});

  final Party party;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final netBalance =
        party.totalCreditGiven - party.totalCreditReceived;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _StatChip(
            label: 'Transactions',
            value: '${party.totalTransactions}',
            icon: Icons.receipt_outlined,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatChip(
            label: 'Total',
            value: _inr(party.totalTransactionAmount),
            icon: Icons.currency_rupee,
          ),
          if (netBalance != 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _StatChip(
              label: netBalance > 0 ? 'You lent' : 'You owe',
              value: _inr(netBalance.abs()),
              icon: netBalance > 0
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              color: netBalance > 0 ? colors.credit : colors.overdue,
            ),
          ],
        ],
      ),
    );
  }

  String _inr(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '₹${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return '₹$s';
    }
    return '₹${v.toStringAsFixed(0)}';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: c)),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact action buttons
// ---------------------------------------------------------------------------

class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          if (party.phoneNumber != null) ...[
            _ActionButton(
              icon: Icons.phone_outlined,
              label: 'Call',
              onTap: () => _launch('tel:+91${party.phoneNumber}'),
            ),
            _ActionButton(
              icon: Icons.message_outlined,
              label: 'SMS',
              onTap: () =>
                  _launch('sms:+91${party.phoneNumber}?body=Hi,'),
            ),
            _ActionButton(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              onTap: () => _launch(
                  'https://wa.me/91${party.phoneNumber}?text=Hi%2C'),
            ),
          ],
          if (party.email != null)
            _ActionButton(
              icon: Icons.email_outlined,
              label: 'Email',
              onTap: () => _launch('mailto:${party.email}'),
            ),          _ActionButton(
            icon: Icons.contact_page_outlined,
            label: 'Save to Contacts',
            onTap: () => _saveToContacts(context),
          ),        ],
      ),
    );
  }

  void _launch(String url) {
    final uri = Uri.parse(url);
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _saveToContacts(BuildContext context) async {
    try {
      final contact = Contact()
        ..name = Name(last: party.name)
        ..phones = [
          if (party.phoneNumber != null) Phone(party.phoneNumber!)
        ]
        ..emails = [
          if (party.email != null) Email(party.email!)
        ];
      await FlutterContacts.openExternalInsert(contact);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open contacts app.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction tile (compact)
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn, required this.colors});

  final Transaction txn;
  final KashCubeColors colors;

  @override
  Widget build(BuildContext context) {
    final isIn = txn.isIncome;
    final amountColor = isIn ? colors.income : colors.expense;
    final prefix = isIn ? '+' : '-';
    final dateStr =
        '${txn.date.day} ${_monthAbbr(txn.date.month)} ${txn.date.year}';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child: Icon(
          _typeIcon(txn.type),
          size: 16,
          color: amountColor,
        ),
      ),
      title: Text(txn.category,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(dateStr,
          style: Theme.of(context).textTheme.labelSmall),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$prefix₹${_fmt(txn.amount)}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: amountColor),
          ),
          if (txn.reminderSentAt != null)
            Icon(Icons.notifications_active_outlined,
                size: 12,
                color: colors.credit),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      if (s.length > 3) {
        return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
      }
      return s;
    }
    return v.toStringAsFixed(0);
  }

  IconData _typeIcon(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.arrow_downward;
      case TransactionType.expense:
        return Icons.arrow_upward;
      case TransactionType.lent:
        return Icons.call_made;
      case TransactionType.borrowed:
        return Icons.call_received;
      case TransactionType.receivedBack:
        return Icons.undo;
      case TransactionType.paidBack:
        return Icons.redo;
      case TransactionType.transfer:
        return Icons.swap_horiz;
      case TransactionType.invested:
        return Icons.trending_up;
      case TransactionType.redeemed:
        return Icons.trending_down;
    }
  }

  String _monthAbbr(int m) {
    const abbr = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return abbr[m];
  }
}

// ---------------------------------------------------------------------------
// Send Reminder bottom sheet
// ---------------------------------------------------------------------------

class _SendReminderSheet extends ConsumerStatefulWidget {
  const _SendReminderSheet(
      {required this.party, required this.onReminderSent});

  final Party party;
  final void Function(int transactionId) onReminderSent;

  @override
  ConsumerState<_SendReminderSheet> createState() =>
      _SendReminderSheetState();
}

class _SendReminderSheetState extends ConsumerState<_SendReminderSheet> {
  String _customMessage = '';

  @override
  void initState() {
    super.initState();
    final name = widget.party.name;
    _customMessage = 'Hi $name, this is a friendly reminder regarding '
        'the outstanding amount. Please let me know when you can settle. '
        'Thank you!';
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.party.phoneNumber;
    final email = widget.party.email;
    final encodedMsg = Uri.encodeComponent(_customMessage);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Send Reminder',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Message editor ────────────────────────────────────────────
          TextField(
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _customMessage = v),
            controller: TextEditingController.fromValue(
              TextEditingValue(
                text: _customMessage,
                selection: TextSelection.collapsed(
                    offset: _customMessage.length),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Send via:',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),

          // ── Channel buttons ───────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (phone != null) ...[
                _ReminderChannelButton(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _send(
                    'https://wa.me/91$phone?text=$encodedMsg',
                    phone,
                  ),
                ),
                _ReminderChannelButton(
                  icon: Icons.message_outlined,
                  label: 'SMS',
                  color: const Color(0xFF1976D2),
                  onTap: () => _send(
                    'sms:+91$phone?body=$encodedMsg',
                    phone,
                  ),
                ),
              ],
              if (email != null)
                _ReminderChannelButton(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  color: const Color(0xFFD32F2F),
                  onTap: () => _send(
                    'mailto:$email?subject=Payment+Reminder&body=$encodedMsg',
                    null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Opening your messaging app. The message is pre-filled.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String url, String? phone) async {
    final uri = Uri.parse(url);
    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open app for this action.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    // Mark reminder sent on all lending transactions with this party
    final txns = await ref
        .read(transactionRepositoryProvider)
        .getTransactionsByParty(widget.party.name);
    for (final t in txns) {
      if (t.isLending && t.id != null) {
        widget.onReminderSent(t.id!);
      }
    }
    if (mounted) Navigator.pop(context);
  }
}

class _ReminderChannelButton extends StatelessWidget {
  const _ReminderChannelButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit sheet (re-uses the same form from parties_screen)
// ---------------------------------------------------------------------------

class _EditPartySheet extends ConsumerStatefulWidget {
  const _EditPartySheet({required this.existing, required this.onSave});

  final Party existing;
  final void Function(Party) onSave;

  @override
  ConsumerState<_EditPartySheet> createState() =>
      _EditPartySheetState();
}

class _EditPartySheetState extends ConsumerState<_EditPartySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _gstin;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late PartyType _type;

  Future<void> _pickFromContacts() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      setState(() {
        if (contact.displayName.isNotEmpty) _name.text = contact.displayName;
        if (contact.phones.isNotEmpty) {
          final raw =
              contact.phones.first.number.replaceAll(RegExp(r'[^\d]'), '');
          final phone = raw.length == 12 && raw.startsWith('91')
              ? raw.substring(2)
              : raw.length > 10
                  ? raw.substring(raw.length - 10)
                  : raw;
          _phone.text = phone;
        }
        if (contact.emails.isNotEmpty) {
          _email.text = contact.emails.first.address;
        }
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p.name);
    _phone = TextEditingController(text: p.phoneNumber ?? '');
    _email = TextEditingController(text: p.email ?? '');
    _gstin = TextEditingController(text: p.gstin ?? '');
    _address = TextEditingController(text: p.address ?? '');
    _notes = TextEditingController(text: p.notes ?? '');
    _type = p.partyType;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.base,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Edit Party',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // ── Pick from contacts ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickFromContacts,
                icon: const Icon(Icons.contacts_outlined, size: 18),
                label: const Text('Pick from Contacts'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: PartyType.values.map((t) {
                final selected = _type == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  prefixText: '+91 '),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: const InputDecoration(
                  labelText: 'GSTIN',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                  counterText: ''),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes_outlined)),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final updated = widget.existing.copyWith(
                    name: _name.text.trim(),
                    phoneNumber: _phone.text.trim().isEmpty
                        ? null
                        : _phone.text.trim(),
                    email: _email.text.trim().isEmpty
                        ? null
                        : _email.text.trim(),
                    gstin: _gstin.text.trim().isEmpty
                        ? null
                        : _gstin.text.trim(),
                    address: _address.text.trim().isEmpty
                        ? null
                        : _address.text.trim(),
                    partyType: _type,
                    notes: _notes.text.trim().isEmpty
                        ? null
                        : _notes.text.trim(),
                    updatedAt: DateTime.now(),
                  );
                  widget.onSave(updated);
                  Navigator.pop(context);
                },
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
