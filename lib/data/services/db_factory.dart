import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// sqflite_common_ffi_web registers the WASM SQLite factory for the browser.
// On Android the default sqflite factory is used — no action needed.
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'
    if (dart.library.io) 'db_factory_stub.dart';

/// Call once in main() before runApp() — sets the correct SQLite backend.
Future<void> initDatabaseFactory() async {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    return;
  }

  // Desktop builds must wire sqflite to the FFI backend before any DB call.
  // Android/iOS keep using the default platform sqflite implementation.
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
