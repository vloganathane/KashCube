import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/database_helper.dart';

/// Sentinel value used in the category dropdown to trigger the "add new" flow.
const kAddCustomCategorysentinel = '__add_custom__';

// ── State ──────────────────────────────────────────────────────────────────

/// Holds the user-created category names split by type.
class CustomCategoriesState {
  const CustomCategoriesState({
    this.expense = const [],
    this.income = const [],
  });

  final List<String> expense;
  final List<String> income;
}

// ── Notifier ───────────────────────────────────────────────────────────────

class CustomCategoriesNotifier
    extends StateNotifier<CustomCategoriesState> {
  CustomCategoriesNotifier() : super(const CustomCategoriesState()) {
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getCustomCategories();
    final expense = <String>[];
    final income = <String>[];
    for (final r in rows) {
      final name = r['name'] as String;
      if (r['category_type'] == 'income') {
        income.add(name);
      } else {
        expense.add(name);
      }
    }
    state = CustomCategoriesState(expense: expense, income: income);
  }

  /// Persist a new custom category and refresh state.
  /// Returns false if the name already exists (duplicate).
  Future<bool> addCategory(String name, String categoryType) async {
    final id = await DatabaseHelper.instance.insertCustomCategory(
      name: name,
      categoryType: categoryType,
    );
    if (id == -1) return false; // duplicate
    await _load();
    return true;
  }

  /// Soft-delete a user-created category and refresh state.
  Future<void> removeCategory(String name) async {
    await DatabaseHelper.instance.deleteCustomCategory(name);
    await _load();
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final customCategoriesProvider =
    StateNotifierProvider<CustomCategoriesNotifier, CustomCategoriesState>(
  (ref) => CustomCategoriesNotifier(),
);

// ── Helpers ────────────────────────────────────────────────────────────────

/// Returns all categories for [type] ('expense' | 'income') including
/// user-created ones, with a trailing sentinel for "add new".
List<String> buildCategoryList(
  CustomCategoriesState custom,
  String type,
) {
  final base = type == 'income'
      ? AppConstants.incomeCategories
      : AppConstants.defaultCategories;

  final userList =
      type == 'income' ? custom.income : custom.expense;

  return [
    ...base,
    ...userList.where((c) => !base.contains(c)),
    kAddCustomCategorysentinel,
  ];
}
