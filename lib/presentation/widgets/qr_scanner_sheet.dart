/// A bottom sheet that opens the device camera to scan a QR code.
/// Parses vCard text and returns a map of contact fields.
/// No network calls — scanning and parsing are 100% on-device.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/vcard_builder.dart' show parseVCard;
import '../../core/utils/deep_link_vcard.dart' show decodeVCardUrl;

/// Opens the QR scanner as a modal bottom sheet.
///
/// Returns a [Map<String, String?>] with recognized vCard fields when a
/// vCard QR is scanned, or `null` if the user cancels.
///
/// Returned map keys (all nullable):
///   `name`, `org`, `title`, `phone`, `email`,
///   `address`, `city`, `state`, `pincode`,
///   `website`, `whatsapp`, `linkedin`, `instagram`, `gstin`
Future<Map<String, String?>?> showQrScannerSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, String?>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QrScannerSheet(),
  );
}

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet();

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _hasScanned = true;
        _controller.stop();
        final parsed = _tryParseVCard(raw);
        if (mounted) Navigator.pop(context, parsed);
        return;
      }
    }
  }

  /// Try parsing the raw string as a vCard.
  /// Handles three formats:
  ///   1. Raw vCard text (BEGIN:VCARD ...)
  ///   2. Kash Cube App Link URL (https://kashcube.com/c?v=base64vcard)
  ///   3. Anything else — returned as {name: raw} so callers can still use it.
  Map<String, String?> _tryParseVCard(String raw) {
    final upper = raw.trimLeft().toUpperCase();
    // Format 1: raw vCard
    if (upper.startsWith('BEGIN:VCARD')) {
      return parseVCard(raw);
    }
    // Format 2: Kash Cube URL-encoded vCard
    final decoded = decodeVCardUrl(raw);
    if (decoded != null) {
      return parseVCard(decoded);
    }
    // Format 3: unrecognised — pass raw value through
    return {'name': raw};
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  'Scan Contact QR',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
          ),

          // ── Camera viewport ───────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base, 0, AppSpacing.base, AppSpacing.base),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                    // Scanner overlay — simple corner-bracket crosshair
                    _ScannerOverlay(),
                  ],
                ),
              ),
            ),
          ),

          // ── Hint text ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(
                bottom: AppSpacing.xxl, left: AppSpacing.xl, right: AppSpacing.xl),
            child: Text(
              'Point the camera at a KashCube contact QR or any vCard QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scanner overlay (corner brackets) ───────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    // Darken everything
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);

    // Clear the central square
    const fraction = 0.60;
    final boxSize = size.width * fraction;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, boxSize, boxSize), const Radius.circular(12)),
      clearPaint,
    );
    canvas.restore();

    // Corner brackets
    final bracketPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bracketLen = 20.0;
    final right = left + boxSize;
    final bottom = top + boxSize;

    void bracket(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x + dx * bracketLen, y), Offset(x, y), bracketPaint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * bracketLen), bracketPaint);
    }

    bracket(left, top, 1, 1);
    bracket(right, top, -1, 1);
    bracket(left, bottom, 1, -1);
    bracket(right, bottom, -1, -1);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Barcode scanner (EAN / UPC / Code128) ──────────────────────────────────

/// Opens the device camera to scan an EAN / UPC / Code128 product barcode.
///
/// Returns the raw barcode string (e.g. `"8901234567890"`) when scanned,
/// or `null` if the user cancels. No network calls — fully on-device.
Future<String?> showBarcodeScannerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BarcodeScannerSheet(),
  );
}

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet();

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf,
    ],
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _hasScanned = true;
        _controller.stop();
        if (mounted) Navigator.pop(context, raw);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text(
                  'Scan Product Barcode',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base, 0, AppSpacing.base, AppSpacing.base),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                    _ScannerOverlay(),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
                bottom: AppSpacing.xxl,
                left: AppSpacing.xl,
                right: AppSpacing.xl),
            child: Text(
              'Point the camera at an EAN, UPC, or Code128 barcode.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
