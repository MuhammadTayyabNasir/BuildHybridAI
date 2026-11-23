import '../core/constants/sections.dart';
import '../models/packing_entry_model.dart';
import '../models/temp_humidity_model.dart';
import '../models/th_threshold_model.dart';

/// Latest temperature / humidity seen for a section.
class SectionReading {
  const SectionReading({
    required this.sectionId,
    this.temperature,
    this.humidity,
    this.tempStatus,
    this.humStatus,
    this.at,
  });
  final String sectionId;
  final double? temperature;
  final double? humidity;
  final String? tempStatus;
  final String? humStatus;
  final DateTime? at;

  /// Worst of the two statuses, for a single dot.
  String get status {
    final s = [tempStatus, humStatus];
    if (s.contains('red')) return 'red';
    if (s.contains('yellow')) return 'yellow';
    if (s.contains('green')) return 'green';
    return 'none';
  }
}

/// Aggregates over local data. Pure functions so the home screen, the
/// analytics dashboard and the tests share one definition of each number.
class PmaMetrics {
  PmaMetrics({
    required this.entries,
    required this.reports,
    required this.threshold,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  final List<PackingEntryModel> entries;
  final List<TempHumidityReport> reports;
  final ThThreshold Function(String sectionId) threshold;
  final DateTime now;

  DateTime get today => DateTime(now.year, now.month, now.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> lastDays(int n) =>
      [for (var i = n - 1; i >= 0; i--) today.subtract(Duration(days: i))];

  int readingsOn(DateTime day) => reports
      .where((r) => _sameDay(r.date, day))
      .fold(0, (n, r) => n + r.rows.length);

  int entriesOn(DateTime day) =>
      entries.where((e) => _sameDay(e.createdAt, day)).length;

  List<double> readingsPerDay(int n) =>
      [for (final d in lastDays(n)) readingsOn(d).toDouble()];

  List<double> entriesPerDay(int n) =>
      [for (final d in lastDays(n)) entriesOn(d).toDouble()];

  /// Percentage change of today vs the average of the previous [n] days.
  /// Null when there is no history to compare against.
  static double? trend(List<double> series) {
    if (series.length < 2) return null;
    final prev = series.sublist(0, series.length - 1);
    final avg = prev.reduce((a, b) => a + b) / prev.length;
    if (avg == 0) return null;
    return (series.last - avg) / avg * 100;
  }

  SectionReading latest(String sectionId) {
    final rows = <(DateTime, TempHumidityRow)>[];
    for (final r in reports.where((r) => r.sectionId == sectionId)) {
      for (final row in r.rows) {
        rows.add((row.enteredAt ?? r.updatedAt, row));
      }
    }
    if (rows.isEmpty) return SectionReading(sectionId: sectionId);
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    double? t;
    double? h;
    DateTime? at;
    for (final (stamp, row) in rows.reversed) {
      t ??= row.temperature;
      h ??= row.humidity;
      at ??= stamp;
      if (t != null && h != null) break;
    }
    final th = threshold(sectionId);
    return SectionReading(
      sectionId: sectionId,
      temperature: t,
      humidity: h,
      tempStatus: t == null ? null : th.classifyTemp(t),
      humStatus: h == null ? null : th.classifyHumidity(h),
      at: at,
    );
  }

  /// Share of packing checks that passed every quality check, last [days].
  double passRate({int days = 7}) {
    final from = today.subtract(Duration(days: days - 1));
    final recent = entries.where((e) => !e.createdAt.isBefore(from)).toList();
    if (recent.isEmpty) return 0;
    bool ok(String s) =>
        const {'pass', 'green', 'ok', 'okay', 'na'}.contains(s.toLowerCase());
    final passed = recent.where((e) =>
        ok(e.weightStatus) && ok(e.printingStatus) && ok(e.leakageStatus) && ok(e.moistureStatus));
    return passed.length / recent.length * 100;
  }

  /// Compact, name-free summary sent to the cloud model for dashboards.
  /// Contains only counts and averages — no operator names or free text.
  Map<String, Object?> summary({int days = 30}) {
    final from = today.subtract(Duration(days: days - 1));
    final sections = <String, Object?>{};
    for (final s in Sections.all) {
      final rows = reports
          .where((r) => r.sectionId == s.id && !r.date.isBefore(from))
          .expand((r) => r.rows)
          .toList();
      final temps = rows.map((r) => r.temperature).whereType<double>().toList();
      final hums = rows.map((r) => r.humidity).whereType<double>().toList();
      final th = threshold(s.id);
      final secEntries =
          entries.where((e) => e.section == s.id && !e.createdAt.isBefore(from)).length;
      sections[s.id] = {
        'name': s.name,
        'readings': rows.length,
        'packingEntries': secEntries,
        'avgTemperature': _avg(temps),
        'maxTemperature': temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b),
        'avgHumidity': _avg(hums),
        'maxHumidity': hums.isEmpty ? null : hums.reduce((a, b) => a > b ? a : b),
        'redTemperature': temps.where((t) => th.classifyTemp(t) == 'red').length,
        'redHumidity': hums.where((h) => th.classifyHumidity(h) == 'red').length,
        'limits': {
          'tempGreenMax': th.tempGreenMax,
          'tempYellowMax': th.tempYellowMax,
          'humGreenMax': th.humGreenMax,
          'humYellowMax': th.humYellowMax,
        },
      };
    }
    final days7 = lastDays(7);
    return {
      'periodDays': days,
      'today': '${today.year}-${today.month}-${today.day}',
      'sections': sections,
      'last7Days': {
        'labels': [for (final d in days7) '${d.day}/${d.month}'],
        'readings': readingsPerDay(7),
        'packingEntries': entriesPerDay(7),
      },
      'packingPassRate7d': double.parse(passRate().toStringAsFixed(1)),
    };
  }

  static double? _avg(List<double> v) => v.isEmpty
      ? null
      : double.parse((v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1));
}
