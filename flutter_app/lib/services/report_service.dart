import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/platform_info.dart';
import '../models/custom_column_model.dart';
import 'firestore_service.dart';
import 'local_storage_service.dart';
import 'realtime_firestore_service.dart';
import 'th_threshold_service.dart';

// Modular Builders
import 'excel_builders/entries_report_builder.dart';
import 'excel_builders/analysis_report_builder.dart';

const kReportEntriesAuto = 'report_entries_auto';
const kReportEntriesDay = 'report_entries_day';
const kReportAnalysisAuto = 'report_analysis_auto';
const kReportAnalysisDay = 'report_analysis_day';
const kReportAnalysisWeeks = 'report_analysis_weeks';
const kReportSavePath = 'report_save_path';
const kWhatsappShare = 'whatsapp_share';
const kWhatsappRecipient = 'whatsapp_recipient';

const _kEntriesAuto = kReportEntriesAuto;
const _kEntriesDay = kReportEntriesDay;
const _kAnalysisAuto = kReportAnalysisAuto;
const _kAnalysisDay = kReportAnalysisDay;
const _kAnalysisWeeks = kReportAnalysisWeeks;
const _kBigGapDays = 7;

class AutoBackupResult {
  final String type;
  final String path;
  AutoBackupResult(this.type, this.path);
  String get fileName => path.split(Platform.pathSeparator).last;
}

class PendingBackup {
  final DateTime from;
  final DateTime to;
  PendingBackup(this.from, this.to);
  int get days => to.difference(from).inDays + 1;
}

class AutoBackupOutcome {
  final List<AutoBackupResult> saved;
  final PendingBackup? pendingEntries;
  AutoBackupOutcome(this.saved, this.pendingEntries);
}

class ReportService {
  final FirestoreService _firestore;
  final LocalStorageService _local;
  final ThThresholdService _thresholds;
  final RealtimeFirestoreService? _realtime;

  ReportService(
      this._firestore,
      this._local,
      this._thresholds, [
        this._realtime,
      ]);

  Future<void> _ensureRangeLocal(DateTime from, DateTime to) async {
    final rt = _realtime;
    if (rt != null) {
      try {
        final list = await rt.fetchEntriesInRange(from, to);
        for (final e in list) {
          if (!_local.hasEntry(e.id)) {
            await _local.saveEntry(e.copyWith(isSynced: true));
          }
        }
      } catch (_) {}
    } else {
      await _mergeFromFirestore(from: from, to: to);
    }
  }

  Future<void> _mergeFromFirestore({DateTime? from, DateTime? to}) async {
    if (PlatformInfo.isMobile) return;
    try {
      final remote = await _firestore.fetchAllEntries(from: from, to: to);
      for (final e in remote) {
        if (!_local.hasEntry(e.id)) {
          await _local.saveEntry(e.copyWith(isSynced: true));
        }
      }
    } catch (_) {}
  }

  Future<String> generateEntriesReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
    await _ensureRangeLocal(f, t);

    final entries = _local.getEntriesByDateRange(from: f, to: t)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final thReports = _local.getTempHumidityReports().where((r) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      return !d.isBefore(f) && !d.isAfter(t);
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    final customCols = await CustomColumnsService.load();
    final downloadDir = await _getDownloadsDir();

    return EntriesReportBuilder.build(
      from: f,
      to: t,
      entries: entries,
      thReports: thReports,
      customCols: customCols,
      thresholds: _thresholds,
      downloadDir: downloadDir,
    );
  }

  Future<String> generateAnalysisReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
    await _ensureRangeLocal(f, t);

    final entries = _local.getEntriesByDateRange(from: f, to: t);
    final customCols = await CustomColumnsService.load();
    final downloadDir = await _getDownloadsDir();

    return AnalysisReportBuilder.build(
      from: f,
      to: t,
      entries: entries,
      customCols: customCols,
      downloadDir: downloadDir,
    );
  }

  Future<AutoBackupOutcome> checkAndAutoDownload() async {
    final saved = <AutoBackupResult>[];
    PendingBackup? pending;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();

      if (prefs.getBool(_kEntriesAuto) ?? false) {
        final day = prefs.getInt(_kEntriesDay) ?? 0;
        final triggerToday = day == 0 || today.weekday == day;
        if (triggerToday) {
          final yesterday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
          final coveredStr = prefs.getString('auto_entries_covered_through');
          final covered = coveredStr == null ? null : DateTime.tryParse(coveredStr);
          final from = covered == null ? yesterday : DateTime(covered.year, covered.month, covered.day).add(const Duration(days: 1));
          if (!from.isAfter(yesterday)) {
            final gapDays = yesterday.difference(from).inDays + 1;
            if (gapDays > _kBigGapDays) {
              pending = PendingBackup(from, yesterday);
            } else {
              final path = await generateEntriesReport(from: from, to: yesterday);
              await prefs.setString('auto_entries_covered_through', yesterday.toIso8601String());
              saved.add(AutoBackupResult('Entries Log', path));
            }
          }
        }
      }

      if (prefs.getBool(_kAnalysisAuto) ?? false) {
        final day = prefs.getInt(_kAnalysisDay) ?? DateTime.monday;
        if (today.weekday == day) {
          if (!_alreadyRanToday(prefs, 'last_auto_analysis')) {
            final weeks = prefs.getInt(_kAnalysisWeeks) ?? 4;
            final path = await generateAnalysisReport(from: today.subtract(Duration(days: weeks * 7)), to: today);
            await prefs.setString('last_auto_analysis', today.toIso8601String());
            saved.add(AutoBackupResult('QC Analysis', path));
          }
        }
      }
    } catch (_) {}
    return AutoBackupOutcome(saved, pending);
  }

  Future<AutoBackupResult> downloadPendingEntries(PendingBackup p) async {
    final path = await generateEntriesReport(from: p.from, to: p.to);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_entries_covered_through', DateTime(p.to.year, p.to.month, p.to.day).toIso8601String());
    return AutoBackupResult('Entries Log', path);
  }

  bool _alreadyRanToday(SharedPreferences prefs, String key) {
    final s = prefs.getString(key);
    if (s == null) return false;
    final last = DateTime.tryParse(s);
    if (last == null) return false;
    final today = DateTime.now();
    return last.year == today.year && last.month == today.month && last.day == today.day;
  }

  Future<String> _getDownloadsDir() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
      return '$home\\Downloads';
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kReportSavePath);
    if (saved != null && saved.isNotEmpty) {
      final d = Directory(saved);
      if (await d.exists()) return saved;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }
}