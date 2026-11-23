import 'package:flutter_test/flutter_test.dart';
import 'package:pma/analytics/dashboard_spec.dart';
import 'package:pma/analytics/pma_metrics.dart';
import 'package:pma/models/temp_humidity_model.dart';
import 'package:pma/models/th_threshold_model.dart';

TempHumidityReport report(String section, DateTime day, List<(double?, double?)> values) =>
    TempHumidityReport(
      id: '$section-${day.day}',
      sectionId: section,
      date: DateTime(day.year, day.month, day.day),
      shift: 'morning',
      rows: [
        for (var i = 0; i < values.length; i++)
          TempHumidityRow(
            time: '09:0$i',
            temperature: values[i].$1,
            humidity: values[i].$2,
            section: section,
            enteredAt: day.add(Duration(minutes: i)),
          ),
      ],
      createdAt: day,
      updatedAt: day,
    );

void main() {
  final now = DateTime(2026, 11, 24, 15);

  PmaMetrics metrics(List<TempHumidityReport> reports) => PmaMetrics(
        entries: const [],
        reports: reports,
        threshold: ThThreshold.defaults,
        now: now,
      );

  group('PmaMetrics', () {
    test('readings per day and trend', () {
      final m = metrics([
        report('chips', now, [(30, 40), (31, 41)]),
        report('nimko', now.subtract(const Duration(days: 1)), [(30, 40)]),
      ]);
      expect(m.readingsPerDay(3), [0, 1, 2]);
      expect(PmaMetrics.trend([1, 1, 2]), 100);
      expect(PmaMetrics.trend([0, 0, 2]), isNull);
    });

    test('latest reading combines last temperature and humidity', () {
      final m = metrics([
        report('chips', now, [(30, null), (null, 60)]),
      ]);
      final r = m.latest('chips');
      expect(r.temperature, 30);
      expect(r.humidity, 60);
      expect(r.humStatus, 'red');
      expect(r.status, 'red');
      expect(m.latest('wafer').status, 'none');
    });

    test('summary has no names, only numbers', () {
      final s = metrics([report('chips', now, [(30, 40)])]).summary(days: 7);
      final chips = (s['sections'] as Map)['chips'] as Map;
      expect(chips['readings'], 1);
      expect(chips['avgHumidity'], 40);
      expect(s.toString(), isNot(contains('operator')));
    });
  });

  group('DashboardSpec', () {
    test('accepts a valid model dashboard', () {
      final spec = DashboardSpec.tryParse('''Here you go:
{"title":"Week","summary":"Fine.","spoken":"All good.",
 "kpis":[{"label":"Readings","value":"42","trend":"+5%","status":"green"}],
 "charts":[{"type":"bar","title":"Per day","labels":["M","T"],"values":[3,4],"unit":""}],
 "insights":["Keep going."]}''')!;
      expect(spec.title, 'Week');
      expect(spec.kpis.single.status, 'green');
      expect(spec.charts.single.values, [3, 4]);
    });

    test('drops unknown chart types, mismatched series and extra kpis', () {
      final spec = DashboardSpec.tryParse('''{"title":"x",
 "kpis":[${List.generate(9, (i) => '{"label":"k$i","value":"$i","status":"purple"}').join(',')}],
 "charts":[{"type":"html","title":"a","labels":["a"],"values":[1]},
           {"type":"line","title":"b","labels":["a","b"],"values":[1]},
           {"type":"line","title":"c","labels":["a"],"values":[2]}]}''')!;
      expect(spec.kpis, hasLength(DashboardSpec.maxKpis));
      expect(spec.kpis.first.status, isNull);
      expect(spec.charts.map((c) => c.title), ['c']);
    });

    test('rejects text that is not a dashboard', () {
      expect(DashboardSpec.tryParse('I cannot help with that.'), isNull);
      expect(DashboardSpec.tryParse('{"title":"empty"}'), isNull);
    });

    test('local fallback flags red and silent sections', () {
      final spec = DashboardSpec.local(
        metrics([report('chips', now, [(45, 40)])]),
        urdu: false,
        days: 7,
      );
      expect(spec.kpis.firstWhere((k) => k.label == 'Red values').value, '1');
      expect(spec.insights.join(' '), contains('Chips'));
      expect(spec.insights.join(' '), contains('Nimko'));
      expect(spec.charts.first.values.last, 1);
    });
  });
}
