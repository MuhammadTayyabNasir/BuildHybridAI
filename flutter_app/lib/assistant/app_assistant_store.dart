import 'dart:async';

import '../models/packing_entry_model.dart';
import '../models/temp_humidity_model.dart';
import '../models/th_threshold_model.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/th_threshold_service.dart';
import 'assistant_service.dart';

/// [AssistantStore] over the app's local-first storage: every write lands in
/// SQLite first and is uploaded in the background when the phone is online,
/// exactly like a reading typed into the temperature & humidity form.
class AppAssistantStore implements AssistantStore {
  AppAssistantStore({
    required this.local,
    required this.firestore,
    required this.thresholds,
    required this.isOnline,
    required this.userId,
    required this.userName,
  });

  final LocalStorageService local;
  final FirestoreService firestore;
  final ThThresholdService thresholds;
  final bool Function() isOnline;
  @override
  final String userId;
  @override
  final String userName;

  @override
  List<PackingEntryModel> packingEntries() => local.getEntries();

  @override
  List<TempHumidityReport> thReports() => local.getTempHumidityReports();

  @override
  ThThreshold thresholdFor(String sectionId) => thresholds.forSection(sectionId);

  @override
  Future<void> saveThReport(TempHumidityReport report) async {
    await local.saveTempHumidityReport(report.copyWith(isSynced: false));
    if (!isOnline()) return;
    unawaited(() async {
      try {
        await firestore.saveTempHumidityReport(report);
        await local.markTempReportSynced(report.id);
      } catch (_) {
        // Stays unsynced; SyncService retries later.
      }
    }());
  }

  @override
  Future<void> deleteThReport(String id) async {
    await local.deleteTempHumidityReport(id);
    if (!isOnline()) return;
    unawaited(() async {
      try {
        await firestore.deleteTempHumidityReport(id);
      } catch (_) {}
    }());
  }

  @override
  String? meta(String key) => local.getMeta(key);

  @override
  Future<void> setMeta(String key, String value) => local.setMeta(key, value);
}
