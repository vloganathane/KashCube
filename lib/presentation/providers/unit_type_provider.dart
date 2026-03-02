import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/database_helper.dart';

/// Immutable snapshot of a unit type row.
class UnitType {
  const UnitType({
    required this.id,
    required this.label,
    required this.isSystem,
  });

  final int id;
  final String label;
  final bool isSystem;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class UnitTypesNotifier extends StateNotifier<List<UnitType>> {
  UnitTypesNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getUnitTypes();
    state = rows
        .map((r) => UnitType(
              id: r['id'] as int,
              label: r['label'] as String,
              isSystem: (r['is_system'] as int) == 1,
            ))
        .toList();
  }

  /// Adds a custom unit. Returns false if the label already exists.
  Future<bool> addUnit(String label) async {
    final id = await DatabaseHelper.instance.insertUnitType(label);
    if (id == -1) return false;
    await _load();
    return true;
  }

  /// Removes a custom (non-system) unit by id. No-op for system units.
  Future<void> removeUnit(int id) async {
    await DatabaseHelper.instance.deleteUnitType(id);
    await _load();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final unitTypesProvider =
    StateNotifierProvider<UnitTypesNotifier, List<UnitType>>(
  (ref) => UnitTypesNotifier(),
);
