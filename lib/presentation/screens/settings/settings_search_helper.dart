import 'package:flutter/material.dart';

/// Searchable setting item for the settings search feature.
class SettingItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String sectionLabel;
  final List<String> keywords;
  final VoidCallback onTap;

  const SettingItem({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.sectionLabel,
    this.keywords = const [],
    required this.onTap,
  });

  /// Returns true if this setting matches the given query.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        (subtitle?.toLowerCase().contains(q) ?? false) ||
        keywords.any((kw) => kw.toLowerCase().contains(q)) ||
        sectionLabel.toLowerCase().contains(q);
  }
}
