/// Dialog that displays a vCard as a QR code and offers Share / Copy actions.
/// No network calls — QR is generated fully on-device.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../../core/constants/app_spacing.dart';
import '../../core/utils/deep_link_vcard.dart';

/// Opens a dialog displaying [vcard] as a scannable QR code.
///
/// [displayName] is shown as the card title.
/// [subtitle] (optional) is the company/phone shown below the name.
Future<void> showVCardQrDialog(
  BuildContext context, {
  required String vcard,
  required String displayName,
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (_) => _VCardQrDialog(
      vcard: vcard,
      displayName: displayName,
      subtitle: subtitle,
    ),
  );
}

class _VCardQrDialog extends StatefulWidget {
  const _VCardQrDialog({
    required this.vcard,
    required this.displayName,
    this.subtitle,
  });

  final String vcard;
  final String displayName;
  final String? subtitle;

  @override
  State<_VCardQrDialog> createState() => _VCardQrDialogState();
}

class _VCardQrDialogState extends State<_VCardQrDialog> {
  final _qrKey = GlobalKey();
  bool _sharing = false;

  Future<Uint8List?> _captureQrImage() async {
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareQr() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _captureQrImage();
      if (bytes == null) {
        _showError('Could not render QR image');
        return;
      }
      final dir = await getTemporaryDirectory();
      final safeName = widget.displayName
          .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_')
          .trim();
      final file = File('${dir.path}/qr_${safeName}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: '${widget.displayName} — Contact QR',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copyVCard() async {
    await Clipboard.setData(ClipboardData(text: widget.vcard));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('vCard text copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    widget.displayName.isNotEmpty
                        ? widget.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null &&
                          widget.subtitle!.isNotEmpty)
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── QR Code ───────────────────────────────────────────────────
            RepaintBoundary(
              key: _qrKey,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white, // Always white for QR readability
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: QrImageView(
                  // Encode as a Kash Cube App Link URL so:
                  //   • Any installed Kash Cube opens the Add Party screen
                  //   • Non-users see the landing page with "Get Kash Cube"
                  //   • "Copy vCard" (below) still copies raw vCard for
                  //     contacts apps
                  data: encodeVCardUrl(widget.vcard),
                  version: QrVersions.auto,
                  size: 220,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            Text(
              'Scan with Kash Cube or any QR reader',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Action Buttons ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy vCard'),
                    onPressed: _copyVCard,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share QR'),
                    onPressed: _sharing ? null : _shareQr,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
