import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import '../models/temp_humidity_model.dart';
import '../models/user_model.dart';

class LocalStorageService {
  static const _dbName = 'pma_db.sqlite';
  static const _dbVersion = 2;
  static const String _kOfflineUser = 'offline_user_data';
  static const String _kOfflinePass = 'offline_user_pass';
  Database? _db;

  // In-memory mirrors — all read methods are synchronous because they read these
  final Map<String, PackingEntryModel> _entries = {};
  final Map<String, ProductModel> _products = {};
  final Map<String, MachineModel> _machines = {};
  final Map<String, String> _kv = {};
  final Set<String> _pendingDeletes = {};
  final Map<String, TempHumidityReport> _tempReports = {};

  // ── Init ─────────────────────────────────────────────────

  Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$_dbName';

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    await _loadAll();
  }
  Future<void> saveOfflineSession(UserModel user, String password) async {
    final prefs = await SharedPreferences.getInstance();

    // Change this to .toJson() so it uses the safe int date and includes the ID!
    await prefs.setString(_kOfflineUser, jsonEncode(user.toJson()));

    await prefs.setString(_kOfflinePass, password);
  }
  /// 2. Validates if the typed credentials match the last saved session
  Future<bool> validateOfflineLogin(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPass = prefs.getString(_kOfflinePass);
    final savedUserData = prefs.getString(_kOfflineUser);

    if (savedPass == null || savedUserData == null) return false;

    try {
      final userMap = jsonDecode(savedUserData) as Map<String, dynamic>;
      final savedUsername = userMap['username'] as String?;

      // Check if both username and password match exactly
      return savedUsername == username && savedPass == password;
    } catch (e) {
      return false;
    }
  }

  /// 3. Retrieves the cached user model to bypass Firebase
  Future<UserModel?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUserData = prefs.getString(_kOfflineUser);

    if (savedUserData == null) return null;

    try {
      final map = jsonDecode(savedUserData) as Map<String, dynamic>;

      // Extract the ID from the map (assuming your toMap uses 'id' or 'uid')
      final String userId = map['id'] ?? map['uid'] ?? '';

      // Pass BOTH arguments expected by your UserModel
      return UserModel.fromMap(map, userId);

    } catch (e) {
      return null;
    }
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createTempHumidityTable(db);
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_th_section ON temp_humidity(section_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_th_date ON temp_humidity(date)');
  }

  Future<void> _loadAll() async {
    final db = _db!;

    for (final row in await db.query('entries')) {
      final id = row['id'] as String;
      final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      _entries[id] = PackingEntryModel.fromMap(map, id);
    }

    for (final row in await db.query('products')) {
      final id = row['id'] as String;
      final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      _products[id] = ProductModel.fromMap(map, id);
    }

    for (final row in await db.query('machines')) {
      final id = row['id'] as String;
      final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      _machines[id] = MachineModel.fromMap(map, id);
    }

    for (final row in await db.query('kv_store')) {
      _kv[row['key'] as String] = row['value'] as String;
    }

    for (final row in await db.query('pending_deletes')) {
      _pendingDeletes.add(row['id'] as String);
    }

    for (final row in await db.query('temp_humidity')) {
      final id = row['id'] as String;
      final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      _tempReports[id] = TempHumidityReport.fromMap(map, id);
    }

    debugPrint('[DB] loaded ${_entries.length} entries, '
        '${_products.length} products, ${_machines.length} machines, '
        '${_tempReports.length} temp-humidity reports');
  }

  // ── Entries ──────────────────────────────────────────────

  Future<void> saveEntry(PackingEntryModel entry) async {
    _entries[entry.id] = entry;
    await _db!.insert(
      'entries',
      {
        'id': entry.id,
        'section': entry.section,
        'created_at': entry.createdAt.millisecondsSinceEpoch,
        'is_synced': entry.isSynced ? 1 : 0,
        'data': jsonEncode(entry.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteEntry(String id) async {
    _entries.remove(id);
    await _db!.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  List<PackingEntryModel> getEntries({String? section}) {
    final all = _entries.values.toList();
    if (section != null) return all.where((e) => e.section == section).toList();
    return all;
  }

  bool hasEntry(String id) => _entries.containsKey(id);

  PackingEntryModel? getEntryById(String id) => _entries[id];

  List<PackingEntryModel> getEntriesByDateRange({
    required DateTime from,
    required DateTime to,
    String? section,
  }) {
    return getEntries(section: section)
        .where((e) => !e.createdAt.isBefore(from) && !e.createdAt.isAfter(to))
        .toList();
  }

  List<PackingEntryModel> getUnsyncedEntries() =>
      _entries.values.where((e) => !e.isSynced).toList();

  Future<void> markSynced(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    final synced = entry.copyWith(isSynced: true);
    _entries[id] = synced;
    await _db!.update(
      'entries',
      {'is_synced': 1, 'data': jsonEncode(synced.toMap())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearEntries(String section) async {
    _entries.removeWhere((_, e) => e.section == section);
    await _db!.delete('entries', where: 'section = ?', whereArgs: [section]);
  }

  Future<int> clearOldSyncedEntries({int days = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final ids = _entries.values
        .where((e) => e.isSynced && e.createdAt.isBefore(cutoff))
        .map((e) => e.id)
        .toList();
    for (final id in ids) {
      _entries.remove(id);
    }
    if (ids.isEmpty) return 0;
    await _db!.delete(
      'entries',
      where: 'is_synced = 1 AND created_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    return ids.length;
  }

  // ── Pending Deletes ───────────────────────────────────────

  Set<String> getPendingDeletes() => Set.unmodifiable(_pendingDeletes);

  Future<void> addPendingDelete(String id) async {
    _pendingDeletes.add(id);
    await _db!.insert(
      'pending_deletes',
      {'id': id},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removePendingDelete(String id) async {
    _pendingDeletes.remove(id);
    await _db!.delete('pending_deletes', where: 'id = ?', whereArgs: [id]);
  }

  // ── Meta / Last Sync ─────────────────────────────────────

  Future<void> setLastSync(String section, DateTime dt) async =>
      _setKv('lastSync_$section', dt.millisecondsSinceEpoch.toString());

  DateTime? getLastSync(String section) {
    final v = _kv['lastSync_$section'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  Future<void> setLastSyncAll(DateTime dt) async =>
      _setKv('lastSyncAll', dt.millisecondsSinceEpoch.toString());

  DateTime? getLastSyncAll() {
    final v = _kv['lastSyncAll'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  // ── Generic metadata (device id, sync cursor, etc.) ──────────
  /// Read an arbitrary metadata string. Returns null if unset.
  String? getMeta(String key) => _kv[key];

  /// Persist an arbitrary metadata string (survives until reinstall).
  Future<void> setMeta(String key, String value) => _setKv(key, value);

  /// Pull cursor: highest entry `updatedAt` we have already ingested.
  /// Null on a fresh install → triggers a full initial pull.
  DateTime? getPullCursor() {
    final v = _kv['pullCursor'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(v));
  }

  Future<void> setPullCursor(DateTime dt) =>
      _setKv('pullCursor', dt.millisecondsSinceEpoch.toString());

  Future<void> _setKv(String key, String value) async {
    _kv[key] = value;
    await _db!.insert(
      'kv_store',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Auth Cache ───────────────────────────────────────────

  Future<void> saveAuthCache(
      String uid, String username, String role, String passwordHash) async {
    final expiryMs =
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
    await _setKv('auth_uid', uid);
    await _setKv('auth_username', username);
    await _setKv('auth_role', role);
    await _setKv('auth_passwordHash', passwordHash);
    await _setKv('auth_expiry', expiryMs.toString());
  }

  Map<String, dynamic>? getAuthCache() {
    final uid = _kv['auth_uid'];
    if (uid == null) return null;
    return {
      'uid': uid,
      'username': _kv['auth_username'],
      'role': _kv['auth_role'],
      'passwordHash': _kv['auth_passwordHash'],
      'authCacheExpiry': int.tryParse(_kv['auth_expiry'] ?? ''),
    };
  }

  Future<void> clearAuthCache() async {
    const keys = [
      'auth_uid', 'auth_username', 'auth_role', 'auth_passwordHash', 'auth_expiry'
    ];
    for (final k in keys) {
      _kv.remove(k);
      await _db!.delete('kv_store', where: 'key = ?', whereArgs: [k]);
    }
  }

  bool isAuthCacheValid() {
    final v = _kv['auth_expiry'];
    if (v == null) return false;
    final ms = int.tryParse(v);
    return ms != null &&
        DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  DateTime? getAuthCacheExpiry() {
    final v = _kv['auth_expiry'];
    if (v == null) return null;
    final ms = int.tryParse(v);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ── Products Cache ────────────────────────────────────────

  Future<void> saveProducts(List<ProductModel> products) async {
    _products.clear();
    for (final p in products) {
      _products[p.id] = p;
    }
    await _db!.transaction((txn) async {
      await txn.delete('products');
      for (final p in products) {
        await txn.insert(
          'products',
          {'id': p.id, 'data': jsonEncode(p.toMap())},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  List<ProductModel> getProducts() => _products.values.toList();

  Future<void> clearProductsCache() async {
    _products.clear();
    await _db!.delete('products');
  }

  // ── Machines Cache ────────────────────────────────────────

  Future<void> saveMachines(List<MachineModel> machines) async {
    _machines.clear();
    for (final m in machines) {
      _machines[m.id] = m;
    }
    await _db!.transaction((txn) async {
      await txn.delete('machines');
      for (final m in machines) {
        await txn.insert(
          'machines',
          {'id': m.id, 'data': jsonEncode(m.toMap())},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  List<MachineModel> getMachines() => _machines.values.toList();

  Future<void> clearMachinesCache() async {
    _machines.clear();
    await _db!.delete('machines');
  }

  // ── Temperature & Humidity Reports ────────────────────────

  Future<void> saveTempHumidityReport(TempHumidityReport report) async {
    _tempReports[report.id] = report;
    await _db!.insert(
      'temp_humidity',
      {
        'id': report.id,
        'section_id': report.sectionId,
        'date': TempHumidityReport.dayOf(report.date).millisecondsSinceEpoch,
        'shift': report.shift,
        'is_synced': report.isSynced ? 1 : 0,
        'data': jsonEncode(report.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTempHumidityReport(String id) async {
    _tempReports.remove(id);
    await _db!.delete('temp_humidity', where: 'id = ?', whereArgs: [id]);
  }

  List<TempHumidityReport> getTempHumidityReports({String? sectionId}) {
    final all = _tempReports.values.toList();
    if (sectionId != null) return all.where((r) => r.sectionId == sectionId).toList();
    return all;
  }

  bool hasTempHumidityReport(String id) => _tempReports.containsKey(id);

  TempHumidityReport? getTempHumidityReportById(String id) => _tempReports[id];

  List<TempHumidityReport> getUnsyncedTempReports() =>
      _tempReports.values.where((r) => !r.isSynced).toList();

  Future<void> markTempReportSynced(String id) async {
    final report = _tempReports[id];
    if (report == null) return;
    final synced = report.copyWith(isSynced: true);
    _tempReports[id] = synced;
    await _db!.update(
      'temp_humidity',
      {'is_synced': 1, 'data': jsonEncode(synced.toMap())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
