import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

/// Opens the on-device SQLite database.
///
/// The database lives in the application documents directory so it is included
/// in Android's app-private storage (and in an `adb backup` performed by the
/// user's own device). Nothing leaves the device unless the user explicitly
/// exports a backup.
LazyDatabase openAppDatabaseConnection({
  String fileName = 'personal_finance_manager.sqlite',
}) {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, fileName));
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(
      file,
      setup: _applyConnectionPragmas,
    );
  });
}

/// In-memory database used by tests. Never used in production code paths.
LazyDatabase openInMemoryConnection() => LazyDatabase(
  () async => NativeDatabase.memory(setup: _applyConnectionPragmas),
);

void _applyConnectionPragmas(Database database) {
  // Foreign keys are off by default in SQLite and are required for the
  // referential integrity of transfers, budgets and goals.
  database.execute('PRAGMA foreign_keys = ON');
  // WAL keeps reads fast while a write transaction is open.
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA synchronous = NORMAL');
  database.execute('PRAGMA busy_timeout = 5000');
}
