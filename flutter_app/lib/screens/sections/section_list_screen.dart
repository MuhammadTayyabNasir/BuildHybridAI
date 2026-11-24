import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../core/utils/date_utils.dart';
import '../../models/packing_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entries_provider.dart';
import '../../providers/machines_provider.dart';
import '../../providers/products_provider.dart';
import '../../widgets/offline_banner.dart';

// Modular UI imports
import 'entry_form_screen.dart';
import 'entry_detail_screen.dart';
import 'excel_entry/excel_entry_screen.dart'; // Updated path if you moved it
import 'analytics/section_analytics_screen.dart';
import 'widgets/entry_row.dart';
import '../../ui/pma_ui.dart';

class SectionListScreen extends StatefulWidget {
  final SectionInfo section;
  final bool embedded;

  const SectionListScreen({
    super.key,
    required this.section,
    this.embedded = false,
  });

  @override
  State<SectionListScreen> createState() => _SectionListScreenState();
}

class _SectionListScreenState extends State<SectionListScreen> {
  DateTime? _filterFrom;
  DateTime? _filterTo;
  String? _filterShift;

  int _page = 0;
  static const int _pageSize = 20;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  bool get _isSingleDay =>
      _filterFrom != null &&
          _filterTo != null &&
          _filterFrom!.year == _filterTo!.year &&
          _filterFrom!.month == _filterTo!.month &&
          _filterFrom!.day == _filterTo!.day;

  bool get _isToday {
    if (!_isSingleDay) return false;
    final now = DateTime.now();
    return _filterFrom!.year == now.year &&
        _filterFrom!.month == now.month &&
        _filterFrom!.day == now.day;
  }

  String get _dateLabel {
    if (_filterFrom == null) return 'All time';
    if (_isSingleDay) {
      return _isToday
          ? 'Today'
          : DateFormat('EEE, dd MMM').format(_filterFrom!);
    }
    return '${DateFormat('dd MMM').format(_filterFrom!)} – '
        '${DateFormat('dd MMM').format(_filterTo!)}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _filterFrom = _startOfDay(now);
    _filterTo = _endOfDay(now);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool forceRemote = false}) async {
    final ep = context.read<EntriesProvider>();
    final pp = context.read<ProductsProvider>();
    final mp = context.read<MachinesProvider>();
    if (forceRemote) ep.forceRefresh(widget.section.id);
    await Future.wait([
      ep.loadSection(widget.section.id),
      pp.loadSection(widget.section.id),
      mp.loadSection(widget.section.id),
    ]);
  }

  List<PackingEntryModel> _applyFilters(List<PackingEntryModel> all) {
    return all.where((e) {
      if (_filterFrom != null && e.createdAt.isBefore(_filterFrom!)) return false;
      if (_filterTo != null && e.createdAt.isAfter(_filterTo!)) return false;
      if (_filterShift != null && e.shift != _filterShift) return false;
      return true;
    }).toList();
  }

  void _setDay(DateTime day) {
    setState(() {
      _filterFrom = _startOfDay(day);
      _filterTo = _endOfDay(day);
      _page = 0;
    });
  }

  void _prevDay() {
    final base = _filterFrom ?? DateTime.now();
    _setDay(DateTime(base.year, base.month, base.day - 1));
  }

  void _nextDay() {
    final base = _filterFrom ?? DateTime.now().subtract(const Duration(days: 1));
    final next = DateTime(base.year, base.month, base.day + 1);
    if (next.isAfter(DateTime.now())) return;
    _setDay(next);
  }

  void _clearToToday() {
    setState(() => _filterShift = null);
    _setDay(DateTime.now());
  }

  void _setAllTime() {
    setState(() {
      _filterFrom = null;
      _filterTo = null;
      _page = 0;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _filterFrom != null && _filterTo != null
          ? DateTimeRange(start: _filterFrom!, end: _filterTo!)
          : DateTimeRange(start: now, end: now),
    );
    if (range != null && context.mounted) {
      setState(() {
        _filterFrom = _startOfDay(range.start);
        _filterTo = AppDateUtils.endOfDay(range.end);
        _page = 0;
      });
    }
  }

  void _showDateMenu() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Today'),
              onTap: () {
                Navigator.pop(ctx);
                _setDay(now);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Yesterday'),
              onTap: () {
                Navigator.pop(ctx);
                _setDay(yesterday);
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Custom date range'),
              onTap: () {
                Navigator.pop(ctx);
                _pickDateRange();
              },
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('All time'),
              onTap: () {
                Navigator.pop(ctx);
                _setAllTime();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ep = context.watch<EntriesProvider>();
    final color = AppColors.sectionColor(widget.section.id);
    final allEntries = _applyFilters(ep.forSection(widget.section.id));
    final auth = context.read<AuthProvider>();

    final totalPages = (allEntries.length / _pageSize).ceil().clamp(1, 99999).toInt();
    final safePage = _page.clamp(0, totalPages - 1);
    final pageEntries = allEntries.skip(safePage * _pageSize).take(_pageSize).toList();

    final body = Column(
      children: [
        if (!widget.embedded) const OfflineBanner(),
        _buildFilterBar(color),
        Expanded(
          child: ep.loading
              ? const Center(child: CircularProgressIndicator())
              : allEntries.isEmpty
              ? _buildEmpty()
              : Column(
            children: [
              _tableHeader(color),
              const Divider(height: 1),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(forceRemote: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: pageEntries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final entry = pageEntries[i];
                      final isViewer = auth.user?.isViewer == true;

                      final rowWidget = EntryRow(
                        entry: entry,
                        sectionColor: color,
                        onTap: () => _openDetail(entry),
                        onEdit: () {
                          if (!isViewer) _openEdit(entry);
                        },
                        onDelete: () {
                          if (!isViewer) _confirmDelete(entry);
                        },
                      );

                      if (isViewer) return rowWidget;

                      return Dismissible(
                        key: ValueKey(entry.id),
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 24),
                          color: Colors.teal,
                          child: const Icon(Icons.edit, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: AppColors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (dir) async {
                          if (dir == DismissDirection.startToEnd) {
                            _openEdit(entry);
                            return false;
                          }
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Entry?'),
                              content: const Text('This action cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (dir) {
                          if (dir == DismissDirection.endToStart) {
                            context.read<EntriesProvider>().deleteEntry(entry);
                          }
                        },
                        child: rowWidget,
                      );
                    },
                  ),
                ),
              ),
              if (allEntries.length > _pageSize)
                _buildPagination(allEntries.length, safePage, totalPages, color),
            ],
          ),
        ),
      ],
    );

    final fab = Padding(
      padding: const EdgeInsets.only(bottom: 30.0, right: 10.0),
      child: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: color,
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
        onPressed: () => _openEntryScreen(),
      ),
    );
    final fabNopermission = Padding(
      padding: const EdgeInsets.only(bottom: 30.0, right: 10.0),
      child: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: color,
        label: const Text('not Allowed'),
        onPressed: () {},
      ),
    );

    if (widget.embedded) {
      if (auth.user?.isViewer != true) {
        return Scaffold(
          body: body,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: fab,
        );
      } else {
        return Scaffold(
          body: body,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: fabNopermission,
        );
      }
    }

    if (auth.user?.isViewer != true) {
      return Scaffold(
        appBar: PmaAppBar(
          title: Text(widget.section.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Analytics',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SectionAnalyticsScreen(section: widget.section),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(forceRemote: true),
            ),
          ],
        ),
        body: body,
        floatingActionButton: fab,
      );
    } else {
      return Scaffold(
        appBar: PmaAppBar(
          title: Text(widget.section.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Analytics',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SectionAnalyticsScreen(section: widget.section),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(forceRemote: true),
            ),
          ],
        ),
        body: body,
        floatingActionButton: const FloatingActionButton(onPressed: null, child: Text("Not Allowed")),
      );
    }
  }

  Widget _buildFilterBar(Color color) {
    final canGoNext = _filterFrom != null && !_isToday && _isSingleDay;

    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: _prevDay,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _showDateMenu,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _dateLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 14, color: color),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: canGoNext ? _nextDay : null,
          ),
          const SizedBox(width: 4),
          _shiftChip('All', null, color),
          const SizedBox(width: 3),
          _shiftChip('☀', 'morning', color),
          const SizedBox(width: 3),
          _shiftChip('🌙', 'night', color),
          if (!_isToday || _filterShift != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _clearToToday,
              child: const Icon(Icons.close, size: 16, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shiftChip(String label, String? value, Color color) {
    final sel = _filterShift == value;
    return GestureDetector(
      onTap: () => setState(() {
        _filterShift = value;
        _page = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: sel ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? color : color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
            color: sel ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPagination(int total, int safePage, int totalPages, Color color) {
    final start = safePage * _pageSize + 1;
    final end = ((safePage + 1) * _pageSize).clamp(1, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.15))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: safePage > 0 ? () => setState(() => _page = safePage - 1) : null,
          ),
          Text(
            '$start–$end of $total',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: safePage < totalPages - 1 ? () => setState(() => _page = safePage + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(Color color) {
    const style = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: const [
          SizedBox(width: 64, child: Text('Date', style: style)),
          SizedBox(width: 38, child: Text('M#', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          Expanded(child: Text('Product', style: style)),
          SizedBox(width: 26),
          SizedBox(width: 48, child: Text('W·M·P·L', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 60),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final auth = context.read<AuthProvider>();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text('No entries found', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            _filterFrom != null ? 'Try a different date or tap "All time"' : 'Add your first entry',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (auth.user?.isViewer != true)
                TextButton.icon(
                  onPressed: () => _openEntryScreen(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add entry'),
                ),
              if (_filterFrom != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _setAllTime,
                  child: const Text('All time'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEntryScreen() async {
    final isWide = MediaQuery.of(context).size.width > 700;
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('input_mode') ?? 'auto';
    final useExcel = mode == 'excel' || (mode == 'auto' && isWide);
    if (!mounted) return;
    if (useExcel) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ExcelEntryScreen(section: widget.section)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EntryFormScreen(section: widget.section)),
      );
    }
    _load();
  }

  void _openDetail(PackingEntryModel entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryDetailScreen(entry: entry, section: widget.section),
      ),
    );
  }

  Future<void> _openEdit(PackingEntryModel entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryFormScreen(section: widget.section, existing: entry),
      ),
    );
    _load();
  }

  Future<void> _confirmDelete(PackingEntryModel entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<EntriesProvider>().deleteEntry(entry);
    }
  }
}