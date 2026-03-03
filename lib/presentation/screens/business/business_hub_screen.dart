import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../providers/booking_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/report_provider.dart';
import '../bills/bills_and_payments_screen.dart';
import '../bookings/bookings_screen.dart';
import '../invoices/delivery_challans_screen.dart';
import '../invoices/invoices_screen.dart';
import '../invoices/item_catalog_screen.dart';
import '../reports/reports_screen.dart';

/// Business hub — top-level entry point for all business-related screens.
/// Accessible from the bottom nav "Business" tab.
class BusinessHubScreen extends ConsumerWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
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
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text = r.watch(catalogProvider).whenOrNull(
                              data: (list) =>
                                  '${list.length} item${list.length == 1 ? '' : 's'}',
                            ) ??
                        'Products & services';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
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
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final summary = r.watch(overdueInvoicesSummaryProvider);
                    final text = (summary != null && summary.count > 0)
                        ? '${summary.count} unpaid'
                            ' · ${CurrencyFormatter.formatCompact(summary.totalDue)} due'
                        : 'Raise & track invoices';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF0D47A1),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const InvoicesScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.local_shipping_outlined,
                label: 'Delivery Challans',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final summary = r.watch(challanSummaryProvider);
                    final text = summary.dispatched > 0
                        ? '${summary.dispatched} dispatched · ${summary.total} total'
                        : summary.total > 0
                            ? '${summary.total} challan${summary.total == 1 ? '' : 's'}'
                            : 'Goods dispatch documents';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF00838F),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DeliveryChallansScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.payments_outlined,
                label: 'Payables',
                subtitle: const _StaticSubtitle('Supplier & vendor dues'),
                color: const Color(0xFFE65100),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BillsAndPaymentsScreen(
                            billContext: 'business',
                          )),
                ),
              ),
              _HubTile(
                icon: Icons.calendar_month_outlined,
                label: 'Bookings',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final stats = r.watch(bookingMonthStatsProvider(now));
                    final text = stats.hasData
                        ? '${stats.confirmedCount + stats.pendingCount} upcoming'
                            ' · ${CurrencyFormatter.formatCompact(stats.completedRevenue)} earned'
                        : 'Appointments & services';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF4A148C),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BookingsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Insights',
            tiles: [
              _HubTile(
                icon: Icons.trending_up_outlined,
                label: 'Business Reports',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final text = r.watch(fyPnLProvider).whenOrNull(
                              data: (p) =>
                                  'Rev ${CurrencyFormatter.formatCompact(p.totalIncome)}'
                                  ' · Net ${CurrencyFormatter.formatCompact(p.netProfitLoss)} this FY',
                            ) ??
                        'Full fiscal year P&L';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF1565C0),
                onTap: () {
                  ref.read(reportPeriodModeProvider.notifier).state = 'this_fy';
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsScreen()),
                  );
                },
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
  final Widget subtitle;
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
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right,
          color: context.colorScheme.outlineVariant),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.xs),
    );
  }
}

class _StaticSubtitle extends StatelessWidget {
  const _StaticSubtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: context.textTheme.bodySmall
            ?.copyWith(color: context.colorScheme.outline));
  }
}


