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

  Color get color => _colorFromHex(hex);
}

Color _colorFromHex(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x1B5E20;
  return Color(0xFF000000 | value);
}

String _hexFromColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

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
  late PdfTemplateConfig _config;

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
    _config = r?.builderConfig ?? const PdfTemplateConfig();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool get _isThermal =>
      _pageSizeName == 'thermal58' || _pageSizeName == 'thermal80';

  bool get _usesCustomAccent =>
      !_kAccentOptions.any((option) => option.hex == _accentHex);

  Future<void> _pickCustomAccent() async {
    final hex = await showDialog<String>(
      context: context,
      builder: (context) => _CustomColorDialog(initialHex: _accentHex),
    );
    if (hex != null && mounted) setState(() => _accentHex = hex);
  }

  void _updateConfig(PdfTemplateConfig config) {
    setState(() => _config = config);
  }

  void _moveSection(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _config.sectionOrder.length) return;
    final order = [..._config.sectionOrder];
    final section = order.removeAt(index);
    order.insert(nextIndex, section);
    _updateConfig(_config.copyWith(sectionOrder: order));
  }

  void _toggleSection(String section, bool visible) {
    final hidden = {..._config.hiddenSections};
    visible ? hidden.remove(section) : hidden.add(section);
    _updateConfig(_config.copyWith(hiddenSections: hidden));
  }

  void _updateColumn(PdfTemplateColumn column) {
    _updateConfig(
      _config.copyWith(
        columns: [
          for (final value in _config.columns)
            if (value.id == column.id) column else value,
        ],
      ),
    );
  }

  Future<void> _pickBalanceColor() async {
    final hex = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CustomColorDialog(initialHex: _config.balanceColorHex),
    );
    if (hex != null && mounted) {
      _updateConfig(_config.copyWith(balanceColorHex: hex));
    }
  }

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
        builderConfigJson: _config.encode(),
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
      builderConfigJson: _config.encode(),
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
                _CustomColorSwatch(
                  color: _colorFromHex(_accentHex),
                  selected: _usesCustomAccent,
                  onTap: _pickCustomAccent,
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
            _SectionOrderEditor(
              config: _config,
              onToggle: _toggleSection,
              onMove: _moveSection,
              onConfigChanged: _updateConfig,
            ),
            _ColumnEditor(config: _config, onChanged: _updateColumn),
            _TypographyEditor(config: _config, onChanged: _updateConfig),
            _HeaderEditor(config: _config, onChanged: _updateConfig),
            _TotalsEditor(
              config: _config,
              onChanged: _updateConfig,
              onPickBalanceColor: _pickBalanceColor,
            ),
            _FooterEditor(config: _config, onChanged: _updateConfig),
          ],

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

const _sectionLabels = {
  'header': 'Header and document title',
  'parties': 'Party and GST details',
  'items': 'Line items table',
  'gst': 'GST summary',
  'totals': 'Totals',
  'transport': 'Transport details',
  'footer': 'Footer and signature',
};

class _SectionOrderEditor extends StatelessWidget {
  const _SectionOrderEditor({
    required this.config,
    required this.onToggle,
    required this.onMove,
    required this.onConfigChanged,
  });

  final PdfTemplateConfig config;
  final void Function(String section, bool visible) onToggle;
  final void Function(int index, int delta) onMove;
  final ValueChanged<PdfTemplateConfig> onConfigChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Sections'),
      subtitle: const Text('Show, hide and arrange document blocks'),
      children: [
        for (final entry in config.sectionOrder.asMap().entries)
          Row(
            children: [
              Checkbox(
                value: config.shows(entry.value),
                onChanged: (value) => onToggle(entry.value, value ?? false),
              ),
              Expanded(child: Text(_sectionLabels[entry.value] ?? entry.value)),
              IconButton(
                tooltip: 'Move up',
                onPressed: entry.key == 0 ? null : () => onMove(entry.key, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: entry.key == config.sectionOrder.length - 1
                    ? null
                    : () => onMove(entry.key, 1),
                icon: const Icon(Icons.arrow_downward),
              ),
            ],
          ),
        const Divider(),
        _ConfigSwitch(
          title: 'Show document number',
          value: config.showDocumentNumber,
          onChanged: (value) =>
              onConfigChanged(config.copyWith(showDocumentNumber: value)),
        ),
        _ConfigSwitch(
          title: 'Show dates',
          value: config.showDates,
          onChanged: (value) =>
              onConfigChanged(config.copyWith(showDates: value)),
        ),
        _ConfigSwitch(
          title: 'Show GSTIN',
          value: config.showGstin,
          onChanged: (value) =>
              onConfigChanged(config.copyWith(showGstin: value)),
        ),
        _ConfigSwitch(
          title: 'Show addresses',
          value: config.showAddresses,
          onChanged: (value) =>
              onConfigChanged(config.copyWith(showAddresses: value)),
        ),
        _ConfigSwitch(
          title: 'Show notes',
          value: config.showNotes,
          onChanged: (value) =>
              onConfigChanged(config.copyWith(showNotes: value)),
        ),
      ],
    );
  }
}

class _ColumnEditor extends StatelessWidget {
  const _ColumnEditor({required this.config, required this.onChanged});

  final PdfTemplateConfig config;
  final ValueChanged<PdfTemplateColumn> onChanged;

  @override
  Widget build(BuildContext context) {
    final width = config.columns
        .where((column) => column.visible)
        .fold<double>(0, (sum, column) => sum + column.widthPct);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Table columns'),
      subtitle: Text('Visible width allocation: ${width.toStringAsFixed(0)}%'),
      children: [
        if (width > 100)
          Text(
            'Column widths exceed 100%. Reduce visible column widths.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final column in config.columns)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(column.label),
            leading: Checkbox(
              value: column.visible,
              onChanged: (value) =>
                  onChanged(column.copyWith(visible: value ?? false)),
            ),
            children: [
              TextFormField(
                initialValue: column.label,
                decoration: const InputDecoration(
                  labelText: 'Column heading',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => onChanged(column.copyWith(label: value)),
              ),
              _ValueSlider(
                label: 'Width',
                value: column.widthPct,
                min: 4,
                max: 60,
                divisions: 56,
                suffix: '%',
                onChanged: (value) =>
                    onChanged(column.copyWith(widthPct: value)),
              ),
              DropdownButtonFormField<PdfTextAlign>(
                initialValue: column.alignment,
                decoration: const InputDecoration(
                  labelText: 'Text alignment',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: PdfTextAlign.left,
                    child: Text('Left'),
                  ),
                  DropdownMenuItem(
                    value: PdfTextAlign.center,
                    child: Text('Centre'),
                  ),
                  DropdownMenuItem(
                    value: PdfTextAlign.right,
                    child: Text('Right'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(column.copyWith(alignment: value));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
      ],
    );
  }
}

class _TypographyEditor extends StatelessWidget {
  const _TypographyEditor({required this.config, required this.onChanged});

  final PdfTemplateConfig config;
  final ValueChanged<PdfTemplateConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Typography'),
      subtitle: const Text('Role sizes, emphasis and row density'),
      children: [
        _ValueSlider(
          label: 'Business name',
          value: config.businessFontSize,
          min: 12,
          max: 26,
          divisions: 14,
          suffix: ' pt',
          onChanged: (value) =>
              onChanged(config.copyWith(businessFontSize: value)),
        ),
        _ValueSlider(
          label: 'Section headings',
          value: config.headingFontSize,
          min: 8,
          max: 16,
          divisions: 8,
          suffix: ' pt',
          onChanged: (value) =>
              onChanged(config.copyWith(headingFontSize: value)),
        ),
        _ValueSlider(
          label: 'Totals',
          value: config.totalsFontSize,
          min: 10,
          max: 18,
          divisions: 8,
          suffix: ' pt',
          onChanged: (value) =>
              onChanged(config.copyWith(totalsFontSize: value)),
        ),
        _ValueSlider(
          label: 'Footer',
          value: config.footerFontSize,
          min: 7,
          max: 12,
          divisions: 5,
          suffix: ' pt',
          onChanged: (value) =>
              onChanged(config.copyWith(footerFontSize: value)),
        ),
        _ConfigSwitch(
          title: 'Bold business name',
          value: config.businessBold,
          onChanged: (value) => onChanged(config.copyWith(businessBold: value)),
        ),
        _ConfigSwitch(
          title: 'Bold section headings',
          value: config.headingBold,
          onChanged: (value) => onChanged(config.copyWith(headingBold: value)),
        ),
        _ConfigSwitch(
          title: 'Bold totals',
          value: config.totalsBold,
          onChanged: (value) => onChanged(config.copyWith(totalsBold: value)),
        ),
        DropdownButtonFormField<String>(
          initialValue: config.rowDensity,
          decoration: const InputDecoration(
            labelText: 'Table row density',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'compact', child: Text('Compact')),
            DropdownMenuItem(value: 'standard', child: Text('Standard')),
            DropdownMenuItem(value: 'spacious', child: Text('Spacious')),
          ],
          onChanged: (value) {
            if (value != null) onChanged(config.copyWith(rowDensity: value));
          },
        ),
      ],
    );
  }
}

class _HeaderEditor extends StatelessWidget {
  const _HeaderEditor({required this.config, required this.onChanged});

  final PdfTemplateConfig config;
  final ValueChanged<PdfTemplateConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Header layout'),
      subtitle: const Text('Logo, title treatment and divider'),
      children: [
        DropdownButtonFormField<String>(
          initialValue: config.logoPosition,
          decoration: const InputDecoration(
            labelText: 'Logo position',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'besideLeft',
              child: Text('Left, next to business details'),
            ),
            DropdownMenuItem(
              value: 'besideRight',
              child: Text('Right, next to business details'),
            ),
            DropdownMenuItem(
              value: 'aboveLeft',
              child: Text('Above business details, left aligned'),
            ),
            DropdownMenuItem(
              value: 'aboveCenter',
              child: Text('Above business details, centred'),
            ),
            DropdownMenuItem(
              value: 'aboveRight',
              child: Text('Above business details, right aligned'),
            ),
            DropdownMenuItem(
              value: 'belowLeft',
              child: Text('Below business details'),
            ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(config.copyWith(logoPosition: value));
          },
        ),
        _ValueSlider(
          label: 'Logo size',
          value: config.logoSize,
          min: 32,
          max: 96,
          divisions: 16,
          suffix: ' pt',
          onChanged: (value) => onChanged(config.copyWith(logoSize: value)),
        ),
        DropdownButtonFormField<String>(
          initialValue: config.titleStyle,
          decoration: const InputDecoration(
            labelText: 'Document title style',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'plain', child: Text('Plain')),
            DropdownMenuItem(value: 'underline', child: Text('Underline')),
            DropdownMenuItem(value: 'boxed', child: Text('Boxed')),
          ],
          onChanged: (value) {
            if (value != null) onChanged(config.copyWith(titleStyle: value));
          },
        ),
        _ValueSlider(
          label: 'Divider thickness',
          value: config.dividerThickness,
          min: 0,
          max: 5,
          divisions: 10,
          suffix: ' pt',
          onChanged: (value) =>
              onChanged(config.copyWith(dividerThickness: value)),
        ),
      ],
    );
  }
}

class _TotalsEditor extends StatelessWidget {
  const _TotalsEditor({
    required this.config,
    required this.onChanged,
    required this.onPickBalanceColor,
  });

  final PdfTemplateConfig config;
  final ValueChanged<PdfTemplateConfig> onChanged;
  final VoidCallback onPickBalanceColor;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Totals and payment'),
      subtitle: const Text('Summary rows, highlight and payment details'),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'left', label: Text('Totals left')),
            ButtonSegment(value: 'right', label: Text('Totals right')),
          ],
          selected: {config.totalsAlignment},
          onSelectionChanged: (value) =>
              onChanged(config.copyWith(totalsAlignment: value.first)),
        ),
        _ConfigSwitch(
          title: 'Show subtotal',
          value: config.showSubtotal,
          onChanged: (value) => onChanged(config.copyWith(showSubtotal: value)),
        ),
        _ConfigSwitch(
          title: 'Show tax breakdown',
          value: config.showTaxBreakdown,
          onChanged: (value) =>
              onChanged(config.copyWith(showTaxBreakdown: value)),
        ),
        _ConfigSwitch(
          title: 'Show paid amount',
          value: config.showPaid,
          onChanged: (value) => onChanged(config.copyWith(showPaid: value)),
        ),
        _ConfigSwitch(
          title: 'Show balance due',
          value: config.showBalance,
          onChanged: (value) => onChanged(config.copyWith(showBalance: value)),
        ),
        _ConfigSwitch(
          title: 'Show amount in words',
          value: config.showAmountInWords,
          onChanged: (value) =>
              onChanged(config.copyWith(showAmountInWords: value)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Balance highlight colour'),
          trailing: _ColorButton(
            color: _colorFromHex(config.balanceColorHex),
            onTap: onPickBalanceColor,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: config.paymentDisplay,
          decoration: const InputDecoration(
            labelText: 'Payment details',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Hidden')),
            DropdownMenuItem(value: 'qr', child: Text('UPI QR code')),
            DropdownMenuItem(value: 'text', child: Text('Text details')),
            DropdownMenuItem(value: 'both', child: Text('QR code and text')),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(config.copyWith(paymentDisplay: value));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          initialValue: config.paymentText,
          decoration: const InputDecoration(
            labelText: 'Payment text',
            hintText: 'Bank account or UPI payment details',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          onChanged: (value) => onChanged(config.copyWith(paymentText: value)),
        ),
      ],
    );
  }
}

class _FooterEditor extends StatelessWidget {
  const _FooterEditor({required this.config, required this.onChanged});

  final PdfTemplateConfig config;
  final ValueChanged<PdfTemplateConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.base),
      title: const Text('Footer'),
      subtitle: const Text('Message, terms, signature and branding'),
      children: [
        TextFormField(
          initialValue: config.footerMessage,
          decoration: const InputDecoration(
            labelText: 'Custom footer message',
            hintText: 'Leave blank to use the document default',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          onChanged: (value) =>
              onChanged(config.copyWith(footerMessage: value)),
        ),
        _ConfigSwitch(
          title: 'Show terms and conditions',
          value: config.showTerms,
          onChanged: (value) => onChanged(config.copyWith(showTerms: value)),
        ),
        _ConfigSwitch(
          title: 'Show signature box',
          value: config.showSignature,
          onChanged: (value) =>
              onChanged(config.copyWith(showSignature: value)),
        ),
        TextFormField(
          initialValue: config.signatureLabel,
          decoration: const InputDecoration(
            labelText: 'Signature label',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              onChanged(config.copyWith(signatureLabel: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'left', label: Text('Signature left')),
            ButtonSegment(value: 'right', label: Text('Signature right')),
          ],
          selected: {config.signatureAlignment},
          onSelectionChanged: (value) =>
              onChanged(config.copyWith(signatureAlignment: value.first)),
        ),
        _ConfigSwitch(
          title: 'Show generated date',
          value: config.showGeneratedDate,
          onChanged: (value) =>
              onChanged(config.copyWith(showGeneratedDate: value)),
        ),
      ],
    );
  }
}

class _ConfigSwitch extends StatelessWidget {
  const _ConfigSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Choose colour',
      onPressed: onTap,
      icon: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
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

class _CustomColorSwatch extends StatelessWidget {
  const _CustomColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Custom colour',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: selected
                ? color
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: 2.5,
            ),
            boxShadow: selected
                ? [BoxShadow(color: color.withAlpha(100), blurRadius: 6)]
                : null,
          ),
          child: Icon(
            selected ? Icons.check : Icons.colorize,
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initialHex});

  final String initialHex;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late final TextEditingController _hexCtrl;
  late Color _color;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _color = _colorFromHex(widget.initialHex);
    _hexCtrl = TextEditingController(text: _hexFromColor(_color));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _setChannel(int channel, double value) {
    final channels = [_color.r, _color.g, _color.b];
    channels[channel] = value / 255;
    setState(() {
      _color = Color.from(
        alpha: 1,
        red: channels[0],
        green: channels[1],
        blue: channels[2],
      );
      _hexCtrl.text = _hexFromColor(_color);
      _errorText = null;
    });
  }

  void _applyHex(String rawValue) {
    final value = rawValue.trim().toUpperCase();
    final normalized = value.startsWith('#') ? value : '#$value';
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)) {
      setState(() => _errorText = 'Enter a 6-digit hex colour.');
      return;
    }
    setState(() {
      _color = _colorFromHex(normalized);
      _hexCtrl.text = normalized;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom accent colour'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            TextField(
              controller: _hexCtrl,
              decoration: InputDecoration(
                labelText: 'Hex colour',
                hintText: '#1B5E20',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: _applyHex,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ColorChannelSlider(
              label: 'Red',
              value: _color.r * 255,
              onChanged: (value) => _setChannel(0, value),
            ),
            _ColorChannelSlider(
              label: 'Green',
              value: _color.g * 255,
              onChanged: (value) => _setChannel(1, value),
            ),
            _ColorChannelSlider(
              label: 'Blue',
              value: _color.b * 255,
              onChanged: (value) => _setChannel(2, value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            _applyHex(_hexCtrl.text);
            if (_errorText == null) {
              Navigator.of(context).pop(_hexFromColor(_color));
            }
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.round().toString())),
      ],
    );
  }
}
