import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/sections.dart';
import '../../../../../models/packing_entry_model.dart';
import '../../../../../core/previews/theme_preview.dart';
import '../models/advanced_helpers.dart';

// ── KPI Row ───────────────────────────────────────────────────────────────────
class AdvancedKpiRow extends StatelessWidget {
  final List<PackingEntryModel> entries;
  final bool showSection;

  const AdvancedKpiRow({super.key, required this.entries, this.showSection = false});

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final defects = entries.where(isAdvancedDefect).length;
    final passRate = total > 0 ? (total - defects) / total * 100 : 0.0;
    final passColor = passRate >= 90 ? AppColors.green : passRate >= 70 ? AppColors.yellow : AppColors.red;

    final machineDefects = <String, int>{};
    for (final e in entries) {
      if (isAdvancedDefect(e)) {
        final k = '${e.section}#${e.machineNumber}';
        machineDefects[k] = (machineDefects[k] ?? 0) + 1;
      }
    }
    final topEntry = machineDefects.isEmpty ? null : machineDefects.entries.reduce((a, b) => a.value > b.value ? a : b);

    var topValue = '—';
    String? topSub;
    if (topEntry != null) {
      final parts = topEntry.key.split('#');
      topValue = 'M${parts[1]}';
      final secName = Sections.byId(parts[0]).name;
      topSub = showSection ? '$secName · ${topEntry.value} defects' : '${topEntry.value} defects';
    }

    return Row(children: [
      Expanded(child: _KpiCard('Total', '$total', Icons.list_alt_rounded, AppColors.primary)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Pass Rate', '${passRate.toStringAsFixed(1)}%', Icons.check_circle_outline, passColor)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Defects', '$defects', Icons.warning_amber_rounded, defects > 0 ? AppColors.red : AppColors.green)),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard('Top Issue', topValue, Icons.precision_manufacturing_outlined, topEntry != null ? AppColors.red : AppColors.textHint, sub: topSub)),
    ]);
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? sub;

  const _KpiCard(this.label, this.value, this.icon, this.color, {this.sub});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }
}

// ── Machine Status Grid ───────────────────────────────────────────────────────
class MachineGrid extends StatelessWidget {
  final Map<String, MachineStats> stats;
  final bool showSection;

  const MachineGrid({super.key, required this.stats, this.showSection = false});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    final sorted = stats.values.toList()..sort((a, b) => b.defectRate.compareTo(a.defectRate));
    final alerts = sorted.where((s) => s.defectRate > 0.15).length;
    final watches = sorted.where((s) => s.defectRate > 0.05 && s.defectRate <= 0.15).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.precision_manufacturing_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Machine Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (alerts > 0) _badge('$alerts alert${alerts > 1 ? 's' : ''}', AppColors.red),
            if (watches > 0) ...[const SizedBox(width: 6), _badge('$watches watch', AppColors.yellow)],
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _dot(AppColors.green, 'Good <5%'),
            const SizedBox(width: 10),
            _dot(AppColors.yellow, 'Watch 5–15%'),
            const SizedBox(width: 10),
            _dot(AppColors.red, 'Alert >15%'),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sorted.map((s) => _MachineTile(stats: s, showSection: showSection)).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _dot(Color c, String label) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
  ]);
}

class _MachineTile extends StatelessWidget {
  final MachineStats stats;
  final bool showSection;

  const _MachineTile({required this.stats, this.showSection = false});

  @override
  Widget build(BuildContext context) {
    final c = stats.statusColor;
    final secName = Sections.byId(stats.section).name;
    return Tooltip(
      message: '${showSection ? '$secName · ' : ''}M${stats.machineNumber} — ${(stats.defectRate * 100).toStringAsFixed(0)}% defect rate · tap for details',
      child: GestureDetector(
        onTap: () => _showDetail(context),
        child: Container(
          width: showSection ? 84 : 72,
          height: showSection ? 84 : 72,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.55), width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (showSection)
              Text(secName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: c.withValues(alpha: 0.85))),
            Text('M${stats.machineNumber}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c)),
            const SizedBox(height: 1),
            Text('${(stats.defectRate * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
            Text('${stats.defectEntries}/${stats.total}', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final passRate = (1 - stats.defectRate) * 100;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: stats.statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Machine ${stats.machineNumber}'),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 260),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _row('Section', stats.section),
            _row('Total Entries', '${stats.total}'),
            _row('Pass Rate', '${passRate.toStringAsFixed(1)}%', valueColor: passRate >= 85 ? AppColors.green : passRate >= 70 ? AppColors.yellow : AppColors.red),
            _row('Defect Entries', '${stats.defectEntries}'),
            const Divider(height: 20),
            if (stats.weightDefects > 0) _defectRow('Weight defects', stats.weightDefects, AppColors.primary),
            if (stats.moistureDefects > 0) _defectRow('Moisture defects', stats.moistureDefects, Colors.blue),
            if (stats.printDefects > 0) _defectRow('Print defects', stats.printDefects, Colors.purple),
            if (stats.leakageDefects > 0) _defectRow('Leakage defects', stats.leakageDefects, Colors.orange),
            if (stats.totalDefects == 0) const Padding(padding: EdgeInsets.only(top: 4), child: Text('No defects recorded', style: TextStyle(color: AppColors.green, fontSize: 13))),
            if (stats.topProduct != null) ...[const Divider(height: 20), _row('Top Product', stats.topProduct!)],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _row(String k, String v, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))), Text(v, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: valueColor))]),
  );

  Widget _defectRow(String label, int count, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      Text('$count', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.red)),
    ]),
  );
}

// ── Daily Stacked Bar Chart ───────────────────────────────────────────────────
class DailyStackedBar extends StatefulWidget {
  final List<PackingEntryModel> entries;
  const DailyStackedBar({super.key, required this.entries});

  @override
  State<DailyStackedBar> createState() => _DailyStackedBarState();
}

class _DailyStackedBarState extends State<DailyStackedBar> {
  bool _showGreen = true, _showYellow = true, _showRed = true;
  static const _grains = ['7d', '14d', '30d', 'Weekly'];
  String _grain = '14d';

  void _tally(DayData d, PackingEntryModel e) {
    final isRed = e.weightStatus == 'red' || e.moistureStatus == 'red' || e.printingStatus == 'not_okay' || e.leakageStatus == 'red';
    final isYellow = !isRed && (e.weightStatus == 'yellow' || e.moistureStatus == 'yellow' || e.leakageStatus == 'yellow');
    if (isRed) {
      d.red++;
    }
    else if (isYellow) {
      d.yellow++;
    }
    else {
      d.green++;
    }
  }

  List<({String label, DayData data})> _buckets() {
    if (_grain == 'Weekly') {
      final fmt = DateFormat('dd/MM');
      final byWeek = <DateTime, DayData>{};
      for (final e in widget.entries) {
        final d0 = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
        final monday = d0.subtract(Duration(days: d0.weekday - 1));
        _tally(byWeek.putIfAbsent(monday, () => DayData()), e);
      }
      final keys = byWeek.keys.toList()..sort();
      return [for (final k in keys) (label: 'W/O ${fmt.format(k)}', data: byWeek[k]!)];
    }
    final n = _grain == '7d' ? 7 : (_grain == '30d' ? 30 : 14);
    final fmt = DateFormat('dd/MM');
    final byDay = <DateTime, DayData>{};
    for (final e in widget.entries) {
      final k = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      _tally(byDay.putIfAbsent(k, () => DayData()), e);
    }
    final keys = byDay.keys.toList()..sort();
    final tail = keys.length > n ? keys.sublist(keys.length - n) : keys;
    return [for (final k in tail) (label: fmt.format(k), data: byDay[k]!)];
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _buckets();
    if (buckets.isEmpty) return const SizedBox.shrink();

    double maxY = 0;
    for (final b in buckets) {
      final d = b.data;
      final t = ((_showGreen ? d.green : 0) + (_showYellow ? d.yellow : 0) + (_showRed ? d.red : 0)).toDouble();
      if (t > maxY) maxY = t;
    }
    if (maxY == 0) maxY = 1;

    final groups = buckets.asMap().entries.map((entry) {
      final d = entry.value.data;
      final g = _showGreen ? d.green.toDouble() : 0.0;
      final y = _showYellow ? d.yellow.toDouble() : 0.0;
      final r = _showRed ? d.red.toDouble() : 0.0;
      final items = <BarChartRodStackItem>[];
      var cursor = 0.0;
      if (g > 0) { items.add(BarChartRodStackItem(cursor, cursor + g, AppColors.green)); cursor += g; }
      if (y > 0) { items.add(BarChartRodStackItem(cursor, cursor + y, AppColors.yellow)); cursor += y; }
      if (r > 0) { items.add(BarChartRodStackItem(cursor, cursor + r, AppColors.red)); cursor += r; }
      return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: cursor, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)), rodStackItems: items)]);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_grain == 'Weekly' ? 'Weekly Analysis' : 'Daily Analysis', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            _legToggle(AppColors.green, 'Pass', _showGreen, () => setState(() => _showGreen = !_showGreen)),
            const SizedBox(width: 10),
            _legToggle(AppColors.yellow, 'Warning', _showYellow, () => setState(() => _showYellow = !_showYellow)),
            const SizedBox(width: 10),
            _legToggle(AppColors.red, 'Fail', _showRed, () => setState(() => _showRed = !_showRed)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [for (final gr in _grains) ChoiceChip(label: Text(gr, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, selected: _grain == gr, onSelected: (_) => setState(() => _grain = gr))]),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (buckets.length * 40.0).clamp(constraints.maxWidth, double.infinity);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  height: 185,
                  width: width.toDouble(),
                  child: BarChart(BarChartData(
                    maxY: maxY * 1.2,
                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1)),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: 1, getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= buckets.length) return const Text('');
                        return Padding(padding: const EdgeInsets.only(top: 4), child: Text(buckets[i].label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)));
                      })),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: maxY > 0 ? (maxY / 4).ceilToDouble() : 1, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)))),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: groups,
                  )),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _legToggle(Color c, String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: on ? 1 : 0.35,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, decoration: on ? null : TextDecoration.lineThrough)),
        ]),
      ),
    );
  }
}

// ── Quality Breakdown ─────────────────────────────────────────────────────────
class QualityBreakdown extends StatelessWidget {
  final List<PackingEntryModel> entries;
  const QualityBreakdown({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final n = entries.length;
    if (n == 0) return const SizedBox.shrink();

    final cats = [
      BreakdownCat('Weight', Icons.scale, entries.where((e) => e.weightStatus == 'green').length, entries.where((e) => e.weightStatus == 'yellow').length, entries.where((e) => e.weightStatus == 'red').length),
      BreakdownCat('Moisture', Icons.water_drop_outlined, entries.where((e) => e.moistureStatus == 'green' || e.moistureStatus == 'na').length, entries.where((e) => e.moistureStatus == 'yellow').length, entries.where((e) => e.moistureStatus == 'red').length),
      BreakdownCat('Printing', Icons.print_outlined, entries.where((e) => e.printingStatus == 'okay').length, entries.where((e) => e.printingStatus == 'not_okay' && e.printingColor == 'yellow').length, entries.where((e) => e.printingStatus == 'not_okay' && e.printingColor != 'yellow').length),
      BreakdownCat('Leakage', Icons.opacity, entries.where((e) => e.leakageStatus == 'green').length, entries.where((e) => e.leakageStatus == 'yellow').length, entries.where((e) => e.leakageStatus == 'red').length),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.pie_chart_outline, size: 18),
            const SizedBox(width: 8),
            Text('Quality Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          ...cats.map((c) => _buildBar(c, n)),
        ]),
      ),
    );
  }

  Widget _buildBar(BreakdownCat cat, int total) {
    final passRate = total > 0 ? cat.pass / total : 0.0;
    final rateColor = passRate >= 0.9 ? AppColors.green : passRate >= 0.7 ? AppColors.yellow : AppColors.red;
    final displayTotal = cat.pass + cat.warn + cat.fail;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cat.icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(cat.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${(passRate * 100).toStringAsFixed(0)}% OK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: rateColor)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 11,
            child: displayTotal > 0
                ? Row(children: [
              if (cat.pass > 0) Expanded(flex: cat.pass, child: Container(color: AppColors.green)),
              if (cat.warn > 0) Expanded(flex: cat.warn, child: Container(color: AppColors.yellow)),
              if (cat.fail > 0) Expanded(flex: cat.fail, child: Container(color: AppColors.red)),
            ])
                : Container(color: AppColors.divider),
          ),
        ),
      ]),
    );
  }
}

// ── Section Comparison ────────────────────────────────────────────────────────
class SectionComparison extends StatelessWidget {
  final List<PackingEntryModel> entries;
  const SectionComparison({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final data = <String, SecData>{};
    for (final e in entries) {
      final d = data.putIfAbsent(e.section, () => SecData());
      d.total++;
      if (isAdvancedDefect(e)) d.defects++;
      if (e.weightStatus == 'red') d.weight++;
      if (e.leakageStatus == 'red') d.leak++;
      if (e.printingStatus == 'not_okay') d.print++;
      if (e.moistureStatus == 'red') d.moist++;
    }
    if (data.isEmpty) return const SizedBox.shrink();

    final rows = Sections.all.where((s) => data.containsKey(s.id)).map((s) => (s: s, d: data[s.id]!)).toList()..sort((a, b) => a.d.passRate.compareTo(b.d.passRate));
    final weakest = rows.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.leaderboard_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Section Comparison', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(
            'Weakest: ${weakest.s.name} · ${(weakest.d.passRate * 100).toStringAsFixed(0)}% pass\n'
                'W Weight  L Leakage  P Print  M Moisture (fails)',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final r in rows) _row(r.s, r.d),
        ]),
      ),
    );
  }

  Widget _row(SectionInfo s, SecData d) {
    final pass = d.passRate;
    final rateColor = pass >= 0.9 ? AppColors.green : pass >= 0.7 ? AppColors.yellow : AppColors.red;
    final color = AppColors.sectionColor(s.id);
    final metrics = <(String, int)>[('W', d.weight), ('L', d.leak), ('P', d.print), ('M', d.moist)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${(pass * 100).toStringAsFixed(0)}% ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: rateColor)),
          Text('· ${d.total}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              if (d.total - d.defects > 0) Expanded(flex: d.total - d.defects, child: Container(color: color)),
              if (d.defects > 0) Expanded(flex: d.defects, child: Container(color: AppColors.red)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (final (label, count) in metrics)
            Padding(padding: const EdgeInsets.only(right: 8), child: _metricChip(label, count)),
        ]),
      ]),
    );
  }

  Widget _metricChip(String label, int fails) {
    final c = fails == 0 ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
      child: Text('$label $fails', style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Shift Comparison ──────────────────────────────────────────────────────────
class ShiftComparison extends StatelessWidget {
  final List<PackingEntryModel> entries;
  const ShiftComparison({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final morning = entries.where((e) => e.shift == 'morning').toList();
    final night = entries.where((e) => e.shift == 'night').toList();
    if (morning.isEmpty && night.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.compare_arrows_rounded, size: 18),
            const SizedBox(width: 8),
            Text('Shift Comparison', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ShiftTile('Morning', morning, Colors.orange.shade700)),
            const SizedBox(width: 12),
            Expanded(child: _ShiftTile('Night', night, Colors.indigo)),
          ]),
        ]),
      ),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  final String label;
  final List<PackingEntryModel> entries;
  final Color color;

  const _ShiftTile(this.label, this.entries, this.color);

  @override
  Widget build(BuildContext context) {
    final icon = label == 'Morning' ? '☀️' : '🌙';
    final total = entries.length;
    if (total == 0) {
      return Container(
        height: 90,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Center(child: Text('$icon No $label data', style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 13))),
      );
    }
    final defects = entries.where(isAdvancedDefect).length;
    final passRate = (total - defects) / total * 100;
    final rateColor = passRate >= 90 ? AppColors.green : passRate >= 70 ? AppColors.yellow : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$icon $label', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)), const Text('entries', style: TextStyle(fontSize: 10, color: AppColors.textSecondary))])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${passRate.toStringAsFixed(0)}%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: rateColor)), const Text('pass rate', style: TextStyle(fontSize: 10, color: AppColors.textSecondary))])),
        ]),
        if (defects > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$defects defect${defects == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w500)),
          ),
        ],
      ]),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Advanced KPI Row')
Widget previewAdvancedKpiRow() => const Scaffold(
  body: Padding(
    padding: EdgeInsets.all(16.0),
    child: AdvancedKpiRow(entries: [], showSection: true),
  ),
);