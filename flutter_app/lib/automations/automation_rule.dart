import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/constants/sections.dart';

/// What an automation does.
enum RuleKind {
  /// Spoken / on-screen reminder at a fixed time every day.
  reminder('reminder'),

  /// At the end of a shift, report scheduled readings that were never made.
  shiftEndCheck('shift_end_check'),

  /// Fires when a saved reading crosses a limit.
  conditionAlert('condition_alert');

  const RuleKind(this.wire);
  final String wire;

  static RuleKind? fromWire(String? s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// One automation. Rules are plain data: the app (and the Cloud Function for
/// pushes) evaluates them deterministically. AI may only *suggest* rules; a
/// suggestion stays paused until an admin approves it.
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.kind,
    this.enabled = true,
    this.origin = 'admin',
    this.approved = true,
    this.time,
    this.shift,
    this.sectionId,
    this.metric,
    this.op,
    this.value,
    this.messageEn = '',
    this.messageUr = '',
    this.notifyManager = false,
    this.reason = '',
  });

  final String id;
  final RuleKind kind;
  final bool enabled;

  /// 'admin' (made by a person) or 'ai' (suggested by Gemini / heuristics).
  final String origin;

  /// AI suggestions start unapproved and cannot be enabled until approved.
  final bool approved;

  /// 'HH:mm' for reminders and shift-end checks.
  final String? time;

  /// 'morning' | 'night' for shift-end checks.
  final String? shift;

  /// Section id, or null for every section.
  final String? sectionId;

  /// 'temperature' | 'humidity' for condition alerts.
  final String? metric;

  /// 'gt' (above [value]), 'lt' (below [value]) or 'red' (above the section's
  /// red limit).
  final String? op;
  final double? value;

  final String messageEn;
  final String messageUr;

  /// Also push to the manager's phone (via Firestore `alerts` + FCM).
  final bool notifyManager;

  /// Why the AI suggested it (shown on the approval card).
  final String reason;

  bool get active => enabled && approved;

  static const metrics = ['temperature', 'humidity'];
  static const ops = ['gt', 'lt', 'red'];

  /// (hour, minute) of [time], or null when it is not a valid 'HH:mm'.
  (int, int)? get clock => parseClock(time);

  static (int, int)? parseClock(String? t) {
    if (t == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  /// Null when the rule is valid, otherwise a short reason.
  String? validate() {
    switch (kind) {
      case RuleKind.reminder:
        if (clock == null) return 'time must be HH:mm';
        if (messageEn.trim().isEmpty && messageUr.trim().isEmpty) {
          return 'reminder needs a message';
        }
      case RuleKind.shiftEndCheck:
        if (clock == null) return 'time must be HH:mm';
        if (shift != 'morning' && shift != 'night') return 'shift must be morning or night';
      case RuleKind.conditionAlert:
        if (!metrics.contains(metric)) return 'metric must be temperature or humidity';
        if (!ops.contains(op)) return 'condition must be above, below or red';
        if (op != 'red') {
          final v = value;
          if (v == null) return 'limit value missing';
          final max = metric == 'humidity' ? 100 : 80;
          if (v < 0 || v > max) return 'limit must be between 0 and $max';
        }
    }
    if (sectionId != null && !Sections.ids.contains(sectionId)) return 'unknown section';
    return null;
  }

  /// Human description for lists and read-backs.
  String describeEn() {
    final where = sectionId == null ? 'all sections' : Sections.byId(sectionId!).name;
    return switch (kind) {
      RuleKind.reminder => 'Every day at $time: "${messageEn.isEmpty ? messageUr : messageEn}"',
      RuleKind.shiftEndCheck =>
        'At $time check $where for missed ${shift == 'morning' ? 'morning' : 'night'} readings',
      RuleKind.conditionAlert => switch (op) {
          'red' => 'Alert when $where $metric goes above the red limit',
          'lt' => 'Alert when $where $metric is below ${_fmt(value)}',
          _ => 'Alert when $where $metric is above ${_fmt(value)}',
        },
    };
  }

  static String _fmt(double? v) =>
      v == null ? '?' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  AutomationRule copyWith({
    bool? enabled,
    bool? approved,
    String? time,
    String? shift,
    String? sectionId,
    bool clearSection = false,
    String? metric,
    String? op,
    double? value,
    String? messageEn,
    String? messageUr,
    bool? notifyManager,
  }) =>
      AutomationRule(
        id: id,
        kind: kind,
        enabled: enabled ?? this.enabled,
        origin: origin,
        approved: approved ?? this.approved,
        time: time ?? this.time,
        shift: shift ?? this.shift,
        sectionId: clearSection ? null : (sectionId ?? this.sectionId),
        metric: metric ?? this.metric,
        op: op ?? this.op,
        value: value ?? this.value,
        messageEn: messageEn ?? this.messageEn,
        messageUr: messageUr ?? this.messageUr,
        notifyManager: notifyManager ?? this.notifyManager,
        reason: reason,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.wire,
        'enabled': enabled,
        'origin': origin,
        'approved': approved,
        if (time != null) 'time': time,
        if (shift != null) 'shift': shift,
        if (sectionId != null) 'sectionId': sectionId,
        if (metric != null) 'metric': metric,
        if (op != null) 'op': op,
        if (value != null) 'value': value,
        if (messageEn.isNotEmpty) 'messageEn': messageEn,
        if (messageUr.isNotEmpty) 'messageUr': messageUr,
        'notifyManager': notifyManager,
        if (reason.isNotEmpty) 'reason': reason,
      };

  /// Strict reader: unknown kinds / fields are dropped, invalid rules → null.
  /// Used for storage and for AI suggestions alike.
  static AutomationRule? fromMap(Map<String, Object?> m, {String? forceOrigin}) {
    final kind = RuleKind.fromWire(m['kind'] as String?);
    if (kind == null) return null;
    String? s(String k) {
      final v = m[k];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty || t == 'null' ? null : t;
    }

    final rawValue = m['value'];
    final ai = (forceOrigin ?? s('origin')) == 'ai';
    final rule = AutomationRule(
      id: s('id') ?? const Uuid().v4(),
      kind: kind,
      origin: ai ? 'ai' : 'admin',
      // An AI rule is never trusted as approved unless storage says so.
      approved: forceOrigin == 'ai' ? false : (m['approved'] as bool? ?? !ai),
      enabled: forceOrigin == 'ai' ? false : (m['enabled'] as bool? ?? true),
      time: s('time'),
      shift: s('shift'),
      sectionId: s('sectionId'),
      metric: s('metric'),
      op: s('op'),
      value: rawValue is num ? rawValue.toDouble() : double.tryParse('${rawValue ?? ''}'),
      messageEn: (s('messageEn') ?? '').trim(),
      messageUr: (s('messageUr') ?? '').trim(),
      notifyManager: m['notifyManager'] == true,
      reason: (s('reason') ?? '').trim(),
    );
    return rule.validate() == null ? rule : null;
  }

  static List<AutomationRule> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return defaults();
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map) ?AutomationRule.fromMap(Map<String, Object?>.from(e)),
      ];
    } catch (_) {
      return defaults();
    }
  }

  static String listToJson(List<AutomationRule> rules) =>
      jsonEncode([for (final r in rules) r.toMap()]);

  /// Shipped defaults: shift-end missed-entry checks for both shifts and a red
  /// humidity alert, all pushed to the manager.
  static List<AutomationRule> defaults() => const [
        AutomationRule(
          id: 'default-morning-check',
          kind: RuleKind.shiftEndCheck,
          time: '19:30',
          shift: 'morning',
          notifyManager: true,
        ),
        AutomationRule(
          id: 'default-night-check',
          kind: RuleKind.shiftEndCheck,
          time: '07:30',
          shift: 'night',
          notifyManager: true,
        ),
        AutomationRule(
          id: 'default-red-humidity',
          kind: RuleKind.conditionAlert,
          metric: 'humidity',
          op: 'red',
          notifyManager: true,
        ),
        AutomationRule(
          id: 'default-red-temperature',
          kind: RuleKind.conditionAlert,
          metric: 'temperature',
          op: 'red',
          notifyManager: true,
        ),
      ];
}
