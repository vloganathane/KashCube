import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/subscription_tier.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../providers/settings_provider.dart';

/// Subscription upgrade screen — shows tier comparison and pricing.
///
/// In the current build, purchase buttons are placeholders; real IAP
/// wiring (via `in_app_purchase`) ships in Sprint 3.
///
/// In debug builds only, simulation buttons allow switching tiers for QA.
class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTier = ref.watch(subscriptionTierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KashCube Plans'),
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
            annualSavingsPct: 30,
            currentTier: currentTier,
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
            annualSavingsPct: 35,
            currentTier: currentTier,
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
    required this.annualSavingsPct,
    required this.currentTier,
    required this.features,
    this.highlight = false,
  });

  final SubscriptionTier tier;
  final String monthlyPrice;
  final String annualPrice;
  final int annualSavingsPct;
  final SubscriptionTier currentTier;
  final List<String> features;
  final bool highlight;

  bool get _isActive => currentTier == tier;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

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

          // CTA buttons
          if (!_isActive) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _showComingSoon(context),
                child: Text('Get $annualPrice/year'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showComingSoon(context),
                child: Text('Try $monthlyPrice/month'),
              ),
            ),
          ],

          // GST note for business users
          const SizedBox(height: AppSpacing.sm),
          Text(
            '18% GST applicable · ITC claimable for GST-registered businesses',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('In-app purchase coming soon — stay tuned!'),
        duration: Duration(seconds: 2),
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
