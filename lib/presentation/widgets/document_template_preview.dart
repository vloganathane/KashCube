import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/document_template_record.dart';
import '../providers/template_preview_provider.dart';

/// A PDF template thumbnail that renders in two passes:
///
/// 1. **Instant** — a Flutter-widget mock (pixel stubs, same aspect ratio and
///    accent colour) shown immediately while the real render is in-flight.
/// 2. **Async** — a genuine rasterised PDF page (produced via a background
///    isolate + [Printing.raster]) shown once ready, replacing the mock.
///
/// The rasterised result is cached by Riverpod ([keepAlive]) so scrolling the
/// template list never triggers a re-render.
///
/// Usage:
/// ```dart
/// // List thumbnail (44 px, low DPI)
/// DocumentTemplatePreview(record: record, width: 44, dpi: 72)
///
/// // Builder live preview (180 px, higher DPI)
/// DocumentTemplatePreview(record: _toRecord(), width: 180, dpi: 150)
/// ```
class DocumentTemplatePreview extends ConsumerWidget {
  const DocumentTemplatePreview({
    super.key,
    required this.record,
    this.width,
    this.dpi = 96,
  });

  final DocumentTemplateRecord record;

  /// Maximum width for the preview card. If null, fills available width.
  final double? width;

  /// Resolution used when rasterising the PDF page.
  ///
  /// Use 72 for tiny list thumbnails, 150 for the builder live preview.
  final int dpi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentHex = record.accentColorHex.replaceFirst('#', '');
    final accentValue = int.tryParse(accentHex, radix: 16) ?? 0x1B5E20;
    final accent = Color(0xFF000000 | accentValue);

    final isThermal = record.isThermal;
    final isBanner = record.headerStyleName == 'banner';
    final ratio = _aspectRatio(record.pageSizeName);

    // Watch the async real render. Returns null while loading / on error.
    final imageBytes =
        ref.watch(templatePreviewProvider(templatePreviewKey(record, dpi))).valueOrNull;

    // Phase 1: instant Flutter mock skeleton.
    // Phase 2: replaced by the real PDF image once rasterised.
    Widget content = imageBytes != null
        ? Image.memory(
            imageBytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          )
        : (isThermal
            ? _ThermalMock(accent: accent)
            : _StandardMock(
                accent: accent,
                isBanner: isBanner,
                showLogo: record.showLogo,
              ));

    Widget preview = AspectRatio(
      aspectRatio: ratio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (width != null) {
      preview = SizedBox(width: width, child: preview);
    }
    return preview;
  }

  static double _aspectRatio(String pageSizeName) {
    switch (pageSizeName) {
      case 'a4':
      case 'a5':
        return 1 / 1.4142; // ISO A series
      case 'letter':
        return 8.5 / 11;
      case 'thermal58':
        return 58 / 200;
      case 'thermal80':
        return 80 / 200;
      default:
        return 1 / 1.4142;
    }
  }
}

// ─── Standard A4 / A5 / Letter mock ──────────────────────────────────────────

/// Design dimensions: 210×297 (matches A4 aspect ratio 1:√2).
/// All pixel values inside are chosen at this "canvas" size; FittedBox
/// scales the whole thing to whatever container size the AspectRatio gives.
class _StandardMock extends StatelessWidget {
  const _StandardMock({
    required this.accent,
    required this.isBanner,
    required this.showLogo,
  });

  final Color accent;
  final bool isBanner;
  final bool showLogo;

  static const _kW = 210.0;
  static const _kH = 297.0;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 12);

    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: _kW,
        height: _kH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            if (isBanner)
              _BannerHeader(accent: accent, showLogo: showLogo)
            else
              _MinimalHeader(accent: accent, showLogo: showLogo),

            const SizedBox(height: 10),

            // ── Party rows ────────────────────────────────────────────────
            Padding(
              padding: pad,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Stub(width: 36, height: 5, color: const Color(0xFFBDBDBD)),
                        const SizedBox(height: 4),
                        _Stub(width: 60, height: 5, color: const Color(0xFFE0E0E0)),
                        const SizedBox(height: 3),
                        _Stub(width: 48, height: 5, color: const Color(0xFFE0E0E0)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Stub(width: 36, height: 5, color: const Color(0xFFBDBDBD)),
                        const SizedBox(height: 4),
                        _Stub(width: 66, height: 5, color: const Color(0xFFE0E0E0)),
                        const SizedBox(height: 3),
                        _Stub(width: 54, height: 5, color: const Color(0xFFE0E0E0)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Items table header ─────────────────────────────────────────
            Container(
              margin: pad,
              height: 8,
              color: accent.withAlpha(30),
            ),

            const SizedBox(height: 4),

            // ── Item rows ─────────────────────────────────────────────────
            for (int i = 0; i < 4; i++) ...[
              Padding(
                padding: pad,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _Stub(
                        height: 5,
                        color: const Color(0xFFE0E0E0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _Stub(
                        height: 5,
                        color: const Color(0xFFE0E0E0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            const Spacer(),

            // ── Totals ────────────────────────────────────────────────────
            Padding(
              padding: pad,
              child: Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Stub(height: 5, color: const Color(0xFFE0E0E0)),
                        const SizedBox(height: 4),
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(220),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Footer strip ──────────────────────────────────────────────
            Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Stub(width: 100, height: 5, color: const Color(0xFFE0E0E0)),
                  const SizedBox(height: 4),
                  _Stub(width: 80, height: 5, color: const Color(0xFFE0E0E0)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Thermal mock ─────────────────────────────────────────────────────────────

class _ThermalMock extends StatelessWidget {
  const _ThermalMock({required this.accent});
  final Color accent;

  /// Design canvas: 160 wide × 400 tall (tall receipt proportions).
  /// FittedBox scales this down to the AspectRatio container without overflow.
  static const _kW = 160.0;
  static const _kH = 400.0;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 12);

    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: _kW,
        height: _kH,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Business name
              Center(
                child: _Stub(width: 80, height: 8, color: const Color(0xFF212121)),
              ),
              const SizedBox(height: 6),
              Center(
                child: _Stub(width: 60, height: 6, color: const Color(0xFFBDBDBD)),
              ),
              const SizedBox(height: 8),
              _DashedLine(color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 8),

              // Meta
              Padding(
                padding: pad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stub(width: 90, height: 6, color: const Color(0xFFE0E0E0)),
                    const SizedBox(height: 5),
                    _Stub(width: 70, height: 6, color: const Color(0xFFE0E0E0)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _DashedLine(color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 8),

              // Items
              for (int i = 0; i < 3; i++) ...[
                Padding(
                  padding: pad,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Stub(
                        width: i.isEven ? 80 : 60,
                        height: 6,
                        color: const Color(0xFFE0E0E0),
                      ),
                      _Stub(width: 36, height: 6, color: const Color(0xFFE0E0E0)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],

              _DashedLine(color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 6),

              // Total
              Padding(
                padding: pad,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Stub(width: 44, height: 8, color: const Color(0xFF212121)),
                    _Stub(width: 48, height: 8, color: accent),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _DashedLine(color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 12),

              // Footer
              Center(
                child: _Stub(width: 70, height: 6, color: const Color(0xFFBDBDBD)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Banner header ────────────────────────────────────────────────────────────

class _BannerHeader extends StatelessWidget {
  const _BannerHeader({required this.accent, required this.showLogo});
  final Color accent;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      color: accent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          if (showLogo) ...[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(60),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.85,
                  child: _Stub(height: 4, color: Colors.white.withAlpha(230)),
                ),
                const SizedBox(height: 3),
                FractionallySizedBox(
                  widthFactor: 0.60,
                  child: _Stub(height: 3, color: Colors.white.withAlpha(160)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.75,
                  child: _Stub(height: 4, color: Colors.white.withAlpha(230)),
                ),
                const SizedBox(height: 2),
                FractionallySizedBox(
                  widthFactor: 0.55,
                  child: _Stub(height: 3, color: Colors.white.withAlpha(160)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Minimal header ───────────────────────────────────────────────────────────

class _MinimalHeader extends StatelessWidget {
  const _MinimalHeader({required this.accent, required this.showLogo});
  final Color accent;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              if (showLogo)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(40),
                    border: Border.all(color: accent.withAlpha(80)),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.85,
                      child: _Stub(height: 4, color: const Color(0xFF212121)),
                    ),
                    const SizedBox(height: 2),
                    FractionallySizedBox(
                      widthFactor: 0.60,
                      child: _Stub(height: 3, color: const Color(0xFFBDBDBD)),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.75,
                      child: _Stub(height: 4, color: accent),
                    ),
                    const SizedBox(height: 2),
                    FractionallySizedBox(
                      widthFactor: 0.55,
                      child: _Stub(height: 3, color: const Color(0xFFBDBDBD)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(height: 1.5, color: accent),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final width = constraints.maxWidth;
      const dashWidth = 3.0;
      const gap = 2.0;
      final count = (width / (dashWidth + gap)).floor();
      return Row(
        children: List.generate(
          count,
          (_) => Container(
            width: dashWidth,
            height: 1,
            margin: const EdgeInsets.only(right: gap),
            color: color,
          ),
        ),
      );
    });
  }
}

/// A solid rectangle used as a text-stub placeholder.
///
/// If [width] is null the stub fills its parent's available width
/// (use inside [Expanded] or [FractionallySizedBox]).
class _Stub extends StatelessWidget {
  const _Stub({
    this.width,
    required this.height,
    required this.color,
  });

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
