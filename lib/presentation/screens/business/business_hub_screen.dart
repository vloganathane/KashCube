import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../bills/bills_and_payments_screen.dart';
import '../bookings/bookings_screen.dart';
import '../invoices/invoices_screen.dart';
import '../invoices/item_catalog_screen.dart';

/// Business hub — top-level entry point for all business-related screens.
/// Accessible from the bottom nav "Business" tab.
class BusinessHubScreen extends StatelessWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HubSection(
            title: 'Manage',
            tiles: [
              _HubTile(
                icon: Icons.inventory_2_outlined,
                label: 'Item Catalog',
                subtitle: 'Products & services',
                color: const Color(0xFF1B5E20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ItemCatalogScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Documents',
            tiles: [
              _HubTile(
                icon: Icons.receipt_long_outlined,
                label: 'Invoices & Quotes',
                subtitle: 'Raise & track invoices',
                color: const Color(0xFF0D47A1),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const InvoicesScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.payments_outlined,
                label: 'Bills & Payments',
                subtitle: 'Track what you owe',
                color: const Color(0xFFE65100),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BillsAndPaymentsScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.calendar_month_outlined,
                label: 'Bookings',
                subtitle: 'Appointments & services',
                color: const Color(0xFF4A148C),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BookingsScreen()),
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
// Internal widgets
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


