import 'package:flutter/material.dart';

/// Custom semantic color tokens for Kash Cube.
/// Access via `Theme.of(context).extension<KashCubeColors>()!`
class KashCubeColors extends ThemeExtension<KashCubeColors> {
  const KashCubeColors({
    required this.income,
    required this.expense,
    required this.credit,
    required this.overdue,
    required this.incomeBackground,
    required this.expenseBackground,
    required this.creditBackground,
    required this.overdueBackground,
  });

  final Color income;
  final Color expense;
  final Color credit;
  final Color overdue;
  final Color incomeBackground;
  final Color expenseBackground;
  final Color creditBackground;
  final Color overdueBackground;

  // Light theme colors
  static const light = KashCubeColors(
    income: Color(0xFF2E7D32),
    expense: Color(0xFFC62828),
    credit: Color(0xFFE65100),
    overdue: Color(0xFFB71C1C),
    incomeBackground: Color(0xFFE8F5E9),
    expenseBackground: Color(0xFFFFEBEE),
    creditBackground: Color(0xFFFFF3E0),
    overdueBackground: Color(0xFFFFCDD2),
  );

  // Dark theme colors
  static const dark = KashCubeColors(
    income: Color(0xFF66BB6A),
    expense: Color(0xFFEF5350),
    credit: Color(0xFFFFA726),
    overdue: Color(0xFFEF5350),
    incomeBackground: Color(0xFF1B5E20),
    expenseBackground: Color(0xFF4E0000),
    creditBackground: Color(0xFF3E2723),
    overdueBackground: Color(0xFF4E0000),
  );

  @override
  KashCubeColors copyWith({
    Color? income,
    Color? expense,
    Color? credit,
    Color? overdue,
    Color? incomeBackground,
    Color? expenseBackground,
    Color? creditBackground,
    Color? overdueBackground,
  }) {
    return KashCubeColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      credit: credit ?? this.credit,
      overdue: overdue ?? this.overdue,
      incomeBackground: incomeBackground ?? this.incomeBackground,
      expenseBackground: expenseBackground ?? this.expenseBackground,
      creditBackground: creditBackground ?? this.creditBackground,
      overdueBackground: overdueBackground ?? this.overdueBackground,
    );
  }

  @override
  KashCubeColors lerp(covariant ThemeExtension<KashCubeColors>? other, double t) {
    if (other is! KashCubeColors) return this;
    return KashCubeColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      credit: Color.lerp(credit, other.credit, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      incomeBackground: Color.lerp(incomeBackground, other.incomeBackground, t)!,
      expenseBackground: Color.lerp(expenseBackground, other.expenseBackground, t)!,
      creditBackground: Color.lerp(creditBackground, other.creditBackground, t)!,
      overdueBackground: Color.lerp(overdueBackground, other.overdueBackground, t)!,
    );
  }
}
