import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/packing_entry_model.dart';
import '../../../../providers/entries_provider.dart';

import '../sections/analytics/models/analytics_helpers.dart';
import 'custom_analysis_screen.dart';
import 'week_analysis_screen.dart';
import 'models/advanced_helpers.dart';
import 'widgets/advanced_components.dart';
import '../../ui/pma_ui.dart';

class AdvancedAnalyticsScreen extends StatefulWidget {
  final bool embedded;
  const AdvancedAnalyticsScreen({super.key, this.embedded = false});

  @override
  State<AdvancedAnalyticsScreen> createState() => _AdvancedAnalyticsScreenState();
}

class _AdvancedAnalyticsScreenState extends State<AdvancedAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<PackingEntryModel> _all = [];
  bool _loading = false;
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String _range = '7d';
  String? _shiftFilter;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: Sections.all.length + 1, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _applyRange(String r) {
    final now = DateTime.now();
    setState(() {
      _range = r;
      switch (r) {
        case 'Today':
          _from = DateTime(now.year, now.month, now.day);
          _to = now;
        case '7d':
          _from = now.subtract(const Duration(days: 7));
          _to = now;
        case '30d':
          _from = now.subtract(const Duration(days: 30));
          _to = now;
      }
    });
    _load();
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _range = 'Custom';
        _from = range.start;
        _to = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      });

      // FIX: Ensure context is still mounted before proceeding after await
      if (!context.mounted) return;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = context.read<EntriesProvider>().localEntriesInRange(from: _from, to: _to);
    setState(() {
      _all = entries;
      _loading = false;
    });
  }

  String? get _activeSectionId {
    if (_tabCtrl.index == 0) return null;
    return Sections.all[_tabCtrl.index - 1].id;
  }

  List<PackingEntryModel> get _filtered {
    var list = _activeSectionId == null
        ? _all
        : _all.where((e) => e.section == _activeSectionId).toList();
    if (_shiftFilter != null) {
      list = list.where((e) => e.shift == _shiftFilter).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      indicatorColor: Colors.white,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      tabs: [
        const Tab(text: 'All'),
        ...Sections.all.map((s) => Tab(text: s.name)),
      ],
    );

    final dateBtn = TextButton.icon(
      icon: const Icon(Icons.date_range, color: Colors.white, size: 16),
      label: Text(
        '${DateFormat('dd MMM').format(_from)} – ${DateFormat('dd MMM').format(_to)}',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      onPressed: _pickRange,
    );

    final filters = _buildFilters();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _filtered.isEmpty
        ? _buildEmpty()
        : _AnalyticsContent(
      entries: _filtered,
      allEntries: _all,
      sectionId: _activeSectionId,
    );

    if (widget.embedded) {
      return Column(children: [
        Material(
          color: AppColors.primary,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                const Expanded(
                  child: Text('Analytics', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                dateBtn,
              ]),
            ),
            tabBar,
          ]),
        ),
        filters,
        Expanded(child: body),
      ]);
    }

    return Scaffold(
      appBar: PmaAppBar(
        title: const Text('Analytics'),
        bottom: tabBar,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_week),
            tooltip: 'Week Analysis (Weak Link)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeekAnalysisScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Custom Analysis',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomAnalysisScreen()),
            ),
          ),
          dateBtn,
        ],
      ),
      body: Column(children: [filters, _weekAnalysisBanner(), Expanded(child: body)]),
    );
  }

  Widget _weekAnalysisBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WeekAnalysisScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Icon(Icons.insights, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Weekly Analysis by Section', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    SizedBox(height: 2),
                    Text('Compare each metric week-over-week — same as the QC report', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ...['Today', '7d', '30d', 'Custom'].map((r) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(r, style: const TextStyle(fontSize: 12)),
              selected: _range == r,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => r == 'Custom' ? _pickRange() : _applyRange(r),
            ),
          )),
          Container(width: 1, height: 24, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
          ...[
            (null, 'All Shifts'),
            ('morning', 'Morning'),
            ('night', 'Night'),
          ].map(((String?, String) pair) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(pair.$2, style: const TextStyle(fontSize: 12)),
              selected: _shiftFilter == pair.$1,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _shiftFilter = pair.$1),
            ),
          )),
          Container(width: 1, height: 24, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
          Text('${_filtered.length} entries', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.analytics_outlined, size: 64, color: AppColors.textHint),
        const SizedBox(height: 16),
        const Text('No entries for selected filters', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            setState(() => _shiftFilter = null);
            _applyRange('30d');
          },
          child: const Text('Try last 30 days'),
        ),
      ]),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  final List<PackingEntryModel> entries;
  final List<PackingEntryModel> allEntries;
  final String? sectionId;

  const _AnalyticsContent({
    required this.entries,
    required this.allEntries,
    required this.sectionId,
  });

  Map<String, MachineStats> get _machineStats {
    final stats = <String, MachineStats>{};
    for (final e in entries) {
      stats.putIfAbsent('${e.section}#${e.machineNumber}', () => MachineStats(e.machineNumber, e.section)).add(e);
    }
    return stats;
  }

  Widget _insightsBanner() {
    final insights = _computeInsights();
    if (insights.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          for (final i in insights)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: i.color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: i.color.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(i.icon, size: 18, color: i.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(i.text, style: TextStyle(fontSize: 12.5, height: 1.3, color: i.color, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  List<AnalyticsInsight> _computeInsights() {
    final out = <AnalyticsInsight>[];
    final total = entries.length;
    if (total == 0) return out;
    final defects = entries.where(isAdvancedDefect).length;
    final rate = (total - defects) / total * 100;

    if (sectionId == null) {
      final data = <String, SecData>{};
      for (final e in entries) {
        final d = data.putIfAbsent(e.section, () => SecData());
        d.total++;
        if (isAdvancedDefect(e)) d.defects++;
      }
      if (data.length > 1) {
        final worst = data.entries.reduce((a, b) => a.value.passRate < b.value.passRate ? a : b);
        if (worst.value.defects > 0 && worst.value.passRate < 0.9) {
          out.add(AnalyticsInsight(Icons.priority_high, AppColors.red, '${Sections.byId(worst.key).name} is the weakest section — ${(worst.value.passRate * 100).toStringAsFixed(0)}% pass rate.'));
        }
      }
    } else {
      final ms = _machineStats.values.toList();
      if (ms.length > 1) {
        final worst = ms.reduce((a, b) => a.defectRate > b.defectRate ? a : b);
        if (worst.defectEntries > 0 && worst.defectRate > 0.15) {
          out.add(AnalyticsInsight(Icons.priority_high, AppColors.red, 'Machine ${worst.machineNumber} needs attention — ${(100 - worst.defectRate * 100).toStringAsFixed(0)}% pass rate (${worst.defectEntries} defect${worst.defectEntries == 1 ? '' : 's'} in ${worst.total}).'));
        }
      }
    }

    var w = 0, m = 0, p = 0, l = 0;
    for (final e in entries) {
      if (e.weightStatus == 'red') w++;
      if (e.moistureStatus == 'red') m++;
      if (e.printingStatus == 'not_okay') p++;
      if (e.leakageStatus == 'red') l++;
    }
    final defs = [('Weight', w), ('Moisture', m), ('Printing', p), ('Leakage', l)].where((e) => e.$2 > 0).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    if (defs.isNotEmpty) {
      out.add(AnalyticsInsight(Icons.bug_report_outlined, AppColors.yellow, '${defs.first.$1} is the leading issue (${defs.first.$2} fail${defs.first.$2 == 1 ? '' : 's'}).'));
    }

    if (out.isEmpty && rate >= 98) {
      out.add(AnalyticsInsight(Icons.verified_outlined, AppColors.green, 'Excellent — ${rate.toStringAsFixed(0)}% pass rate, no major concerns.'));
    }
    return out.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _insightsBanner(),
          AdvancedKpiRow(entries: entries, showSection: sectionId == null),
          const SizedBox(height: 14),
          if (sectionId == null) ...[
            SectionComparison(entries: allEntries),
            const SizedBox(height: 14),
          ],
          QualityBreakdown(entries: entries),
          const SizedBox(height: 14),
          DailyStackedBar(entries: entries),
          const SizedBox(height: 14),
          MachineGrid(stats: _machineStats, showSection: sectionId == null),
          const SizedBox(height: 14),
          ShiftComparison(entries: entries),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}