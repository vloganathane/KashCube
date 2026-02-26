import 'package:equatable/equatable.dart';

/// A product or service in the item catalog.
class ItemCatalog extends Equatable {
  const ItemCatalog({
    this.id,
    required this.name,
    this.description,
    this.unit = 'pcs',
    required this.unitPrice,
    this.taxPct = 0,
    this.hsnCode,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? description;
  final String unit;
  final double unitPrice;
  final double taxPct;
  final String? hsnCode;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ItemCatalog copyWith({
    int? id,
    String? name,
    String? description,
    String? unit,
    double? unitPrice,
    double? taxPct,
    String? hsnCode,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItemCatalog(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      taxPct: taxPct ?? this.taxPct,
      hsnCode: hsnCode ?? this.hsnCode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'unit': unit,
        'unit_price': unitPrice,
        'tax_pct': taxPct,
        'hsn_code': hsnCode,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ItemCatalog.fromMap(Map<String, dynamic> map) => ItemCatalog(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String?,
        unit: (map['unit'] as String?) ?? 'pcs',
        unitPrice: (map['unit_price'] as num).toDouble(),
        taxPct: (map['tax_pct'] as num?)?.toDouble() ?? 0,
        hsnCode: map['hsn_code'] as String?,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props =>
      [id, name, description, unit, unitPrice, taxPct, hsnCode, isActive];
}
