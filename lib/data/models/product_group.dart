import 'package:equatable/equatable.dart';

/// A product group for managing variants (e.g., T-shirt in multiple colors/sizes).
///
/// Implements schema.org ProductGroup for variant collections.
/// Items in `item_catalog` link to a group via `product_group_id`.
class ProductGroup extends Equatable {
  const ProductGroup({
    this.id,
    required this.name,
    this.description,
    this.variesBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int? id;

  /// Display name for the product group (e.g., "Classic T-Shirt").
  final String name;

  /// Optional description of the product family.
  final String? description;

  /// JSON array of attribute names that vary (e.g., ["color", "size"]).
  /// Used to drive variant picker UI logic.
  final String? variesBy;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Helper to parse variesBy JSON array into List<String>.
  List<String> get variesByList {
    if (variesBy == null || variesBy!.isEmpty) return [];
    
    // Try parsing as JSON array first
    try {
      final decoded = variesBy!.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
      return decoded.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      // Fallback: treat as comma-separated string
      return variesBy!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
  }

  ProductGroup copyWith({
    int? id,
    String? name,
    String? description,
    String? variesBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ProductGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      variesBy: variesBy ?? this.variesBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        if (description != null) 'description': description,
        if (variesBy != null) 'varies_by': variesBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      };

  factory ProductGroup.fromMap(Map<String, dynamic> map) => ProductGroup(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String?,
        variesBy: map['varies_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        variesBy,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}
