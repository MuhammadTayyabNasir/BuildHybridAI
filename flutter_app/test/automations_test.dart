import 'package:flutter_test/flutter_test.dart';
import 'package:pma/analytics/pma_metrics.dart';
import 'package:pma/assistant/assistant_intent.dart';
import 'package:pma/assistant/hybrid_ai.dart';
import 'package:pma/automations/automation_engine.dart';
import 'package:pma/automations/automation_rule.dart';
import 'package:pma/automations/automation_service.dart';
import 'package:pma/automations/rule_suggester.dart';
import 'package:pma/models/temp_humidity_model.dart';
import 'package:pma/models/th_threshold_model.dart';

TempHumidityReport report(String section, DateTime at,
        {double? t, double? h, String shift = 'morning', String id = 'r1'}) =>
    TempHumidityReport(
      id: id,
      sectionId: section,
      date: DateTime(at.year, at.month, at.day),
      shift: shift,
      rows: [
        TempHumidityRow(time: '10:00', temperature: t, humidity: h, section: section, enteredAt: at),
      ],
      createdAt: at,
      updatedAt: at,
    );

class TextAi implements HybridAi {
  TextAi(this.text);
  final String? text;
  @override
  bool get available => true;
  @override
  Future<String> status() async => 'available';
  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async => null;
  @override
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false}) async =>
      text == null ? null : HybridAnswer(text!, AnswerSource.onDevice);
}

void main() {
  const engine = AutomationEngine();
  ThThreshold th(String s) => ThThreshold.defaults(s);
  List<({String sectionId, String shift, String missing})> none(DateTime _) => const [];

  group('AutomationRule', () {
    test('defaults are valid and round-trip through JSON', () {
      final rules = AutomationRule.defaults();
      expect(rules.every((r) => r.validate() == null), isTrue);
      final back = AutomationRule.listFromJson(AutomationRule.listToJson(rules));
      expect(back.map((r) => r.describeEn()), rules.map((r) => r.describeEn()));
    });

    test('validation rejects bad times, metrics and limits', () {
      expect(const AutomationRule(id: 'a', kind: RuleKind.reminder, time: '25:00', messageEn: 'x').validate(),
          isNotNull);
      expect(const AutomationRule(id: 'a', kind: RuleKind.conditionAlert, metric: 'pressure', op: 'gt', value: 3)
          .validate(), isNotNull);
      expect(const AutomationRule(id: 'a', kind: RuleKind.conditionAlert, metric: 'humidity', op: 'gt', value: 140)
          .validate(), isNotNull);
      expect(const AutomationRule(id: 'a', kind: RuleKind.conditionAlert, metric: 'humidity', op: 'gt', value: 50)
          .validate(), isNull);
    });

    test('AI-origin rules are forced unapproved and paused', () {
      final r = AutomationRule.fromMap({
        'kind': 'condition_alert',
        'metric': 'humidity',
        'op': 'gt',
        'value': 52,
        'approved': true,
        'enabled': true,
      }, forceOrigin: 'ai')!;
      expect(r.approved, isFalse);
      expect(r.enabled, isFalse);
      expect(r.active, isFalse);
    });
  });

  group('AutomationEngine', () {
    final now = DateTime(2026, 11, 24, 19, 40);

    test('condition alert fires once per reading and respects dedupe', () {
      final rules = [
        const AutomationRule(id: 'hum', kind: RuleKind.conditionAlert, metric: 'humidity', op: 'red'),
      ];
      final reports = [report('chips', now.subtract(const Duration(hours: 1)), h: 60)];
      final first = engine.evaluate(
          rules: rules, now: now, reports: reports, threshold: th, missing: none, alreadyFired: {});
      expect(first, hasLength(1));
      expect(first.single.severity, 'critical');
      expect(first.single.en, contains('Chips humidity 60%'));
      final again = engine.evaluate(
          rules: rules,
          now: now,
          reports: reports,
          threshold: th,
          missing: none,
          alreadyFired: {first.single.key});
      expect(again, isEmpty);
    });

    test('green readings and paused rules do not fire', () {
      final reports = [report('chips', now, h: 40)];
      final rules = [
        const AutomationRule(id: 'hum', kind: RuleKind.conditionAlert, metric: 'humidity', op: 'red'),
        const AutomationRule(
            id: 'p', kind: RuleKind.conditionAlert, metric: 'humidity', op: 'gt', value: 10, enabled: false),
      ];
      expect(
          engine.evaluate(
              rules: rules, now: now, reports: reports, threshold: th, missing: none, alreadyFired: {}),
          isEmpty);
    });

    test('shift-end check reports missed readings for its shift only', () {
      final rule = const AutomationRule(id: 'm', kind: RuleKind.shiftEndCheck, time: '19:30', shift: 'morning');
      final events = engine.evaluate(
        rules: [rule],
        now: now,
        reports: const [],
        threshold: th,
        missing: (day) => [
          (sectionId: 'chips', shift: 'morning', missing: 'humidity'),
          (sectionId: 'wafer', shift: 'night', missing: 'both'),
        ],
        alreadyFired: {},
      );
      expect(events, hasLength(1));
      expect(events.single.en, contains('Chips (humidity)'));
      expect(events.single.en, isNot(contains('Wafer')));
    });

    test('night check in the morning looks at the previous day', () {
      DateTime? asked;
      engine.evaluate(
        rules: [const AutomationRule(id: 'n', kind: RuleKind.shiftEndCheck, time: '07:30', shift: 'night')],
        now: DateTime(2026, 11, 24, 7, 45),
        reports: const [],
        threshold: th,
        missing: (day) {
          asked = day;
          return const [];
        },
        alreadyFired: {},
      );
      expect(asked, DateTime(2026, 11, 23));
    });

    test('reminder fires inside its window, not before or long after', () {
      final rule = const AutomationRule(id: 'r', kind: RuleKind.reminder, time: '09:00', messageEn: 'Take readings');
      List<AutomationEvent> at(DateTime t) => engine.evaluate(
          rules: [rule], now: t, reports: const [], threshold: th, missing: none, alreadyFired: {});
      expect(at(DateTime(2026, 11, 24, 8, 59)), isEmpty);
      expect(at(DateTime(2026, 11, 24, 9, 5)), hasLength(1));
      expect(at(DateTime(2026, 11, 24, 13, 0)), isEmpty);
    });
  });

  group('RuleSuggester', () {
    final now = DateTime(2026, 11, 24, 12);
    PmaMetrics metrics() => PmaMetrics(
          entries: const [],
          reports: [
            report('nimko', now.subtract(const Duration(days: 1)), h: 62, id: 'a'),
            report('nimko', now.subtract(const Duration(days: 2)), h: 64, id: 'b'),
          ],
          threshold: th,
          now: now,
        );

    test('parses whitelisted model JSON and drops invalid rules', () async {
      final ai = TextAi('{"rules":[{"kind":"condition_alert","sectionId":"nimko","metric":"humidity",'
          '"op":"gt","value":54,"notifyManager":true,"reason":"2 red readings"},'
          '{"kind":"delete_everything"},'
          '{"kind":"condition_alert","metric":"humidity","op":"gt","value":900}]}');
      final res = await RuleSuggester(ai).suggest(metrics(), const []);
      expect(res.source, AnswerSource.onDevice);
      expect(res.rules, hasLength(1));
      expect(res.rules.single.origin, 'ai');
      expect(res.rules.single.approved, isFalse);
    });

    test('falls back to heuristics without a model', () async {
      final res = await RuleSuggester(TextAi(null)).suggest(metrics(), const []);
      expect(res.source, AnswerSource.rules);
      expect(res.rules.single.sectionId, 'nimko');
      expect(res.rules.single.metric, 'humidity');
    });
  });

  group('AutomationService', () {
    test('queues manager alerts offline and sends them when online', () async {
      final kv = <String, String>{};
      var online = false;
      final sent = <String>[];
      final now = DateTime(2026, 11, 24, 12);
      final svc = AutomationService(
        readMeta: (k) => kv[k],
        writeMeta: (k, v) async => kv[k] = v,
        reports: () => [report('chips', now, t: 45)],
        threshold: th,
        missing: none,
        isOnline: () => online,
        sendAlert: (e) async => sent.add(e.key),
        clock: () => now,
      );
      final fired = await svc.tick();
      expect(fired, hasLength(1)); // red temperature default rule
      expect(sent, isEmpty);
      expect(svc.pendingAlerts, 1);

      online = true;
      expect(await svc.tick(), isEmpty); // deduped
      expect(sent, hasLength(1));
      expect(svc.pendingAlerts, 0);
      expect(svc.inbox, hasLength(1));
    });

    test('suggestions need approval before they run', () async {
      final kv = <String, String>{};
      final now = DateTime(2026, 11, 24, 12);
      final svc = AutomationService(
        readMeta: (k) => kv[k],
        writeMeta: (k, v) async => kv[k] = v,
        reports: () => const [],
        threshold: th,
        missing: none,
        clock: () => now,
      );
      final ai = TextAi('{"rules":[{"kind":"reminder","time":"09:00","messageEn":"Check chips humidity"}]}');
      final res = await svc.suggest(RuleSuggester(ai),
          PmaMetrics(entries: const [], reports: const [], threshold: th, now: now));
      expect(res.added, 1);
      final id = svc.suggestions.single.id;
      expect(svc.rules.any((r) => r.id == id), isFalse);
      await svc.setEnabled(id, true); // cannot enable an unapproved rule
      expect(svc.suggestions.single.enabled, isFalse);
      await svc.approve(id);
      expect(svc.rules.singleWhere((r) => r.id == id).active, isTrue);
    });
  });
}
