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
