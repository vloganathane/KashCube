import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../providers/booking_provider.dart';
import '../../providers/business_provider.dart';
import '../../providers/credit_provider.dart';
import '../../providers/delivery_challan_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/report_provider.dart';
import '../../providers/scheduled_payment_provider.dart';
import '../../providers/settings_provider.dart';
import '../bills/bills_and_payments_screen.dart';
import '../bookings/bookings_screen.dart';
import '../gst/gstr1_screen.dart';
import '../gst/gstr3b_offset_screen.dart';
import '../gst/purchase_bills_screen.dart';
import '../inventory/inventory_screen.dart';
import '../invoices/delivery_challans_screen.dart';
import '../invoices/invoices_screen.dart';
import '../invoices/item_catalog_screen.dart';
import '../ledger/credits_screen.dart';
import '../ledger/ledger_screen.dart';
import '../loans/loans_screen.dart';
import '../reports/budget_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/businesses_screen.dart';
import '../staff/staff_list_screen.dart';
import 'global_document_ledger_screen.dart';
import 'tally_export_screen.dart';

/// Business hub — top-level entry point for all business-related screens.
/// When business mode is OFF, renders the Personal Finance hub instead.
/// Accessible from the bottom nav "Business" tab.
class BusinessHubScreen extends ConsumerWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusiness = ref.watch(businessModeProvider);
    return isBusiness
        ? const _BusinessHub()
        : const _PersonalFinanceHub();
  }
}

// ---------------------------------------------------------------------------
// Personal Finance Hub (shown when business mode is OFF)
// ---------------------------------------------------------------------------

class _PersonalFinanceHub extends ConsumerWidget {
  const _PersonalFinanceHub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kashColors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.storefront_outlined, size: 16),
            label: const Text('Enable Business'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BusinessesScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _HubSection(
            title: 'Credit & Loans',
            tiles: [
              _HubTile(
                icon: Icons.currency_rupee_outlined,
                label: 'Dues',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final given =
                        r.watch(totalCreditsPendingGivenProvider).valueOrNull ?? 0.0;
                    final text = given > 0
                        ? '${CurrencyFormatter.formatCompact(given)} to collect'
                        : 'Track who owes whom';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: colors.credit,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreditsScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.handshake_outlined,
                label: 'Loans',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final lent =
                        r.watch(totalPendingLentProvider).valueOrNull ?? 0.0;
                    final text = lent > 0
                        ? '${CurrencyFormatter.formatCompact(lent)} lent out'
                        : 'Formal loans with EMI';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF1B5E20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoansScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.people_outline,
                label: 'Ledger',
                subtitle: const _StaticSubtitle('Party-wise transaction history'),
                color: const Color(0xFF37474F),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LedgerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Bills & Payments',
            tiles: [
              _HubTile(
                icon: Icons.event_repeat_outlined,
                label: 'Bills & Subscriptions',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final monthly =
                        r.watch(totalMonthlyScheduledExpenseProvider).valueOrNull ?? 0.0;
                    final text = monthly > 0
                        ? '${CurrencyFormatter.formatCompact(monthly)}/month'
                        : 'Rent, EMIs, subscriptions';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFFE65100),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const BillsAndPaymentsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _HubSection(
            title: 'Insights',
            tiles: [
              _HubTile(
                icon: Icons.bar_chart_outlined,
                label: 'Budget',
                subtitle: const _StaticSubtitle('Monthly spending limits'),
                color: const Color(0xFF6A1B9A),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BudgetScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.trending_up_outlined,
                label: 'Reports',
                subtitle: const _StaticSubtitle('Income, expenses & trends'),
                color: const Color(0xFF1565C0),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          // ── Upgrade nudge ────────────────────────────────────────────────
          Card(
            color: context.colorScheme.primaryContainer.withValues(alpha: 0.5),
            child: ListTile(
              leading: Icon(Icons.storefront_outlined,
                  color: context.colorScheme.primary),
              title: const Text('Running a business?'),
              subtitle: const Text(
                'Enable business mode for invoices, GST, item catalog & more.',
              ),
              trailing: Icon(Icons.arrow_forward_ios,
                  size: 14,
                  color: context.colorScheme.primary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BusinessesScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Business Hub (shown when business mode is ON)
// ---------------------------------------------------------------------------

class _BusinessHub extends ConsumerWidget {
  const _BusinessHub();

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
              _HubTile(
                icon: Icons.warehouse_outlined,
                label: 'Inventory',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final activeId = r.watch(activeBusinessProvider)?.id;
                    final count = r.watch(lowStockCountProvider(activeId));
                    final text = count > 0
                        ? '$count low-stock alert${count > 1 ? 's' : ''}'
                        : 'Stock levels & movements';
                    return Text(
                      text,
                      style: ctx.textTheme.bodySmall?.copyWith(
                        color: count > 0
                            ? ctx.kashColors.expense
                            : ctx.colorScheme.outline,
                      ),
                    );
                  },
                ),
                color: const Color(0xFF2E7D32),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const InventoryScreen()),
                ),
              ),
              // Staff & Payroll
              _HubTile(
                icon: Icons.badge_outlined,
                label: 'Staff & Payroll',
                subtitle: const _StaticSubtitle('Employees, salary & HR'),
                color: const Color(0xFF1565C0),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StaffListScreen()),
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
                icon: Icons.receipt_long_outlined,
                label: 'Purchase Bills',
                subtitle: const _StaticSubtitle('Vendor invoices, RCM & ITC'),
                color: const Color(0xFF1565C0),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const PurchaseBillsScreen()),
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
              _HubTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Party Doc Ledger',
                subtitle: Consumer(
                  builder: (ctx, r, _) {
                    final summary = r.watch(overdueInvoicesSummaryProvider);
                    final text = (summary != null && summary.totalDue > 0)
                        ? '${CurrencyFormatter.formatCompact(summary.totalDue)} outstanding'
                        : 'Docs grouped by party';
                    return Text(text,
                        style: ctx.textTheme.bodySmall
                            ?.copyWith(color: ctx.colorScheme.outline));
                  },
                ),
                color: const Color(0xFF37474F),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const GlobalDocumentLedgerScreen()),
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
              _HubTile(
                icon: Icons.receipt_outlined,
                label: 'GST Returns (GSTR-1)',
                subtitle: const _StaticSubtitle(
                    'Generate workbook CSV + PDF summary for your CA'),
                color: const Color(0xFF006064),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const Gstr1Screen()),
                ),
              ),
              _HubTile(
                icon: Icons.balance_outlined,
                label: 'GSTR-3B Offset Summary',
                subtitle: const _StaticSubtitle(
                    'Compute ITC offset and cash required to file'),
                color: const Color(0xFF4E342E),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const Gstr3bOffsetScreen()),
                ),
              ),
              _HubTile(
                icon: Icons.import_export_outlined,
                label: 'Tally XML Export',
                subtitle: const _StaticSubtitle(
                    'Export transactions for Tally ERP import'),
                color: const Color(0xFF37474F),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TallyExportScreen()),
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


