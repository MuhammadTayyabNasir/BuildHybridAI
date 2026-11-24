import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'extracted_form.dart';

/// Reads one page (1-based) and returns the model's raw JSON text.
typedef PageReader = Future<String> Function(int page);

/// Bulk extraction of a multi-page scanned PDF, one page per cloud call.
///
/// * Each page is retried with backoff; a page that still fails is recorded
///   and the job moves on, so one smudged page never blocks 79 others.
/// * Progress is saved after every page under a key derived from the file's
///   hash, so closing the app (or losing the network) resumes where it
///   stopped instead of paying for pages again.
class PdfExtractionJob extends ChangeNotifier {
  PdfExtractionJob({
    required this.fileHash,
    required this.fileName,
    required this.pageCount,
    required this.readPage,
    required this.readMeta,
    required this.writeMeta,
    this.maxAttempts = 3,
    this.backoff = const Duration(seconds: 2),
  }) {
    _restore();
  }

  final String fileHash;
  final String fileName;
  final int pageCount;
  final PageReader readPage;
  final String? Function(String key) readMeta;
  final Future<void> Function(String key, String value) writeMeta;
  final int maxAttempts;
  final Duration backoff;

  final Map<int, ExtractedPage> pages = {};
  final Map<int, String> failures = {};
  bool running = false;
  bool _cancel = false;
  int? current;

  String get _key => 'pma_pdf_job_$fileHash';
  int get done => pages.length;
  bool get complete => pages.length + failures.length >= pageCount && !running;

  void _restore() {
    final raw = readMeta(_key);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      for (final p in (m['pages'] as List? ?? const [])) {
        final page = ExtractedPage.fromJson(Map<String, Object?>.from(p as Map));
        pages[page.page] = page;
      }
      (m['failures'] as Map? ?? const {}).forEach((k, v) => failures[int.parse('$k')] = '$v');
    } catch (_) {
      // Corrupt progress: start over.
    }
  }

  Future<void> _persist() => writeMeta(
        _key,
        jsonEncode({
          'file': fileName,
          'pageCount': pageCount,
          'pages': [for (final p in pages.values) p.toJson()],
          'failures': {for (final e in failures.entries) '${e.key}': e.value},
        }),
      );

  /// Runs (or resumes) the job. [retryFailed] also re-attempts pages that
  /// failed in an earlier run.
  Future<void> run({bool retryFailed = false}) async {
    if (running) return;
    running = true;
    _cancel = false;
    notifyListeners();
    try {
      for (var page = 1; page <= pageCount; page++) {
        if (_cancel) break;
        if (pages.containsKey(page)) continue;
        if (failures.containsKey(page) && !retryFailed) continue;
        current = page;
        notifyListeners();
        final result = await _readWithRetry(page);
        if (result.page != null) {
          DittoFill.apply(result.page!.rows);
          pages[page] = result.page!;
          failures.remove(page);
        } else {
          failures[page] = result.error ?? 'unreadable';
        }
        await _persist();
        notifyListeners();
      }
    } finally {
      running = false;
      current = null;
      notifyListeners();
    }
  }

  Future<({ExtractedPage? page, String? error})> _readWithRetry(int page) async {
    String? error;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final raw = await readPage(page);
        final parsed = ExtractedPage.parseModel(raw, page);
        if (parsed != null) return (page: parsed, error: null);
        error = 'model reply was not a table';
      } catch (e) {
        error = '$e';
      }
      if (attempt < maxAttempts && backoff > Duration.zero) {
        await Future<void>.delayed(backoff * attempt);
      }
    }
    return (page: null, error: error);
  }

  void cancel() => _cancel = true;

  /// Forget saved progress (after the rows were saved or discarded).
  Future<void> clear() async {
    pages.clear();
    failures.clear();
    await writeMeta(_key, '');
    notifyListeners();
  }

  /// All rows in page order with their page header.
  List<({int page, ExtractedPage header, ExtractedRow row})> allRows() {
    final out = <({int page, ExtractedPage header, ExtractedRow row})>[];
    final keys = pages.keys.toList()..sort();
    for (final k in keys) {
      final p = pages[k]!;
      for (final r in p.rows) {
        out.add((page: k, header: p, row: r));
      }
    }
    return out;
  }
}
