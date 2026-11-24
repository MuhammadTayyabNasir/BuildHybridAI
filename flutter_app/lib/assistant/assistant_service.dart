import 'dart:convert';

import '../analytics/pma_metrics.dart';
import '../core/constants/sections.dart';
import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import '../models/temp_humidity_model.dart';
import '../models/th_threshold_model.dart';
import 'assistant_intent.dart';
import 'hybrid_ai.dart';
import 'packing_voice.dart';
import 'rules_parser.dart';

/// Data the assistant reads and writes. Backed by the app's local-first
/// storage in production and by an in-memory fake in tests.
abstract class AssistantStore {
  String get userId;
  String get userName;
  List<PackingEntryModel> packingEntries();
  List<TempHumidityReport> thReports();
  ThThreshold thresholdFor(String sectionId);
  Future<void> saveThReport(TempHumidityReport report);
  Future<void> deleteThReport(String id);
  List<ProductModel> products();
  List<MachineModel> machines();

  /// Saves a packing check the same way the entry form does; returns its id.
  Future<String> savePackingEntry(PackingEntryModel entry);
  Future<void> deletePackingEntry(String id);
  String? meta(String key);
  Future<void> setMeta(String key, String value);
}

/// Where the UI should navigate after an `open_screen` intent.
class NavTarget {
  const NavTarget(this.screen, this.sectionId);
  final String screen;
  final String? sectionId;
}

enum PendingKind {
  thReading,
  needSection,
  fastModeOn,
  fastModeOff,
  undo,
  batchReview,
  packingNeedInfo,
  packingReview,
}

/// A temperature / humidity reading waiting for the operator's "haan".
class ThDraft {
  const ThDraft({
    required this.sectionId,
    required this.shift,
    required this.source,
    required this.confidence,
    this.temperature,
    this.humidity,
  });

  final String sectionId;
  final String shift;
  final AnswerSource source;
  final double confidence;
  final double? temperature;
  final double? humidity;

  ThDraft copyWith({String? sectionId, double? temperature, double? humidity}) =>
      ThDraft(
        sectionId: sectionId ?? this.sectionId,
        shift: shift,
        source: source,
        confidence: 1, // the operator stated it themselves
        temperature: temperature ?? this.temperature,
        humidity: humidity ?? this.humidity,
      );
}

class PendingAction {
  const PendingAction(this.kind, {this.draft, this.batch = const [], this.packing});
  final PendingKind kind;
  final ThDraft? draft;

  /// Packing check being collected or waiting for "haan".
  final PackingDraft? packing;

  /// Items waiting for one confirmation in batch mode.
  final List<ThDraft> batch;
}

/// One assistant turn, in both languages, with the engine that understood it.
class AssistantReply {
  const AssistantReply({
    required this.en,
    required this.ur,
    required this.source,
    this.pending,
    this.navigate,
    this.saved = false,
    this.statuses = const {},
  });

  final String en;
  final String ur;
  final AnswerSource source;
  final PendingAction? pending;
  final NavTarget? navigate;
  final bool saved;

  /// 'temperature' / 'humidity' -> 'green' | 'yellow' | 'red' for the card.
  final Map<String, String> statuses;

  String text(bool urdu) => urdu ? ur : en;
}

/// Admin-defined reading schedule. Default: temperature + humidity once per
/// shift (morning and night) for every section.
class ThSchedule {
  const ThSchedule({required this.sectionIds, required this.shifts});

  factory ThSchedule.defaults() => ThSchedule(
        sectionIds: Sections.ids,
        shifts: const ['morning', 'night'],
      );

  factory ThSchedule.fromJson(String? raw) {
    if (raw == null) return ThSchedule.defaults();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ThSchedule(
        sectionIds: List<String>.from(m['sections'] as List),
        shifts: List<String>.from(m['shifts'] as List),
      );
    } catch (_) {
      return ThSchedule.defaults();
    }
  }

  final List<String> sectionIds;
  final List<String> shifts;

  String toJson() => jsonEncode({'sections': sectionIds, 'shifts': shifts});

  /// A shift's reading is due once the shift has started.
  static bool started(String shift, DateTime now) =>
      shift == 'morning' ? now.hour >= 8 : now.hour >= 20;
}

class AssistantService {
  AssistantService({
    required this.store,
    required this.ai,
    this.rules = const RulesParser(),
    DateTime Function()? clock,
    Future<bool> Function()? isOnline,
  })  : _clock = clock ?? DateTime.now,
        isOnline = isOnline ?? _assumeOnline;

  static Future<bool> _assumeOnline() async => true;

  /// Whether the cloud model can be reached right now.
  final Future<bool> Function() isOnline;

  static const fastModeKey = 'pma_fast_mode';
  static const scheduleKey = 'pma_th_schedule';

  final AssistantStore store;
  final HybridAi ai;
  final RulesParser rules;
  final PackingVoice packingVoice = const PackingVoice();
  final DateTime Function() _clock;

  /// Id of the last packing check saved by voice, for "undo".
  String? _lastPackingId;

  PendingAction? pending;

  /// Readings collected while batch dictation is on (null when it is off).
  List<ThDraft>? batch;
  static const maxBatch = 20;
  ({String reportId, TempHumidityReport? before})? _lastSave;

  bool get fastMode => store.meta(fastModeKey) == '1';
  ThSchedule get schedule => ThSchedule.fromJson(store.meta(scheduleKey));

  /// Understands [text] with the hybrid model, falling back to rules.
  Future<AssistantIntent> understand(String text) async {
    final local = rules.parse(text);
    // Clear commands ("peri peri humidity 45", "aaj kitni entries") are
    // answered at once from the phone. The model is asked only when the
    // rules are unsure or a reading has no section, and never while offline
    // without Nano, where it could only time out.
    final clear = local.type != IntentType.unknown &&
        local.confidence >= 0.85 &&
        (local.type != IntentType.addThReading || local.section != null);
    if (clear && !ai.onDeviceReady) return local;
    if (!ai.onDeviceReady && !(await isOnline())) return local;
    final answer = await ai.parseIntent(text, now: _clock());
    final model = answer == null
        ? null
        : AssistantIntent.tryParseJson(answer.text, answer.source);
    if (model == null || model.type == IntentType.unknown) return local;
    if (model.type == local.type) {
      // Keep the model's reading but fill slots it missed from the rules.
      return AssistantIntent(
        type: model.type,
        source: model.source,
        section: model.section ?? local.section,
        temperature: model.temperature ?? local.temperature,
        humidity: model.humidity ?? local.humidity,
        shift: model.shift ?? local.shift,
        screen: model.screen ?? local.screen,
        period: model.period,
        product: model.product,
        weight: model.weight ?? local.weight,
        confidence: model.confidence,
      );
    }
    return model;
  }

  Future<AssistantReply> handle(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const AssistantReply(
        en: 'I did not hear anything. Please say it again.',
        ur: 'کچھ سنائی نہیں دیا۔ دوبارہ بولیں۔',
        source: AnswerSource.rules,
      );
    }
    if (pending != null) return _answerPending(trimmed);
    if (batch != null) return _collectBatch(trimmed);
    if (rules.isBatchStart(trimmed)) {
      batch = [];
      return const AssistantReply(
        en: 'Batch mode on. Say readings one by one, for example "chips humidity 45". Say "done" when finished and I will read them all back once.',
        ur: 'بیچ موڈ آن۔ ریڈنگز ایک ایک کر کے بولیں، مثلاً "چپس ہیومیڈیٹی 45"۔ ختم ہونے پر "بس" بولیں، میں سب ایک ساتھ سناؤں گا۔',
        source: AnswerSource.rules,
      );
    }

    final fast = rules.fastModeCommand(trimmed);
    if (fast != null) {
      pending = PendingAction(fast ? PendingKind.fastModeOn : PendingKind.fastModeOff);
      return AssistantReply(
        en: fast
            ? 'Turn on fast mode? Normal readings will save without asking. Red values, settings and deletes will still ask. Say yes or no.'
            : 'Turn fast mode off, so every reading is read back first? Say yes or no.',
        ur: fast
            ? 'فاسٹ موڈ آن کر دوں؟ عام ریڈنگ بغیر پوچھے محفوظ ہوگی۔ سرخ ویلیو، سیٹنگ اور ڈیلیٹ پر پھر بھی پوچھوں گا۔ ہاں یا نہیں؟'
            : 'فاسٹ موڈ بند کر دوں تاکہ ہر ریڈنگ پہلے سنائی جائے؟ ہاں یا نہیں؟',
        source: AnswerSource.rules,
        pending: pending,
      );
    }
    if (rules.isUndo(trimmed)) return _askUndo();
    final norm = RulesParser.normalize(trimmed);
    if (_lastEntryWords.any(norm.contains)) return _lastEntry();
    if (_listWords.any(norm.contains)) return _listCatalogue(norm);
    if (packingVoice.looksLikePacking(trimmed)) return _startPacking(trimmed);

    final intent = await understand(trimmed);
    switch (intent.type) {
      case IntentType.countEntries:
        return countEntries(intent);
      case IntentType.findMissingEntries:
        return missingEntries(intent);
      case IntentType.addThReading:
        return _startReading(intent);
      case IntentType.openScreen:
        return _open(intent);
      case IntentType.dailySummary:
        return dailySummary(intent);
      case IntentType.addPackingEntry:
        return _startPacking(trimmed,
            base: PackingDraft(sectionId: intent.section), source: intent.source);
      case IntentType.unknown:
        return AssistantReply(
          en: 'Sorry, I did not understand. You can say: "Peri Peri humidity 45", "how many entries today", or "any missed entries today".',
          ur: 'معاف کیجیے، سمجھ نہیں آیا۔ آپ کہہ سکتے ہیں: "پیری پیری ہیومیڈیٹی 45"، "آج کتنی انٹریاں ہوئیں"، یا "آج کوئی انٹری مس تو نہیں ہوئی"۔',
          source: intent.source,
        );
    }
  }

  // ---------------------------------------------------------------- queries

  AssistantReply countEntries(AssistantIntent intent) {
    final range = _range(intent.period);
    final mine = store.packingEntries().where((e) =>
        _inRange(e.createdAt, range) &&
        (e.operatorId == store.userId || e.operatorName == store.userName) &&
        (intent.section == null || e.section == intent.section));
    var readings = 0;
    for (final r in store.thReports()) {
      if (!_inRange(r.date, range)) continue;
      if (intent.section != null && r.sectionId != intent.section) continue;
      for (final row in r.rows) {
        final by = row.enteredBy.isNotEmpty ? row.enteredBy : r.preparedBy;
        if (by == store.userName) readings++;
      }
    }
    final packing = mine.length;
    final when = _periodEn(intent.period);
    final whenUr = _periodUr(intent.period);
    final scope = intent.section == null ? '' : ' in ${_nameEn(intent.section!)}';
    final scopeUr = intent.section == null ? '' : ' ${_nameUr(intent.section!)} میں';
    return AssistantReply(
      en: '$when you made $packing packing ${packing == 1 ? 'entry' : 'entries'} and $readings temperature/humidity ${readings == 1 ? 'reading' : 'readings'}$scope.',
      ur: '$whenUr آپ نے$scopeUr $packing پیکنگ انٹریاں اور $readings ٹمپریچر/ہیومیڈیٹی ریڈنگز کیں۔',
      source: intent.source,
    );
  }

  /// Short report of today. Facts are computed on the phone; Gemini (Nano
  /// when available) only phrases them, in English and Urdu. Without a model
  /// the same facts are read out as fixed sentences.
  Future<AssistantReply> dailySummary(AssistantIntent intent) async {
    final now = _clock();
    final m = PmaMetrics(
      entries: store.packingEntries(),
      reports: store.thReports(),
      threshold: store.thresholdFor,
      now: now,
    );
    final today = m.today;
    var red = 0;
    for (final r in store.thReports().where((r) => _sameDay(r.date, today))) {
      final th = store.thresholdFor(r.sectionId);
      for (final row in r.rows) {
        if ((row.temperature != null && th.classifyTemp(row.temperature!) == 'red') ||
            (row.humidity != null && th.classifyHumidity(row.humidity!) == 'red')) {
          red++;
        }
      }
    }
    final readings = m.readingsOn(today);
    final checks = m.entriesOn(today);
    final missing = missingReadings(now).length;
    final factsEn = 'Today: $readings temperature/humidity readings ($red above the red limit), '
        '$checks packing checks, $missing scheduled readings still missing.';
    final factsUr = 'آج: $readings ٹمپریچر/ہیومیڈیٹی ریڈنگز ($red سرخ حد سے اوپر)، '
        '$checks پیکنگ چیکس، $missing شیڈول ریڈنگز باقی۔';
    final canAsk = ai.onDeviceReady || await isOnline();
    final answer = !canAsk ? null : await ai.generate(
      'You brief a snack factory shift supervisor. Using ONLY these facts, write two lines. '
      'Line 1: one or two short English sentences. Line 2: the same in Urdu script. '
      'No other text. Facts: $factsEn',
    );
    if (answer != null) {
      final lines = answer.text
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.replaceFirst(RegExp(r'^\s*(line\s*\d\s*[:.-]|\d[.)])\s*', caseSensitive: false), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length >= 2 && lines[0].length < 400 && lines[1].length < 400) {
        return AssistantReply(en: lines[0], ur: lines[1], source: answer.source);
      }
    }
    return AssistantReply(en: factsEn, ur: factsUr, source: AnswerSource.rules);
  }

  /// Scheduled readings (per section, per started shift) that are missing or
  /// incomplete. Computed only from local storage, so it works offline.
  List<({String sectionId, String shift, String missing})> missingReadings(
      DateTime day, {String? sectionId}) {
    final now = _clock();
    final isToday = _sameDay(day, now);
    final sched = schedule;
    final out = <({String sectionId, String shift, String missing})>[];
    for (final sec in sched.sectionIds) {
      if (sectionId != null && sec != sectionId) continue;
      for (final shift in sched.shifts) {
        if (isToday && !ThSchedule.started(shift, now)) continue;
        final rows = store
            .thReports()
            .where((r) => r.sectionId == sec && r.shift == shift && _sameDay(r.date, day))
            .expand((r) => r.rows);
        final hasT = rows.any((r) => r.temperature != null);
        final hasH = rows.any((r) => r.humidity != null);
        if (!hasT && !hasH) {
          out.add((sectionId: sec, shift: shift, missing: 'both'));
        } else if (!hasT) {
          out.add((sectionId: sec, shift: shift, missing: 'temperature'));
        } else if (!hasH) {
          out.add((sectionId: sec, shift: shift, missing: 'humidity'));
        }
      }
    }
    return out;
  }

  AssistantReply missingEntries(AssistantIntent intent) {
    final now = _clock();
    final day = intent.period == 'yesterday'
        ? DateTime(now.year, now.month, now.day - 1)
        : now;
    final miss = missingReadings(day, sectionId: intent.section);
    final when = intent.period == 'yesterday' ? 'Yesterday' : 'Today';
    final whenUr = intent.period == 'yesterday' ? 'کل' : 'آج';
    if (miss.isEmpty) {
      return AssistantReply(
        en: '$when no scheduled temperature/humidity reading is missing.',
        ur: '$whenUr کوئی شیڈول ریڈنگ مس نہیں ہوئی۔',
        source: intent.source,
      );
    }
    String what(String m) => m == 'both' ? 'temperature and humidity' : m;
    String whatUr(String m) => m == 'both'
        ? 'ٹمپریچر اور ہیومیڈیٹی'
        : m == 'temperature'
            ? 'ٹمپریچر'
            : 'ہیومیڈیٹی';
    final en = miss
        .map((m) => '${_nameEn(m.sectionId)} ${_shiftEn(m.shift)} (${what(m.missing)})')
        .join('; ');
    final ur = miss
        .map((m) => '${_nameUr(m.sectionId)} ${_shiftUr(m.shift)} (${whatUr(m.missing)})')
        .join('، ');
    return AssistantReply(
      en: '$when ${miss.length} scheduled ${miss.length == 1 ? 'reading is' : 'readings are'} missing: $en.',
      ur: '$whenUr ${miss.length} ریڈنگز باقی ہیں: $ur۔',
      source: intent.source,
    );
  }

  // ---------------------------------------------------------------- readings

  Future<AssistantReply> _startReading(AssistantIntent intent) async {
    final hour = _clock().hour;
    // Same rule as ShiftHelper.detectShift(), but on the injected clock.
    final shift = intent.shift ?? (hour >= 8 && hour < 20 ? 'morning' : 'night');
    final section = intent.section;
    if (section == null) {
      pending = PendingAction(
        PendingKind.needSection,
        draft: ThDraft(
          sectionId: '',
          shift: shift,
          source: intent.source,
          confidence: intent.confidence,
          temperature: intent.temperature,
          humidity: intent.humidity,
        ),
      );
      return AssistantReply(
        en: 'Which section? Chips, Peri Peri, Nimko, Wafer or Chocolate?',
        ur: 'کون سا سیکشن؟ چپس، پیری پیری، نمکو، ویفر یا چاکلیٹ؟',
        source: intent.source,
        pending: pending,
      );
    }
    return _review(ThDraft(
      sectionId: section,
      shift: shift,
      source: intent.source,
      confidence: intent.confidence,
      temperature: intent.temperature,
      humidity: intent.humidity,
    ));
  }

  /// Validates a draft and either asks for confirmation or (fast mode, safe
  /// values, confident parse) saves it straight away.
  Future<AssistantReply> _review(ThDraft d, {bool forceConfirm = false}) async {
    final error = _rangeError(d);
    if (error != null) {
      pending = null;
      return AssistantReply(en: error.$1, ur: error.$2, source: d.source);
    }
    final statuses = _statuses(d);
    final risky = forceConfirm ||
        statuses.values.contains('red') ||
        d.confidence < 0.75;
    if (fastMode && !risky) {
      await _save(d, confirmedBy: '');
      pending = null;
      return AssistantReply(
        en: 'Saved: ${_readbackEn(d, statuses)}. Say "undo" to remove it.',
        ur: 'محفوظ کر دیا: ${_readbackUr(d, statuses)}۔ ہٹانے کے لیے "واپس لو" بولیں۔',
        source: d.source,
        saved: true,
        statuses: statuses,
      );
    }
    pending = PendingAction(PendingKind.thReading, draft: d);
    final warnEn = statuses.values.contains('red')
        ? ' Warning: this is above the red limit.'
        : '';
    final warnUr = statuses.values.contains('red') ? ' خبردار: یہ سرخ حد سے زیادہ ہے۔' : '';
    return AssistantReply(
      en: '${_readbackEn(d, statuses)}.$warnEn Save it? Say yes or no.',
      ur: '${_readbackUr(d, statuses)}۔$warnUr محفوظ کروں؟ ہاں یا نہیں بولیں۔',
      source: d.source,
      pending: pending,
      statuses: statuses,
    );
  }

  // ---------------------------------------------------------------- batch

  Future<AssistantReply> _collectBatch(String text) async {
    final items = batch!;
    if (rules.isBatchEnd(text)) return _batchReview();
    if (rules.confirmReply(text).kind == ConfirmKind.no && items.isEmpty) {
      batch = null;
      return _cancelled();
    }
    final intent = await understand(text);
    if (intent.type != IntentType.addThReading) {
      return AssistantReply(
        en: 'In batch mode, say a reading like "nimko temperature 30", or "done" to finish.',
        ur: 'بیچ موڈ میں ریڈنگ بولیں جیسے "نمکو ٹمپریچر 30"، یا ختم کرنے کے لیے "بس"۔',
        source: intent.source,
      );
    }
    if (intent.section == null) {
      return AssistantReply(
        en: 'Please include the section, for example "chips humidity 45".',
        ur: 'سیکشن کا نام بھی بولیں، مثلاً "چپس ہیومیڈیٹی 45"۔',
        source: intent.source,
      );
    }
    final hour = _clock().hour;
    final d = ThDraft(
      sectionId: intent.section!,
      shift: intent.shift ?? (hour >= 8 && hour < 20 ? 'morning' : 'night'),
      source: intent.source,
      confidence: intent.confidence,
      temperature: intent.temperature,
      humidity: intent.humidity,
    );
    final error = _rangeError(d);
    if (error != null) {
      return AssistantReply(en: error.$1, ur: error.$2, source: intent.source);
    }
    items.add(d);
    final st = _statuses(d);
    if (items.length >= maxBatch) return _batchReview();
    return AssistantReply(
      en: '#${items.length}: ${_readbackEn(d, st)}.',
      ur: '#${items.length}: ${_readbackUr(d, st)}۔',
      source: intent.source,
      statuses: st,
    );
  }

  AssistantReply _batchReview() {
    final items = batch ?? const <ThDraft>[];
    batch = null;
    if (items.isEmpty) {
      pending = null;
      return const AssistantReply(
        en: 'Batch closed. No readings were dictated.',
        ur: 'بیچ بند۔ کوئی ریڈنگ نہیں بولی گئی۔',
        source: AnswerSource.rules,
      );
    }
    pending = PendingAction(PendingKind.batchReview, batch: items);
    return _batchReadback(items);
  }

  AssistantReply _batchReadback(List<ThDraft> items) {
    final en = StringBuffer();
    final ur = StringBuffer();
    var red = 0;
    for (var i = 0; i < items.length; i++) {
      final st = _statuses(items[i]);
      if (st.values.contains('red')) red++;
      en.write('${i + 1}. ${_readbackEn(items[i], st)}. ');
      ur.write('${i + 1}۔ ${_readbackUr(items[i], st)}۔ ');
    }
    final warnEn = red == 0 ? '' : '$red ${red == 1 ? 'item is' : 'items are'} above the red limit. ';
    final warnUr = red == 0 ? '' : '$red سرخ حد سے اوپر ہیں۔ ';
    return AssistantReply(
      en: '${items.length} readings: $en${warnEn}Save all? Say yes, no, "number 3 humidity 48" to correct, or "number 3 hatao" to remove.',
      ur: '${items.length} ریڈنگز: $ur$warnUrسب محفوظ کروں؟ ہاں، نہیں، درستگی کے لیے "نمبر 3 ہیومیڈیٹی 48"، یا ہٹانے کے لیے "نمبر 3 ہٹاؤ" بولیں۔',
      source: AnswerSource.rules,
      pending: pending,
    );
  }

  Future<AssistantReply> _answerBatch(PendingAction p, String text) async {
    final cmd = rules.itemCommand(text);
    if (cmd != null) {
      final items = [...p.batch];
      final i = cmd.item - 1;
      if (i < 0 || i >= items.length) {
        return AssistantReply(
          en: 'There is no item ${cmd.item}. Items are 1 to ${items.length}.',
          ur: 'آئٹم ${cmd.item} موجود نہیں۔ آئٹم 1 سے ${items.length} تک ہیں۔',
          source: AnswerSource.rules,
          pending: p,
        );
      }
      if (cmd.remove) {
        items.removeAt(i);
      } else {
        final d = items[i];
        var t = cmd.temperature;
        var h = cmd.humidity;
        if (t == null && h == null && cmd.value != null) {
          if (d.humidity != null && d.temperature == null) {
            h = cmd.value;
          } else if (d.temperature != null && d.humidity == null) {
            t = cmd.value;
          } else {
            return const AssistantReply(
              en: 'Say which value: for example "number 3 humidity 48".',
              ur: 'کون سی ویلیو؟ مثلاً "نمبر 3 ہیومیڈیٹی 48" بولیں۔',
              source: AnswerSource.rules,
            );
          }
        }
        final fixed = d.copyWith(temperature: t, humidity: h);
        final error = _rangeError(fixed);
        if (error != null) {
          return AssistantReply(en: error.$1, ur: error.$2, source: AnswerSource.rules, pending: p);
        }
        items[i] = fixed;
      }
      if (items.isEmpty) return _cancelled();
      pending = PendingAction(PendingKind.batchReview, batch: items);
      return _batchReadback(items);
    }
    switch (rules.confirmReply(text).kind) {
      case ConfirmKind.yes:
        return _confirm(p);
      case ConfirmKind.no:
        return _cancelled();
      case ConfirmKind.correct:
      case ConfirmKind.unclear:
        return _batchReadback(p.batch);
    }
  }

  Future<AssistantReply> _answerPending(String text) async {
    final p = pending!;
    if (p.kind == PendingKind.batchReview) return _answerBatch(p, text);
    if (p.kind == PendingKind.packingNeedInfo || p.kind == PendingKind.packingReview) {
      final kind = rules.confirmReply(text).kind;
      if (kind == ConfirmKind.no) return _cancelled();
      if (kind == ConfirmKind.yes && p.kind == PendingKind.packingReview) return _confirm(p);
      // Anything else adds or corrects details; a change is always read back.
      return _startPacking(text, base: p.packing, forceConfirm: p.kind == PendingKind.packingReview);
    }
    if (p.kind == PendingKind.needSection) {
      final sec = AssistantIntent.normalizeSection(RulesParser.normalize(text));
      if (sec == null) {
        if (rules.confirmReply(text).kind == ConfirmKind.no) return _cancelled();
        return const AssistantReply(
          en: 'Please say the section name: Chips, Peri Peri, Nimko, Wafer or Chocolate.',
          ur: 'سیکشن کا نام بولیں: چپس، پیری پیری، نمکو، ویفر یا چاکلیٹ۔',
          source: AnswerSource.rules,
        );
      }
      return _review(p.draft!.copyWith(sectionId: sec));
    }

    final reply = rules.confirmReply(text);
    switch (reply.kind) {
      case ConfirmKind.yes:
        return _confirm(p);
      case ConfirmKind.no:
        return _cancelled();
      case ConfirmKind.correct:
        if (p.kind != PendingKind.thReading) return _repeat(p);
        final d = p.draft!;
        double? t = reply.temperature;
        double? h = reply.humidity;
        if (t == null && h == null) {
          if (d.temperature != null && d.humidity != null) {
            return const AssistantReply(
              en: 'Which value should change? Say for example "temperature 30" or "humidity 48".',
              ur: 'کون سی ویلیو بدلنی ہے؟ مثلاً "ٹمپریچر 30" یا "ہیومیڈیٹی 48" بولیں۔',
              source: AnswerSource.rules,
            );
          }
          if (d.humidity != null) {
            h = reply.value;
          } else {
            t = reply.value;
          }
        }
        // A correction is always read back again before saving.
        return _review(d.copyWith(temperature: t, humidity: h), forceConfirm: true);
      case ConfirmKind.unclear:
        return _repeat(p);
    }
  }

  Future<AssistantReply> _confirm(PendingAction p) async {
    pending = null;
    switch (p.kind) {
      case PendingKind.packingReview:
        final d = p.packing!;
        _lastPackingId = await store.savePackingEntry(_packingEntry(d));
        _lastSave = null;
        return AssistantReply(
          en: 'Saved the packing check. ${_packingEn(d)}.',
          ur: 'پیکنگ چیک محفوظ ہو گیا۔ ${_packingUr(d)}۔',
          source: AnswerSource.rules,
          saved: true,
          statuses: _packingStatuses(d),
        );
      case PendingKind.packingNeedInfo:
        return _repeat(p);
      case PendingKind.thReading:
        final d = p.draft!;
        await _save(d, confirmedBy: store.userName);
        final st = _statuses(d);
        return AssistantReply(
          en: 'Saved. ${_readbackEn(d, st)}.',
          ur: 'محفوظ ہو گیا۔ ${_readbackUr(d, st)}۔',
          source: AnswerSource.rules,
          saved: true,
          statuses: st,
        );
      case PendingKind.fastModeOn:
      case PendingKind.fastModeOff:
        final on = p.kind == PendingKind.fastModeOn;
        await store.setMeta(fastModeKey, on ? '1' : '0');
        return AssistantReply(
          en: on ? 'Fast mode is on.' : 'Fast mode is off. I will read back every reading.',
          ur: on ? 'فاسٹ موڈ آن ہو گیا۔' : 'فاسٹ موڈ بند۔ ہر ریڈنگ پہلے سناؤں گا۔',
          source: AnswerSource.rules,
        );
      case PendingKind.undo:
        final packingId = _lastPackingId;
        if (packingId != null) {
          await store.deletePackingEntry(packingId);
          _lastPackingId = null;
          return const AssistantReply(
            en: 'Done. The last packing check was removed.',
            ur: 'ہو گیا۔ آخری پیکنگ چیک ہٹا دیا گیا۔',
            source: AnswerSource.rules,
          );
        }
        final last = _lastSave;
        if (last == null) return _nothingToUndo();
        if (last.before == null) {
          await store.deleteThReport(last.reportId);
        } else {
          await store.saveThReport(last.before!);
        }
        _lastSave = null;
        return const AssistantReply(
          en: 'Done. The last reading was removed.',
          ur: 'ہو گیا۔ آخری ریڈنگ ہٹا دی گئی۔',
          source: AnswerSource.rules,
        );
      case PendingKind.batchReview:
        for (final d in p.batch) {
          await _save(d, confirmedBy: store.userName);
        }
        _lastSave = null; // undo covers single readings only
        return AssistantReply(
          en: 'Saved ${p.batch.length} readings.',
          ur: '${p.batch.length} ریڈنگز محفوظ ہو گئیں۔',
          source: AnswerSource.rules,
          saved: true,
        );
      case PendingKind.needSection:
        return _cancelled();
    }
  }

  AssistantReply _askUndo() {
    if (_lastSave == null && _lastPackingId == null) return _nothingToUndo();
    pending = const PendingAction(PendingKind.undo);
    return AssistantReply(
      en: 'Remove the last reading I saved? Say yes or no.',
      ur: 'آخری محفوظ کی گئی ریڈنگ ہٹا دوں؟ ہاں یا نہیں؟',
      source: AnswerSource.rules,
      pending: pending,
    );
  }

  AssistantReply _nothingToUndo() => const AssistantReply(
        en: 'There is nothing to undo.',
        ur: 'واپس لینے کے لیے کچھ نہیں ہے۔',
        source: AnswerSource.rules,
      );

  AssistantReply _cancelled() {
    pending = null;
    return const AssistantReply(
      en: 'Okay, cancelled. Nothing was saved.',
      ur: 'ٹھیک ہے، منسوخ۔ کچھ محفوظ نہیں ہوا۔',
      source: AnswerSource.rules,
    );
  }

  AssistantReply _repeat(PendingAction p) {
    if (p.kind == PendingKind.thReading) {
      final d = p.draft!;
      final st = _statuses(d);
      return AssistantReply(
        en: '${_readbackEn(d, st)}. Say yes to save, no to cancel, or "no, 48" to correct.',
        ur: '${_readbackUr(d, st)}۔ محفوظ کرنے کے لیے ہاں، منسوخ کے لیے نہیں، یا درستگی کے لیے "نہیں 48" بولیں۔',
        source: AnswerSource.rules,
        pending: p,
        statuses: st,
      );
    }
    return const AssistantReply(
      en: 'Please say yes or no.',
      ur: 'براہ کرم ہاں یا نہیں بولیں۔',
      source: AnswerSource.rules,
    );
  }

  /// Confirm / cancel buttons on the card call these.
  Future<AssistantReply> confirmPending() =>
      pending == null ? Future.value(_cancelled()) : _confirm(pending!);
  AssistantReply cancelPending() => _cancelled();

  Future<void> _save(ThDraft d, {required String confirmedBy}) async {
    _lastPackingId = null;
    final now = _clock();
    final day = TempHumidityReport.dayOf(now);
    final existing = store.thReports().where((r) =>
        r.sectionId == d.sectionId && r.shift == d.shift && _sameDay(r.date, day));
    final before = existing.isEmpty ? null : existing.first;
    final row = TempHumidityRow(
      time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      temperature: d.temperature,
      humidity: d.humidity,
      section: _nameEn(d.sectionId),
      verifiedByQc: store.userName,
      enteredBy: store.userName,
      source: 'assistant:${d.source.name}',
      confirmedBy: confirmedBy,
      enteredAt: now,
    );
    final report = before == null
        ? TempHumidityReport(
            id: TempHumidityReport.generateId(),
            sectionId: d.sectionId,
            date: day,
            shift: d.shift,
            rows: [row],
            preparedBy: store.userName,
            createdAt: now,
            updatedAt: now,
          )
        : before.copyWith(rows: [...before.rows, row], updatedAt: now, isSynced: false);
    await store.saveThReport(report);
    _lastSave = (reportId: report.id, before: before);
  }

  // ---------------------------------------------------------------- helpers

  (String, String)? _rangeError(ThDraft d) {
    if (d.temperature == null && d.humidity == null) {
      return (
        'I did not catch a temperature or humidity value. Please say it again.',
        'ٹمپریچر یا ہیومیڈیٹی کی ویلیو سمجھ نہیں آئی۔ دوبارہ بولیں۔',
      );
    }
    final t = d.temperature;
    if (t != null && (t < -10 || t > 70)) {
      return (
        'Temperature $t is not a possible room reading. Please check and say it again.',
        'ٹمپریچر $t ممکن نہیں لگتا۔ چیک کر کے دوبارہ بولیں۔',
      );
    }
    final h = d.humidity;
    if (h != null && (h < 0 || h > 100)) {
      return (
        'Humidity must be between 0 and 100 percent. Please say it again.',
        'ہیومیڈیٹی 0 سے 100 فیصد کے درمیان ہونی چاہیے۔ دوبارہ بولیں۔',
      );
    }
    return null;
  }

  Map<String, String> _statuses(ThDraft d) {
    final th = store.thresholdFor(d.sectionId);
    return {
      if (d.temperature != null) 'temperature': th.classifyTemp(d.temperature!),
      if (d.humidity != null) 'humidity': th.classifyHumidity(d.humidity!),
    };
  }

  String _readbackEn(ThDraft d, Map<String, String> st) {
    final parts = <String>[
      if (d.temperature != null) 'temperature ${_fmt(d.temperature!)}°C (${st['temperature']})',
      if (d.humidity != null) 'humidity ${_fmt(d.humidity!)}% (${st['humidity']})',
    ];
    return '${_nameEn(d.sectionId)}, ${_shiftEn(d.shift)} shift: ${parts.join(', ')}';
  }

  String _readbackUr(ThDraft d, Map<String, String> st) {
    String c(String? s) => s == 'green' ? 'سبز' : s == 'yellow' ? 'پیلا' : 'سرخ';
    final parts = <String>[
      if (d.temperature != null) 'ٹمپریچر ${_fmt(d.temperature!)} ڈگری (${c(st['temperature'])})',
      if (d.humidity != null) 'ہیومیڈیٹی ${_fmt(d.humidity!)} فیصد (${c(st['humidity'])})',
    ];
    return '${_nameUr(d.sectionId)}، ${_shiftUr(d.shift)} شفٹ: ${parts.join('، ')}';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  AssistantReply _open(AssistantIntent intent) {
    final screen = intent.screen ?? 'entries';
    final sec = intent.section;
    final needsSection = screen == 'entries' || screen == 'temp_humidity';
    final label = switch (screen) {
      'temp_humidity' => ('temperature & humidity sheet', 'ٹمپریچر اور ہیومیڈیٹی شیٹ'),
      'settings' => ('settings', 'سیٹنگز'),
      'automations' => ('automations', 'آٹومیشنز'),
      'extraction' => ('paper form scanner', 'کاغذی فارم اسکینر'),
      'analytics' => ('analytics', 'اینالیٹکس'),
      'dashboard' => ('dashboard', 'ڈیش بورڈ'),
      _ => ('packing sheet', 'پیکنگ شیٹ'),
    };
    if (needsSection && sec == null) {
      return AssistantReply(
        en: 'Which section\'s ${label.$1}? Say for example "Peri Peri ki sheet kholo".',
        ur: 'کس سیکشن کی ${label.$2}؟ مثلاً "پیری پیری کی شیٹ کھولو" بولیں۔',
        source: intent.source,
      );
    }
    return AssistantReply(
      en: 'Opening ${sec == null ? '' : '${_nameEn(sec)} '}${label.$1}.',
      ur: '${sec == null ? '' : '${_nameUr(sec)} کی '}${label.$2} کھول رہا ہوں۔',
      source: intent.source,
      navigate: NavTarget(screen, sec),
    );
  }

  (DateTime, DateTime) _range(String period) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      'yesterday' => (today.subtract(const Duration(days: 1)), today),
      'week' => (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
      _ => (today, today.add(const Duration(days: 1))),
    };
  }

  static bool _inRange(DateTime t, (DateTime, DateTime) r) =>
      !t.isBefore(r.$1) && t.isBefore(r.$2);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _periodEn(String p) =>
      p == 'yesterday' ? 'Yesterday' : p == 'week' ? 'In the last 7 days' : 'Today';
  static String _periodUr(String p) =>
      p == 'yesterday' ? 'کل' : p == 'week' ? 'پچھلے 7 دنوں میں' : 'آج';

  static const _lastEntryWords = [
    'last entry', 'aakhri entry', 'akhri entry', 'pichli entry', 'latest entry',
    'آخری انٹری', 'پچھلی انٹری',
  ];
  static const _listWords = [
    'kaun si products', 'konsi products', 'kon si products', 'which products',
    'list products', 'products batao', 'kitni machines', 'which machines',
    'machines batao', 'kaun si machines', 'پروڈکٹس', 'مشینیں',
  ];

  /// "Aakhri entry kya thi?": the newest packing check and reading.
  AssistantReply _lastEntry() {
    final entries = [...store.packingEntries()]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (entries.isEmpty) {
      return const AssistantReply(
        en: 'There are no packing entries yet.',
        ur: 'ابھی کوئی پیکنگ انٹری نہیں ہے۔',
        source: AnswerSource.rules,
      );
    }
    final e = entries.first;
    final when = '${e.createdAt.day}/${e.createdAt.month} ${e.createdAt.hour.toString().padLeft(2, '0')}:${e.createdAt.minute.toString().padLeft(2, '0')}';
    return AssistantReply(
      en: 'Last entry: ${_nameEn(e.section)}, machine ${e.machineNumber}, ${e.productName}, by ${e.operatorName} at $when. Weight ${e.weightStatus}, leakage ${e.leakageStatus}.',
      ur: 'آخری انٹری: ${_nameUr(e.section)}، مشین ${e.machineNumber}، ${e.productName}، ${e.operatorName} نے $when پر کی۔',
      source: AnswerSource.rules,
      statuses: {'weight': e.weightStatus, 'leakage': e.leakageStatus},
    );
  }

  /// "Chips ki kaun si products hain?" / "kitni machines hain?"
  AssistantReply _listCatalogue(String norm) {
    final section = AssistantIntent.normalizeSection(norm);
    if (norm.contains('machine') || norm.contains('مشین')) {
      final ms = store.machines().where((m) => m.isActive && (section == null || m.section == section)).toList();
      final by = <String, int>{};
      for (final m in ms) {
        by[m.section] = (by[m.section] ?? 0) + 1;
      }
      final en = by.entries.map((e) => '${_nameEn(e.key)} ${e.value}').join(', ');
      final ur = by.entries.map((e) => '${_nameUr(e.key)} ${e.value}').join('، ');
      return AssistantReply(
        en: '${ms.length} machines: $en.',
        ur: '${ms.length} مشینیں: $ur۔',
        source: AnswerSource.rules,
      );
    }
    final ps = store.products().where((p) => p.isActive && (section == null || p.section == section)).toList();
    final names = ps.take(8).map((p) => p.name).join(', ');
    final more = ps.length > 8 ? ' and ${ps.length - 8} more' : '';
    return AssistantReply(
      en: '${ps.length} products${section == null ? '' : ' in ${_nameEn(section)}'}: $names$more.',
      ur: '${section == null ? '' : '${_nameUr(section)} میں '}${ps.length} پروڈکٹس: $names۔',
      source: AnswerSource.rules,
    );
  }

  // ---------------------------------------------------------------- packing

  /// Collects a spoken packing check, asks for whatever is missing, then
  /// reads it back. It is saved only after "haan" (fast mode skips the
  /// question for an all-green check that stated leakage and printing).
  Future<AssistantReply> _startPacking(
    String text, {
    PackingDraft? base,
    AnswerSource source = AnswerSource.rules,
    bool forceConfirm = false,
  }) async {
    final hintSection = base?.sectionId ??
        AssistantIntent.normalizeSection(RulesParser.normalize(text));
    final heard = packingVoice.parse(text, products: store.products(), sectionId: hintSection);
    var d = (base ?? const PackingDraft()).merge(heard);
    if (d.product == null && d.sectionId != null) {
      final pool = store.products().where((p) => p.isActive && p.section == d.sectionId).toList();
      d = d.withProduct(PackingVoice.matchProduct(RulesParser.normalize(text), pool));
    }
    final missing = packingVoice.missing(d).toList();
    if (d.machineNumber != null &&
        d.sectionId != null &&
        packingVoice.machineFor(d, store.machines()) == null) {
      // Not a machine of this section: ask again instead of saving a guess.
      missing.add('machine');
      d = PackingDraft(
        sectionId: d.sectionId,
        product: d.product,
        productQuery: d.productQuery,
        weights: d.weights,
        moisture: d.moisture,
        leakageOk: d.leakageOk,
        printingOk: d.printingOk,
      );
    }
    if (missing.isNotEmpty) {
      pending = PendingAction(PendingKind.packingNeedInfo, packing: d);
      return _askPacking(d, missing.first, source);
    }
    final st = _packingStatuses(d);
    final bad = st.values.any((v) => v == 'red' || v == 'yellow');
    final stated = d.leakageOk != null && d.printingOk != null;
    if (fastMode && !forceConfirm && !bad && stated) {
      return _confirm(PendingAction(PendingKind.packingReview, packing: d));
    }
    pending = PendingAction(PendingKind.packingReview, packing: d);
    return AssistantReply(
      en: '${_packingEn(d)}.${bad ? ' This is outside the limit.' : ''} Save it? Say yes or no, or say what to change.',
      ur: '${_packingUr(d)}۔${bad ? ' یہ حد سے باہر ہے۔' : ''} محفوظ کر دوں؟ ہاں یا نہیں، یا بتائیں کیا بدلنا ہے۔',
      source: source,
      pending: pending,
      statuses: st,
    );
  }

  AssistantReply _askPacking(PackingDraft d, String missing, AnswerSource source) {
    final products = store
        .products()
        .where((p) => p.isActive && (d.sectionId == null || p.section == d.sectionId))
        .take(4)
        .map((p) => p.name)
        .join(', ');
    final section = d.sectionId;
    final (String en, String ur) = switch (missing) {
      'section' => (
          'Which section is this packing check for? Chips, Peri Peri, Nimko, Wafer or Chocolate.',
          'یہ پیکنگ چیک کس سیکشن کا ہے؟ چپس، پیری پیری، نمکو، ویفر یا چاکلیٹ۔'
        ),
      'product' => (
          'Which product? For example: $products.',
          'کون سی پروڈکٹ؟ مثلاً: $products۔'
        ),
      'machine' => (
          'Which machine number${section == null ? '' : ' in ${_nameEn(section)}'}?',
          '${section == null ? '' : '${_nameUr(section)} میں '}کون سی مشین نمبر؟'
        ),
      _ => (
          'Say the pouch weights in grams, up to four, for example "weight 52 53 51 52".',
          'پاؤچ کا وزن گرام میں بولیں، چار تک، مثلاً "وزن 52 53 51 52"۔'
        ),
    };
    return AssistantReply(en: en, ur: ur, source: source, pending: pending);
  }

  Map<String, String> _packingStatuses(PackingDraft d) => {
        'weight': d.weightStatus(),
        if (d.moistureStatus() != 'na') 'moisture': d.moistureStatus(),
        'leakage': d.leakageOk == false ? 'red' : 'green',
        'printing': d.printingOk == false ? 'red' : 'green',
      };

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _packingEn(PackingDraft d) {
    final w = d.weights.map(_num).join(', ');
    return '${_nameEn(d.sectionId!)}, machine ${d.machineNumber}, ${d.product!.name}: '
        'pouches $w g (${d.weightStatus()})'
        '${d.moisture == null ? '' : ', moisture ${_num(d.moisture!)} (${d.moistureStatus()})'}'
        ', leakage ${d.leakageOk == false ? 'found' : 'OK'}'
        ', printing ${d.printingOk == false ? 'not OK' : 'OK'}';
  }

  String _packingUr(PackingDraft d) {
    final w = d.weights.map(_num).join('، ');
    const st = {'green': 'سبز', 'yellow': 'پیلا', 'red': 'سرخ', 'na': ''};
    return '${_nameUr(d.sectionId!)}، مشین ${d.machineNumber}، ${d.product!.name}: '
        'پاؤچ $w گرام (${st[d.weightStatus()]})'
        '${d.moisture == null ? '' : '، نمی ${_num(d.moisture!)} (${st[d.moistureStatus()]})'}'
        '، لیکج ${d.leakageOk == false ? 'ہے' : 'ٹھیک'}'
        '، پرنٹنگ ${d.printingOk == false ? 'ٹھیک نہیں' : 'ٹھیک'}';
  }

  PackingEntryModel _packingEntry(PackingDraft d) {
    final p = d.product!;
    final m = packingVoice.machineFor(d, store.machines());
    final now = _clock();
    double? pouch(int i) => i < d.weights.length ? d.weights[i] : null;
    return PackingEntryModel(
      id: '',
      machineId: m?.id ?? '',
      machineNumber: d.machineNumber!,
      section: d.sectionId!,
      productId: p.id,
      productName: p.displayName,
      price: p.price,
      shift: ShiftHelper.detectShift(),
      operatorId: store.userId,
      operatorName: store.userName,
      dateCodingManufacture: now,
      dateCodingExpiry: now.add(Duration(days: p.expiryDays)),
      grossWeight: p.weightGrams,
      pouch1Weight: pouch(0),
      pouch2Weight: pouch(1),
      pouch3Weight: pouch(2),
      pouch4Weight: pouch(3),
      moistureIdeal: p.moistureMax,
      moistureActual: d.moisture,
      weightStatus: d.weightStatus(),
      printingStatus: d.printingOk == false ? 'not_okay' : 'okay',
      printingColor: d.printingOk == false ? 'red' : null,
      leakageStatus: d.leakageOk == false ? 'red' : 'green',
      moistureStatus: d.moistureStatus(),
      isSynced: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _nameEn(String id) => Sections.byId(id).name;
  static String _nameUr(String id) => const {
        'chips': 'چپس',
        'peri_peri': 'پیری پیری',
        'nimko': 'نمکو',
        'wafer': 'ویفر',
        'chocolate': 'چاکلیٹ',
      }[id] ??
      id;
  static String _shiftEn(String s) => s == 'morning' ? 'morning' : 'night';
  static String _shiftUr(String s) => s == 'morning' ? 'صبح' : 'رات';
}
