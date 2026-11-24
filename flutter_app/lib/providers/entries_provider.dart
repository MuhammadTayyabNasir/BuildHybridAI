import '../core/constants/firebase_config.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/packing_entry_model.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';

class EntriesProvider extends ChangeNotifier {
  final FirestoreService _firestore;
  final LocalStorageService _local;
  final ConnectivityService _connectivity;
  final SyncService _sync;

  final _uuid = const Uuid();
  final Map<String, List<PackingEntryModel>> _cache = {};
  bool _loading = false;
  String? _error;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<QuerySnapshot>? _snapshotSub;

  EntriesProvider(
      this._firestore,
      this._local,
      this._connectivity,
      this._sync,
      ) {
    // When connectivity returns, flush any local offline edits to Firestore
    _connSub = _connectivity.onChanged.listen((online) {
      if (online) _flushPending();
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _snapshotSub?.cancel();
    super.dispose();
  }

  // ── gRPC Real-Time Listener ────────────────────────────────────────────────
  void startListening() {
    _snapshotSub?.cancel();

    // Listen to all packing entries in real-time (gRPC)
    _snapshotSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: FirebaseConfig.databaseId)
        .collection('packing_entries')
        .snapshots()
        .listen((snap) async {

      final pendingDeletes = _local.getPendingDeletes();
      final unsynced = _local.getUnsyncedEntries().map((e) => e.id).toSet();

      final newCache = <String, List<PackingEntryModel>>{};

      for (final doc in snap.docs) {
        final entry = PackingEntryModel.fromMap(doc.data(), doc.id);
        // Protect local edits: Don't overwrite local data that hasn't synced to the cloud yet
        if (pendingDeletes.contains(entry.id) || unsynced.contains(entry.id)) {
          continue;
        }

        // Keep SQLite up to date for instant offline loading
        await _local.saveEntry(entry.copyWith(isSynced: true));

        newCache.putIfAbsent(entry.section, () => []).add(entry);
      }

      // Add back the unsynced local entries so they stay visible in the UI
      for (final localEntry in _local.getUnsyncedEntries()) {
        newCache.putIfAbsent(localEntry.section, () => []).add(localEntry);
      }

      // Sort all sections
      for (final section in newCache.keys) {
        newCache[section]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      _cache.clear();
      _cache.addAll(newCache);

      _loading = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[EntriesProvider] Snapshot listener error: $e');
    });
  }

  void stopListening() {
    _snapshotSub?.cancel();
    _snapshotSub = null;
  }
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _flushPending() async {
    for (final e in _local.getUnsyncedEntries()) {
      try {
        await _firestore.saveEntry(e);
        await _local.markSynced(e.id);
      } catch (_) {}
    }
    for (final id in _local.getPendingDeletes().toList()) {
      try {
        await _firestore.deleteEntry(id);
        await _local.removePendingDelete(id);
      } catch (_) {}
    }
    refreshFromLocal();
  }

  bool get loading => _loading;
  String? get error => _error;
  List<PackingEntryModel> forSection(String section) => _cache[section] ?? [];
  int get pendingCount => _local.getUnsyncedEntries().length;
  LocalStorageService get localStorageService => _local;

  Future<void> loadSection(String section, {DateTime? from, DateTime? to}) async {
    _error = null;
    final pendingDeletes = _local.getPendingDeletes();
    final cached = _local.getEntries(section: section)
        .where((e) => !pendingDeletes.contains(e.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _cache[section] = cached;

    // Completely remove the _loading = true logic.
    // The UI will immediately show the local cache (which is empty if it's a fresh install),
    // and if the gRPC stream later finds cloud data, it will notify and populate automatically.
    _loading = false;
    notifyListeners();
  }
  Future<List<PackingEntryModel>> loadAll({DateTime? from, DateTime? to}) async {
    if (from != null || to != null) {
      return _local.getEntriesByDateRange(
        from: from ?? DateTime(2000),
        to: to ?? DateTime.now(),
      );
    } else {
      return _local.getEntries();
    }
  }

  List<PackingEntryModel> localEntriesInRange({
    DateTime? from,
    DateTime? to,
    String? section,
  }) {
    if (from == null && to == null) {
      return _local.getEntries(section: section);
    }
    return _local.getEntriesByDateRange(
      from: from ?? DateTime(2000),
      to: to ?? DateTime.now(),
      section: section,
    );
  }

  Future<String?> addEntry(PackingEntryModel entry) async {
    await addEntryReturningId(entry);
    return null;
  }

  /// Same as [addEntry] but returns the new entry's id (voice undo needs it).
  Future<String> addEntryReturningId(PackingEntryModel entry) async {
    final withId = entry.copyWith(id: _uuid.v4(), isSynced: false);
    await _local.saveEntry(withId);
    _cache.putIfAbsent(withId.section, () => []).insert(0, withId);
    notifyListeners();
    _uploadInBackground(withId);
    return withId.id;
  }

  Future<int> addEntries(List<PackingEntryModel> entries) async {
    if (entries.isEmpty) return 0;
    final prepared = <PackingEntryModel>[];
    for (final entry in entries) {
      final withId = entry.copyWith(id: _uuid.v4(), isSynced: false);
      await _local.saveEntry(withId);
      _cache.putIfAbsent(withId.section, () => []).insert(0, withId);
      prepared.add(withId);
    }
    notifyListeners();
    for (final e in prepared) {
      _uploadInBackground(e);
    }
    return prepared.length;
  }

  Future<String?> updateEntry(PackingEntryModel entry) async {
    final updated = entry.copyWith(updatedAt: DateTime.now(), isSynced: false);
    await _local.saveEntry(updated);
    final list = _cache[entry.section] ?? [];
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx != -1) {
      list[idx] = updated;
    }
    notifyListeners();
    _uploadInBackground(updated);
    return null;
  }

  void _uploadInBackground(PackingEntryModel entry) {
    Future.microtask(() async {
      final online = await _connectivity.isOnline();
      if (!online) return;
      try {
        await _firestore.saveEntry(entry);
        await _local.markSynced(entry.id);

        final list = _cache[entry.section];
        if (list != null) {
          final idx = list.indexWhere((e) => e.id == entry.id);
          if (idx != -1) {
            list[idx] = list[idx].copyWith(isSynced: true);
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('[Entries] upload FAILED ${entry.id}: $e');
      }
    });
  }

  Future<String?> deleteEntry(PackingEntryModel entry) async {
    _cache[entry.section]?.removeWhere((e) => e.id == entry.id);
    await _local.deleteEntry(entry.id);
    notifyListeners();

    if (entry.isSynced) {
      final online = await _connectivity.isOnline();
      if (online) {
        try {
          await _firestore.deleteEntry(entry.id);
          await _local.removePendingDelete(entry.id);
        } catch (e) {
          await _local.addPendingDelete(entry.id);
        }
      } else {
        await _local.addPendingDelete(entry.id);
      }
    }
    return null;
  }

  void forceRefresh(String section) {
    // Handled naturally by gRPC snapshots now, no manual fetch needed
  }

  Future<void> syncAndNotify() async {
    await _sync.syncPendingEntries();
    notifyListeners();
  }

  void refreshFromLocal() {
    final pendingDeletes = _local.getPendingDeletes();
    for (final section in _cache.keys.toList()) {
      _cache[section] = _local
          .getEntries(section: section)
          .where((e) => !pendingDeletes.contains(e.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _loading = false;
    notifyListeners();
  }

  Future<({int uploaded, int downloaded})> manualSync() async {
    final online = await _connectivity.isOnline();
    if (!online) return (uploaded: 0, downloaded: 0);

    var uploaded = 0;
    for (final e in _local.getUnsyncedEntries()) {
      try {
        await _firestore.saveEntry(e);
        await _local.markSynced(e.id);
        uploaded++;
      } catch (_) {}
    }
    for (final id in _local.getPendingDeletes().toList()) {
      try {
        await _firestore.deleteEntry(id);
        await _local.removePendingDelete(id);
      } catch (_) {}
    }

    await _sync.pullFromFirestore(); // Failsafe DB catchup
    refreshFromLocal();

    return (uploaded: uploaded, downloaded: 0);
  }

  Future<int> wipeAll({void Function(int done, int total)? onProgress}) async {
    final all = _local.getEntries();
    final total = all.length;
    final online = await _connectivity.isOnline();
    var done = 0;
    for (final e in all) {
      if (online) {
        try {
          await _firestore.deleteEntry(e.id);
        } catch (_) {
          await _local.addPendingDelete(e.id);
        }
      } else {
        await _local.addPendingDelete(e.id);
      }
      await _local.deleteEntry(e.id);
      done++;
      onProgress?.call(done, total);
    }
    _cache.clear();
    await _local.setPullCursor(DateTime.now());
    notifyListeners();
    return done;
  }
}