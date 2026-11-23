import 'dart:convert';

/// Which engine understood the operator's words.
enum AnswerSource {
  onDevice('On-device'),
  cloud('Cloud'),
  rules('Rules');

  const AnswerSource(this.label);
  final String label;

  static AnswerSource fromChannel(String? s) =>
      s == 'on-device' ? AnswerSource.onDevice : AnswerSource.cloud;
}

enum IntentType {
  countEntries('count_entries'),
  findMissingEntries('find_missing_entries'),
  addThReading('add_th_reading'),
  addPackingEntry('add_packing_entry'),
  openScreen('open_screen'),
  dailySummary('daily_summary'),
  unknown('unknown');

  const IntentType(this.wire);
  final String wire;

  static IntentType fromWire(String? s) => IntentType.values.firstWhere(
        (t) => t.wire == s,
        orElse: () => IntentType.unknown,
      );
}

/// Structured result of understanding one operator command.
///
/// The model (or rules parser) only fills these slots. Nothing here is trusted
/// until [AssistantService] validates it against sections, ranges and
/// thresholds.
class AssistantIntent {
  const AssistantIntent({
    required this.type,
    required this.source,
    this.section,
    this.temperature,
    this.humidity,
    this.shift,
    this.screen,
    this.period = 'today',
    this.product,
    this.weight,
    this.confidence = 1,
  });

  final IntentType type;
  final AnswerSource source;
  final String? section;
  final double? temperature;
  final double? humidity;
  final String? shift;
  final String? screen;
  final String period;
  final String? product;
  final double? weight;
  final double confidence;

  /// Parses the strict JSON produced by the hybrid model. Returns null when the
  /// text is not the expected shape, so the caller can fall back to rules.
  static AssistantIntent? tryParseJson(String raw, AnswerSource source) {
    try {
      var text = raw.trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      text = text.substring(start, end + 1);
      final m = jsonDecode(text);
      if (m is! Map) return null;
      String? str(String k) {
        final v = m[k];
        if (v is! String) return null;
        final t = v.trim();
        return t.isEmpty || t == 'null' ? null : t;
      }

      double? numv(String k) {
        final v = m[k];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      return AssistantIntent(
        type: IntentType.fromWire(str('intent')),
        source: source,
        section: normalizeSection(str('section')),
        temperature: numv('temperature'),
        humidity: numv('humidity'),
        shift: _normShift(str('shift')),
        screen: str('screen'),
        period: str('period') ?? 'today',
        product: str('product'),
        weight: numv('weight'),
        confidence: (numv('confidence') ?? 0.8).clamp(0, 1).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _normShift(String? s) {
    if (s == null) return null;
    final l = s.toLowerCase();
    if (l.startsWith('morn') || l.contains('subah') || l.contains('din')) {
      return 'morning';
    }
    if (l.startsWith('night') || l.startsWith('even') || l.contains('raat') ||
        l.contains('shaam')) {
      return 'night';
    }
    return null;
  }

  /// Maps any spelling the model or operator used to a section id.
  static String? normalizeSection(String? s) {
    if (s == null) return null;
    final l = s.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (l.isEmpty) return null;
    if (l.contains('peri') || l.contains('پیری')) return 'peri_peri';
    if (l.contains('chip') || l.contains('چپس')) return 'chips';
    if (l.contains('nimko') || l.contains('namko') || l.contains('نمکو')) {
      return 'nimko';
    }
    if (l.contains('wafer') || l.contains('ویفر')) return 'wafer';
    if (l.contains('choc') || l.contains('چاکلیٹ')) return 'chocolate';
    return null;
  }
}
