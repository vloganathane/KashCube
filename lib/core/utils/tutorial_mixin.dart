import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../presentation/providers/settings_provider.dart';

/// A single entry in the `?` tutorial dropdown (or the sole button label).
class TutorialMenuItem {
  final String label;
  final VoidCallback onTap;
  const TutorialMenuItem({required this.label, required this.onTap});
}

/// Mixin that adds tutorial coach mark support to a [ConsumerStatefulWidget].
///
/// Usage:
/// ```dart
/// class _MyScreenState extends ConsumerState<MyScreen>
///     with TutorialMixin<MyScreen> {
///
///   @override
///   String get tutorialKey => SettingsKeys.tutorialMyScreenDone;
///
///   @override
///   List<TargetFocus> buildTargets() => [...];
///
///   @override
///   void initState() {
///     super.initState();
///     maybeShowTutorial();
///   }
/// }
/// ```
///
/// Drop [buildTutorialAppBarAction] into `AppBar.actions`:
/// ```dart
/// appBar: AppBar(actions: [buildTutorialAppBarAction(), ...])
/// ```
/// It renders as a plain `IconButton` when there's only one guide, or as a
/// `PopupMenuButton` dropdown when the screen exposes multiple guides.
/// Override [tutorialMenuItems] to add flow entries alongside the tour.
mixin TutorialMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The settings key that stores the "tutorial seen" flag ('true'/'false').
  String get tutorialKey;

  /// Return the ordered list of [TargetFocus] steps for this screen's tour.
  List<TargetFocus> buildTargets();

  /// Optional: title shown in the intro dialog before the tutorial starts.
  /// Default: 'Quick Tutorial'
  String get tutorialTitle => 'Quick Tutorial';

  /// Optional: description shown in the intro dialog.
  /// Default: generic message about walking through key features.
  String get tutorialDescription =>
      'This quick guide will walk you through the key features of this screen. '
      'You can skip anytime using the SKIP button.';

  /// The items shown in the `?` AppBar action.
  ///
  /// Default: one entry that replays the orientation tour.
  /// Override on screens that also have flow-following guides.
  List<TutorialMenuItem> get tutorialMenuItems => [
    TutorialMenuItem(label: 'Replay orientation tour', onTap: replayTutorial),
  ];

  /// Builds the `?` AppBar action.
  ///
  /// - 1 item → plain `IconButton` (no extra tap required).
  /// - 2+ items → `PopupMenuButton` dropdown listing all guides.
  Widget buildTutorialAppBarAction() {
    final items = tutorialMenuItems;
    if (items.length == 1) {
      return IconButton(
        icon: const Icon(Icons.help_outline_rounded),
        tooltip: items.first.label,
        onPressed: items.first.onTap,
      );
    }
    return PopupMenuButton<TutorialMenuItem>(
      icon: const Icon(Icons.help_outline_rounded),
      tooltip: 'Tutorial guides',
      onSelected: (item) => item.onTap(),
      itemBuilder: (_) => items
          .map((item) => PopupMenuItem(value: item, child: Text(item.label)))
          .toList(),
    );
  }

  /// Show the tutorial if it hasn't been completed yet.
  /// Safe to call from [initState] — defers to the first rendered frame.
  void maybeShowTutorial() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final done =
          await ref.read(settingsRepositoryProvider).get(tutorialKey) == 'true';
      if (!mounted || done) return;
      _showTutorial();
    });
  }

  /// Replay the tutorial regardless of completion state.
  /// Hook this to the `?` help button in the AppBar.
  void replayTutorial() {
    if (mounted) _showTutorial();
  }

  void _showTutorial() {
    final targets = buildTargets();
    if (targets.isEmpty) return;

    // Show intro dialog first
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.school_outlined,
              color: Theme.of(ctx).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                tutorialTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          tutorialDescription,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(false); // Skip
              _markDone();
            },
            child: const Text('Skip for now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true), // Start
            child: const Text('Start Tutorial'),
          ),
        ],
      ),
    ).then((start) {
      if (start != true || !mounted) return;

      // Show the coach marks
      TutorialCoachMark(
        targets: targets,
        colorShadow: Colors.black,
        opacityShadow: 0.85,
        textSkip: 'SKIP',
        textStyleSkip: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
        alignSkip: Alignment.bottomLeft,
        paddingFocus: 8,
        pulseEnable: true,
        onFinish: () => _markDone(),
        onSkip: () {
          _markDone();
          return true;
        },
      ).show(context: context);
    });
  }

  Future<void> _markDone() async {
    await ref.read(settingsRepositoryProvider).set(tutorialKey, 'true');
  }
}

/// Helper to build a standard coach mark content card shown beside a target.
///
/// Returns a [Column] with a bold [title] and body [message] in white,
/// matching KashCube's dark overlay style.
Widget tutorialContentCard({required String title, required String message}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      ),
    ],
  );
}
