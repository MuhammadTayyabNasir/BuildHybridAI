import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/dashboard_spec.dart';
import '../../analytics/pma_metrics.dart';
import '../../assistant/assistant_intent.dart';
import '../../assistant/hybrid_ai.dart';
import '../../assistant/voice_io.dart';
import '../../providers/connectivity_provider.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_threshold_service.dart';
import '../../ui/dabba_mascot.dart';
import '../../ui/pma_ui.dart';
import '../assistant/assistant_screen.dart' show SourceBadge;
import '../../assistant/hybrid_ai_factory.dart';

/// Manager insights. Cloud Gemini (long context) designs a dashboard from
/// aggregated numbers and writes a spoken explanation; Gemini Nano gives a
/// short on-device summary; without any model the phone builds the same
/// dashboard deterministically.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.ai, this.voice});
  final HybridAi? ai;
  final VoiceIo? voice;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final HybridAi _ai = widget.ai ?? createHybridAi();
  late final VoiceIo _voice = widget.voice ?? VoiceIo();
  int _days = 30;
  bool _urdu = false;
  bool _loading = false;
  DashboardSpec? _spec;
  AnswerSource _source = AnswerSource.rules;
  String? _quick;
  AnswerSource? _quickSource;
  String? _note;

  PmaMetrics _metrics() => PmaMetrics(
        entries: context.read<LocalStorageService>().getEntries(),
        reports: context.read<LocalStorageService>().getTempHumidityReports(),
        threshold: context.read<ThThresholdService>().forSection,
      );

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _build({required bool cloud}) async {
    setState(() {
      _loading = true;
      _note = null;
    });
    final metrics = _metrics();
    DashboardSpec? spec;
    var source = AnswerSource.rules;
    if (cloud) {
      final answer = await _ai.generate(
        DashboardSpec.prompt(metrics.summary(days: _days), urdu: _urdu),
        cloudOnly: true,
      );
      if (answer != null) {
        spec = DashboardSpec.tryParse(answer.text);
        source = answer.source;
        if (spec == null) _note = 'The AI answer was not a valid dashboard; showing the on-phone version.';
      } else {
        _note = _ai.available
            ? 'Cloud AI is not reachable right now; showing the on-phone version.'
            : 'Cloud dashboards run through the Android app; showing the on-phone version.';
      }
    }
    spec ??= DashboardSpec.local(metrics, urdu: _urdu, days: _days);
    if (spec.kpis.isEmpty || spec.summary.isEmpty) source = AnswerSource.rules;
    if (!mounted) return;
    setState(() {
      _spec = spec;
      _source = spec == null ? AnswerSource.rules : source;
      _loading = false;
    });
  }

  Future<void> _quickSummary() async {
    final m = _metrics();
    final today = m.lastDays(1).single;
    final facts =
        'Today: ${m.readingsOn(today)} temperature/humidity readings, ${m.entriesOn(today)} packing checks. '
        '7-day pass rate ${m.passRate().toStringAsFixed(0)}%.';
    setState(() => _quick = '…');
    final answer = await _ai.generate(
      'In ${_urdu ? 'Urdu script' : 'English'}, write ONE short sentence for a factory shift manager '
      'summarising these numbers. Use only these facts: $facts',
    );
    if (!mounted) return;
    setState(() {
      _quick = answer?.text.trim() ?? facts;
      _quickSource = answer?.source ?? AnswerSource.rules;
    });
    await _voice.say(_quick!, urdu: _urdu && answer != null);
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityProvider>().isOnline;
    final spec = _spec;
    return Scaffold(
      backgroundColor: Pma.canvas,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHero(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Insights',
                            style: TextStyle(
                                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                      ),
                      TrendPill(label: online ? 'Cloud ready' : 'Offline', onDark: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ask Gemini to build a dashboard from your factory\'s numbers and explain it out loud.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final d in const [7, 30])
                        ChoiceChip(
                          label: Text('$d days'),
                          selected: _days == d,
                          onSelected: (_) => setState(() => _days = d),
                        ),
                      ChoiceChip(
                        label: const Text('اردو'),
                        selected: _urdu,
                        onSelected: (v) => setState(() => _urdu = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Pma.ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _loading ? null : () => _build(cloud: true),
                          icon: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.auto_awesome),
                          label: const Text('Build AI dashboard'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          foregroundColor: Colors.white,
                        ),
                        tooltip: 'Quick on-device summary',
                        onPressed: _quickSummary,
                        icon: const Icon(Icons.bolt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_quick != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: PmaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Quick summary',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (_quickSource != null) SourceBadge(_quickSource!),
                    ]),
                    const SizedBox(height: 6),
                    Text(_quick!),
                  ],
                ),
              ),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(_note!, style: const TextStyle(color: Pma.inkSoft, fontSize: 12)),
            ),
          if (spec == null && !_loading)
            Padding(
              padding: const EdgeInsets.all(20),
              child: PmaCard(
                child: Column(
                  children: [
                    const Dabba(mood: DabbaMood.thinking, size: 84),
                    const SizedBox(height: 8),
                    const Text('No dashboard yet', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap "Build AI dashboard". Only counts and averages are sent to the cloud — no names.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Pma.inkSoft),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _build(cloud: false),
                      child: const Text('Show the on-phone version'),
                    ),
                  ],
                ),
              ),
            ),
          if (spec != null) ..._dashboard(spec),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _dashboard(DashboardSpec spec) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(spec.title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              SourceBadge(_source),
            ],
          ),
        ),
        if (spec.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(spec.summary, style: const TextStyle(color: Pma.inkSoft, height: 1.4)),
          ),
        if (spec.spoken.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                onPressed: () => _voice.say(spec.spoken, urdu: _urdu),
                icon: const Icon(Icons.volume_up),
                label: Text(_urdu ? 'سنیں' : 'Listen to the explanation'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final k in spec.kpis)
                  SizedBox(
                    width: w,
                    child: PmaCard(
                      padding: const EdgeInsets.all(16),
                      child: KpiTile(
                        caption: k.label,
                        value: k.value,
                        pill: k.trend == null && k.status == null
                            ? null
                            : TrendPill(
                                label: k.trend ?? k.status!,
                                up: k.trend == null ? null : !k.trend!.startsWith('-'),
                                color: k.status == null ? null : Pma.status(k.status!),
                              ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
        for (final c in spec.charts)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: PmaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  c.type == 'line'
                      ? AreaTrendChart(values: c.values, labels: c.labels, unit: c.unit)
                      : RoundedBarChart(values: c.values, labels: c.labels, unit: c.unit),
                ],
              ),
            ),
          ),
        if (spec.insights.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: PmaCard(
              color: Pma.ink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What to do',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final i in spec.insights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6, right: 8),
                            child: Icon(Icons.circle, size: 6, color: Pma.sun),
                          ),
                          Expanded(
                            child: Text(i, style: const TextStyle(color: Colors.white, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ];
}
