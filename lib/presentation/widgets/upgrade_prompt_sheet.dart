import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/utils/adaptive_sheet.dart';

/// Action returned by [showUpgradePromptSheet].
enum UpgradePromptAction {
  /// User chose to share/export the document with the watermark.
  shareWithWatermark,

  /// User tapped "Upgrade" — caller should open the Upgrade Screen.
  upgrade,
}

/// Shows a bottom sheet asking the user whether to share a watermarked PDF
/// or to upgrade to Starter to remove it.
///
/// Never hard-blocks the flow — the user can always choose to share as-is.
///
/// Usage:
/// ```dart
/// final action = await showUpgradePromptSheet(context, featureName: 'invoice');
/// if (action == UpgradePromptAction.shareWithWatermark) {
///   await _sharePdf(showFreeWatermark: true);
/// } else if (action == UpgradePromptAction.upgrade) {
///   // push upgrade screen
/// }
/// ```
Future<UpgradePromptAction?> showUpgradePromptSheet(
  BuildContext context, {

  /// Short name of the document type shown in the sheet body (e.g. 'invoice').
  String featureName = 'document',
}) {
  return showAdaptiveSheet<UpgradePromptAction>(
    context,
    builder: (_) => _UpgradePromptContent(featureName: featureName),
  );
}

class _UpgradePromptContent extends StatelessWidget {
  const _UpgradePromptContent({required this.featureName});

  final String featureName;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final tt = context.textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium_outlined,
              color: cs.primary,
              size: AppSpacing.iconLg,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Title
          Text(
            'Remove the KashCube watermark',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Body
          Text(
            'Upgrade to Starter to share professional, watermark-free\n'
            '${featureName}s with your customers.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Feature bullets
          _FeatureBullet(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Watermark-free PDFs',
          ),
          const SizedBox(height: AppSpacing.sm),
          _FeatureBullet(
            icon: Icons.download_outlined,
            label: 'Export reports to CSV & PDF',
          ),
          const SizedBox(height: AppSpacing.sm),
          _FeatureBullet(
            icon: Icons.qr_code_outlined,
            label: 'UPI payment QR on invoices',
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Primary CTA — annual
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpgradePromptAction.upgrade),
              child: const Text('Upgrade to Starter — ₹499/year'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Secondary — share with watermark
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(UpgradePromptAction.shareWithWatermark),
              child: Text(
                'Share with Watermark',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Cancel guarantee note
          Text(
            'Cancel anytime. Your data stays readable forever.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: context.textTheme.bodyMedium),
      ],
    );
  }
}
