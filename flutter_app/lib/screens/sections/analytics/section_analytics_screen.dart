import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/packing_entry_model.dart';
import '../../../../providers/entries_provider.dart';

// Modular imports
import 'drill_down_screen.dart';
import 'models/analytics_helpers.dart';
import 'widgets/section_card_shell.dart';

enum AnalyticsPeriod { daily, weekly, monthly, custom }

class SectionAnalyticsScreen extends StatefulWidget {
  final SectionInfo section;

  const SectionAnalyticsScreen({super.key, required this.section});

  @override
  State<SectionAnalyticsScreen> createState() => _SectionAnalyticsScreenState();
}

class _SectionAnalyticsScreenState extends State<SectionAnalyticsScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.weekly;
  DateTime? _customFrom;
  DateTime? _customTo;

  List<PackingEntryModel> _current = [];
  List<PackingEntryModel> _previous = [];
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _loading = false;

  bool get _tracksMoisture => widget.section.moistureRule != 'na';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ({DateTime from, DateTime to}) _bounds() {
    final now = DateTime.now();
    switch (_period) {
      case AnalyticsPeriod.daily:
        return (from: DateTime(now.year, now.month, now.day), to: now);
      case AnalyticsPeriod.weekly:
        final f = now.subtract(Duration(days: now.weekday - 1));
        return (from: DateTime(f.year, f.month, f.day), to: now);
      case AnalyticsPeriod.monthly:
        return (from: DateTime(now.year, now.month, 1), to: now);
      case AnalyticsPeriod.custom:
        return (
          from: _customFrom ?? now.subtract(const Duration(days: 7)),
          to: _customTo ?? now,
        );
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final b = _bounds();
    _from = b.from;
    _to = b.to;
    final len = _to.difference(_from);
    final prevFrom = _from.subtract(len);

    final mine = context.read<EntriesProvider>().localEntriesInRange(
      from: prevFrom,
      to: _to,
      section: widget.section.id,
    );

    if (!context.mounted) return;
    setState(() {
      _current = mine.where((e) => !e.createdAt.isBefore(_from)).toList();
      _previous = mine.where((e) => e.createdAt.isBefore(_from)).toList();
      _loading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : null,
    );
    if (range != null) {
      setState(() {
        _customFrom = range.start;
        _customTo = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
        );
        _period = AnalyticsPeriod.custom;
      });
      if (context.mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text('${widget.section.name} Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPeriodBar(color),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _current.isEmpty
                ? _buildEmpty(color)
                : _buildContent(color),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBar(Color color) {
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _periodChip('Today', AnalyticsPeriod.daily, color),
              const SizedBox(width: 8),
              _periodChip('This Week', AnalyticsPeriod.weekly, color),
              const SizedBox(width: 8),
              _periodChip('This Month', AnalyticsPeriod.monthly, color),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(
                  _period == AnalyticsPeriod.custom && _customFrom != null
                      ? '${DateFormat('dd MMM').format(_customFrom!)} – ${DateFormat('dd MMM').format(_customTo!)}'
                      : 'Custom',
                  style: const TextStyle(fontSize: 13),
                ),
                avatar: const Icon(Icons.date_range, size: 16),
                selected: _period == AnalyticsPeriod.custom,
                selectedColor: color.withValues(alpha: 0.18),
                onSelected: (_) => _pickCustomRange(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodChip(String label, AnalyticsPeriod p, Color color) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: _period == p,
      selectedColor: color.withValues(alpha: 0.18),
      onSelected: (_) {
        setState(() => _period = p);
        _load();
      },
    );
  }

  Widget _buildEmpty(Color color) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insights_outlined,
            size: 64,
            color: color.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No data for this period',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _period = AnalyticsPeriod.monthly);
              _load();
            },
            child: const Text('Try this month'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color color) {
    final isWide = MediaQuery.of(context).size.width > 820;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _insightsBanner(color),
          _kpiRow(color),
          const SizedBox(height: 14),
          _trendCard(color),
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _qualityBreakdownCard()),
                const SizedBox(width: 14),
                Expanded(child: _machineCard(color)),
              ],
            )
          else ...[
            _qualityBreakdownCard(),
            const SizedBox(height: 14),
            _machineCard(color),
          ],
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _productCard(color)),
                const SizedBox(width: 14),
                Expanded(child: _shiftCard()),
              ],
            )
          else ...[
            _productCard(color),
            const SizedBox(height: 14),
            _shiftCard(),
          ],
          const SizedBox(height: 14),
          _supervisorCard(color),
          if (_tracksMoisture) ...[
            const SizedBox(height: 14),
            _moistureCard(color),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _insightsBanner(Color color) {
    final insights = _computeInsights();
    if (insights.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: insights
            .map(
              (i) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: i.color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: i.color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(i.icon, size: 18, color: i.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i.text,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: i.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  List<AnalyticsInsight> _computeInsights() {
    final out = <AnalyticsInsight>[];
    final curRate = passRate(_current);

    if (_previous.isNotEmpty) {
      final prevRate = passRate(_previous);
      final delta = curRate - prevRate;
      if (delta.abs() >= 3) {
        out.add(
          AnalyticsInsight(
            delta > 0 ? Icons.trending_up : Icons.trending_down,
            delta > 0 ? AppColors.green : AppColors.red,
            delta > 0
                ? 'Quality improved ${delta.toStringAsFixed(0)}% vs previous period (${prevRate.toStringAsFixed(0)}% → ${curRate.toStringAsFixed(0)}%).'
                : 'Quality dropped ${delta.abs().toStringAsFixed(0)}% vs previous period (${prevRate.toStringAsFixed(0)}% → ${curRate.toStringAsFixed(0)}%).',
          ),
        );
      }
    }

    final machines = _machineAggs();
    if (machines.length > 1) {
      final worst = machines.reduce(
        (a, b) => a.passRatePct < b.passRatePct ? a : b,
      );
      if (worst.fails > 0 && worst.passRatePct < 85) {
        out.add(
          AnalyticsInsight(
            Icons.priority_high,
            AppColors.red,
            'Machine ${worst.number} needs attention — ${worst.passRatePct.toStringAsFixed(0)}% pass rate (${worst.fails} defect${worst.fails == 1 ? '' : 's'} in ${worst.total}).',
          ),
        );
      }
    }

    final dom = _dominantDefect();
    if (dom != null) {
      out.add(
        AnalyticsInsight(
          Icons.bug_report_outlined,
          AppColors.yellow.withValues(alpha: 1),
          '${dom.$1} is the leading issue this period (${dom.$2} failure${dom.$2 == 1 ? '' : 's'}).',
        ),
      );
    }

    if (out.isEmpty && curRate >= 98) {
      out.add(
        AnalyticsInsight(
          Icons.verified_outlined,
          AppColors.green,
          'Excellent — ${curRate.toStringAsFixed(0)}% pass rate with no major concerns.',
        ),
      );
    }
    return out.take(3).toList();
  }

  (String, int)? _dominantDefect() {
    int w = 0, m = 0, p = 0, l = 0;
    for (final e in _current) {
      if (e.weightStatus == 'red') w++;
      if (e.moistureStatus == 'red') m++;
      if (e.printingStatus == 'not_okay') p++;
      if (e.leakageStatus == 'red') l++;
    }
    final entries = [
      ('Weight', w),
      ('Moisture', m),
      ('Printing', p),
      ('Leakage', l),
    ].where((e) => e.$2 > 0).toList();
    if (entries.isEmpty) return null;
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    return entries.first;
  }

  Widget _kpiRow(Color color) {
    final total = _current.length;
    final fails = _current.where(isFail).length;
    final warns = _current.where(isWarn).length;
    final rate = passRate(_current);
    final prevRate = _previous.isEmpty ? null : passRate(_previous);
    final prevTotal = _previous.length;

    final cards = [
      _kpiCard(
        'Total Entries',
        '$total',
        Icons.inventory_2_outlined,
        AppColors.primary,
        delta: prevTotal > 0 ? total - prevTotal : null,
        deltaSuffix: ' vs prev',
      ),
      _kpiCard(
        'Pass Rate',
        '${rate.toStringAsFixed(0)}%',
        Icons.check_circle_outline,
        rateColor(rate),
        deltaDouble: prevRate != null ? rate - prevRate : null,
      ),
      _kpiCard(
        'Defects',
        '$fails',
        Icons.warning_amber_rounded,
        fails > 0 ? AppColors.red : AppColors.green,
      ),
      _kpiCard(
        'Warnings',
        '$warns',
        Icons.error_outline,
        warns > 0 ? AppColors.yellow : AppColors.green,
      ),
    ];
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    int? delta,
    double? deltaDouble,
    String deltaSuffix = '',
  }) {
    Widget? deltaWidget;
    if (deltaDouble != null && deltaDouble.abs() >= 0.5) {
      final up = deltaDouble > 0;
      deltaWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 11,
            color: up ? AppColors.green : AppColors.red,
          ),
          Text(
            '${deltaDouble.abs().toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: up ? AppColors.green : AppColors.red,
            ),
          ),
        ],
      );
    } else if (delta != null && delta != 0) {
      final up = delta > 0;
      deltaWidget = Text(
        '${up ? '+' : ''}$delta$deltaSuffix',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: up ? AppColors.green : AppColors.textSecondary,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const Spacer(),
                ?deltaWidget,
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendCard(Color color) {
    final fmt = DateFormat('dd/MM');
    final byDay = <String, List<PackingEntryModel>>{};
    for (final e in _current) {
      byDay.putIfAbsent(fmt.format(e.createdAt), () => []).add(e);
    }
    final days = byDay.keys.toList()
      ..sort((a, b) {
        final pa = a.split('/'), pb = b.split('/');
        final ma = int.parse(pa[1]), mb = int.parse(pb[1]);
        if (ma != mb) return ma.compareTo(mb);
        return int.parse(pa[0]).compareTo(int.parse(pb[0]));
      });

    if (days.length < 2) {
      return SectionCardShell(
        icon: Icons.show_chart,
        title: 'Pass Rate Trend',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text(
              'Need at least 2 days of data to plot a trend.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    final volumes = <int>[];
    for (var i = 0; i < days.length; i++) {
      final list = byDay[days[i]]!;
      spots.add(FlSpot(i.toDouble(), passRate(list)));
      volumes.add(list.length);
    }
    final avg = spots.map((s) => s.y).reduce((a, b) => a + b) / spots.length;
    final skip = days.length > 8 ? (days.length / 6).ceil() : 1;

    return SectionCardShell(
      icon: Icons.show_chart,
      title: 'Pass Rate Trend',
      trailing: Text(
        'avg ${avg.toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: rateColor(avg),
        ),
      ),
      child: SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 100,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
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
                    if (i < 0 || i >= days.length || i % skip != 0) {
                      return const Text('');
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        days[i],
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: 25,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}%',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.25,
                color: color,
                barWidth: 3,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                    radius: 3.5,
                    color: rateColor(spot.y),
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.12),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF2D3142),
                getTooltipItems: (touched) => touched.map((s) {
                  final i = s.x.toInt();
                  return LineTooltipItem(
                    '${days[i]}\n${s.y.toStringAsFixed(0)}% pass\n${volumes[i]} entries',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _qualityBreakdownCard() {
    final n = _current.length;
    final cats = <AnalyticsCat>[
      AnalyticsCat(
        'Weight',
        Icons.scale,
        _current.where((e) => e.weightStatus == 'green').length,
        _current.where((e) => e.weightStatus == 'yellow').length,
        _current.where((e) => e.weightStatus == 'red').length,
      ),
      if (_tracksMoisture)
        AnalyticsCat(
          'Moisture',
          Icons.water_drop_outlined,
          _current
              .where(
                (e) => e.moistureStatus == 'green' || e.moistureStatus == 'na',
              )
              .length,
          _current.where((e) => e.moistureStatus == 'yellow').length,
          _current.where((e) => e.moistureStatus == 'red').length,
        ),
      AnalyticsCat(
        'Printing',
        Icons.print_outlined,
        _current.where((e) => e.printingStatus == 'okay').length,
        _current
            .where(
              (e) =>
                  e.printingStatus == 'not_okay' && e.printingColor == 'yellow',
            )
            .length,
        _current
            .where(
              (e) =>
                  e.printingStatus == 'not_okay' && e.printingColor != 'yellow',
            )
            .length,
      ),
      AnalyticsCat(
        'Leakage',
        Icons.opacity,
        _current.where((e) => e.leakageStatus == 'green').length,
        _current.where((e) => e.leakageStatus == 'yellow').length,
        _current.where((e) => e.leakageStatus == 'red').length,
      ),
    ];

    return SectionCardShell(
      icon: Icons.donut_small,
      title: 'Quality Breakdown',
      child: Column(
        children: [
          for (final c in cats) _qualityBar(c, n),
          const SizedBox(height: 4),
          Row(
            children: [
              _legendDot(AppColors.green, 'Pass'),
              const SizedBox(width: 12),
              _legendDot(AppColors.yellow, 'Warn'),
              const SizedBox(width: 12),
              _legendDot(AppColors.red, 'Fail'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualityBar(AnalyticsCat cat, int total) {
    final shown = cat.pass + cat.warn + cat.fail;
    final okPct = shown > 0 ? cat.pass / shown * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                cat.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${okPct.toStringAsFixed(0)}% OK',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: rateColor(okPct),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 11,
              child: shown > 0
                  ? Row(
                      children: [
                        if (cat.pass > 0)
                          Expanded(
                            flex: cat.pass,
                            child: Container(color: AppColors.green),
                          ),
                        if (cat.warn > 0)
                          Expanded(
                            flex: cat.warn,
                            child: Container(color: AppColors.yellow),
                          ),
                        if (cat.fail > 0)
                          Expanded(
                            flex: cat.fail,
                            child: Container(color: AppColors.red),
                          ),
                      ],
                    )
                  : Container(color: AppColors.divider),
            ),
          ),
          if (cat.warn > 0 || cat.fail > 0) ...[
            const SizedBox(height: 3),
            Text(
              [
                if (cat.warn > 0) '${cat.warn} warn',
                if (cat.fail > 0) '${cat.fail} fail',
              ].join('  ·  '),
              style: const TextStyle(fontSize: 10, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }

  List<MachineAgg> _machineAggs() {
    final map = <int, MachineAgg>{};
    for (final e in _current) {
      map
          .putIfAbsent(e.machineNumber, () => MachineAgg(e.machineNumber))
          .add(e);
    }
    return map.values.toList()
      ..sort((a, b) => a.passRatePct.compareTo(b.passRatePct));
  }

  Widget _machineCard(Color color) {
    final machines = _machineAggs();
    if (machines.isEmpty) return const SizedBox.shrink();
    return SectionCardShell(
      icon: Icons.precision_manufacturing_outlined,
      title: 'Machine Performance',
      trailing: Text(
        '${machines.length} machine${machines.length == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      child: Column(
        children: machines
            .map(
              (m) => InkWell(
                onTap: () => _showMachineDetail(m),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: m.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'M${m.number}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: m.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: m.passRatePct / 100,
                                minHeight: 7,
                                backgroundColor: AppColors.red.withValues(
                                  alpha: 0.18,
                                ),
                                valueColor: AlwaysStoppedAnimation(m.color),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${m.fails} defect${m.fails == 1 ? '' : 's'} · ${m.total} entries',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${m.passRatePct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: m.color,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showMachineDetail(MachineAgg m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: m.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text('Machine ${m.number}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow('Entries', '${m.total}'),
            _detailRow(
              'Pass Rate',
              '${m.passRatePct.toStringAsFixed(1)}%',
              color: m.color,
            ),
            _detailRow('Warnings', '${m.warns}'),
            _detailRow('Defects', '${m.fails}'),
            const Divider(height: 20),
            if (m.weight > 0) _detailRow('Weight fails', '${m.weight}'),
            if (m.moisture > 0) _detailRow('Moisture fails', '${m.moisture}'),
            if (m.print > 0) _detailRow('Printing fails', '${m.print}'),
            if (m.leak > 0) _detailRow('Leakage fails', '${m.leak}'),
            if (m.weight + m.moisture + m.print + m.leak == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No defects recorded',
                  style: TextStyle(color: AppColors.green, fontSize: 13),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _drill('Machine ${m.number}', (e) => e.machineNumber == m.number);
            },
            child: const Text('View entries'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _drill(String title, bool Function(PackingEntryModel) match) {
    final matches = _current.where(match).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrillDownScreen(
          title: title,
          section: widget.section,
          entries: matches,
        ),
      ),
    );
  }

  Widget _productCard(Color color) {
    final map = <String, ProductAgg>{};
    for (final e in _current) {
      final key = '${e.productId}@@${e.price}';
      final display = e.price > 0
          ? '${e.productName} (Rs ${e.price.toStringAsFixed(0)})'
          : e.productName;
      final a = map.putIfAbsent(key, () => ProductAgg(display));
      a.total++;
      if (isFail(e)) a.fails++;
    }
    final list = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final top = list.take(6).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final maxTotal = top.first.total;

    return SectionCardShell(
      icon: Icons.category_outlined,
      title: 'Product Performance',
      trailing: Text(
        '${list.length} product${list.length == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      child: Column(
        children: top.map((p) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${p.total}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (p.fails > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${p.fails} fail',
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.total / maxTotal,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(
                      rateColor(p.passRatePct).withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _shiftCard() {
    final morning = _current.where((e) => e.shift == 'morning').toList();
    final night = _current.where((e) => e.shift == 'night').toList();
    if (morning.isEmpty && night.isEmpty) return const SizedBox.shrink();
    return SectionCardShell(
      icon: Icons.compare_arrows_rounded,
      title: 'Shift Comparison',
      child: Row(
        children: [
          Expanded(
            child: _shiftTile('Morning', '☀️', morning, Colors.orange.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(child: _shiftTile('Night', '🌙', night, Colors.indigo)),
        ],
      ),
    );
  }

  Widget _shiftTile(
    String label,
    String emoji,
    List<PackingEntryModel> list,
    Color color,
  ) {
    if (list.isEmpty) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text(
            '$emoji No $label data',
            style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 12),
          ),
        ),
      );
    }
    final rate = passRate(list);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $label',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${list.length}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const Text(
                      'entries',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${rate.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: rateColor(rate),
                      ),
                    ),
                    const Text(
                      'pass rate',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moistureCard(Color color) {
    final withData = _current
        .where((e) => e.moistureActual != null && e.moistureIdeal != null)
        .toList();
    if (withData.isEmpty) {
      return SectionCardShell(
        icon: Icons.water_drop_outlined,
        title: 'Moisture Analysis',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              'No moisture readings recorded this period.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final actuals = withData.map((e) => e.moistureActual!).toList();
    final avgActual = actuals.reduce((a, b) => a + b) / actuals.length;
    final avgIdeal =
        withData.map((e) => e.moistureIdeal!).reduce((a, b) => a + b) /
        withData.length;
    final deviation = avgActual - avgIdeal;
    final minA = actuals.reduce((a, b) => a < b ? a : b);
    final maxA = actuals.reduce((a, b) => a > b ? a : b);
    final devColor = deviation.abs() <= 0.5
        ? AppColors.green
        : deviation.abs() <= 1.5
        ? AppColors.yellow
        : AppColors.red;

    return SectionCardShell(
      icon: Icons.water_drop_outlined,
      title: 'Moisture Analysis',
      trailing: Text(
        '${withData.length} readings',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _moistureStat(
                  'Avg Actual',
                  '${avgActual.toStringAsFixed(1)}%',
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _moistureStat(
                  'Target',
                  '${avgIdeal.toStringAsFixed(1)}%',
                  AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _moistureStat(
                  'Deviation',
                  '${deviation >= 0 ? '+' : ''}${deviation.toStringAsFixed(1)}%',
                  devColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _moistureRangeBar(minA, maxA, avgActual, avgIdeal, devColor),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'min ${minA.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
              Text(
                'target ${avgIdeal.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'max ${maxA.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moistureStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _moistureRangeBar(
    double min,
    double max,
    double avg,
    double target,
    Color devColor,
  ) {
    final lo = [min, target].reduce((a, b) => a < b ? a : b) - 0.5;
    final hi = [max, target].reduce((a, b) => a > b ? a : b) + 0.5;
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    double pos(double v) => ((v - lo) / span).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 22,
          child: Stack(
            children: [
              Positioned(
                left: pos(min) * w,
                right: (1 - pos(max)) * w,
                top: 9,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: devColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: pos(target) * w - 1,
                top: 3,
                child: Container(width: 2, height: 16, color: Colors.black54),
              ),
              Positioned(
                left: pos(avg) * w - 5,
                top: 5,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: devColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _supervisorCard(Color color) {
    final map = <String, SupAgg>{};
    for (final e in _current) {
      final qc = e.operatorName.trim().isEmpty
          ? 'Unknown'
          : e.operatorName.trim();
      map.putIfAbsent(qc, () => SupAgg(qc)).add(e);
    }
    final sups = map.values.toList()
      ..sort((a, b) => a.passRatePct.compareTo(b.passRatePct));
    if (sups.isEmpty) return const SizedBox.shrink();
    return SectionCardShell(
      icon: Icons.badge_outlined,
      title: 'By Supervisor (QC)',
      trailing: Text(
        '${sups.length} QC',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      child: Column(
        children: sups
            .map(
              (s) => InkWell(
                onTap: () => _showSupDetail(s),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: s.passRatePct / 100,
                                minHeight: 7,
                                backgroundColor: AppColors.red.withValues(
                                  alpha: 0.18,
                                ),
                                valueColor: AlwaysStoppedAnimation(s.color),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${s.fails} defect${s.fails == 1 ? '' : 's'} · ${s.total} entries',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${s.passRatePct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: s.color,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showSupDetail(SupAgg s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow('Entries', '${s.total}'),
            _detailRow(
              'Pass Rate',
              '${s.passRatePct.toStringAsFixed(1)}%',
              color: s.color,
            ),
            _detailRow('Warnings', '${s.warns}'),
            _detailRow('Defects', '${s.fails}'),
            const Divider(height: 20),
            if (s.weight > 0) _detailRow('Weight fails', '${s.weight}'),
            if (s.moisture > 0) _detailRow('Moisture fails', '${s.moisture}'),
            if (s.print > 0) _detailRow('Printing fails', '${s.print}'),
            if (s.leak > 0) _detailRow('Leakage fails', '${s.leak}'),
            if (s.weight + s.moisture + s.print + s.leak == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No defects recorded',
                  style: TextStyle(color: AppColors.green, fontSize: 13),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _drill(
                s.name,
                (e) =>
                    (e.operatorName.trim().isEmpty
                        ? 'Unknown'
                        : e.operatorName.trim()) ==
                    s.name,
              );
            },
            child: const Text('View entries'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _legendDot(Color c, String label) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    ],
  );
}
