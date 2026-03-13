import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';

// sqflite_common_ffi_web registers the WASM SQLite factory for the browser.
// On Android the default sqflite factory is used — no action needed.
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'
    if (dart.library.io) 'db_factory_stub.dart';

/// Call once in main() before runApp() — sets the correct SQLite backend.
Future<void> initDatabaseFactory() async {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
}
