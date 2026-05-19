import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kash_cube/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
            return '.dart_tool/test_tmp';
          case 'getApplicationSupportDirectory':
            return '.dart_tool/test_support';
          default:
            return '.dart_tool';
        }
      });

  testWidgets('App renders root shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KashCubeApp()));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byType(KashCubeApp), findsOneWidget);
  });
}
