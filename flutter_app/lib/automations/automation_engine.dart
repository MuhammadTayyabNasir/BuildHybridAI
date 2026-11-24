import '../core/constants/sections.dart';
import '../models/temp_humidity_model.dart';
import '../models/th_threshold_model.dart';
import 'automation_rule.dart';

/// One thing an automation wants to tell people.
class AutomationEvent {
  const AutomationEvent({
    required this.ruleId,
    required this.key,
    required this.en,
    required this.ur,
    required this.severity,
    required this.notifyManager,
    required this.at,
    this.sectionId,
  });

  final String ruleId;

  /// Dedupe key: an event with the same key never fires twice.
  final String key;
  final String en;
  final String ur;

  /// 'info' | 'warning' | 'critical'
  final String severity;
  final bool notifyManager;
  final DateTime at;
  final String? sectionId;

  Map<String, Object?> toMap() => {
        'ruleId': ruleId,
        'key': key,
        'en': en,
        'ur': ur,
        'severity': severity,
        'notifyManager': notifyManager,
        'at': at.millisecondsSinceEpoch,
        if (sectionId != null) 'sectionId': sectionId,
      };

  static AutomationEvent? fromMap(Map<String, Object?> m) {
    try {
      return AutomationEvent(
        ruleId: m['ruleId'] as String,
        key: m['key'] as String,
        en: m['en'] as String,
        ur: m['ur'] as String,
        severity: m['severity'] as String? ?? 'info',
        notifyManager: m['notifyManager'] == true,
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        sectionId: m['sectionId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef MissingFn = List<({String sectionId, String shift, String missing})> Function(
    DateTime day);

/// Pure, deterministic evaluation of automation rules against local data.
/// No AI runs here: the model may only propose rules, never decide alerts.
class AutomationEngine {
  const AutomationEngine({
    this.reminderWindow = const Duration(hours: 3),
    this.checkWindow = const Duration(hours: 6),
  });

  /// A reminder still fires if the app opens this long after its time.
  final Duration reminderWindow;

  /// Same for shift-end checks.
  final Duration checkWindow;

  List<AutomationEvent> evaluate({
    required List<AutomationRule> rules,
    required DateTime now,
    required List<TempHumidityReport> reports,
    required ThThreshold Function(String sectionId) threshold,
    required MissingFn missing,
    required Set<String> alreadyFired,
  }) {
    final out = <AutomationEvent>[];
    for (final rule in rules) {
      if (!rule.active || rule.validate() != null) continue;
      final events = switch (rule.kind) {
        RuleKind.reminder => _reminder(rule, now),
        RuleKind.shiftEndCheck => _shiftEnd(rule, now, missing),
        RuleKind.conditionAlert => _condition(rule, now, reports, threshold),
      };
      for (final e in events) {
        if (alreadyFired.contains(e.key)) continue;
        if (out.any((o) => o.key == e.key)) continue;
        out.add(e);
      }
    }
    return out;
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The most recent occurrence of [rule]'s clock time at or before [now].
  static DateTime? _lastDue(AutomationRule rule, DateTime now) {
    final c = rule.clock;
    if (c == null) return null;
    var due = DateTime(now.year, now.month, now.day, c.$1, c.$2);
    if (due.isAfter(now)) due = due.subtract(const Duration(days: 1));
    return due;
  }

  List<AutomationEvent> _reminder(AutomationRule rule, DateTime now) {
    final due = _lastDue(rule, now);
    if (due == null || now.difference(due) > reminderWindow) return const [];
    return [
      AutomationEvent(
        ruleId: rule.id,
        key: '${rule.id}|${_day(due)}',
        en: rule.messageEn.isEmpty ? rule.messageUr : rule.messageEn,
        ur: rule.messageUr.isEmpty ? rule.messageEn : rule.messageUr,
        severity: 'info',
        notifyManager: rule.notifyManager,
        at: now,
        sectionId: rule.sectionId,
      ),
    ];
  }

  List<AutomationEvent> _shiftEnd(AutomationRule rule, DateTime now, MissingFn missing) {
    final due = _lastDue(rule, now);
    if (due == null || now.difference(due) > checkWindow) return const [];
    // A night shift (20:00 → 08:00) checked in the morning belongs to the
    // previous calendar day, which is the day its report is filed under.
    final shiftDay = rule.shift == 'night' && due.hour < 12
        ? DateTime(due.year, due.month, due.day - 1)
        : DateTime(due.year, due.month, due.day);
    final miss = missing(shiftDay)
        .where((m) => m.shift == rule.shift)
        .where((m) => rule.sectionId == null || m.sectionId == rule.sectionId)
        .toList();
    if (miss.isEmpty) return const [];
    String what(String m) => m == 'both' ? 'temperature + humidity' : m;
    String whatUr(String m) => m == 'both'
        ? 'ٹمپریچر + ہیومیڈیٹی'
        : m == 'temperature'
            ? 'ٹمپریچر'
            : 'ہیومیڈیٹی';
    final shiftEn = rule.shift == 'morning' ? 'Morning' : 'Night';
    final shiftUr = rule.shift == 'morning' ? 'صبح' : 'رات';
    return [
      AutomationEvent(
        ruleId: rule.id,
        key: '${rule.id}|${_day(shiftDay)}',
        en: '$shiftEn shift ended with ${miss.length} missed '
            '${miss.length == 1 ? 'reading' : 'readings'}: '
            '${miss.map((m) => '${Sections.byId(m.sectionId).name} (${what(m.missing)})').join(', ')}.',
        ur: '$shiftUr کی شفٹ میں ${miss.length} ریڈنگز رہ گئیں: '
            '${miss.map((m) => '${_urName(m.sectionId)} (${whatUr(m.missing)})').join('، ')}۔',
        severity: 'warning',
        notifyManager: rule.notifyManager,
        at: now,
        sectionId: rule.sectionId,
      ),
    ];
  }

  List<AutomationEvent> _condition(
    AutomationRule rule,
    DateTime now,
    List<TempHumidityReport> reports,
    ThThreshold Function(String) threshold,
  ) {
    final out = <AutomationEvent>[];
    final since = now.subtract(const Duration(hours: 24));
    for (final r in reports) {
      if (rule.sectionId != null && r.sectionId != rule.sectionId) continue;
      if (r.date.isBefore(DateTime(since.year, since.month, since.day))) continue;
      final th = threshold(r.sectionId);
      for (var i = 0; i < r.rows.length; i++) {
        final row = r.rows[i];
        final v = rule.metric == 'temperature' ? row.temperature : row.humidity;
        if (v == null) continue;
        final at = row.enteredAt ?? r.updatedAt;
        if (at.isBefore(since)) continue;
        final hit = switch (rule.op) {
          'red' => (rule.metric == 'temperature'
                  ? th.classifyTemp(v)
                  : th.classifyHumidity(v)) ==
              'red',
          'lt' => v < (rule.value ?? double.negativeInfinity),
          _ => v > (rule.value ?? double.infinity),
        };
        if (!hit) continue;
        final unit = rule.metric == 'temperature' ? '°C' : '%';
        final name = Sections.byId(r.sectionId).name;
        final limit = rule.op == 'red'
            ? 'above the red limit'
            : rule.op == 'lt'
                ? 'below ${_fmt(rule.value!)}$unit'
                : 'above ${_fmt(rule.value!)}$unit';
        final metricUr = rule.metric == 'temperature' ? 'ٹمپریچر' : 'ہیومیڈیٹی';
        final limitUr = rule.op == 'red'
            ? 'سرخ حد سے اوپر'
            : rule.op == 'lt'
                ? '${_fmt(rule.value!)}$unit سے کم'
                : '${_fmt(rule.value!)}$unit سے زیادہ';
        out.add(AutomationEvent(
          ruleId: rule.id,
          key: '${rule.id}|${r.id}|$i|${_fmt(v)}',
          en: '$name ${rule.metric} ${_fmt(v)}$unit is $limit (${row.time}).',
          ur: '${_urName(r.sectionId)} $metricUr ${_fmt(v)}$unit — $limitUr (${row.time})۔',
          severity: rule.op == 'red' ? 'critical' : 'warning',
          notifyManager: rule.notifyManager,
          at: now,
          sectionId: r.sectionId,
        ));
      }
    }
    return out;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _urName(String id) => const {
        'chips': 'چپس',
        'peri_peri': 'پیری پیری',
        'nimko': 'نمکو',
        'wafer': 'ویفر',
        'chocolate': 'چاکلیٹ',
      }[id] ??
      id;
}
