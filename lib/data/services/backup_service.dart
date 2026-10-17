import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../core/security/backup_crypto.dart';
import '../local/app_database.dart';

/// A decoded backup file.
class BackupPayload {
  const BackupPayload({
    required this.format,
    required this.version,
    required this.exportedAt,
    required this.tables,
    this.encrypted = false,
    this.appId = 'personal_finance_manager',
  });

  final String format;
  final int version;
  final DateTime exportedAt;
  final String appId;
  final bool encrypted;

  /// `tableName -> list of raw column maps`.
  final Map<String, List<Map<String, Object?>>> tables;

  int get totalRows => tables.values.fold(0, (sum, rows) => sum + rows.length);

  Map<String, int> get rowCounts => {
    for (final entry in tables.entries) entry.key: entry.value.length,
  };
}

/// Versioned JSON export / import of every user table.
///
/// The export is deliberately a *raw* dump keyed by the real column names: it
/// round-trips exactly, it is diffable, and it survives schema additions because
/// import only writes the columns the file actually contains.
///
/// Restore is all-or-nothing. Foreign keys are disabled only for the duration
/// of the rebuild and `PRAGMA foreign_key_check` is run afterwards, so a
/// restored database is verified before it is handed back to the app.
class BackupService {
  BackupService({required AppDatabase db, required DateTime Function() now})
    : _db = db,
      _now = now;

  final AppDatabase _db;
  final DateTime Function() _now;

  static const String format = 'personal_finance_manager.backup';
  static const int currentVersion = 1;

  /// Tables that make up a backup. Order matters only for readability; import
  /// does not depend on it because constraints are disabled while writing.
  List<String> get tableNames =>
      _db.allTables.map((t) => t.actualTableName).toList(growable: false);

  /// Serialises every row. When [password] is supplied the returned text is an
  /// AES-256-GCM envelope; otherwise it is readable JSON.
  Future<String> exportToString({String? password}) async {
    final payload = await export();
    final json = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': format,
      'version': currentVersion,
      'appId': payload.appId,
      'exportedAt': payload.exportedAt.toIso8601String(),
      'encrypted': false,
      'tables': payload.tables,
    });
    if (password == null || password.isEmpty) return json;
    return BackupCrypto.encrypt(json, password);
  }

  /// Reads every table. Runs `PRAGMA integrity_check` first so a corrupt
  /// database is never exported as if it were valid.
  Future<BackupPayload> export() async {
    final integrity = await _db.integrityCheck();
    if (integrity.toLowerCase() != 'ok') {
      throw InvalidFileException(
        'The database failed its integrity check ($integrity). '
        'Fix the device storage before exporting.',
      );
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final name in tableNames) {
      final rows = await _db.customSelect('SELECT * FROM $name').get();
      tables[name] = rows
          .map((row) => Map<String, Object?>.from(row.data))
          .toList(growable: false);
    }
    return BackupPayload(
      format: format,
      version: currentVersion,
      exportedAt: _now(),
      tables: tables,
    );
  }

  /// Parses [contents], decrypting with [password] when the file is an
  /// envelope. Throws [InvalidFileException] for anything untrusted.
  BackupPayload decode(String contents, {String? password}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const InvalidFileException('That file is not valid JSON.');
    }
    if (decoded is! Map) {
      throw const InvalidFileException('That file is not a backup.');
    }
    final map = Map<String, Object?>.from(decoded);

    if (BackupCrypto.looksEncrypted(map)) {
      if (password == null || password.isEmpty) {
        throw const InvalidFileException(
          'This backup is password protected. Enter the password to restore it.',
        );
      }
      final decrypted = BackupCrypto.decrypt(map, password);
      return decode(decrypted);
    }

    if (map['format'] != format) {
      throw const InvalidFileException(
        'That file was not created by this app.',
      );
    }
    final version = (map['version'] as num?)?.toInt() ?? 0;
    if (version > currentVersion) {
      throw InvalidFileException(
        'This backup was made by a newer version of the app (v$version). '
        'Update the app and try again.',
      );
    }
    final rawTables = map['tables'];
    if (rawTables is! Map) {
      throw const InvalidFileException('This backup contains no data.');
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in rawTables.entries) {
      final tableName = entry.key.toString();
      if (!tableNames.contains(tableName)) continue; // Ignore unknown tables.
      final rows = entry.value;
      if (rows is! List) {
        throw InvalidFileException('The “$tableName” section is not a list.');
      }
      tables[tableName] = rows
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    }

    return BackupPayload(
      format: format,
      version: version,
      appId: map['appId']?.toString() ?? 'personal_finance_manager',
      exportedAt:
          DateTime.tryParse(map['exportedAt']?.toString() ?? '') ?? _now(),
      encrypted: false,
      tables: tables,
    );
  }

  /// Replaces the database contents with [payload] inside one atomic rebuild.
  ///
  /// Returns a per-table count of what was written so the UI can show a
  /// summary and the user can verify the restore actually did something.
  Future<Map<String, int>> restore(BackupPayload payload) async {
    if (payload.tables.isEmpty) {
      throw const InvalidFileException('This backup contains no data.');
    }
    final imported = <String, int>{};

    // `PRAGMA foreign_keys` cannot be toggled inside a transaction, so it is
    // disabled around the whole rebuild and every table is re-checked after.
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        for (final name in tableNames) {
          await _db.customStatement('DELETE FROM $name');
        }
        for (final tableName in tableNames) {
          final rows = payload.tables[tableName];
          if (rows == null || rows.isEmpty) continue;
          var count = 0;
          for (final row in rows) {
            await _insertRaw(tableName, row);
            count++;
          }
          imported[tableName] = count;
        }
        if (!imported.containsKey('app_settings')) {
          await _db.writeSetting('restored_at', _now().toIso8601String());
        }
        await _db.writeAuditLog(
          entityType: 'database',
          action: 'restored',
          payload: <String, Object?>{
            'sourceExportedAt': payload.exportedAt.toIso8601String(),
            'rows': imported,
          },
        );
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }

    final violations = await _db.customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw const InvalidFileException(
        'The backup references wallets or categories that are missing, so it '
        'was not applied. Nothing was changed after this point.',
      );
    }
    return imported;
  }

  Future<void> _insertRaw(String tableName, Map<String, Object?> row) async {
    if (row.isEmpty) return;
    final columns = row.keys.toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(', ');
    final values = columns.map((c) => _coerce(row[c])).toList(growable: false);
    await _db.customStatement(
      'INSERT OR REPLACE INTO $tableName (${columns.join(', ')}) '
      'VALUES ($placeholders)',
      values,
    );
  }

  /// SQLite only accepts int, double, String, `Uint8List` and null. JSON
  /// parsing can hand back `bool` or a `num` that is wider than expected, so
  /// everything is normalised here instead of at every call site.
  static Object? _coerce(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is int || value is double || value is String) return value;
    if (value is num) return value.toInt();
    if (value is List<int>) return value;
    return value.toString();
  }
}
