import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_db.dart';

const _dbVersion = 2;

Future<LocalDb> openLocalDb(String name) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final dir = await getApplicationDocumentsDirectory();
  final db = await openDatabase(
    '${dir.path}${Platform.pathSeparator}$name.sqlite',
    version: _dbVersion,
    onCreate: _onCreate,
    onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2) await _createTempHumidityTable(db);
    },
  );
  return SqliteLocalDb(db);
}

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE entries (
      id TEXT PRIMARY KEY,
      section TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0,
      data TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_entries_section ON entries(section)');
  await db.execute('CREATE INDEX idx_entries_created_at ON entries(created_at)');
  await db.execute('CREATE INDEX idx_entries_is_synced ON entries(is_synced)');
  await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
  await db.execute('CREATE TABLE machines (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
  await db.execute('CREATE TABLE kv_store (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute('CREATE TABLE pending_deletes (id TEXT PRIMARY KEY)');
  await _createTempHumidityTable(db);
}

Future<void> _createTempHumidityTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS temp_humidity (
      id TEXT PRIMARY KEY,
      section_id TEXT NOT NULL,
      date INTEGER NOT NULL,
      shift TEXT NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0,
      data TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_th_section ON temp_humidity(section_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_th_date ON temp_humidity(date)');
}

class SqliteLocalDb implements LocalDb {
  SqliteLocalDb(this._db);
  final Database _db;

  String _key(String table) => LocalDb.tables[table]!;

  @override
  Future<List<Map<String, Object?>>> all(String table) => _db.query(table);

  @override
  Future<void> put(String table, Map<String, Object?> row) =>
      _db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> replaceAll(String table, List<Map<String, Object?>> rows) =>
      _db.transaction((txn) async {
        await txn.delete(table);
        for (final r in rows) {
          await txn.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  @override
  Future<void> delete(String table, String key) =>
      _db.delete(table, where: '${_key(table)} = ?', whereArgs: [key]);

  @override
  Future<void> deleteMany(String table, Iterable<String> keys) async {
    final list = keys.toList();
    if (list.isEmpty) return;
    await _db.transaction((txn) async {
      for (final k in list) {
        await txn.delete(table, where: '${_key(table)} = ?', whereArgs: [k]);
      }
    });
  }

  @override
  Future<void> clear(String table) => _db.delete(table);
}
