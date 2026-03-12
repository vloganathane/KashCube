import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../data/services/iap_service.dart';
import '../../providers/iap_provider.dart';
import '../../providers/settings_provider.dart';

/// Subscription upgrade screen — shows tier comparison and pricing.
///
/// CTA buttons trigger Google Play's in-app purchase flow via [IapService].
/// In debug builds, simulation chips allow switching tiers for QA without IAP.
class UpgradeScreen extends ConsumerStatefulWidget {
  const UpgradeScreen({super.key});

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends ConsumerState<UpgradeScreen> {
  /// Product ID currently being purchased — shows loading while Play UI is open.
  String? _purchasingProductId;

  Future<void> _purchase(String productId) async {
    final iapAsync = ref.read(iapServiceProvider);
    final iap = iapAsync.valueOrNull;
    if (iap == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Play Store billing is not available on this device.'),
          ),
        );
      }
      return;
    }

    setState(() => _purchasingProductId = productId);
    try {
      await iap.buySubscription(productId);
      // Purchase result arrives via the IapService stream listener;
      // tier will be updated automatically in [subscriptionTierProvider].
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _purchasingProductId = null);
    }
  }

  Future<void> _restorePurchases() async {
    final iap = ref.read(iapServiceProvider).valueOrNull;
    if (iap == null) return;
    await iap.restorePurchases();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchases restored')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTier = ref.watch(subscriptionTierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KashCube Plans'),
        actions: [
          TextButton(
            onPressed: _restorePurchases,
            child: const Text('Restore'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.lg,
        ),
        children: [
          _CurrentTierBanner(tier: currentTier),
          const SizedBox(height: AppSpacing.xl),

          _PricingCard(
            tier: SubscriptionTier.starter,
            monthlyPrice: '₹59',
            annualPrice: '₹499',
            annualProductId: KashCubeProducts.starterAnnual,
            monthlyProductId: KashCubeProducts.starterMonthly,
            annualSavingsPct: 30,
            currentTier: currentTier,
            purchasingProductId: _purchasingProductId,
            onPurchase: _purchase,
            features: const [
              'Watermark-free PDFs & documents',
              'UPI payment QR on invoices',
              'Export reports to CSV',
              '5 industry invoice templates',
              'Unlimited invoices, credits & bookings',
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _PricingCard(
            tier: SubscriptionTier.business,
            monthlyPrice: '₹129',
            annualPrice: '₹999',
            annualProductId: KashCubeProducts.businessAnnual,
            monthlyProductId: KashCubeProducts.businessMonthly,
            annualSavingsPct: 35,
            currentTier: currentTier,
            purchasingProductId: _purchasingProductId,
            onPurchase: _purchase,
            features: const [
              'Everything in Starter',
              'GSTR-1 JSON + Tally XML export',
              'Inventory with reorder alerts',
              'Staff payroll module',
              'Multi-device LAN sync',
            ],
            highlight: true,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Cancel guarantee
          _GuaranteeBanner(),
          const SizedBox(height: AppSpacing.xl),

          // Free tier feature recap
          _FreeTierNote(),

          // Debug-only simulation panel
          if (kDebugMode) ...[
            const SizedBox(height: AppSpacing.xxl),
            _DebugTierPanel(currentTier: currentTier),
          ],
        ],
      ),
    );
  }
}

// ── Current tier banner ──────────────────────────────────────────────────────

class _CurrentTierBanner extends StatelessWidget {
  const _CurrentTierBanner({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final isPaid = tier.isStarter;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: isPaid ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            isPaid ? Icons.workspace_premium : Icons.lock_open_outlined,
            color: isPaid ? cs.primary : cs.onSurfaceVariant,
            size: AppSpacing.iconLg,
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current plan: ${tier.displayName}',
                style: context.textTheme.titleMedium?.copyWith(
                  color: isPaid ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isPaid)
                Text(
                  'Upgrade to unlock professional features',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pricing card ─────────────────────────────────────────────────────────────

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.tier,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.annualProductId,
    required this.monthlyProductId,
    required this.annualSavingsPct,
    required this.currentTier,
    required this.purchasingProductId,
    required this.onPurchase,
    required this.features,
    this.highlight = false,
  });

  final SubscriptionTier tier;
  final String monthlyPrice;
  final String annualPrice;
  final String annualProductId;
  final String monthlyProductId;
  final int annualSavingsPct;
  final SubscriptionTier currentTier;
  /// The product ID currently being purchased (null = none in-flight).
  final String? purchasingProductId;
  final void Function(String productId) onPurchase;
  final List<String> features;
  final bool highlight;

  bool get _isActive => currentTier == tier;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

    final buyingAnnual = purchasingProductId == annualProductId;
    final buyingMonthly = purchasingProductId == monthlyProductId;
    final anyBuying = purchasingProductId != null;

    return Container(
      decoration: BoxDecoration(
        color: highlight ? cs.primaryContainer.withAlpha(80) : cs.surface,
        border: Border.all(
          color: _isActive
              ? cs.primary
              : highlight
                  ? cs.primary.withAlpha(120)
                  : cs.outlineVariant,
          width: _isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tier.displayName,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (_isActive)
                Chip(
                  label: const Text('Active'),
                  backgroundColor: cs.primaryContainer,
                  labelStyle: TextStyle(
                    color: cs.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Annual price (primary CTA price)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                annualPrice,
                style: tt.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              Text('/year', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'Save $annualSavingsPct%',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'or $monthlyPrice/month',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),

          // Feature list
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: cs.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(f, style: tt.bodyMedium),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.md),

          // CTA buttons — shown only if this tier is not already active
          if (!_isActive) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: anyBuying ? null : () => onPurchase(annualProductId),
                child: buyingAnnual
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Get $annualPrice/year'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: anyBuying ? null : () => onPurchase(monthlyProductId),
                child: buyingMonthly
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Try $monthlyPrice/month'),
              ),
            ),
          ],

          // GST note
          const SizedBox(height: AppSpacing.sm),
          Text(
            '18% GST applicable · ITC claimable for GST-registered businesses',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Guarantee banner ─────────────────────────────────────────────────────────

class _GuaranteeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: cs.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You own the data. We own the software.',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Cancel anytime. Your data stays fully readable forever — '
                  'even on the Free plan. We never hold your data hostage.',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Free tier note ───────────────────────────────────────────────────────────

class _FreeTierNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Free plan includes: unlimited transactions, expense tracking, '
      'credits (udhar), invoices with watermark, cash-flow reports, '
      'encrypted backups, and more — forever free.',
      style: context.textTheme.bodySmall?.copyWith(
        color: context.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ── Debug-only tier simulation panel ─────────────────────────────────────────

class _DebugTierPanel extends ConsumerWidget {
  const _DebugTierPanel({required this.currentTier});

  final SubscriptionTier currentTier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEBUG — Simulate Tier',
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: SubscriptionTier.values.map((tier) {
            final isActive = currentTier == tier;
            return ActionChip(
              label: Text(tier.displayName),
              backgroundColor: isActive
                  ? context.colorScheme.errorContainer
                  : null,
              labelStyle: isActive
                  ? TextStyle(color: context.colorScheme.onErrorContainer)
                  : null,
              onPressed: () => ref
                  .read(subscriptionTierProvider.notifier)
                  .setTier(tier),
            );
          }).toList(),
        ),
      ],
    );
  }
}
