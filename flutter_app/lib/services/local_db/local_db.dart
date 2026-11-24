import 'local_db_io.dart' if (dart.library.js_interop) 'local_db_web.dart' as impl;

/// Minimal row store behind [LocalStorageService]. The service keeps every
/// table mirrored in memory (reads are synchronous), so the backend only has
/// to persist rows by primary key and load them all at start-up.
///
/// * Android / iOS / desktop: SQLite (sqflite / sqflite_common_ffi).
/// * Web (Chrome): browser storage (see `local_db_web.dart`).
abstract class LocalDb {
  /// Tables and their primary-key column.
  static const tables = {
    'entries': 'id',
    'products': 'id',
    'machines': 'id',
    'kv_store': 'key',
    'pending_deletes': 'id',
    'temp_humidity': 'id',
  };

  Future<List<Map<String, Object?>>> all(String table);

  /// Insert or replace one row (must contain the table's key column).
  Future<void> put(String table, Map<String, Object?> row);

  /// Replace the whole table content.
  Future<void> replaceAll(String table, List<Map<String, Object?>> rows);

  Future<void> delete(String table, String key);

  Future<void> deleteMany(String table, Iterable<String> keys);

  Future<void> clear(String table);

  static Future<LocalDb> open(String name) => impl.openLocalDb(name);
}
