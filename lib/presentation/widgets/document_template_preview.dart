import 'package:flutter/material.dart';

import '../../data/models/document_template_record.dart';

/// A zero-async, pixel-level mock of a PDF document, used for instant preview
/// in the template builder screen.
///
/// Renders using plain Flutter widgets, no PDF generation required.
///
/// Usage:
/// ```dart
/// DocumentTemplatePreview(record: record, width: 260)
/// ```
class DocumentTemplatePreview extends StatelessWidget {
  const DocumentTemplatePreview({
    super.key,
    required this.record,
    this.width,
  });

  final DocumentTemplateRecord record;

  /// Maximum width for the preview card. If null, the widget fills available
  /// width respecting the aspect ratio.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final accentHex = record.accentColorHex.replaceFirst('#', '');
    final accentValue = int.tryParse(accentHex, radix: 16) ?? 0x1B5E20;
    final accent = Color(0xFF000000 | accentValue);

    final isThermal = record.isThermal;
    final isBanner = record.headerStyleName == 'banner';

    // Aspect ratio: width / height
    final ratio = _aspectRatio(record.pageSizeName);

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
        child: isThermal
            ? _ThermalMock(accent: accent)
            : _StandardMock(
                accent: accent,
                isBanner: isBanner,
                showLogo: record.showLogo,
              ),
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

class _StandardMock extends StatelessWidget {
  const _StandardMock({
    required this.accent,
    required this.isBanner,
    required this.showLogo,
  });

  final Color accent;
  final bool isBanner;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    const stub = _Stub.short;
    const stubMed = _Stub.medium;
    const pad = EdgeInsets.symmetric(horizontal: 6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        if (isBanner)
          _BannerHeader(accent: accent, showLogo: showLogo)
        else
          _MinimalHeader(accent: accent, showLogo: showLogo),

        const SizedBox(height: 4),

        // ── Party rows ───────────────────────────────────────────────────────
        Padding(
          padding: pad,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stub(width: 26, height: 3, color: const Color(0xFFBDBDBD)),
                    const SizedBox(height: 2),
                    _Stub(width: 40, height: 3, color: const Color(0xFFE0E0E0)),
                    const SizedBox(height: 1),
                    _Stub(width: 32, height: 3, color: const Color(0xFFE0E0E0)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stub(width: 26, height: 3, color: const Color(0xFFBDBDBD)),
                    const SizedBox(height: 2),
                    _Stub(width: 44, height: 3, color: const Color(0xFFE0E0E0)),
                    const SizedBox(height: 1),
                    _Stub(width: 36, height: 3, color: const Color(0xFFE0E0E0)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // ── Items table header ───────────────────────────────────────────────
        Container(
          margin: pad,
          height: 5,
          color: accent.withAlpha(30),
        ),

        const SizedBox(height: 2),

        // ── Item rows ────────────────────────────────────────────────────────
        for (int i = 0; i < 4; i++) ...[
          Padding(
            padding: pad,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _Stub(
                    width: i.isEven ? 55 : 45,
                    height: 3,
                    color: const Color(0xFFE0E0E0),
                  ),
                ),
                _Stub(
                  width: 22,
                  height: 3,
                  color: const Color(0xFFE0E0E0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
        ],

        const Spacer(),

        // ── Totals ───────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(6, 0, 6, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  stubMed,
                  const SizedBox(height: 2),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(220),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // ── Footer strip ─────────────────────────────────────────────────────
        Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [stub, const SizedBox(height: 2), stub],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─── Thermal mock ─────────────────────────────────────────────────────────────

class _ThermalMock extends StatelessWidget {
  const _ThermalMock({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 4);
    const ts = _Stub.short;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Business name
          Center(
            child: _Stub(width: 40, height: 4, color: const Color(0xFF212121)),
          ),
          const SizedBox(height: 2),
          Center(
            child: _Stub(width: 30, height: 3, color: const Color(0xFFBDBDBD)),
          ),
          const SizedBox(height: 3),
          _DashedLine(color: const Color(0xFFBDBDBD)),
          const SizedBox(height: 3),

          // Meta
          Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ts,
                const SizedBox(height: 2),
                ts,
              ],
            ),
          ),
          const SizedBox(height: 3),
          _DashedLine(color: const Color(0xFFBDBDBD)),
          const SizedBox(height: 3),

          // Items
          for (int i = 0; i < 3; i++) ...[
            Padding(
              padding: pad,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Stub(width: i.isEven ? 36 : 28, height: 3, color: const Color(0xFFE0E0E0)),
                  _Stub(width: 16, height: 3, color: const Color(0xFFE0E0E0)),
                ],
              ),
            ),
            const SizedBox(height: 2),
          ],
          _DashedLine(color: const Color(0xFFBDBDBD)),
          const SizedBox(height: 2),

          // Total
          Padding(
            padding: pad,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Stub(width: 20, height: 4, color: const Color(0xFF212121)),
                _Stub(width: 22, height: 4, color: accent),
              ],
            ),
          ),
          const SizedBox(height: 3),
          _DashedLine(color: const Color(0xFFBDBDBD)),
          const SizedBox(height: 4),

          // Footer
          Center(
            child: _Stub(width: 32, height: 3, color: const Color(0xFFBDBDBD)),
          ),
        ],
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

  static const short = _Stub(
    width: 40,
    height: 3,
    color: Color(0xFFE0E0E0),
  );
  static const medium = _Stub(
    width: 56,
    height: 3,
    color: Color(0xFFE0E0E0),
  );

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
