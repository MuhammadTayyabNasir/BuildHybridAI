import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../models/packing_entry_model.dart';
import '../../providers/entries_provider.dart';

/// "Week Analysis" (Weak Link) — side-by-side multi-week comparison mirroring
/// the QC weekly deck: for each metric, Yellow %/Red % defect rates per ISO
/// week, plus this-week-vs-last-week deltas and the latest week's weak-link
/// machines. All local-first; in-app colours are the real green/yellow/red.
class WeekAnalysisScreen extends StatefulWidget {
  const WeekAnalysisScreen({super.key});

  @override
  State<WeekAnalysisScreen> createState() => _WeekAnalysisScreenState();
}

class _Metric {
  final String label;
  final String Function(PackingEntryModel) cls; // green/yellow/red or 'na'
  const _Metric(this.label, this.cls);
}

class _WeekBucket {
  final int week;
  final DateTime start;
  final List<PackingEntryModel> entries;
  _WeekBucket(this.week, this.start, this.entries);
}

class _WeekAnalysisScreenState extends State<WeekAnalysisScreen> {
  int _weeks = 6; // number of weeks to compare (capped to the 90-day window)
  String? _sectionId; // null = All sections (mirrors the Excel per-section deck)
  List<_WeekBucket> _buckets = [];
  bool _loading = true;

  String get _sectionLabel =>
      _sectionId == null ? 'All Sections' : Sections.byId(_sectionId!).name;

  static final _metrics = <_Metric>[
    _Metric('Weight Variation', (e) => e.weightStatus),
    _Metric('Leakage', (e) => e.leakageStatus),
    _Metric('Printing', (e) => e.printingStatus == 'okay'
        ? 'green'
        : (e.printingColor == 'yellow' ? 'yellow' : 'red')),
    _Metric('Moisture', (e) => e.moistureStatus),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    // Cap to the 90-day local window; +1 week of slack for the partial week.
    final days = (_weeks * 7).clamp(7, 90);
    final from = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    var entries = context
        .read<EntriesProvider>()
        .localEntriesInRange(from: from, to: now);
    // Per-section focus (matches the Excel "Weekly By Section" deck).
    if (_sectionId != null) {
      entries = entries.where((e) => e.section == _sectionId).toList();
    }

    final map = <DateTime, List<PackingEntryModel>>{};
    for (final e in entries) {
      final d = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      map.putIfAbsent(monday, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    var buckets = [for (final k in keys) _WeekBucket(_isoWeek(k), k, map[k]!)];
    if (buckets.length > _weeks) {
      buckets = buckets.sublist(buckets.length - _weeks);
    }
    if (!mounted) return;
    setState(() {
      _buckets = buckets;
      _loading = false;
    });
  }

  int _isoWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final dayOfYear = int.parse(DateFormat('D').format(d));
    final woy = (dayOfYear - d.weekday + 10) ~/ 7;
    if (woy < 1) return _isoWeek(DateTime(date.year - 1, 12, 31));
    return woy;
  }

  // ── defect stats for a metric within a bucket ──────────────────────────────
  ({int tot, int yellow, int red}) _stat(_WeekBucket b, _Metric m) {
    final list = b.entries.where((e) => m.cls(e) != 'na');
    var y = 0, r = 0, t = 0;
    for (final e in list) {
      t++;
      final s = m.cls(e);
      if (s == 'yellow') y++;
      if (s == 'red') r++;
    }
    return (tot: t, yellow: y, red: r);
  }

  double _pct(int n, int tot) => tot == 0 ? 0 : n / tot * 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Week Analysis · Weak Link'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () { setState(() => _loading = true); _load(); },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          // Selectors stay visible always, so an empty section isn't a dead end.
          _sectionSelector(),
          const SizedBox(height: 8),
          _weekSelector(),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('No entries for $_sectionLabel in the selected weeks.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else ...[
            _comparisonCard(),
            const SizedBox(height: 8),
            for (final m in _metrics) ...[
              _metricChartCard(m),
              const SizedBox(height: 8),
            ],
            _weakLinkCard(),
          ],
        ],
      ),
    );
  }

  // ── Section focus selector (All + each section) ────────────────────────────
  Widget _sectionSelector() {
    Widget chip(String label, String? id) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: _sectionId == id,
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              if (_sectionId == id) return;
              setState(() { _sectionId = id; _loading = true; });
              _load();
            },
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.category_outlined, size: 18),
              SizedBox(width: 8),
              Text('Section', style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip('All', null),
                  for (final s in Sections.all) chip(s.name, s.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.calendar_view_week, size: 18),
            const SizedBox(width: 8),
            const Text('Compare', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final w in const [4, 6, 8, 12]) ...[
                      ChoiceChip(
                        label: Text('$w wk'),
                        selected: _weeks == w,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() { _weeks = w; _loading = true; });
                          _load();
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── This week vs last week deltas ──────────────────────────────────────────
  Widget _comparisonCard() {
    final cur = _buckets.last;
    final prev = _buckets.length >= 2 ? _buckets[_buckets.length - 2] : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.compare_arrows, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prev == null
                      ? '$_sectionLabel · Week ${cur.week} (defect %)'
                      : '$_sectionLabel · Wk ${prev.week} → Wk ${cur.week} (defect %)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Defect % = warning + fail. Lower is better.',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            const Divider(),
            for (final m in _metrics) _comparisonRow(m, cur, prev),
          ],
        ),
      ),
    );
  }

  Widget _comparisonRow(_Metric m, _WeekBucket cur, _WeekBucket? prev) {
    final c = _stat(cur, m);
    final curPct = _pct(c.yellow + c.red, c.tot);
    double? prevPct;
    if (prev != null) {
      final p = _stat(prev, m);
      prevPct = _pct(p.yellow + p.red, p.tot);
    }
    final delta = prevPct == null ? null : curPct - prevPct;
    final improved = delta != null && delta < -0.05;
    final worse = delta != null && delta > 0.05;
    final color = worse ? AppColors.red : (improved ? AppColors.green : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(m.label, style: const TextStyle(fontSize: 13))),
          if (prevPct != null)
            Expanded(
              flex: 2,
              child: Text('${prevPct.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text('${curPct.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          if (delta != null)
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    improved ? Icons.arrow_downward : (worse ? Icons.arrow_upward : Icons.remove),
                    size: 13, color: color,
                  ),
                  Text('${delta.abs().toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Per-metric grouped bar chart (Yellow % / Red % per week) ────────────────
  Widget _metricChartCard(_Metric m) {
    var maxY = 5.0;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < _buckets.length; i++) {
      final s = _stat(_buckets[i], m);
      final yp = _pct(s.yellow, s.tot);
      final rp = _pct(s.red, s.tot);
      if (yp > maxY) maxY = yp;
      if (rp > maxY) maxY = rp;
      groups.add(BarChartGroupData(x: i, barsSpace: 3, barRods: [
        BarChartRodData(
            toY: yp, width: 9, color: AppColors.yellow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
        BarChartRodData(
            toY: rp, width: 9, color: AppColors.red,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
      ]));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('WEAK LINK · ${m.label}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _dot(AppColors.yellow, 'Yellow'),
              const SizedBox(width: 10),
              _dot(AppColors.red, 'Red'),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.2,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: AppColors.divider, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= _buckets.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Wk ${_buckets[i].week}',
                                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: (maxY / 4).ceilToDouble().clamp(1, double.infinity),
                        getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, gi, rod, ri) {
                        final s = _stat(_buckets[group.x], m);
                        final label = ri == 0 ? 'Yellow' : 'Red';
                        return BarTooltipItem(
                          'Wk ${_buckets[group.x].week}\n$label ${rod.toY.toStringAsFixed(2)}%\n'
                          '${s.tot} entries',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  barGroups: groups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Weak-link machines for the latest week ─────────────────────────────────
  Widget _weakLinkCard() {
    final cur = _buckets.last;
    final byMachine = <String, ({int defects, Set<String> issues, int n})>{};
    for (final e in cur.entries) {
      final key = '${Sections.byId(e.section).name} · M${e.machineNumber}';
      final issues = <String>{
        if (e.weightStatus == 'red') 'Weight',
        if (e.moistureStatus == 'red') 'Moisture',
        if (e.printingStatus == 'not_okay') 'Printing',
        if (e.leakageStatus == 'red') 'Leakage',
      };
      final prev = byMachine[key];
      byMachine[key] = (
        defects: (prev?.defects ?? 0) + (issues.isEmpty ? 0 : 1),
        issues: {...?prev?.issues, ...issues},
        n: (prev?.n ?? 0) + 1,
      );
    }
    final ranked = byMachine.entries.where((e) => e.value.defects > 0).toList()
      ..sort((a, b) => b.value.defects.compareTo(a.value.defects));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.link_off, size: 18, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Weak-link machines · Week ${cur.week}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Machines with the most failed entries this week.',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
            const Divider(),
            if (ranked.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No failures this week — all machines green. ✅',
                    style: TextStyle(color: AppColors.green)),
              )
            else
              for (final e in ranked.take(12))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 30, height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${e.value.defects}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.key,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Flexible(
                        child: Text(e.value.issues.join(', '),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      );
}
