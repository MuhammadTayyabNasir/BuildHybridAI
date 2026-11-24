import 'dart:convert';

import '../analytics/pma_metrics.dart';
import '../assistant/assistant_intent.dart';
import '../assistant/hybrid_ai.dart';
import '../core/constants/sections.dart';
import 'automation_rule.dart';

/// Proposes new automations from recent readings. Gemini (on-device first,
/// cloud fallback) reads a name-free summary and may return up to three rules
/// in a whitelisted JSON shape. Every suggestion is validated and stored as
/// `origin: ai, approved: false, enabled: false` — it does nothing until an
/// admin approves it. Without a model, simple heuristics propose rules.
class RuleSuggester {
  const RuleSuggester(this.ai);

  final HybridAi ai;

  static const maxSuggestions = 3;

  Future<({List<AutomationRule> rules, AnswerSource source})> suggest(
    PmaMetrics metrics,
    List<AutomationRule> existing,
  ) async {
    final summary = metrics.summary(days: 14);
    final answer = await ai.generate(prompt(summary, existing));
    if (answer != null) {
      final parsed = parse(answer.text, existing);
      if (parsed.isNotEmpty) return (rules: parsed, source: answer.source);
    }
    return (rules: heuristics(summary, existing), source: AnswerSource.rules);
  }

  static String prompt(Map<String, Object?> summary, List<AutomationRule> existing) =>
      'You help a snack factory QC manager set up automations for temperature and humidity '
      'logging. Based on the 14-day summary, propose at most $maxSuggestions NEW rules that '
      'would catch real problems. Reply with JSON only, no prose: '
      '{"rules":[{"kind":"condition_alert|shift_end_check|reminder",'
      '"sectionId":"${Sections.ids.join('|')}|null","metric":"temperature|humidity",'
      '"op":"gt|lt|red","value":number,"time":"HH:mm","shift":"morning|night",'
      '"messageEn":"...","messageUr":"... (Urdu script)","notifyManager":true,'
      '"reason":"one short sentence citing the numbers"}]}. '
      'Only include fields the kind needs. Do not repeat these existing rules: '
      '${jsonEncode([for (final r in existing) r.describeEn()])}. '
      'Summary: ${jsonEncode(summary)}';

  /// Strictly reads the model output. Anything outside the whitelist or
  /// duplicating an existing rule is dropped.
  static List<AutomationRule> parse(String raw, List<AutomationRule> existing) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return const [];
      final m = jsonDecode(raw.substring(start, end + 1));
      final list = m is Map ? m['rules'] : null;
      if (list is! List) return const [];
      final out = <AutomationRule>[];
      for (final e in list) {
        if (e is! Map) continue;
        final map = Map<String, Object?>.from(e)..remove('id');
        final rule = AutomationRule.fromMap(map, forceOrigin: 'ai');
        if (rule == null) continue;
        if (_duplicate(rule, [...existing, ...out])) continue;
        out.add(rule);
        if (out.length == maxSuggestions) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static bool _duplicate(AutomationRule r, List<AutomationRule> others) => others.any((o) =>
      o.kind == r.kind &&
      o.sectionId == r.sectionId &&
      o.metric == r.metric &&
      o.op == r.op &&
      o.shift == r.shift &&
      (o.value ?? -1) == (r.value ?? -1) &&
      (r.kind != RuleKind.reminder || o.time == r.time));

  /// Offline fallback: an early-warning alert at the yellow limit for every
  /// section that hit red at least twice.
  static List<AutomationRule> heuristics(
      Map<String, Object?> summary, List<AutomationRule> existing) {
    final out = <AutomationRule>[];
    final sections = summary['sections'];
    if (sections is! Map) return out;
    for (final entry in sections.entries) {
      final s = entry.value;
      if (s is! Map) continue;
      final limits = s['limits'] as Map?;
      for (final metric in AutomationRule.metrics) {
        final reds = (metric == 'temperature' ? s['redTemperature'] : s['redHumidity']) as int? ?? 0;
        if (reds < 2) continue;
        final yellow = (limits?[metric == 'temperature' ? 'tempYellowMax' : 'humYellowMax'] as num?)
            ?.toDouble();
        if (yellow == null) continue;
        final rule = AutomationRule(
          id: 'ai-${entry.key}-$metric-${yellow.toInt()}',
          kind: RuleKind.conditionAlert,
          origin: 'ai',
          approved: false,
          enabled: false,
          sectionId: entry.key as String,
          metric: metric,
          op: 'gt',
          value: yellow - 1,
          notifyManager: true,
          reason: '${s['name']} went into red $metric $reds times in 14 days; '
              'warn one point before the yellow limit.',
        );
        if (rule.validate() == null && !_duplicate(rule, [...existing, ...out])) out.add(rule);
        if (out.length == maxSuggestions) return out;
      }
    }
    return out;
  }
}
