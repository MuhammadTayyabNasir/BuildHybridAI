import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/temp_humidity_model.dart';
import '../../../../models/th_threshold_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/th_sync.dart';
import '../../../../services/th_threshold_service.dart';

import 'controllers/th_row_controller.dart';

const _thWNum = 36.0;
const _thWTime = 70.0;
const _thWTemp = 82.0;
const _thWHum = 82.0;
const _thWSection = 96.0;
const _thWQc = 110.0;
const _thWRemarks = 160.0;
const _thWDel = 44.0;
const _thRowH = 52.0;
const _thHeadH = 38.0;
const _defaultTHRowsFallback = 8;

class TempHumidityExcelScreen extends StatefulWidget {
  final SectionInfo section;
  final TempHumidityReport? existing;

  const TempHumidityExcelScreen({
    super.key,
    required this.section,
    this.existing,
  });

  @override
  State<TempHumidityExcelScreen> createState() => _TempHumidityExcelScreenState();
}

class _TempHumidityExcelScreenState extends State<TempHumidityExcelScreen> {
  late DateTime _date;
  late String _shift;
  final List<THRowController> _rows = [];
  bool _saving = false;
  bool _ready = false;
  int _defaultTHRows = _defaultTHRowsFallback;
  final _hScrollCtrl = ScrollController();

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _shift = DateTime.now().hour < 18 ? 'morning' : 'night';

    if (isEdit) {
      final e = widget.existing!;
      _date = e.date;
      _shift = e.shift;
      for (final row in e.rows) {
        _rows.add(THRowController.fromRow(row));
      }
      _ready = true;
    } else {
      _initRows();
    }
  }

  Future<void> _initRows() async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    _defaultTHRows = prefs.getInt('th_excel_rows') ?? _defaultTHRowsFallback;
    for (int i = 0; i < _defaultTHRows; i++) {
      _addRowInternal();
    }
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _hScrollCtrl.dispose();
    super.dispose();
  }

  void _addRowInternal() {
    final row = THRowController();
    row.time.text = DateFormat('HH:mm').format(DateTime.now());
    _rows.add(row);
  }

  void _addRow() => setState(() => _addRowInternal());

  void _removeRow(int i) {
    if (_rows.length == 1) return;
    _rows[i].dispose();
    _rows.removeAt(i);
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final qcName = auth.user?.username ?? '';
    final validRows = _rows.where((r) => r.temperature.text.trim().isNotEmpty || r.humidity.text.trim().isNotEmpty).toList();

    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one reading'), backgroundColor: AppColors.red),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = isEdit ? widget.existing!.id : TempHumidityReport.generateId();
      final report = TempHumidityReport(
        id: id,
        sectionId: widget.section.id,
        date: TempHumidityReport.dayOf(_date),
        shift: _shift,
        rows: _rows.map((r) => r.toRow(widget.section.name, qcName)).toList(),
        preparedBy: qcName,
        isSynced: false,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await saveTempHumidityLocalFirst(context, report);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
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
    if (confirm != true || !mounted) return;
    await deleteTempHumidityLocalFirst(context, widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  double get _tableWidth => _thWNum + _thWTime + _thWTemp + _thWHum + _thWSection + _thWQc + _thWRemarks + _thWDel + 16;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    final auth = context.watch<AuthProvider>();
    final qcName = auth.user?.username ?? '';

    if (!_ready) {
      return Scaffold(
        appBar: AppBar(backgroundColor: color, title: Text('${widget.section.name} — T&H Report')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final thresholdSvc = context.read<ThThresholdService>();
    return ValueListenableBuilder<Map<String, ThThreshold>>(
      valueListenable: thresholdSvc.current,
      builder: (context, _, _) {
        final threshold = thresholdSvc.forSection(widget.section.id);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: color,
            title: Text('${widget.section.name} — T&H Report'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                label: Text(DateFormat('dd/MM/yy').format(_date), style: const TextStyle(color: Colors.white, fontSize: 13)),
                onPressed: _pickDate,
              ),
              TextButton.icon(
                icon: Icon(_shift == 'morning' ? Icons.wb_sunny : Icons.nights_stay, color: Colors.white, size: 16),
                label: Text(_shift == 'morning' ? 'Morning' : 'Night', style: const TextStyle(color: Colors.white, fontSize: 13)),
                onPressed: () => setState(() => _shift = _shift == 'morning' ? 'night' : 'morning'),
              ),
              if (isEdit) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _delete),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_alt, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save All'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                color: color.withValues(alpha: 0.07),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('QC: $qcName', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 16),
                    const Icon(Icons.factory_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('Section: ${widget.section.name}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _tableWidth,
                    child: Column(
                      children: [
                        _buildHeader(color),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (_, i) => _buildDataRow(i, _rows[i], color, qcName, threshold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildFooter(color),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Color accent) {
    return Container(
      height: _thHeadH,
      color: accent.withValues(alpha: 0.12),
      child: Row(
        children: [
          _hCell('#', _thWNum),
          _hCell('Time', _thWTime),
          _hCell('Temp (°C)', _thWTemp),
          _hCell('Humidity %', _thWHum),
          _hCell('Section', _thWSection),
          _hCell('QC Sign', _thWQc),
          _hCell('Remarks', _thWRemarks),
          SizedBox(width: _thWDel),
        ],
      ),
    );
  }

  Widget _hCell(String label, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
    ),
  );

  Widget _buildDataRow(int i, THRowController row, Color accent, String qcName, ThThreshold threshold) {
    final odd = i.isOdd;
    final bg = odd ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35) : null;

    return Container(
      height: _thRowH,
      color: bg,
      child: Row(
        children: [
          SizedBox(width: _thWNum, child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)))),
          _editableCell(row.time, _thWTime, hint: 'HH:MM'),
          _numCell(
            row.temperature,
            _thWTemp,
            hint: '33.5',
            formatter: FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            classify: (t) {
              final v = double.tryParse(t);
              return v == null ? null : threshold.classifyTemp(v);
            },
          ),
          _numCell(
            row.humidity,
            _thWHum,
            hint: '28',
            formatter: FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            classify: (t) {
              final v = double.tryParse(t);
              return v == null ? null : threshold.classifyHumidity(v);
            },
          ),
          _autoCell(widget.section.name, _thWSection),
          _autoCell(qcName, _thWQc),
          _editableCell(row.remarks, _thWRemarks, hint: 'OK'),
          SizedBox(
            width: _thWDel,
            child: IconButton(
              icon: Icon(Icons.remove_circle_outline, size: 18, color: AppColors.red.withValues(alpha: 0.7)),
              onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numCell(
      TextEditingController ctrl,
      double width, {
        String hint = '',
        TextInputFormatter? formatter,
        String? Function(String)? classify,
      }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (context, value, _) {
            final status = classify?.call(value.text);
            Color? borderColor;
            IconData? icon;
            String? tooltip;
            if (status == 'yellow') {
              borderColor = Colors.orange.shade700;
              icon = Icons.warning_amber_rounded;
              tooltip = 'Warning band';
            } else if (status == 'red') {
              borderColor = Colors.red.shade700;
              icon = Icons.error_outline;
              tooltip = 'Alert — outside safe range';
            }
            return TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [formatter ?? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                border: const OutlineInputBorder(),
                enabledBorder: borderColor != null
                    ? OutlineInputBorder(borderSide: BorderSide(color: borderColor, width: 1.4))
                    : const OutlineInputBorder(),
                focusedBorder: borderColor != null
                    ? OutlineInputBorder(borderSide: BorderSide(color: borderColor, width: 2))
                    : null,
                suffixIcon: icon != null
                    ? Tooltip(message: tooltip, child: Icon(icon, size: 16, color: borderColor))
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _editableCell(TextEditingController ctrl, double width, {String hint = ''}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 11),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _autoCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildFooter(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Row'),
            onPressed: _addRow,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Duplicate Last'),
            onPressed: _rows.isEmpty
                ? null
                : () {
              final last = _rows.last;
              final dup = THRowController();
              dup.time.text = DateFormat('HH:mm').format(DateTime.now());
              dup.temperature.text = last.temperature.text;
              dup.humidity.text = last.humidity.text;
              dup.remarks.text = last.remarks.text;
              setState(() => _rows.add(dup));
            },
          ),
          const Text('Time, Section & QC are auto-filled', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}