import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/ewb_transport_details.dart';
import '../../../data/services/eway_bill_service.dart';

/// Full-screen e-Way Bill preview.
///
/// Shows:
///  - Transport summary card
///  - Validity chip
///  - Collapsible raw JSON
///  - "Share JSON" button
///  - "Open e-Way Bill Portal" button (url_launcher → ewaybillgst.gov.in)
class EwbPreviewScreen extends StatefulWidget {
  const EwbPreviewScreen({
    super.key,
    required this.result,
    required this.docNo,
    required this.transport,
  });

  final EwbExportResult result;
  /// Document number shown in the title bar and share subject
  /// (e.g. invoice number or challan number).
  final String docNo;
  /// Transport details used to populate the transport card.
  final EwbTransportDetails transport;

  @override
  State<EwbPreviewScreen> createState() => _EwbPreviewScreenState();
}

class _EwbPreviewScreenState extends State<EwbPreviewScreen> {
  bool _jsonExpanded = false;
  bool _sharing = false;

  static const _portalUrl = 'https://ewaybillgst.gov.in';

  String get _validityLabel {
    final days = widget.result.validUntil
        .difference(widget.result.generatedAt)
        .inDays;
    final until = _fmt(widget.result.validUntil);
    return 'Valid $days day${days == 1 ? '' : 's'} · till $until';
  }

  String _fmt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await Share.shareXFiles(
        [XFile(widget.result.file.path, mimeType: 'application/json')],
        subject: 'e-Way Bill — ${widget.docNo}',
        text: 'e-Way Bill JSON for ${widget.docNo}',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openPortal() async {
    final uri = Uri.parse(_portalUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transport = widget.transport;
    final result = widget.result;
    final isExpired = !result.isValid;

    return Scaffold(
      appBar: AppBar(
        title: Text('e-Way Bill · ${widget.docNo}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy JSON',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.jsonContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // ── Validity banner ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isExpired
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isExpired
                      ? Icons.warning_amber_rounded
                      : Icons.verified_outlined,
                  size: 20,
                  color: isExpired
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isExpired
                        ? 'EWB expired on ${_fmt(result.validUntil)}'
                        : _validityLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isExpired
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Transport details card ─────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Transport Details',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  _DetailRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Mode',
                    value: _modeName(transport.mode),
                  ),
                  if (transport.vehicleNo != null)
                    _DetailRow(
                      icon: Icons.directions_car_outlined,
                      label: 'Vehicle',
                      value: transport.vehicleNo!,
                    ),
                  if (transport.transporterName != null)
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Transporter',
                      value: transport.transporterName!,
                    ),
                  if (transport.transporterGstin != null)
                    _DetailRow(
                      icon: Icons.badge_outlined,
                      label: 'GSTIN',
                      value: transport.transporterGstin!,
                    ),
                  if (transport.distanceKm != null)
                    _DetailRow(
                      icon: Icons.straighten_outlined,
                      label: 'Distance',
                      value: '${transport.distanceKm} km',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Raw JSON (collapsible) ────────────────────────────────────────
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.code),
              title: const Text('Raw JSON'),
              subtitle: Text(
                result.file.path.split('/').last,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              initiallyExpanded: _jsonExpanded,
              onExpansionChanged: (v) => setState(() => _jsonExpanded = v),
              children: [
                const Divider(height: 1),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result.jsonContent,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Actions ───────────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            label: const Text('Share JSON'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _openPortal,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open e-Way Bill Portal'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _portalUrl,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  static String _modeName(String code) => switch (code) {
        '1' => 'Road',
        '2' => 'Rail',
        '3' => 'Air',
        '4' => 'Ship / Water',
        _ => code,
      };
}

// ── Helper ────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text('$label  ',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
