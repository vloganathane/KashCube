import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../extensions/context_extensions.dart';

/// Shows a bottom sheet on compact/medium windows and a centred [Dialog] on
/// expanded windows (≥840 dp — desktop browser / wide tablet).
///
/// This is the single call-site replacement for every [showModalBottomSheet]
/// used for pickers and forms in the app.  All sheet content on mobile works
/// unchanged inside the dialog on desktop because:
///   - `mainAxisSize: MainAxisSize.min` columns size naturally
///   - `MediaQuery.viewInsetsOf(...).bottom` is 0 on desktop (no slide-up
///     keyboard), so any keyboard padding just becomes extra spacing
///   - The dialog clips to rounded corners, so built-in drag handles are
///     hidden by [Clip.antiAlias]
///
/// Example:
/// ```dart
/// final result = await showAdaptiveSheet<MyType>(
///   context,
///   builder: (_) => MyPickerSheet(...),
/// );
/// ```
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  /// Max width of the centred dialog on expanded windows. Defaults to 560 dp.
  double maxDialogWidth = 560,
}) {
  if (context.isExpanded) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxDialogWidth,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: builder(ctx),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    builder: builder,
  );
}
