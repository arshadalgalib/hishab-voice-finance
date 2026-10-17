import '../../domain/models/app_settings.dart';
import '../local/app_database.dart';

/// Persists [AppSettings] in the `app_settings` key/value table.
///
/// Sensitive values (PIN hash, cloud token) are deliberately **not** stored
/// here — they live in secure storage via `SecureStore`.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<AppSettings> watch() {
    return _db.select(_db.appSettings).watch().map(_toSettings);
  }

  Future<AppSettings> load() async {
    final rows = await _db.readAllSettings();
    return AppSettings.mergeFlatRows(rows);
  }

  Future<void> save(AppSettings settings) async {
    final rows = settings.toFlatRows();
    await _db.transaction(() async {
      for (final entry in rows.entries) {
        await _db.writeSetting(entry.key, entry.value);
      }
    });
  }

  Future<AppSettings> update(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = await load();
    final next = transform(current);
    await save(next);
    return next;
  }

  AppSettings _toSettings(List<AppSettingRow> rows) {
    return AppSettings.mergeFlatRows({
      for (final row in rows) row.key: row.value,
    });
  }
}
