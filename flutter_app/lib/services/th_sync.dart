import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/temp_humidity_model.dart';
import '../providers/connectivity_provider.dart';
import 'firestore_service.dart';
import 'local_storage_service.dart';

Future<void> saveTempHumidityLocalFirst(
    BuildContext context, TempHumidityReport report) async {

  final local = context.read<LocalStorageService>();
  final online = context.read<ConnectivityProvider>().isOnline;
  final firestore = context.read<FirestoreService>();

  await local.saveTempHumidityReport(report.copyWith(isSynced: false));

  if (online) {
    unawaited((() async {
      try {
        await firestore.saveTempHumidityReport(report);
        await local.markTempReportSynced(report.id);
      } catch (_) {}
    })());
  }
}

Future<void> deleteTempHumidityLocalFirst(
    BuildContext context, String id) async {

  final local = context.read<LocalStorageService>();
  final online = context.read<ConnectivityProvider>().isOnline;
  final firestore = context.read<FirestoreService>();

  await local.deleteTempHumidityReport(id);

  if (online) {
    unawaited((() async {
      try {
        await firestore.deleteTempHumidityReport(id);
      } catch (_) {}
    })());
  }
}