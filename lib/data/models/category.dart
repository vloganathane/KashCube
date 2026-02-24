import 'package:equatable/equatable.dart';

/// Financial category definition.
class Category extends Equatable {
  const Category({
    this.id,
    required this.name,
    this.parentCategory,
    required this.categoryType,
    this.mode = 'both',
    required this.icon,
    required this.color,
    this.sortOrder = 0,
    this.isSystem = true,
    this.isActive = true,
    this.keywords,
    this.createdAt,
  });

  final int? id;
  final String name;
  final String? parentCategory;
  final String categoryType; // 'income', 'expense'
  final String mode; // 'personal', 'business', 'both'
  final String icon; // Material icon name
  final String color; // Hex color string
  final int sortOrder;
  final bool isSystem;
  final bool isActive;
  final List<String>? keywords;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'parent_category': parentCategory,
      'category_type': categoryType,
      'mode': mode,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'is_system': isSystem ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'keywords': keywords?.join(','),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      parentCategory: map['parent_category'] as String?,
      categoryType: map['category_type'] as String,
      mode: map['mode'] as String? ?? 'both',
      icon: map['icon'] as String,
      color: map['color'] as String,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isSystem: (map['is_system'] as int? ?? 1) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      keywords: (map['keywords'] as String?)?.split(',').where((k) => k.isNotEmpty).toList(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, name, categoryType];
}
