import 'dart:convert';

import '../core/constants/sections.dart';
import 'pma_metrics.dart';

class KpiSpec {
  const KpiSpec({required this.label, required this.value, this.trend, this.status});
  final String label;
  final String value;
  final String? trend; // e.g. "+12%"
  final String? status; // green | yellow | red
}

class ChartSpec {
  const ChartSpec({
    required this.type,
    required this.title,
    required this.labels,
    required this.values,
    this.unit = '',
  });
  final String type; // line | bar
  final String title;
  final List<String> labels;
  final List<double> values;
  final String unit;
}

/// A small declarative dashboard: the cloud model chooses which numbers and
/// charts matter and writes the explanation; the app renders only these
/// whitelisted components with its own widgets, so model output can never
/// inject UI or code.
class DashboardSpec {
  const DashboardSpec({
    required this.title,
    required this.summary,
    required this.spoken,
    required this.kpis,
    required this.charts,
    required this.insights,
  });

  final String title;
  final String summary;
  final String spoken;
  final List<KpiSpec> kpis;
  final List<ChartSpec> charts;
  final List<String> insights;

  static const maxKpis = 6;
  static const maxCharts = 4;
  static const maxPoints = 31;

  /// Prompt for cloud Gemini. [facts] is [PmaMetrics.summary]: counts and
  /// averages only, no names or free text.
  static String prompt(Map<String, Object?> facts, {required bool urdu}) => '''
You are the analyst for a snack factory's quality team. Using ONLY the JSON
facts below, design a small dashboard for the manager. Return ONLY JSON with
this exact shape and nothing else:
{"title": string, "summary": string (2-3 sentences, English),
 "spoken": string (a 20-40 second spoken explanation in ${urdu ? 'Urdu script' : 'simple English'}),
 "kpis": [{"label": string, "value": string, "trend": string or null, "status": "green"|"yellow"|"red"|null}] (max 6),
 "charts": [{"type": "line"|"bar", "title": string, "labels": [string], "values": [number], "unit": string}] (max 4, values and labels same length, max 31 points),
 "insights": [string] (max 4, each one sentence, actionable)}
Point out sections with red readings, sections with no readings, and trends.
Never invent numbers that are not derivable from the facts.
Facts: ${jsonEncode(facts)}
''';

  /// Parses and validates model output. Returns null if it is not usable.
  static DashboardSpec? tryParse(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final m = jsonDecode(raw.substring(start, end + 1));
      if (m is! Map) return null;
      String s(Object? v, [int max = 400]) {
        final t = v is String ? v.trim() : '';
        return t.length > max ? t.substring(0, max) : t;
      }

      final kpis = <KpiSpec>[];
      for (final k in (m['kpis'] is List ? m['kpis'] as List : const [])) {
        if (k is! Map || kpis.length >= maxKpis) continue;
        final label = s(k['label'], 40);
        final value = s(k['value'], 16);
        if (label.isEmpty || value.isEmpty) continue;
        final status = s(k['status'], 8);
        kpis.add(KpiSpec(
          label: label,
          value: value,
          trend: s(k['trend'], 10).isEmpty ? null : s(k['trend'], 10),
          status: const {'green', 'yellow', 'red'}.contains(status) ? status : null,
        ));
      }
      final charts = <ChartSpec>[];
      for (final c in (m['charts'] is List ? m['charts'] as List : const [])) {
        if (c is! Map || charts.length >= maxCharts) continue;
        final type = s(c['type'], 6);
        if (type != 'line' && type != 'bar') continue;
        final labels = (c['labels'] is List ? c['labels'] as List : const [])
            .map((e) => s(e, 12))
            .toList();
        final values = (c['values'] is List ? c['values'] as List : const [])
            .map((e) => e is num ? e.toDouble() : double.tryParse('$e'))
            .toList();
        if (values.isEmpty ||
            values.length != labels.length ||
            values.length > maxPoints ||
            values.any((v) => v == null || v.isNaN || v.isInfinite)) {
          continue;
        }
        charts.add(ChartSpec(
          type: type,
          title: s(c['title'], 60),
          labels: labels,
          values: values.cast<double>(),
          unit: s(c['unit'], 10),
        ));
      }
      final insights = (m['insights'] is List ? m['insights'] as List : const [])
          .map((e) => s(e, 220))
          .where((e) => e.isNotEmpty)
          .take(4)
          .toList();
      final title = s(m['title'], 60);
      if (kpis.isEmpty && charts.isEmpty) return null;
      return DashboardSpec(
        title: title.isEmpty ? 'Quality dashboard' : title,
        summary: s(m['summary'], 600),
        spoken: s(m['spoken'], 1200),
        kpis: kpis,
        charts: charts,
        insights: insights,
      );
    } catch (_) {
      return null;
    }
  }

  /// Deterministic dashboard built on the phone when no model is reachable.
  factory DashboardSpec.local(PmaMetrics metrics, {required bool urdu, int days = 30}) {
    final facts = metrics.summary(days: days);
    final sections = facts['sections'] as Map<String, Object?>;
    final last7 = facts['last7Days'] as Map<String, Object?>;
    var totalReadings = 0;
    var red = 0;
    final silent = <String>[];
    final hot = <String>[];
    final avgHum = <String>[];
    final avgHumVals = <double>[];
    for (final s in Sections.all) {
      final m = sections[s.id] as Map<String, Object?>;
      final n = m['readings'] as int;
      totalReadings += n;
      final r = (m['redTemperature'] as int) + (m['redHumidity'] as int);
      red += r;
      if (n == 0) silent.add(s.name);
      if (r > 0) hot.add(s.name);
      final h = m['avgHumidity'] as double?;
      if (h != null) {
        avgHum.add(s.name);
        avgHumVals.add(h);
      }
    }
    final pass = facts['packingPassRate7d'] as double;
    final readings7 = (last7['readings'] as List).cast<double>();
    final entries7 = (last7['packingEntries'] as List).cast<double>();
    final labels7 = (last7['labels'] as List).cast<String>();
    final trend = PmaMetrics.trend(readings7);
    final insights = <String>[
      if (hot.isNotEmpty) 'Red readings in ${hot.join(', ')} — check ventilation and packing room conditions.',
      if (silent.isNotEmpty) 'No readings recorded in ${silent.join(', ')} over the last $days days.',
      if (pass < 90 && entries7.any((e) => e > 0)) 'Only ${pass.toStringAsFixed(0)}% of packing checks passed every test this week.',
      if (hot.isEmpty && silent.isEmpty) 'All sections are reporting and no reading crossed the red limit.',
    ];
    final spokenEn = 'In the last $days days the team recorded $totalReadings readings, '
        'with $red above the red limit. '
        '${hot.isEmpty ? 'No section went red.' : hot.length >= 5 ? 'Every section had at least one red reading.' : 'Watch ${_list(hot)}.'} '
        '${pass > 0 ? 'This week ${pass.toStringAsFixed(0)} percent of packing checks passed.' : ''}';
    final spokenUr = 'پچھلے $days دنوں میں $totalReadings ریڈنگز ہوئیں، جن میں سے $red سرخ حد سے اوپر تھیں۔ '
        '${hot.isEmpty ? 'کوئی سیکشن سرخ نہیں ہوا۔' : hot.length >= 5 ? 'ہر سیکشن میں کم از کم ایک سرخ ریڈنگ آئی۔' : '${hot.join('، ')} پر نظر رکھیں۔'}';
    return DashboardSpec(
      title: 'Last $days days',
      summary: spokenEn,
      spoken: urdu ? spokenUr : spokenEn,
      kpis: [
        KpiSpec(
          label: 'Readings',
          value: '$totalReadings',
          trend: trend == null ? null : '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(0)}%',
        ),
        KpiSpec(label: 'Red values', value: '$red', status: red == 0 ? 'green' : 'red'),
        KpiSpec(
          label: 'Checks passed',
          value: '${pass.toStringAsFixed(0)}%',
          status: pass >= 95 ? 'green' : pass >= 85 ? 'yellow' : 'red',
        ),
        KpiSpec(
          label: 'Silent sections',
          value: '${silent.length}',
          status: silent.isEmpty ? 'green' : 'yellow',
        ),
      ],
      charts: [
        ChartSpec(type: 'line', title: 'Readings per day', labels: labels7, values: readings7),
        ChartSpec(type: 'bar', title: 'Packing checks per day', labels: labels7, values: entries7),
        if (avgHumVals.isNotEmpty)
          ChartSpec(
            type: 'bar',
            title: 'Average humidity by section',
            labels: avgHum,
            values: avgHumVals,
            unit: '%',
          ),
      ],
      insights: insights,
    );
  }
}

/// "A", "A and B", "A, B and C".
String _list(List<String> items) => items.length <= 2
    ? items.join(' and ')
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
