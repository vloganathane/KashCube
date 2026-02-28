import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../ledger/ledger_screen.dart';
import '../loans/loans_screen.dart';
import '../recurring/recurring_transactions_screen.dart';
import 'transactions_screen.dart';

/// Transactions hub — entry point for all money-movement screens.
class TransactionsHubScreen extends StatelessWidget {
  const TransactionsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HubSection(
            title: 'Activity',
            tiles: [
              _HubTile(
                icon: Icons.receipt_long_outlined,
                label: 'Transactions',
                subtitle: 'All income & expenses',
                color: const Color(0xFF1B5E20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TransactionsScreen(),
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.menu_book_outlined,
                label: 'Ledger',
                subtitle: 'Party-wise account book',
                color: const Color(0xFF006064),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LedgerScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Credit',
            tiles: [
              _HubTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Loans & Credits',
                subtitle: 'Lent, borrowed & udhar',
                color: const Color(0xFFE65100),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoansScreen(),
                  ),
                ),
              ),
              _HubTile(
                icon: Icons.event_repeat_outlined,
                label: 'Recurring',
                subtitle: 'Scheduled transactions',
                color: const Color(0xFF0D47A1),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecurringTransactionsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers (mirrors ContactsHubScreen for visual consistency)
// ---------------------------------------------------------------------------

class _HubSection extends StatelessWidget {
  const _HubSection({required this.title, required this.tiles});
  final String title;
  final List<_HubTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xs, bottom: AppSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colorScheme.outline,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i < tiles.length - 1)
                  Divider(
                    height: 1,
                    indent: AppSpacing.base + 40 + AppSpacing.base,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Icon(icon, color: color, size: AppSpacing.iconMd),
      ),
      title: Text(label,
          style: context.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colorScheme.outline)),
      trailing: Icon(Icons.chevron_right,
          color: context.colorScheme.outlineVariant),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
    );
  }
}
