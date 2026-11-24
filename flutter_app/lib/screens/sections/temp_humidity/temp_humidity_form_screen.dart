import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/temp_humidity_model.dart';
import '../../../../models/th_threshold_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/th_sync.dart';
import '../../../../services/th_threshold_service.dart';
import '../../../../widgets/offline_banner.dart';

import 'controllers/th_row_controller.dart';
import '../../../ui/pma_ui.dart';

class TempHumidityFormScreen extends StatefulWidget {
  final SectionInfo section;
  final TempHumidityReport? existing;

  const TempHumidityFormScreen({
    super.key,
    required this.section,
    this.existing,
  });

  @override
  State<TempHumidityFormScreen> createState() => _TempHumidityFormScreenState();
}

class _TempHumidityFormScreenState extends State<TempHumidityFormScreen> {
  late DateTime _date;
  late String _shift;
  late List<THRowController> _rows;
  bool _saving = false;
  bool _isDirty = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    // Defaulting safely if ShiftHelper isn't strictly imported
    _shift = DateTime.now().hour < 18 ? 'morning' : 'night';

    if (isEdit) {
      final e = widget.existing!;
      _date = e.date;
      _shift = e.shift;
      _rows = e.rows.map((r) => THRowController.fromRow(r)).toList();
    } else {
      _rows = [];
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final row = THRowController();
    row.time.text = DateFormat('HH:mm').format(DateTime.now());
    setState(() {
      _isDirty = true;
      _rows.add(row);
    });
  }

  void _removeRow(int index) {
    setState(() {
      _isDirty = true;
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _isDirty = true;
        _date = picked;
      });
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (auth.user?.isViewer == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not allowed to edit'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one reading'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final qcName = auth.user?.username ?? '';
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
      if (context.mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text('This cannot be undone.'),
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
    if (confirm != true || !mounted) return;
    await deleteTempHumidityLocalFirst(context, widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(widget.section.id);
    final auth = context.watch<AuthProvider>();
    final qcName = auth.user?.username ?? '';
    final thresholdSvc = context.read<ThThresholdService>();

    return ValueListenableBuilder<Map<String, ThThreshold>>(
      valueListenable: thresholdSvc.current,
      builder: (context, _, _) {
        final threshold = thresholdSvc.forSection(widget.section.id);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (!_isDirty) {
              Navigator.of(context).pop();
              return;
            }
            final discard = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('You have unsaved changes.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            );
            if (discard == true && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: PmaAppBar(
              title: Text('${widget.section.name} — T&H Report'),
              actions: [
                if (isEdit)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: _delete,
                  ),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'SAVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: color,
              icon: const Icon(Icons.add),
              label: const Text('Add Reading'),
              onPressed: _addRow,
            ),
            body: Column(
              children: [
                const OfflineBanner(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _pickDate,
                        child: _chip(Icons.calendar_today, DateFormat('dd MMM yyyy').format(_date), color),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => setState(() {
                          _isDirty = true;
                          _shift = _shift == 'morning' ? 'night' : 'morning';
                        }),
                        child: _chip(
                          _shift == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
                          _shift == 'morning' ? '☀️ Morning' : '🌙 Night',
                          color,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                const Divider(height: 1),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.thermostat, size: 56, color: color.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        const Text('No readings yet', style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add first reading'),
                          onPressed: _addRow,
                        ),
                      ],
                    ),
                  )
                      : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (_, i) => _buildFormRow(i, color, threshold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFormRow(int index, Color color, ThThreshold threshold) {
    final row = _rows[index];
    final tempVal = double.tryParse(row.temperature.text);
    final tempStatus = tempVal == null ? null : threshold.classifyTemp(tempVal);
    final humVal = double.tryParse(row.humidity.text);
    final humStatus = humVal == null ? null : threshold.classifyHumidity(humVal);

    String? tempError() => switch (tempStatus) {
      'yellow' => 'Warning: ${threshold.tempGreenMax.toStringAsFixed(0)}–${threshold.tempYellowMax.toStringAsFixed(0)}°C band',
      'red' => 'Alert: above ${threshold.tempYellowMax.toStringAsFixed(0)}°C',
      _ => null,
    };
    String? humError() => switch (humStatus) {
      'yellow' => 'Warning: ${threshold.humGreenMax.toStringAsFixed(0)}–${threshold.humYellowMax.toStringAsFixed(0)}% band',
      'red' => 'Alert: above ${threshold.humYellowMax.toStringAsFixed(0)}%',
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('Reading ${index + 1}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.red, size: 20),
                  onPressed: () => _removeRow(index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.time,
                    decoration: const InputDecoration(labelText: 'Time', hintText: 'HH:MM', isDense: true),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.temperature,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: 'Temperature',
                      suffixText: '°C',
                      isDense: true,
                      errorText: tempError(),
                      errorStyle: TextStyle(color: tempStatus == 'red' ? Colors.red.shade700 : Colors.orange.shade700),
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.humidity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Humidity',
                      suffixText: '%',
                      isDense: true,
                      errorText: humError(),
                      errorStyle: TextStyle(color: humStatus == 'red' ? Colors.red.shade700 : Colors.orange.shade700),
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: row.remarks,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Remarks', hintText: 'Optional notes', isDense: true),
              onChanged: (_) => setState(() => _isDirty = true),
            ),
          ],
        ),
      ),
    );
  }
}