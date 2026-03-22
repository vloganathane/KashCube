import 'package:flutter/material.dart';

import '../theme/kash_cube_colors.dart';

/// Convenient extensions on [BuildContext] for accessing theme tokens.
extension ContextExtensions on BuildContext {
  /// Access the current [ThemeData].
  ThemeData get theme => Theme.of(this);

  /// Access the current [ColorScheme].
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Access Kash Cube semantic colors.
  KashCubeColors get kashColors => Theme.of(this).extension<KashCubeColors>()!;

  /// Access the current [TextTheme].
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Access [MediaQueryData].
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  /// Screen width.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Screen height.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  // ── Material 3 Adaptive Window Classes ────────────────────────────────────

  /// Compact window class (< 600 dp) — phone portrait.
  bool get isCompact => MediaQuery.sizeOf(this).width < 600;

  /// Medium window class (600–839 dp) — tablet / small laptop.
  bool get isMedium =>
      MediaQuery.sizeOf(this).width >= 600 &&
      MediaQuery.sizeOf(this).width < 840;

  /// Expanded window class (≥ 840 dp) — desktop browser / wide tablet.
  /// When true, AppShell shows a NavigationRail instead of a bottom bar.
  bool get isExpanded => MediaQuery.sizeOf(this).width >= 840;

  /// Show a [SnackBar] with the given message.
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }
}
