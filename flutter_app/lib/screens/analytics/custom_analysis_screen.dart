import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../models/custom_column_model.dart';
import '../../models/packing_entry_model.dart';
import '../../providers/entries_provider.dart';
import '../sections/entry_detail_screen.dart';

// ── Helpers (shared, top-level) ───────────────────────────────────────────────
bool _isFail(PackingEntryModel e) =>
    e.weightStatus == 'red' ||
    e.moistureStatus == 'red' ||
    e.printingStatus == 'not_okay' ||
    e.leakageStatus == 'red';

bool _isWarn(PackingEntryModel e) =>
    !_isFail(e) &&
    (e.weightStatus == 'yellow' ||
        e.moistureStatus == 'yellow' ||
        e.leakageStatus == 'yellow');

Color _rateColor(double pct) {
  if (pct >= 90) return AppColors.green;
  if (pct >= 70) return AppColors.yellow;
  return AppColors.red;
}

/// A group-by dimension — built-in OR derived from a custom column at runtime
/// (that's what makes new error types / fields flow in automatically).
class _Dimension {
  final String key;
  final String label;
  final String Function(PackingEntryModel) extract;
  const _Dimension(this.key, this.label, this.extract);
}

class _GroupAgg {
  final String label;
  final List<PackingEntryModel> entries = [];
  _GroupAgg(this.label);

  int get total => entries.length;
  int get fails => entries.where(_isFail).length;
  int get warns => entries.where(_isWarn).length;
  double get passRate => total == 0 ? 0 : (total - fails) / total * 100;
  Color get color => _rateColor(passRate);
}

/// Custom Analysis — pick a Group-by dimension × filters → live breakdown.
/// All local-first (reads SQLite); group-by dimensions include any custom
/// columns so new fields appear here without a code change.
class CustomAnalysisScreen extends StatefulWidget {
  const CustomAnalysisScreen({super.key});

  @override
  State<CustomAnalysisScreen> createState() => _CustomAnalysisScreenState();
}

class _CustomAnalysisScreenState extends State<CustomAnalysisScreen> {
  List<PackingEntryModel> _all = [];
  List<CustomColumn> _customCols = [];
  bool _loading = true;

  // Filters
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String? _sectionFilter; // null = all
  String? _shiftFilter; // null = all
  String _groupKey = 'section';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cols = await CustomColumnsService.load();
    if (!mounted) return;
    final entries = context.read<EntriesProvider>().localEntriesInRange(
          from: DateTime(_from.year, _from.month, _from.day),
          to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
        );
    setState(() {
      _customCols = cols;
      _all = entries;
      _loading = false;
    });
  }

  List<_Dimension> get _dimensions => [
        _Dimension('section', 'Section',
            (e) => Sections.byId(e.section).name),
        _Dimension('machine', 'Machine',
            (e) => '${Sections.byId(e.section).name} · M${e.machineNumber}'),
        _Dimension(
            'supervisor',
            'Supervisor (QC)',
            (e) => e.operatorName.trim().isEmpty
                ? 'Unknown'
                : e.operatorName.trim()),
        _Dimension(
            'product',
            'Product',
            (e) => e.price > 0
                ? '${e.productName} (Rs ${e.price.toStringAsFixed(0)})'
                : e.productName),
        _Dimension('shift', 'Shift',
            (e) => e.shift == 'morning' ? 'Morning' : 'Night'),
        _Dimension(
            'day', 'Day', (e) => DateFormat('dd MMM yyyy').format(e.createdAt)),
        // Dynamic — one dimension per custom column.
        for (final c in _customCols)
          _Dimension('cf_${c.id}', c.heading, (e) {
            final v = e.customFields?[c.id]?.trim();
            return (v == null || v.isEmpty) ? '—' : v;
          }),
      ];

  _Dimension get _activeDim =>
      _dimensions.firstWhere((d) => d.key == _groupKey,
          orElse: () => _dimensions.first);

  List<PackingEntryModel> get _filtered => _all.where((e) {
        if (_sectionFilter != null && e.section != _sectionFilter) return false;
        if (_shiftFilter != null && e.shift != _shiftFilter) return false;
        return true;
      }).toList();

  List<_GroupAgg> get _groups {
    final map = <String, _GroupAgg>{};
    final dim = _activeDim;
    for (final e in _filtered) {
      map.putIfAbsent(dim.extract(e), () => _GroupAgg(dim.extract(e))).entries.add(e);
    }
    return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      // Local window is 90 days (bounded sync); analyse within it.
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null && mounted) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _controls(),
                const Divider(height: 1),
                Expanded(child: _results()),
              ],
            ),
    );
  }

  // ── Controls ───────────────────────────────────────────────────────────────
  Widget _controls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group by
          Row(
            children: [
              const Text('Group by',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _groupKey,
                  underline: const SizedBox.shrink(),
                  items: _dimensions
                      .map((d) => DropdownMenuItem(
                            value: d.key,
                            child: Text(d.label,
                                style: const TextStyle(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _groupKey = v ?? 'section'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(
                  '${DateFormat('dd MMM').format(_from)} – ${DateFormat('dd MMM').format(_to)}',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _pickRange,
              ),
              const SizedBox(width: 8),
              _filterMenu<String?>(
                icon: Icons.grid_view_outlined,
                label: _sectionFilter == null
                    ? 'All sections'
                    : Sections.byId(_sectionFilter!).name,
                value: _sectionFilter,
                items: [
                  const PopupMenuItem(value: null, child: Text('All sections')),
                  ...Sections.all.map((s) =>
                      PopupMenuItem(value: s.id, child: Text(s.name))),
                ],
                onSelected: (v) => setState(() => _sectionFilter = v),
              ),
              const SizedBox(width: 8),
              _filterMenu<String?>(
                icon: Icons.schedule,
                label: _shiftFilter == null
                    ? 'All shifts'
                    : (_shiftFilter == 'morning' ? 'Morning' : 'Night'),
                value: _shiftFilter,
                items: const [
                  PopupMenuItem(value: null, child: Text('All shifts')),
                  PopupMenuItem(value: 'morning', child: Text('Morning')),
                  PopupMenuItem(value: 'night', child: Text('Night')),
                ],
                onSelected: (v) => setState(() => _shiftFilter = v),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _filterMenu<T>({
    required IconData icon,
    required String label,
    required T value,
    required List<PopupMenuEntry<T>> items,
    required void Function(T) onSelected,
  }) {
    return PopupMenuButton<T>(
      itemBuilder: (_) => items,
      onSelected: onSelected,
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  // ── Results ────────────────────────────────────────────────────────────────
  Widget _results() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(
        child: Text('No entries for these filters',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    final groups = _groups;
    final total = filtered.length;
    final fails = filtered.where(_isFail).length;
    final passRate = (total - fails) / total * 100;
    final maxTotal = groups.isEmpty ? 1 : groups.first.total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        // Summary
        Row(children: [
          _summary('Entries', '$total', AppColors.primary),
          _summary('Pass Rate', '${passRate.toStringAsFixed(0)}%',
              _rateColor(passRate)),
          _summary('Defects', '$fails',
              fails > 0 ? AppColors.red : AppColors.green),
          _summary('${_activeDim.label}s', '${groups.length}',
              AppColors.textSecondary),
        ]),
        const SizedBox(height: 14),
        Text('${_activeDim.label} breakdown',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Tap a row to see the underlying entries',
            style: TextStyle(fontSize: 11, color: AppColors.textHint)),
        const SizedBox(height: 10),
        ...groups.map((g) => _groupRow(g, maxTotal)),
      ],
    );
  }

  Widget _summary(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _groupRow(_GroupAgg g, int maxTotal) {
    return InkWell(
      onTap: () => _drill(g),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(g.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text('${g.passRate.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: g.color)),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
            ]),
            const SizedBox(height: 4),
            // Volume bar (width = share of entries) tinted by pass rate.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxTotal == 0 ? 0 : g.total / maxTotal,
                minHeight: 8,
                backgroundColor: AppColors.divider.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation(g.color.withValues(alpha: 0.85)),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${g.total} entr${g.total == 1 ? 'y' : 'ies'} · '
              '${g.fails} defect${g.fails == 1 ? '' : 's'}'
              '${g.warns > 0 ? ' · ${g.warns} warning${g.warns == 1 ? '' : 's'}' : ''}',
              style: const TextStyle(fontSize: 10, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  void _drill(_GroupAgg g) {
    final entries = [...g.entries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CustomDrillScreen(title: g.label, entries: entries),
      ),
    );
  }
}

/// Drill-down list for the custom analysis (entries span sections, so each row
/// shows its section). Tap → full entry detail.
class _CustomDrillScreen extends StatelessWidget {
  final String title;
  final List<PackingEntryModel> entries;
  const _CustomDrillScreen({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text('${entries.length} entries',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ),
        ),
      ),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = entries[i];
          final section = Sections.byId(e.section);
          final issues = <String>[
            if (e.weightStatus == 'red') 'Weight',
            if (e.moistureStatus == 'red') 'Moisture',
            if (e.printingStatus == 'not_okay') 'Printing',
            if (e.leakageStatus == 'red') 'Leakage',
          ];
          return ListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      EntryDetailScreen(entry: e, section: section)),
            ),
            title: Text(
              '${DateFormat('dd MMM · HH:mm').format(e.createdAt)}   ·   '
              '${section.name} M${e.machineNumber}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.productName}${e.operatorName.trim().isEmpty ? '' : ' · ${e.operatorName.trim()}'}',
                  style: const TextStyle(fontSize: 11),
                ),
                if (issues.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: issues
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(s,
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: AppColors.red,
                                      fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
            trailing: issues.isEmpty
                ? const Icon(Icons.check_circle, color: AppColors.green, size: 18)
                : const Icon(Icons.chevron_right, size: 18),
            isThreeLine: issues.isNotEmpty,
          );
        },
      ),
    );
  }
}
