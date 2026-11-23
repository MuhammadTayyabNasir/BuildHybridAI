import 'package:flutter_test/flutter_test.dart';
import 'package:pma/assistant/assistant_intent.dart';
import 'package:pma/assistant/assistant_service.dart';
import 'package:pma/assistant/hybrid_ai.dart';
import 'package:pma/assistant/rules_parser.dart';
import 'package:pma/models/packing_entry_model.dart';
import 'package:pma/models/temp_humidity_model.dart';
import 'package:pma/models/th_threshold_model.dart';

class FakeStore implements AssistantStore {
  final reports = <String, TempHumidityReport>{};
  final entries = <PackingEntryModel>[];
  final kv = <String, String>{};

  @override
  String get userId => 'u1';
  @override
  String get userName => 'operator1';
  @override
  List<PackingEntryModel> packingEntries() => entries;
  @override
  List<TempHumidityReport> thReports() => reports.values.toList();
  @override
  ThThreshold thresholdFor(String sectionId) => ThThreshold.defaults(sectionId);
  @override
  Future<void> saveThReport(TempHumidityReport r) async => reports[r.id] = r;
  @override
  Future<void> deleteThReport(String id) async => reports.remove(id);
  @override
  String? meta(String key) => kv[key];
  @override
  Future<void> setMeta(String key, String value) async => kv[key] = value;
}

/// No on-device model and no network: everything goes through the rules.
class OfflineAi implements HybridAi {
  @override
  bool get available => false;
  @override
  Future<String> status() async => 'unsupported';
  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async => null;
  @override
  Future<HybridAnswer?> generate(String prompt, {bool cloudOnly = false}) async => null;
}

class ScriptedAi extends OfflineAi {
  ScriptedAi(this.json, this.source);
  final String json;
  final AnswerSource source;
  @override
  bool get available => true;
  @override
  Future<HybridAnswer?> parseIntent(String text, {required DateTime now}) async =>
      HybridAnswer(json, source);
}

PackingEntryModel entry(DateTime at, {String op = 'u1'}) => PackingEntryModel(
      id: 'e${at.microsecondsSinceEpoch}',
      machineId: 'm1',
      machineNumber: 1,
      section: 'chips',
      productId: 'p1',
      productName: 'Test chips',
      price: 20,
      shift: 'morning',
      operatorId: op,
      operatorName: op == 'u1' ? 'operator1' : 'someone',
      dateCodingManufacture: at,
      dateCodingExpiry: at,
      grossWeight: 20,
      weightStatus: 'pass',
      printingStatus: 'pass',
      leakageStatus: 'pass',
      moistureStatus: 'pass',
      createdAt: at,
      updatedAt: at,
    );

void main() {
  const rules = RulesParser();

  group('RulesParser', () {
    test('Roman Urdu humidity with section', () {
      final i = rules.parse('Peri Peri section ki humidity 45 dal do');
      expect(i.type, IntentType.addThReading);
      expect(i.section, 'peri_peri');
      expect(i.humidity, 45);
      expect(i.temperature, isNull);
      expect(i.source, AnswerSource.rules);
    });

    test('Urdu number words and both values', () {
      final i = rules.parse('chips ki humidity paintalis aur temperature pachees degree');
      expect(i.section, 'chips');
      expect(i.humidity, 45);
      expect(i.temperature, 25);
    });

    test('humidity first then temperature keeps each value', () {
      final i = rules.parse('aj ki nimko humidity 30 or temperature 25 degree dal do');
      expect(i.humidity, 30);
      expect(i.temperature, 25);
    });

    test('Urdu script digits and words', () {
      final i = rules.parse('ویفر کی نمی پینتالیس');
      expect(i.type, IntentType.addThReading);
      expect(i.section, 'wafer');
      expect(i.humidity, 45);
    });

    test('count, missing and open intents', () {
      expect(rules.parse('aaj main ne kitni entries ki?').type, IntentType.countEntries);
      expect(rules.parse('aaj meri koi entry miss to nahi hui?').type,
          IntentType.findMissingEntries);
      final open = rules.parse('Peri Peri ki sheet kholo');
      expect(open.type, IntentType.openScreen);
      expect(open.section, 'peri_peri');
      expect(open.screen, 'entries');
    });

    test('confirmation replies', () {
      expect(rules.confirmReply('haan').kind, ConfirmKind.yes);
      expect(rules.confirmReply('theek hai').kind, ConfirmKind.yes);
      expect(rules.confirmReply('nahi').kind, ConfirmKind.no);
      final c = rules.confirmReply('nahi 48 karo');
      expect(c.kind, ConfirmKind.correct);
      expect(c.value, 48);
    });

    test('fast mode voice command', () {
      expect(rules.fastModeCommand('ab se confirm ki zaroorat nahi'), isTrue);
      expect(rules.fastModeCommand('confirm kiya karo'), isFalse);
      expect(rules.fastModeCommand('humidity 40'), isNull);
    });
  });

  group('AssistantIntent JSON', () {
    test('parses model JSON and normalizes section', () {
      final i = AssistantIntent.tryParseJson(
        '{"intent":"add_th_reading","section":"Peri Peri","humidity":45,"confidence":0.9}',
        AnswerSource.onDevice,
      )!;
      expect(i.type, IntentType.addThReading);
      expect(i.section, 'peri_peri');
      expect(i.humidity, 45);
      expect(i.source, AnswerSource.onDevice);
    });

    test('rejects non JSON', () {
      expect(AssistantIntent.tryParseJson('sorry', AnswerSource.cloud), isNull);
    });
  });

  group('AssistantService', () {
    late FakeStore store;
    late AssistantService svc;
    final now = DateTime(2026, 11, 24, 10, 30);

    setUp(() {
      store = FakeStore();
      svc = AssistantService(store: store, ai: OfflineAi(), clock: () => now);
    });

    test('reading is read back and saved only after haan', () async {
      final r1 = await svc.handle('Peri Peri section ki humidity 45 dal do');
      expect(r1.pending?.kind, PendingKind.thReading);
      expect(store.reports, isEmpty);
      expect(r1.statuses['humidity'], 'green');

      final r2 = await svc.handle('haan');
      expect(r2.saved, isTrue);
      final saved = store.reports.values.single;
      expect(saved.sectionId, 'peri_peri');
      expect(saved.shift, 'morning');
      expect(saved.rows.single.humidity, 45);
      expect(saved.rows.single.confirmedBy, 'operator1');
      expect(saved.rows.single.source, 'assistant:rules');
    });

    test('nahi cancels', () async {
      await svc.handle('chips humidity 45');
      final r = await svc.handle('nahi');
      expect(r.saved, isFalse);
      expect(svc.pending, isNull);
      expect(store.reports, isEmpty);
    });

    test('nahi 48 karo corrects and re-confirms', () async {
      await svc.handle('chips humidity 45');
      final r = await svc.handle('nahi 48 karo');
      expect(r.pending?.draft?.humidity, 48);
      expect(store.reports, isEmpty);
      await svc.handle('okay');
      expect(store.reports.values.single.rows.single.humidity, 48);
    });

    test('asks for a section when none was said', () async {
      final r = await svc.handle('humidity 40 dal do');
      expect(r.pending?.kind, PendingKind.needSection);
      final r2 = await svc.handle('nimko');
      expect(r2.pending?.draft?.sectionId, 'nimko');
    });

    test('out of range humidity is rejected', () async {
      final r = await svc.handle('chips humidity 140');
      expect(r.pending, isNull);
      expect(store.reports, isEmpty);
    });

    test('fast mode saves safe values but still confirms red', () async {
      await store.setMeta(AssistantService.fastModeKey, '1');
      final safe = await svc.handle('chips humidity 45');
      expect(safe.saved, isTrue);
      final red = await svc.handle('chips humidity 70');
      expect(red.saved, isFalse);
      expect(red.pending?.kind, PendingKind.thReading);
    });

    test('fast mode voice toggle needs confirmation', () async {
      final r = await svc.handle('ab se confirm ki zaroorat nahi');
      expect(r.pending?.kind, PendingKind.fastModeOn);
      expect(svc.fastMode, isFalse);
      await svc.handle('haan');
      expect(svc.fastMode, isTrue);
    });

    test('undo removes the last saved reading after confirmation', () async {
      await svc.handle('chips humidity 45');
      await svc.handle('haan');
      expect(store.reports, hasLength(1));
      final ask = await svc.handle('undo');
      expect(ask.pending?.kind, PendingKind.undo);
      await svc.handle('haan');
      expect(store.reports, isEmpty);
    });

    test('missing entries uses the schedule and only started shifts', () async {
      await store.setMeta(AssistantService.scheduleKey,
          const ThSchedule(sectionIds: ['chips', 'nimko'], shifts: ['morning', 'night']).toJson());
      var miss = svc.missingReadings(now);
      expect(miss.map((m) => m.sectionId), ['chips', 'nimko']); // night not started
      await svc.handle('chips humidity 45 temperature 30');
      await svc.handle('haan');
      miss = svc.missingReadings(now);
      expect(miss.single.sectionId, 'nimko');
      final r = await svc.handle('aaj koi entry miss to nahi hui');
      expect(r.en, contains('Nimko'));
    });

    test('count entries counts only my entries today', () async {
      store.entries.addAll([
        entry(now),
        entry(now.subtract(const Duration(hours: 1))),
        entry(now, op: 'other'),
        entry(now.subtract(const Duration(days: 1))),
      ]);
      await svc.handle('chips temperature 30');
      await svc.handle('haan');
      final r = await svc.handle('aaj main ne kitni entries ki?');
      expect(r.en, contains('2 packing entries'));
      expect(r.en, contains('1 temperature/humidity reading'));
    });

    test('batch dictation reads back once and saves all on haan', () async {
      await svc.handle('batch shuru karo');
      expect(svc.batch, isEmpty);
      await svc.handle('chips humidity 45');
      await svc.handle('nimko temperature 30');
      final noSection = await svc.handle('humidity 40');
      expect(noSection.en, contains('section'));
      await svc.handle('wafer humidity paintalis');
      expect(store.reports, isEmpty);
      final review = await svc.handle('bas');
      expect(review.pending?.kind, PendingKind.batchReview);
      expect(review.pending?.batch, hasLength(3));
      expect(review.en, startsWith('3 readings'));

      final fixed = await svc.handle('number 2 temperature 32');
      expect(fixed.pending?.batch[1].temperature, 32);
      final removed = await svc.handle('number 3 hatao');
      expect(removed.pending?.batch, hasLength(2));

      final saved = await svc.handle('haan');
      expect(saved.saved, isTrue);
      expect(store.reports, hasLength(2));
      final nimko = store.reports.values.firstWhere((r) => r.sectionId == 'nimko');
      expect(nimko.rows.single.temperature, 32);
      expect(nimko.rows.single.confirmedBy, 'operator1');
    });

    test('batch item number out of range is reported', () async {
      await svc.handle('batch mode');
      await svc.handle('chips humidity 45');
      await svc.handle('done');
      final r = await svc.handle('number 5 humidity 40');
      expect(r.en, contains('no item 5'));
      expect(svc.pending?.kind, PendingKind.batchReview);
    });

    test('model answer source is reported', () async {
      final cloud = AssistantService(
        store: store,
        ai: ScriptedAi('{"intent":"count_entries","period":"today"}', AnswerSource.cloud),
        clock: () => now,
      );
      final r = await cloud.handle('how many entries did I make today');
      expect(r.source, AnswerSource.cloud);
    });
  });
}
