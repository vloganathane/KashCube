// Stub used on Android/iOS — sqflite's default factory is already correct.
// The web build imports sqflite_common_ffi_web/sqflite_ffi_web.dart instead.
import 'package:sqflite/sqflite.dart';

// Returns the current (default) factory so db_factory.dart can read it.
// On web this file is never imported.
DatabaseFactory get databaseFactoryFfiWeb => databaseFactory;
