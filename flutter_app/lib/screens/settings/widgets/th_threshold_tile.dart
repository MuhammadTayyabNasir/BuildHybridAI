import 'package:flutter/material.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/th_threshold_model.dart';
import '../../../../core/previews/theme_preview.dart';

class ThThresholdTile extends StatefulWidget {
  final SectionInfo section;
  final ThThreshold threshold;
  final bool editable;
  final ValueChanged<ThThreshold> onChanged;

  const ThThresholdTile({
    super.key,
    required this.section,
    required this.threshold,
    required this.editable,
    required this.onChanged,
  });

  @override
  State<ThThresholdTile> createState() => _ThThresholdTileState();
}

class _ThThresholdTileState extends State<ThThresholdTile> {
  late double _tempGreen;
  late double _tempYellow;
  late double _humGreen;
  late double _humYellow;

  @override
  void initState() {
    super.initState();
    _tempGreen = widget.threshold.tempGreenMax;
    _tempYellow = widget.threshold.tempYellowMax;
    _humGreen = widget.threshold.humGreenMax;
    _humYellow = widget.threshold.humYellowMax;
  }

  @override
  void didUpdateWidget(covariant ThThresholdTile old) {
    super.didUpdateWidget(old);
    if (old.threshold.tempGreenMax != widget.threshold.tempGreenMax) {
      _tempGreen = widget.threshold.tempGreenMax;
    }
    if (old.threshold.tempYellowMax != widget.threshold.tempYellowMax) {
      _tempYellow = widget.threshold.tempYellowMax;
    }
    if (old.threshold.humGreenMax != widget.threshold.humGreenMax) {
      _humGreen = widget.threshold.humGreenMax;
    }
    if (old.threshold.humYellowMax != widget.threshold.humYellowMax) {
      _humYellow = widget.threshold.humYellowMax;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.section.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          const Text(
            'Temperature',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          _MetricRow(
            icon: Icons.thermostat_outlined,
            unit: '°C',
            greenLabel: 'Green up to',
            yellowLabel: 'Yellow up to (above = red)',
            green: _tempGreen,
            yellow: _tempYellow,
            min: -20,
            max: 100,
            editable: widget.editable,
            onGreenChanged: (v) => setState(() {
              _tempGreen = v;
              if (_tempGreen >= _tempYellow) _tempYellow = _tempGreen + 1;
            }),
            onYellowChanged: (v) => setState(() {
              _tempYellow = v;
              if (_tempYellow <= _tempGreen) _tempGreen = _tempYellow - 1;
            }),
            onCommit: () => widget.onChanged(
              widget.threshold.copyWith(tempGreenMax: _tempGreen, tempYellowMax: _tempYellow),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Humidity',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          _MetricRow(
            icon: Icons.water_drop_outlined,
            unit: '%',
            greenLabel: 'Green up to',
            yellowLabel: 'Yellow up to (above = red)',
            green: _humGreen,
            yellow: _humYellow,
            min: 0,
            max: 100,
            editable: widget.editable,
            onGreenChanged: (v) => setState(() {
              _humGreen = v;
              if (_humGreen >= _humYellow) _humYellow = _humGreen + 1;
            }),
            onYellowChanged: (v) => setState(() {
              _humYellow = v;
              if (_humYellow <= _humGreen) _humGreen = _humYellow - 1;
            }),
            onCommit: () => widget.onChanged(
              widget.threshold.copyWith(humGreenMax: _humGreen, humYellowMax: _humYellow),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String unit;
  final String greenLabel;
  final String yellowLabel;
  final double green;
  final double yellow;
  final double min;
  final double max;
  final bool editable;
  final ValueChanged<double>? onGreenChanged;
  final ValueChanged<double>? onYellowChanged;
  final VoidCallback? onCommit;

  const _MetricRow({
    required this.icon,
    required this.unit,
    required this.greenLabel,
    required this.yellowLabel,
    required this.green,
    required this.yellow,
    required this.min,
    required this.max,
    required this.editable,
    this.onGreenChanged,
    this.onYellowChanged,
    this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(
              '$greenLabel ${green.toStringAsFixed(0)}$unit',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (editable)
          Slider(
            value: green.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${green.toStringAsFixed(0)}$unit',
            onChanged: onGreenChanged,
            onChangeEnd: (_) => onCommit?.call(),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            const SizedBox(width: 22),
            Expanded(
              child: Text(
                '$yellowLabel ${yellow.toStringAsFixed(0)}$unit',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (editable)
          Slider(
            value: yellow.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${yellow.toStringAsFixed(0)}$unit',
            onChanged: onYellowChanged,
            onChangeEnd: (_) => onCommit?.call(),
          )
        else
          const SizedBox(height: 4),
        Text(
          '${green.toStringAsFixed(0)}$unit or below = green · '
              '${(green + 1).toStringAsFixed(0)}–${yellow.toStringAsFixed(0)}$unit = yellow · '
              'above ${yellow.toStringAsFixed(0)}$unit = red',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Threshold Tile')
Widget previewThThresholdTile() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16.0),
    child: ThThresholdTile(
      section: Sections.all.first,
      threshold: ThThreshold.defaults(Sections.all.first.id),
      editable: true,
      onChanged: (v) {},
    ),
  ),
);