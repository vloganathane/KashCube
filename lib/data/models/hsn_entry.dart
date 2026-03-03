/// Represents a single HSN or SAC code entry from the master table.
class HsnEntry {
  const HsnEntry({
    required this.code,
    required this.description,
    required this.isSac,
  });

  final String code;
  final String description;
  final bool isSac;

  /// "8471 – Computers and peripheral units"
  String get displayLabel => '$code – $description';

  /// 'HSN' or 'SAC'
  String get type => isSac ? 'SAC' : 'HSN';

  factory HsnEntry.fromMap(Map<String, dynamic> map) => HsnEntry(
        code: map['code'] as String,
        description: map['description'] as String,
        isSac: (map['type'] as String?) == 'SAC',
      );
}
