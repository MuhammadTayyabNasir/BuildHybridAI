import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/temp_humidity_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/local_storage_service.dart';
import '../../../../widgets/offline_banner.dart';

import 'temp_humidity_excel_screen.dart';
import 'temp_humidity_form_screen.dart';
import 'widgets/th_report_row.dart';
import '../../../ui/pma_ui.dart';

class TempHumidityScreen extends StatefulWidget {
  final SectionInfo section;
  final bool embedded;

  const TempHumidityScreen({
    super.key,
    required this.section,
    this.embedded = false,
  });

  @override
  State<TempHumidityScreen> createState() => _TempHumidityScreenState();
}

class _TempHumidityScreenState extends State<TempHumidityScreen> {
  List<TempHumidityReport> _reports = [];
  bool _loading = true;
  late final auth = context.read<AuthProvider>();

  String? _thShift;
  DateTime? _thFrom;
  DateTime? _thTo;

  List<TempHumidityReport> get _filtered {
    return _reports.where((r) {
      if (_thShift != null && r.shift != _thShift) return false;
      if (_thFrom != null && r.date.isBefore(_thFrom!)) return false;
      if (_thTo != null && r.date.isAfter(_thTo!)) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _thFrom = _startOfDay(now);
    _thTo = _endOfDay(now);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!context.mounted) return;
    final local = context.read<LocalStorageService>();
    final cached = local.getTempHumidityReports(sectionId: widget.section.id)
      ..sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _reports = cached;
      _loading = false;
    });
  }

  Future<void> _openReport(TempHumidityReport? existing) async {
    final isWide = MediaQuery.of(context).size.width > 700;
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('input_mode') ?? 'auto';
    final useExcel = mode == 'excel' || (mode == 'auto' && isWide);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => useExcel
            ? TempHumidityExcelScreen(section: widget.section, existing: existing)
            : TempHumidityFormScreen(section: widget.section, existing: existing),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    final fab = FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: color,
      icon: const Icon(Icons.add),
      label: const Text('New Report'),
      onPressed: () => _openReport(null),
    );
    final fabNotAllowed = FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: color,
      label: const Text('Not Allowed'),
      onPressed: () {},
    );

    if (widget.embedded) {
      if (auth.user?.isViewer != true) {
        return Scaffold(body: _content(color), floatingActionButton: fab);
      } else {
        return Scaffold(body: _content(color), floatingActionButton: fabNotAllowed);
      }
    }

    if (auth.user?.isViewer != true) {
      return Scaffold(
        appBar: PmaAppBar(
          title: Text('Temp & Humidity — ${widget.section.name}'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
          ],
        ),
        body: Column(children: [const OfflineBanner(), Expanded(child: _content(color))]),
        floatingActionButton: fab,
      );
    } else {
      return Scaffold(
        appBar: PmaAppBar(
          title: Text('Temp & Humidity — ${widget.section.name}'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
          ],
        ),
        body: Column(children: [const OfflineBanner(), Expanded(child: _content(color))]),
        floatingActionButton: fabNotAllowed,
      );
    }
  }

  Widget _content(Color color) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_reports.isEmpty) return _emptyState(color);
    final filtered = _filtered;
    return Column(
      children: [
        _filterBar(color),
        Expanded(child: filtered.isEmpty ? _noMatch(color) : _buildList(color, filtered)),
      ],
    );
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  bool get _thIsSingleDay =>
      _thFrom != null && _thTo != null && _thFrom!.year == _thTo!.year && _thFrom!.month == _thTo!.month && _thFrom!.day == _thTo!.day;
  bool get _thIsToday {
    if (!_thIsSingleDay) return false;
    final now = DateTime.now();
    return _thFrom!.year == now.year && _thFrom!.month == now.month && _thFrom!.day == now.day;
  }

  String get _thDateLabel {
    if (_thFrom == null) return 'All time';
    if (_thIsSingleDay) return _thIsToday ? 'Today' : DateFormat('EEE, dd MMM').format(_thFrom!);
    return '${DateFormat('dd MMM').format(_thFrom!)} – ${DateFormat('dd MMM').format(_thTo!)}';
  }

  void _setThDay(DateTime day) => setState(() {
    _thFrom = _startOfDay(day);
    _thTo = _endOfDay(day);
  });

  void _thPrevDay() {
    final b = _thFrom ?? DateTime.now();
    _setThDay(DateTime(b.year, b.month, b.day - 1));
  }

  void _thNextDay() {
    final b = _thFrom ?? DateTime.now().subtract(const Duration(days: 1));
    final n = DateTime(b.year, b.month, b.day + 1);
    if (n.isAfter(DateTime.now())) return;
    _setThDay(n);
  }

  void _thAllTime() => setState(() {
    _thFrom = null;
    _thTo = null;
  });

  void _thDateMenu() {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(leading: const Icon(Icons.today), title: const Text('Today'), onTap: () { Navigator.pop(ctx); _setThDay(now); }),
            ListTile(leading: const Icon(Icons.history), title: const Text('Yesterday'), onTap: () { Navigator.pop(ctx); _setThDay(now.subtract(const Duration(days: 1))); }),
            ListTile(leading: const Icon(Icons.date_range), title: const Text('Custom date range'), onTap: () { Navigator.pop(ctx); _pickThRange(); }),
            ListTile(leading: const Icon(Icons.all_inclusive), title: const Text('All time'), onTap: () { Navigator.pop(ctx); _thAllTime(); }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(Color color) {
    final canNext = _thFrom != null && !_thIsToday && _thIsSingleDay;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left, size: 20), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, onPressed: _thPrevDay),
          Expanded(
            child: GestureDetector(
              onTap: _thDateMenu,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(_thDateLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
                    ),
                    Icon(Icons.arrow_drop_down, size: 14, color: color),
                  ],
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right, size: 20), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, onPressed: canNext ? _thNextDay : null),
          const SizedBox(width: 4),
          _thChip('All', null, color),
          const SizedBox(width: 3),
          _thChip('☀', 'morning', color),
          const SizedBox(width: 3),
          _thChip('🌙', 'night', color),
        ],
      ),
    );
  }

  Widget _thChip(String label, String? value, Color color) {
    final sel = _thShift == value;
    return GestureDetector(
      onTap: () => setState(() => _thShift = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? color : color.withValues(alpha: 0.35)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: sel ? Colors.white : AppColors.textSecondary, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }

  Future<void> _pickThRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _thFrom != null && _thTo != null ? DateTimeRange(start: _thFrom!, end: _thTo!) : null,
    );
    if (range != null && context.mounted) {
      setState(() {
        _thFrom = DateTime(range.start.year, range.start.month, range.start.day);
        _thTo = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      });
    }
  }

  Widget _noMatch(Color color) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 48, color: color.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          const Text('No reports match the filter', style: TextStyle(color: AppColors.textSecondary)),
          TextButton(onPressed: () => setState(() { _thFrom = null; _thTo = null; _thShift = null; }), child: const Text('Clear filters')),
        ],
      ),
    );
  }

  Widget _emptyState(Color color) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat, size: 72, color: color.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No reports yet', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Tap + to log today\'s temperature & humidity', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.add),
            label: const Text('New Report'),
            onPressed: () => _openReport(null),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Color color, List<TempHumidityReport> reports) {
    final isViewer = context.read<AuthProvider>().user?.isViewer == true;
    const hStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: color.withValues(alpha: 0.08),
          child: Row(
            children: const [
              SizedBox(width: 68, child: Text('Date', style: hStyle)),
              SizedBox(width: 34, child: Text('Shift', style: hStyle, textAlign: TextAlign.center)),
              SizedBox(width: 36, child: Text('Cnt', style: hStyle, textAlign: TextAlign.center)),
              Expanded(child: Text('Avg Temp', style: hStyle, textAlign: TextAlign.center)),
              Expanded(child: Text('Avg Hum', style: hStyle, textAlign: TextAlign.center)),
              SizedBox(width: 16),
              SizedBox(width: 32),
              SizedBox(width: 32),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final report = reports[i];
              final rowWidget = THReportRow(
                report: report,
                color: color,
                onTap: () => _showDetail(report, color),
                onEdit: () { if (!isViewer) _openReport(report); },
                onDelete: () { if (!isViewer) _deleteReport(report); },
              );

              if (isViewer) return rowWidget;

              return Dismissible(
                key: ValueKey(report.id),
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
                    _openReport(report);
                    return false;
                  }
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Report?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
                    context.read<LocalStorageService>().deleteTempHumidityReport(report.id);
                  }
                },
                child: rowWidget,
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetail(TempHumidityReport report, Color color) {
    final shiftLabel = report.shift == 'morning' ? '☀️ Morning' : '🌙 Night';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${DateFormat('dd MMM yyyy').format(report.date)} · $shiftLabel',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
              if (report.rows.isEmpty)
                const Expanded(child: Center(child: Text('No readings in this report')))
              else
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 14,
                        headingRowHeight: 34,
                        dataRowMinHeight: 30,
                        dataRowMaxHeight: 30,
                        columns: const [
                          DataColumn(label: Text('Time', style: TextStyle(fontSize: 11))),
                          DataColumn(label: Text('Temp °C', style: TextStyle(fontSize: 11))),
                          DataColumn(label: Text('Hum %', style: TextStyle(fontSize: 11))),
                          DataColumn(label: Text('Section', style: TextStyle(fontSize: 11))),
                          DataColumn(label: Text('QC', style: TextStyle(fontSize: 11))),
                          DataColumn(label: Text('Remarks', style: TextStyle(fontSize: 11))),
                        ],
                        rows: report.rows
                            .map((r) => DataRow(
                          cells: [
                            DataCell(Text(r.time, style: const TextStyle(fontSize: 11))),
                            DataCell(Text(r.temperature != null ? r.temperature!.toStringAsFixed(1) : '—', style: const TextStyle(fontSize: 11))),
                            DataCell(Text(r.humidity != null ? r.humidity!.toStringAsFixed(1) : '—', style: const TextStyle(fontSize: 11))),
                            DataCell(Text(r.section, style: const TextStyle(fontSize: 11))),
                            DataCell(Text(r.verifiedByQc, style: const TextStyle(fontSize: 11))),
                            DataCell(Text(r.remarks, style: const TextStyle(fontSize: 11))),
                          ],
                        ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (auth.user?.isViewer != true)
                      TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Edit'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openReport(report);
                        },
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteReport(TempHumidityReport report) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<LocalStorageService>().deleteTempHumidityReport(report.id);
      _load();
    }
  }
}

// Keeping original alias for backward compatibility[cite: 11]
typedef TempHumidityEntryScreen = TempHumidityExcelScreen;