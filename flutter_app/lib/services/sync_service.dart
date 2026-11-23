import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import 'firestore_service.dart';
import 'local_storage_service.dart';

class SyncService {
  final FirestoreService _firestore;
  final LocalStorageService _local;
  final ConnectivityService _connectivity;

  SyncService(this._firestore, this._local, this._connectivity);

  /// Pull all machines, products, and entries from Firestore into local DB.
  /// Only saves items not already present locally to avoid clobbering unsynced edits.
  Future<void> pullFromFirestore() async {
    if (!await _connectivity.isOnline()) return;
    try {
      final machines = await _firestore.fetchMachines();
      if (machines.isNotEmpty) await _local.saveMachines(machines);

      final products = await _firestore.fetchProducts();
      if (products.isNotEmpty) await _local.saveProducts(products);

      // Pull all entries — only new ones are written to local DB
      final remote = await _firestore.fetchAllEntries();
      int pulled = 0;
      for (final e in remote) {
        if (!_local.hasEntry(e.id)) {
          await _local.saveEntry(e.copyWith(isSynced: true));
          pulled++;
        }
      }
      // Pull all temp/humidity reports
      final remoteReports = await _firestore.fetchTempHumidityReports();
      int pulledReports = 0;
      for (final r in remoteReports) {
        if (!_local.hasTempHumidityReport(r.id)) {
          await _local.saveTempHumidityReport(r.copyWith(isSynced: true));
          pulledReports++;
        }
      }
      debugPrint('[Sync] pull: ${machines.length} machines, '
          '${products.length} products, $pulled new entries, '
          '$pulledReports temp-humidity reports');
    } catch (e) {
      debugPrint('[Sync] pull failed: $e');
    }
  }

  Future<int> syncPendingEntries() async {
    if (!await _connectivity.isOnline()) {
      debugPrint('[Sync] offline — skipping sync');
      return 0;
    }

    // Process pending deletes first
    final pendingDeletes = _local.getPendingDeletes();
    if (pendingDeletes.isNotEmpty) {
      debugPrint('[Sync] retrying ${pendingDeletes.length} pending deletes');
    }
    for (final id in pendingDeletes.toList()) {
      try {
        await _firestore.deleteEntry(id);
        await _local.removePendingDelete(id);
        debugPrint('[Sync] delete OK: $id');
      } catch (e) {
        debugPrint('[Sync] delete FAILED $id: $e');
      }
    }

    // Then upload unsynced entries
    final pending = _local.getUnsyncedEntries();
    debugPrint('[Sync] found ${pending.length} unsynced entries');
    int synced = 0;
    for (final entry in pending) {
      debugPrint('[Sync] uploading entry id=${entry.id} section=${entry.section} product=${entry.productName}');
      try {
        await _firestore.saveEntry(entry);
        await _local.markSynced(entry.id);
        synced++;
        debugPrint('[Sync] upload OK: ${entry.id}');
      } catch (e) {
        debugPrint('[Sync] upload FAILED ${entry.id}: $e');
      }
    }
    if (synced > 0) {
      await _local.setLastSyncAll(DateTime.now());
      debugPrint('[Sync] synced $synced entries');
    }

    // Sync unsynced temp/humidity reports
    final unsyncedReports = _local.getUnsyncedTempReports();
    for (final report in unsyncedReports) {
      try {
        await _firestore.saveTempHumidityReport(report);
        await _local.markTempReportSynced(report.id);
      } catch (e) {
        debugPrint('[Sync] temp report upload FAILED ${report.id}: $e');
      }
    }

    return synced;
  }
}
