import 'package:flutter/material.dart';

/// Maps category names to their Material icons and colors.
///
/// Used across the app for consistent category visualization.
class CategoryHelper {
  CategoryHelper._();

  /// Get the icon for a category name.
  static IconData getIcon(String category) {
    return _categoryIcons[category] ?? Icons.more_horiz;
  }

  /// Get the color for a category name.
  static Color getColor(String category) {
    final hex = _categoryColors[category];
    if (hex == null) return const Color(0xFF9E9E9E);
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  static const Map<String, IconData> _categoryIcons = {
    // Expense
    'Food & Dining': Icons.restaurant,
    'Transportation': Icons.directions_car,
    'Shopping': Icons.shopping_bag,
    'Bills & Utilities': Icons.receipt_long,
    'Healthcare': Icons.local_hospital,
    'Entertainment': Icons.movie,
    'Groceries': Icons.local_grocery_store,
    'Education': Icons.school,
    'Business Expense': Icons.business_center,
    'Other': Icons.more_horiz,
    // Income
    'Salary': Icons.account_balance_wallet,
    'Business Income': Icons.store,
    'Freelance': Icons.laptop_mac,
    'Investment': Icons.trending_up,
    'Refund': Icons.replay,
    'Other Income': Icons.attach_money,
  };

  static const Map<String, String> _categoryColors = {
    // Expense
    'Food & Dining': '#FF5722',
    'Transportation': '#2196F3',
    'Shopping': '#9C27B0',
    'Bills & Utilities': '#607D8B',
    'Healthcare': '#F44336',
    'Entertainment': '#E91E63',
    'Groceries': '#4CAF50',
    'Education': '#3F51B5',
    'Business Expense': '#795548',
    'Other': '#9E9E9E',
    // Income
    'Salary': '#2E7D32',
    'Business Income': '#1B5E20',
    'Freelance': '#00695C',
    'Investment': '#0D47A1',
    'Refund': '#FF6F00',
    'Other Income': '#388E3C',
  };
}
