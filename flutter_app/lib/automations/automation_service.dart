import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../analytics/pma_metrics.dart';
import '../assistant/assistant_intent.dart';
import '../models/temp_humidity_model.dart';
import '../models/th_threshold_model.dart';
import 'automation_engine.dart';
import 'automation_rule.dart';
import 'rule_suggester.dart';

/// Owns the automation rules, runs them every minute while the app is open,
/// keeps an in-app inbox of fired events and queues manager alerts for
/// Firestore (`alerts`), where a Cloud Function pushes them with FCM.
///
/// Everything is local-first: rules, fired keys, inbox and the unsent alert
/// outbox live in the app's key-value store, so checks run offline and alerts
/// are delivered when the phone is back online.
class AutomationService extends ChangeNotifier {
  AutomationService({
    required this.readMeta,
    required this.writeMeta,
    required this.reports,
    required this.threshold,
    required this.missing,
    this.sendAlert,
    this.publishRules,
    this.isOnline,
    this.engine = const AutomationEngine(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _load();
  }

  static const rulesKey = 'pma_automations';
  static const firedKey = 'pma_automation_fired';
  static const inboxKey = 'pma_automation_inbox';
  static const outboxKey = 'pma_alert_outbox';
  static const maxFired = 400;
  static const maxInbox = 50;

  final String? Function(String key) readMeta;
  final Future<void> Function(String key, String value) writeMeta;
  final List<TempHumidityReport> Function() reports;
  final ThThreshold Function(String sectionId) threshold;
  final MissingFn missing;

  /// Writes one manager alert to the cloud. Throws when offline / denied.
  final Future<void> Function(AutomationEvent event)? sendAlert;

  /// Mirrors active rules to the cloud for the scheduled Cloud Function.
  final Future<void> Function(List<AutomationRule> rules)? publishRules;
  final bool Function()? isOnline;
  final AutomationEngine engine;
  final DateTime Function() _clock;

  /// Called for every newly fired event (UI banner / spoken alert).
  void Function(AutomationEvent event)? onEvent;

  List<AutomationRule> _rules = const [];
  List<String> _fired = [];
  List<AutomationEvent> _inbox = [];
  List<AutomationEvent> _outbox = [];
  Timer? _timer;

  /// Approved rules, active or paused.
  List<AutomationRule> get rules => _rules.where((r) => r.approved).toList();

  /// AI suggestions waiting for approval.
  List<AutomationRule> get suggestions => _rules.where((r) => !r.approved).toList();
  List<AutomationEvent> get inbox => List.unmodifiable(_inbox);
  int get pendingAlerts => _outbox.length;

  void _load() {
    _rules = AutomationRule.listFromJson(readMeta(rulesKey));
    _fired = _decodeList(readMeta(firedKey)).whereType<String>().toList();
    _inbox = _events(readMeta(inboxKey));
    _outbox = _events(readMeta(outboxKey));
  }

  static List<Object?> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<AutomationEvent> _events(String? raw) => [
        for (final e in _decodeList(raw))
          if (e is Map) ?AutomationEvent.fromMap(Map<String, Object?>.from(e)),
      ];

  Future<void> _saveRules({bool publish = true}) async {
    await writeMeta(rulesKey, AutomationRule.listToJson(_rules));
    notifyListeners();
    if (publish && publishRules != null && (isOnline?.call() ?? true)) {
      try {
        await publishRules!(_rules.where((r) => r.active).toList());
      } catch (e) {
        debugPrint('Publishing automations failed: $e');
      }
    }
  }

  // ------------------------------------------------------------ editing

  /// Adds or replaces [rule]. Returns a validation error, or null on success.
  Future<String?> upsert(AutomationRule rule) async {
    final err = rule.validate();
    if (err != null) return err;
    final i = _rules.indexWhere((r) => r.id == rule.id);
    _rules = [..._rules];
    if (i < 0) {
      _rules.add(rule);
    } else {
      _rules[i] = rule;
    }
    await _saveRules();
    return null;
  }

  Future<void> remove(String id) async {
    _rules = _rules.where((r) => r.id != id).toList();
    await _saveRules();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _rules = [
      for (final r in _rules)
        if (r.id == id && r.approved) r.copyWith(enabled: enabled) else r,
    ];
    await _saveRules();
  }

  /// Admin approval of an AI suggestion: it becomes a normal, active rule.
  Future<void> approve(String id) async {
    _rules = [
      for (final r in _rules)
        if (r.id == id) r.copyWith(approved: true, enabled: true) else r,
    ];
    await _saveRules();
  }

  Future<void> dismiss(String id) => remove(id);

  /// Asks Gemini (or heuristics) for new rules and stores them as unapproved
  /// suggestions. Returns how many were added and which engine produced them.
  Future<({int added, AnswerSource source})> suggest(RuleSuggester suggester, PmaMetrics metrics) async {
    final res = await suggester.suggest(metrics, _rules);
    final fresh = res.rules.where((s) => !_rules.any((r) => r.id == s.id)).toList();
    if (fresh.isNotEmpty) {
      _rules = [..._rules, ...fresh];
      await _saveRules(publish: false);
    }
    return (added: fresh.length, source: res.source);
  }

  // ------------------------------------------------------------ running

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => tick());
    tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Evaluates every active rule once. Returns the newly fired events.
  Future<List<AutomationEvent>> tick() async {
    final events = engine.evaluate(
      rules: _rules,
      now: _clock(),
      reports: reports(),
      threshold: threshold,
      missing: missing,
      alreadyFired: _fired.toSet(),
    );
    if (events.isNotEmpty) {
      _fired = [..._fired, ...events.map((e) => e.key)];
      if (_fired.length > maxFired) _fired = _fired.sublist(_fired.length - maxFired);
      _inbox = [...events.reversed, ..._inbox];
      if (_inbox.length > maxInbox) _inbox = _inbox.sublist(0, maxInbox);
      _outbox = [..._outbox, ...events.where((e) => e.notifyManager)];
      await writeMeta(firedKey, jsonEncode(_fired));
      await writeMeta(inboxKey, jsonEncode([for (final e in _inbox) e.toMap()]));
      await _saveOutbox();
      for (final e in events) {
        onEvent?.call(e);
      }
      notifyListeners();
    }
    await flushAlerts();
    return events;
  }

  Future<void> _saveOutbox() =>
      writeMeta(outboxKey, jsonEncode([for (final e in _outbox) e.toMap()]));

  /// Sends queued manager alerts; failures stay queued for the next tick.
  Future<void> flushAlerts() async {
    if (_outbox.isEmpty || sendAlert == null) return;
    if (!(isOnline?.call() ?? true)) return;
    final left = <AutomationEvent>[];
    for (final e in _outbox) {
      try {
        await sendAlert!(e);
      } catch (err) {
        debugPrint('Alert not sent yet: $err');
        left.add(e);
      }
    }
    if (left.length != _outbox.length) {
      _outbox = left;
      await _saveOutbox();
      notifyListeners();
    }
  }

  Future<void> clearInbox() async {
    _inbox = [];
    await writeMeta(inboxKey, '[]');
    notifyListeners();
  }
}
