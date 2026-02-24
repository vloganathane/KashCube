import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/kash_cube_theme.dart';
import 'presentation/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KashCubeApp()));
}

/// Root widget for Kash Cube.
class KashCubeApp extends StatelessWidget {
  const KashCubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kash Cube',
      debugShowCheckedModeBanner: false,
      theme: KashCubeTheme.light,
      darkTheme: KashCubeTheme.dark,
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
