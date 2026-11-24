import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';

/// Chrome build: each table is one JSON object in browser storage
/// (shared_preferences → window.localStorage), keyed by primary key.
/// Fine for a shift's worth of factory data; the cloud copy in Firestore
/// remains the source of truth for history.
Future<LocalDb> openLocalDb(String name) async =>
    WebLocalDb(await SharedPreferences.getInstance(), name);

class WebLocalDb implements LocalDb {
  WebLocalDb(this._prefs, this._name);

  final SharedPreferences _prefs;
  final String _name;
  final Map<String, Map<String, Map<String, Object?>>> _cache = {};

  String _storeKey(String table) => '${_name}__$table';
  String _key(String table) => LocalDb.tables[table]!;

  Map<String, Map<String, Object?>> _table(String table) => _cache.putIfAbsent(table, () {
        final raw = _prefs.getString(_storeKey(table));
        if (raw == null || raw.isEmpty) return {};
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          return {
            for (final e in m.entries) e.key: Map<String, Object?>.from(e.value as Map),
          };
        } catch (_) {
          return {};
        }
      });

  Future<void> _flush(String table) =>
      _prefs.setString(_storeKey(table), jsonEncode(_table(table)));

  @override
  Future<List<Map<String, Object?>>> all(String table) async =>
      _table(table).values.map((r) => Map<String, Object?>.from(r)).toList();

  @override
  Future<void> put(String table, Map<String, Object?> row) {
    _table(table)['${row[_key(table)]}'] = Map<String, Object?>.from(row);
    return _flush(table);
  }

  @override
  Future<void> replaceAll(String table, List<Map<String, Object?>> rows) {
    _cache[table] = {for (final r in rows) '${r[_key(table)]}': Map<String, Object?>.from(r)};
    return _flush(table);
  }

  @override
  Future<void> delete(String table, String key) {
    _table(table).remove(key);
    return _flush(table);
  }

  @override
  Future<void> deleteMany(String table, Iterable<String> keys) {
    final t = _table(table);
    for (final k in keys) {
      t.remove(k);
    }
    return _flush(table);
  }

  @override
  Future<void> clear(String table) {
    _cache[table] = {};
    return _flush(table);
  }
}
