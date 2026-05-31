import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/document_template_record.dart';
import '../../../data/services/pdf_document_data.dart';
import '../../providers/document_template_provider.dart';
import '../../widgets/document_template_preview.dart';

// ── Constant accent palette (10 choices) ─────────────────────────────────────

const _kAccentOptions = <_AccentOption>[
  _AccentOption(label: 'Forest', hex: '#1B5E20'),
  _AccentOption(label: 'Ocean', hex: '#0D47A1'),
  _AccentOption(label: 'Teal', hex: '#004D40'),
  _AccentOption(label: 'Purple', hex: '#4A148C'),
  _AccentOption(label: 'Indigo', hex: '#1A237E'),
  _AccentOption(label: 'Ruby', hex: '#B71C1C'),
  _AccentOption(label: 'Ember', hex: '#E65100'),
  _AccentOption(label: 'Brown', hex: '#3E2723'),
  _AccentOption(label: 'Slate', hex: '#37474F'),
  _AccentOption(label: 'Onyx', hex: '#212121'),
];

class _AccentOption {
  const _AccentOption({required this.label, required this.hex});
  final String label;
  final String hex;

  Color get color {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x1B5E20;
    return Color(0xFF000000 | v);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Create a new custom PDF template or edit an existing non-preset one.
///
/// Pass [existing] to edit; pass null to create fresh.
class TemplateBuilderScreen extends ConsumerStatefulWidget {
  const TemplateBuilderScreen({super.key, this.existing});

  final DocumentTemplateRecord? existing;

  @override
  ConsumerState<TemplateBuilderScreen> createState() =>
      _TemplateBuilderScreenState();
}

class _TemplateBuilderScreenState extends ConsumerState<TemplateBuilderScreen> {
  late final TextEditingController _nameCtrl;

  late String _pageSizeName;
  late String _headerStyleName;
  late String _accentHex;
  late bool _showLogo;
  late int _decimalDigits;
  late String _fontFamilyName;
  late double _bodyFontSize;
  late double _titleFontSize;
  late double _pageMargin;
  late double _sectionSpacing;
  late double _itemColumnWidthPct;
  late String _headerAlignmentName;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _pageSizeName = r?.pageSizeName ?? 'a4';
    _headerStyleName = r?.headerStyleName ?? 'minimal';
    _accentHex = r?.accentColorHex ?? '#1B5E20';
    _showLogo = r?.showLogo ?? true;
    _decimalDigits = r?.amountDecimalDigits ?? 0;
    _fontFamilyName = r?.fontFamilyName ?? 'helvetica';
    _bodyFontSize = r?.bodyFontSize ?? 9;
    _titleFontSize = r?.titleFontSize ?? 22;
    _pageMargin = r?.pageMargin ?? 32;
    _sectionSpacing = r?.sectionSpacing ?? 20;
    _itemColumnWidthPct = r?.itemColumnWidthPct ?? 45;
    _headerAlignmentName = r?.headerAlignmentName ?? 'left';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool get _isThermal =>
      _pageSizeName == 'thermal58' || _pageSizeName == 'thermal80';

  DocumentTemplateRecord _toRecord({bool? isActive}) {
    final now = DateTime.now().toIso8601String();
    final basedOn = widget.existing?.basedOn ?? 'modern';
    final shouldBeActive = isActive ?? widget.existing?.isActive ?? true;
    if (widget.existing != null) {
      return widget.existing!.copyWith(
        name: _nameCtrl.text.trim(),
        accentColorHex: _isThermal ? '#000000' : _accentHex,
        headerStyleName: _isThermal ? 'minimal' : _headerStyleName,
        showLogo: _isThermal ? false : _showLogo,
        amountDecimalDigits: _decimalDigits,
        pageSizeName: _pageSizeName,
        fontFamilyName: _fontFamilyName,
        bodyFontSize: _bodyFontSize,
        titleFontSize: _titleFontSize,
        pageMargin: _pageMargin,
        sectionSpacing: _sectionSpacing,
        itemColumnWidthPct: _itemColumnWidthPct,
        headerAlignmentName: _headerAlignmentName,
        isActive: shouldBeActive,
      );
    }
    return DocumentTemplateRecord(
      id: 0, // ignored on insert
      name: _nameCtrl.text.trim(),
      basedOn: basedOn,
      accentColorHex: _isThermal ? '#000000' : _accentHex,
      headerStyleName: _isThermal ? 'minimal' : _headerStyleName,
      showLogo: _isThermal ? false : _showLogo,
      amountDecimalDigits: _decimalDigits,
      pageSizeName: _pageSizeName,
      fontFamilyName: _fontFamilyName,
      bodyFontSize: _bodyFontSize,
      titleFontSize: _titleFontSize,
      pageMargin: _pageMargin,
      sectionSpacing: _sectionSpacing,
      itemColumnWidthPct: _itemColumnWidthPct,
      headerAlignmentName: _headerAlignmentName,
      isActive: shouldBeActive,
      isPreset: false,
      createdAt: now,
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a template name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(documentTemplatesProvider.notifier);
    try {
      if (widget.existing != null) {
        await notifier.save(_toRecord());
      } else {
        await notifier.create(_toRecord());
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Template' : 'New Template'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // ── Live preview ────────────────────────────────────────────────────
          Center(
            child: DocumentTemplatePreview(
              record: _toRecord(),
              width: 180,
              dpi: 150,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Template name ────────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Template name',
              hintText: 'e.g. My Invoice',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Page size ────────────────────────────────────────────────────────
          Text('Page size', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _SectionLabel(label: 'Standard'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final s in [PageSize.a4, PageSize.a5, PageSize.letter])
                ChoiceChip(
                  label: Text(s.label),
                  selected: _pageSizeName == s.name,
                  onSelected: (_) => setState(() => _pageSizeName = s.name),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _SectionLabel(label: 'Thermal roll'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final s in [PageSize.thermal58, PageSize.thermal80])
                ChoiceChip(
                  label: Text(s.label),
                  selected: _pageSizeName == s.name,
                  onSelected: (_) => setState(() {
                    _pageSizeName = s.name;
                    // Thermal forces monochrome / no logo
                    _accentHex = '#000000';
                    _showLogo = false;
                    _headerStyleName = 'minimal';
                  }),
                ),
            ],
          ),

          if (!_isThermal) ...[
            const SizedBox(height: AppSpacing.xl),

            // ── Header style ──────────────────────────────────────────────────
            Text('Header style', style: tt.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'banner',
                  label: Text('Banner'),
                  icon: Icon(Icons.view_compact_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 'minimal',
                  label: Text('Minimal'),
                  icon: Icon(Icons.article_outlined, size: 16),
                ),
              ],
              selected: {_headerStyleName},
              onSelectionChanged: (v) =>
                  setState(() => _headerStyleName = v.first),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Accent colour ─────────────────────────────────────────────────
            Text('Accent colour', style: tt.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final opt in _kAccentOptions)
                  _ColorSwatch(
                    option: opt,
                    selected: _accentHex == opt.hex,
                    onTap: () => setState(() => _accentHex = opt.hex),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Logo toggle ───────────────────────────────────────────────────
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show business logo'),
              subtitle: const Text('Logo set in Business Profile'),
              value: _showLogo,
              onChanged: (v) => setState(() => _showLogo = v),
            ),
          ],

          const SizedBox(height: AppSpacing.base),

          // ── Decimal digits ────────────────────────────────────────────────
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show paise (two decimal places)'),
            subtitle: Text(
              _decimalDigits == 2
                  ? '₹10.50 shown as ₹10.50'
                  : '₹10.50 shown as ₹11',
            ),
            value: _decimalDigits == 2,
            onChanged: (v) => setState(() => _decimalDigits = v ? 2 : 0),
          ),

          if (!_isThermal) ...[
            const SizedBox(height: AppSpacing.base),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
              title: const Text('Advanced layout'),
              subtitle: const Text('Typography, spacing and table sizing'),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _fontFamilyName,
                  decoration: const InputDecoration(
                    labelText: 'Font family',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'helvetica',
                      child: Text('Helvetica'),
                    ),
                    DropdownMenuItem(value: 'times', child: Text('Times')),
                    DropdownMenuItem(value: 'courier', child: Text('Courier')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _fontFamilyName = v);
                  },
                ),
                const SizedBox(height: AppSpacing.base),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'left',
                      label: Text('Business left'),
                      icon: Icon(Icons.format_align_left, size: 16),
                    ),
                    ButtonSegment(
                      value: 'right',
                      label: Text('Business right'),
                      icon: Icon(Icons.format_align_right, size: 16),
                    ),
                  ],
                  selected: {_headerAlignmentName},
                  onSelectionChanged: (v) =>
                      setState(() => _headerAlignmentName = v.first),
                ),
                const SizedBox(height: AppSpacing.base),
                _ValueSlider(
                  label: 'Body text size',
                  value: _bodyFontSize,
                  min: 7,
                  max: 12,
                  divisions: 10,
                  suffix: ' pt',
                  onChanged: (v) => setState(() => _bodyFontSize = v),
                ),
                _ValueSlider(
                  label: 'Document title size',
                  value: _titleFontSize,
                  min: 16,
                  max: 30,
                  divisions: 14,
                  suffix: ' pt',
                  onChanged: (v) => setState(() => _titleFontSize = v),
                ),
                _ValueSlider(
                  label: 'Page margin',
                  value: _pageMargin,
                  min: 16,
                  max: 56,
                  divisions: 10,
                  suffix: ' pt',
                  onChanged: (v) => setState(() => _pageMargin = v),
                ),
                _ValueSlider(
                  label: 'Section spacing',
                  value: _sectionSpacing,
                  min: 8,
                  max: 32,
                  divisions: 12,
                  suffix: ' pt',
                  onChanged: (v) => setState(() => _sectionSpacing = v),
                ),
                _ValueSlider(
                  label: 'Item description column',
                  value: _itemColumnWidthPct,
                  min: 30,
                  max: 65,
                  divisions: 7,
                  suffix: '%',
                  onChanged: (v) => setState(() => _itemColumnWidthPct = v),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayValue = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $displayValue$suffix'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '$displayValue$suffix',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: option.color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2.5,
                  )
                : Border.all(color: Colors.transparent, width: 2.5),
            boxShadow: selected
                ? [BoxShadow(color: option.color.withAlpha(100), blurRadius: 6)]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : null,
        ),
      ),
    );
  }
}
