import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../models/temp_humidity_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/local_storage_service.dart';
import '../../services/th_sync.dart';
import 'analytics/section_analytics_screen.dart';
import 'section_list_screen.dart';
import 'temp_humidity/temp_humidity_screen.dart';
import 'package:flutter/services.dart';
import '../../models/th_threshold_model.dart';
import '../../services/th_threshold_service.dart';
import 'temp_humidity/temp_humidity_excel_screen.dart';
import 'temp_humidity/temp_humidity_form_screen.dart';

class SectionHomeScreen extends StatefulWidget {
  final SectionInfo section;

  const SectionHomeScreen({super.key, required this.section});

  @override
  State<SectionHomeScreen> createState() => _SectionHomeScreenState();
}

class _SectionHomeScreenState extends State<SectionHomeScreen>
    with SingleTickerProviderStateMixin {
  SectionInfo get section => widget.section;

  // Drives the narrow (phone) tab layout so we can jump to the Packing Report
  // tab automatically once the T&H prompt is dealt with.
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // T&H-first flow: as soon as the section opens, prompt the operator to
    // record (or carry over) today's Temp & Humidity before filling entries.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybePromptTempHumidity(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Jump to the Packing Report tab (narrow layout only; harmless otherwise).
  void _goToEntries() {
    if (mounted && _tabController.index != 1) _tabController.animateTo(1);
  }

  // ── T&H-first prompt ────────────────────────────────────────────────────────

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  // A QC visits a section ~4×/day and logs a reading each time (values vary).
  // Each reading is a row in that day/shift's report. Re-prompt on each visit.
  // The gap (minutes) below which we DON'T re-ask is a user setting; 0 = Off
  // (ask every single time the section opens). Default: Off.
  static const _revisitGapPrefKey = 'th_reprompt_gap_minutes';

  Future<void> _maybePromptTempHumidity() async {
    if (!mounted) return;
    final local = context.read<LocalStorageService>();
    final shift = ShiftHelper.detectShift();
    final reports = local.getTempHumidityReports(sectionId: section.id)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Today's report for the CURRENT shift (a QC adds several readings to it
    // through the day). Fall back to the most recent report for "old details".
    TempHumidityReport? todayReport;
    for (final r in reports) {
      if (_isToday(r.date) && r.shift == shift) {
        todayReport = r;
        break;
      }
    }
    final source = todayReport ?? (reports.isNotEmpty ? reports.first : null);

    // Respect the user's re-prompt gap. 0 = Off → always ask on every entry.
    final prefs = await SharedPreferences.getInstance();
    final gap = prefs.getInt(_revisitGapPrefKey) ?? 0;
    final lastTime = source == null ? null : _lastReadingTime(source);
    if (gap > 0 &&
        lastTime != null &&
        DateTime.now().difference(lastTime).inMinutes < gap) {
      return;
    }

    // The last reading (if any) pre-fills the fields — unchanged + Save = "keep".
    final lastRow = (source != null && source.rows.isNotEmpty)
        ? source.rows.last
        : null;
    if (!mounted) return;
    final result = await showDialog<_THResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _THQuickDialog(
        section: section,
        lastRow: lastRow,
        lastTime: lastTime,
        todayCount: todayReport?.rows.length ?? 0,
      ),
    );
    if (!mounted) return;

    if (result != null && result.action == _THAction.save) {
      await _saveQuickReading(
        todayReport,
        shift,
        result.temp!,
        result.humidity!,
      );
      if (mounted) {
        _snack(
          'T&H saved at ${DateFormat('HH:mm').format(DateTime.now())} · '
          '${result.temp!.toStringAsFixed(1)} °C · '
          '${result.humidity!.toStringAsFixed(1)} %',
        );
      }
    } else if (result != null && result.action == _THAction.full) {
      // Power-user path: full report editor (remarks, multiple rows, etc.).
      await _openEditor(todayReport);
    }
    // Either way, take the operator straight to the Daily Entries tab.
    _goToEntries();
  }

  /// Append ONE time-stamped reading (temp + humidity) to today's shift report,
  /// creating the report if this is the first reading of the shift.
  Future<void> _saveQuickReading(
    TempHumidityReport? todayReport,
    String shift,
    double temp,
    double humidity,
  ) async {
    final qc = context.read<AuthProvider>().user?.username ?? '';
    final now = DateTime.now();
    final newRow = TempHumidityRow(
      time: DateFormat('HH:mm').format(now),
      temperature: temp,
      humidity: humidity,
      section: section.name,
      verifiedByQc: qc,
      remarks: '',
    );
    final report = todayReport != null
        ? todayReport.copyWith(
            rows: [...todayReport.rows, newRow],
            isSynced: false,
            updatedAt: now,
          )
        : TempHumidityReport(
            id: TempHumidityReport.generateId(),
            sectionId: section.id,
            date: TempHumidityReport.dayOf(now),
            shift: shift,
            rows: [newRow],
            preparedBy: qc,
            isSynced: false,
            createdAt: now,
            updatedAt: now,
          );
    await _saveReport(report);
  }

  /// Timestamp of the latest reading in [r] (parsed from the row's HH:mm on its
  /// date; falls back to updatedAt only for today's report).
  DateTime? _lastReadingTime(TempHumidityReport r) {
    DateTime? latest;
    for (final row in r.rows) {
      final t = _parseTimeOn(r.date, row.time);
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest ?? (_isToday(r.date) ? r.updatedAt : null);
  }

  DateTime? _parseTimeOn(DateTime day, String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final mi = int.tryParse(m.group(2)!);
    if (h == null || mi == null || h > 23 || mi > 59) return null;
    return DateTime(day.year, day.month, day.day, h, mi);
  }

  Future<void> _saveReport(TempHumidityReport report) =>
      saveTempHumidityLocalFirst(context, report);

  /// Open the T&H editor (Excel/Form per input-mode) for [existing] (or new).
  Future<void> _openEditor(TempHumidityReport? existing) async {
    final isWide = MediaQuery.of(context).size.width > 700;
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('input_mode') ?? 'auto';
    final useExcel = mode == 'excel' || (mode == 'auto' && isWide);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => useExcel
            ? TempHumidityExcelScreen(section: section, existing: existing)
            : TempHumidityFormScreen(section: section, existing: existing),
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
  );

  // ── Layout (unchanged: split on wide, tabs on narrow) ───────────────────────

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(section.id);
    final isWide = MediaQuery.of(context).size.width >= 700;

    if (isWide) {
      return Scaffold(
        appBar: _buildAppBar(context, color),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PanelLabel(
                    label: 'Temperature & Humidity',
                    icon: Icons.thermostat,
                    color: color,
                  ),
                  Expanded(
                    child: TempHumidityScreen(section: section, embedded: true),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PanelLabel(
                    label: 'Packing Report',
                    icon: Icons.assignment,
                    color: color,
                  ),
                  Expanded(
                    child: SectionListScreen(section: section, embedded: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text(section.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Analytics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SectionAnalyticsScreen(section: section),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.thermostat), text: 'Temp & Humidity'),
            Tab(icon: Icon(Icons.assignment), text: 'Packing Report'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TempHumidityScreen(section: section, embedded: true),
          SectionListScreen(section: section, embedded: true),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Color color) {
    return AppBar(
      backgroundColor: color,
      foregroundColor: Colors.white,
      title: Text(section.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.analytics_outlined),
          tooltip: 'Analytics',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SectionAnalyticsScreen(section: section),
            ),
          ),
        ),
      ],
    );
  }
}

// ── T&H quick-entry dialog ──────────────────────────────────────────────────
// One small dialog per visit: last reading pre-fills the two fields.
//   • Unchanged + Save  = "keep same"
//   • Edit + Save        = "change"
//   • Skip / Open full form for the rare full-report case.

enum _THAction { save, full, skip }

class _THResult {
  final _THAction action;
  final double? temp;
  final double? humidity;

  const _THResult(this.action, {this.temp, this.humidity});
}

class _THQuickDialog extends StatefulWidget {
  final SectionInfo section;
  final TempHumidityRow? lastRow; // last reading, to pre-fill + show
  final DateTime? lastTime;
  final int todayCount; // readings already logged today (this shift)
  const _THQuickDialog({
    required this.section,
    this.lastRow,
    this.lastTime,
    this.todayCount = 0,
  });

  @override
  State<_THQuickDialog> createState() => _THQuickDialogState();
}

class _THQuickDialogState extends State<_THQuickDialog> {
  late final TextEditingController _temp;
  late final TextEditingController _hum;
  late final ThThreshold _threshold;
  String? _error;
  late final auth = context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    final lr = widget.lastRow;
    _temp = TextEditingController(
      text: lr?.temperature != null ? lr!.temperature!.toStringAsFixed(1) : '',
    );
    _hum = TextEditingController(
      text: lr?.humidity != null ? lr!.humidity!.toStringAsFixed(1) : '',
    );
    // Read once — this dialog is on screen for a few seconds, so a live
    // Firestore stream isn't needed here (unlike the full entry screens).
    _threshold = context.read<ThThresholdService>().forSection(
      widget.section.id,
    );
  }

  @override
  void dispose() {
    _temp.dispose();
    _hum.dispose();
    super.dispose();
  }

  static final _tempFmt = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9.\-]'),
  );
  static final _humFmt = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

  String? get _tempStatus {
    final v = double.tryParse(_temp.text.trim());
    return v == null ? null : _threshold.classifyTemp(v);
  }

  String? get _humStatus {
    final v = double.tryParse(_hum.text.trim());
    return v == null ? null : _threshold.classifyHumidity(v);
  }

  void _save() {
    final t = double.tryParse(_temp.text.trim());
    final h = double.tryParse(_hum.text.trim());
    if (t == null || h == null) {
      setState(() => _error = 'Enter both temperature and humidity.');
      return;
    }
    // Humidity is a percentage — 0–100 is a physical limit, not a QC threshold.
    if (h < 0 || h > 100) {
      setState(() => _error = 'Humidity must be between 0–100%.');
      return;
    }
    // Temperature has NO upper cap tied to the yellow/red thresholds — a
    // reading can legitimately spike past whatever red starts at, and it
    // still needs to save so the QC has a record. This is just a generous
    // sanity check to catch an obvious typo (e.g. "600" instead of "60").
    if (t < -50 || t > 200) {
      setState(
        () => _error = 'That temperature looks like a typo — please check it.',
      );
      return;
    }
    Navigator.pop(context, _THResult(_THAction.save, temp: t, humidity: h));
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    final lr = widget.lastRow;
    final headline = widget.todayCount > 0
        ? 'Reading #${widget.todayCount + 1} today'
              '${widget.lastTime != null ? ' · last at ${DateFormat('HH:mm').format(widget.lastTime!)}' : ''}'
        : 'First reading — please record it';

    return AlertDialog(
      title: Text('Temp & Humidity · ${widget.section.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (lr != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last: ${lr.temperature?.toStringAsFixed(1) ?? '—'} °C  ·  '
                        '${lr.humidity?.toStringAsFixed(1) ?? '—'} %',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _numField(
                    _temp,
                    'Temperature',
                    '°C',
                    _tempStatus,
                    _tempFmt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numField(_hum, 'Humidity', '%', _humStatus, _humFmt),
                ),
              ],
            ),
            _statusLine(), // NEW — live yellow/red badges
            const SizedBox(height: 8),
            Text(
              lr != null
                  ? 'Same as last? Just tap Save. Changed? Edit the numbers.'
                  : 'Enter this visit\'s reading, then Save.',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              ),
            ],
            if (auth.user?.isViewer != true)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const _THResult(_THAction.full)),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Open full form'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const _THResult(_THAction.skip)),
          child: const Text('Skip'),
        ),
        if (auth.user?.isViewer != true)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: _save,
            child: const Text('Save'),
          ),
      ],
    );
  }

  // NEW — colored badge row shown as soon as a value crosses green.
  // Mirrors the weight-alert badge style you referenced, just for temp/humidity.
  Widget _statusLine() {
    final t = _tempStatus;
    final h = _humStatus;
    if (t == null && h == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          if (t != null) _metricBadge('Temperature', t),
          if (h != null) _metricBadge('Humidity', h),
        ],
      ),
    );
  }

  Widget _metricBadge(String label, String status) {
    final (badgeColor, text, icon) = switch (status) {
      'yellow' => (
        Colors.orange.shade700,
        'Warning',
        Icons.warning_amber_rounded,
      ),
      'red' => (Colors.red.shade700, 'Alert', Icons.error_outline),
      _ => (Colors.green.shade700, 'Normal', Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            '$label: $text',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Field border now highlights orange/red the moment the value crosses green,
  // same visual language as the weight-alert field in your entries form.
  Widget _numField(
    TextEditingController c,
    String label,
    String unit,
    String? status,
    TextInputFormatter formatter,
  ) {
    final borderColor = switch (status) {
      'yellow' => Colors.orange.shade700,
      'red' => Colors.red.shade700,
      _ => null,
    };
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [formatter],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        isDense: true,
        border: const OutlineInputBorder(),
        enabledBorder: borderColor != null
            ? OutlineInputBorder(
                borderSide: BorderSide(color: borderColor, width: 1.4),
              )
            : const OutlineInputBorder(),
        focusedBorder: borderColor != null
            ? OutlineInputBorder(
                borderSide: BorderSide(color: borderColor, width: 2),
              )
            : null,
      ),
      onChanged: (_) => setState(
        () => _error = null,
      ), // also refreshes _tempStatus/_humStatus each keystroke
    );
  }
}

class _PanelLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _PanelLabel({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.25), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
