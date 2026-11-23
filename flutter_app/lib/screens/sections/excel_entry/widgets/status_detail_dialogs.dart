import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/previews/theme_preview.dart';

// ── Previews ────────────────────────────────────────────────────────────
@ThemePreview(name: 'Print Detail Dialog')
Widget previewPrintDetailDialog() => const PrintDetailDialog(
  status: 'not_okay',
  color: 'yellow',
  remarks: 'Faded ink',
);

@ThemePreview(name: 'Leakage Detail Dialog')
Widget previewLeakageDetailDialog() => const LeakageDetailDialog(
  status: 'minor',
  remarks: 'Small seal leak',
);
Color _statusColor(String o) {
  switch (o) {
    case 'green':
    case 'okay':
      return AppColors.green;
    case 'yellow':
    case 'minor':
      return AppColors.yellow;
    default:
      return AppColors.red;
  }
}

Widget _statusChoiceRow(
    String label, List<String> opts, String current, void Function(String) onTap) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: opts.map((o) {
          final color = _statusColor(o);
          return ChoiceChip(
            label: Text(o[0].toUpperCase() + o.substring(1),
                style: const TextStyle(fontSize: 12)),
            selected: o == current,
            selectedColor: color.withValues(alpha: 0.2),
            onSelected: (_) => onTap(o),
          );
        }).toList(),
      ),
    ],
  );
}

/// Printing detail dialog. Pops (status, color?, remarks) or null on cancel.
class PrintDetailDialog extends StatefulWidget {
  final String status;
  final String color;
  final String remarks;

  const PrintDetailDialog({
    super.key,
    required this.status,
    required this.color,
    required this.remarks,
  });

  @override
  State<PrintDetailDialog> createState() => _PrintDetailDialogState();
}

class _PrintDetailDialogState extends State<PrintDetailDialog> {
  late String _status = widget.status;
  late String _color = widget.color;
  late final TextEditingController _remarkCtrl =
  TextEditingController(text: widget.remarks);

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Printing Details'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusChoiceRow('Status', const ['okay', 'minor', 'major'], _status,
                      (v) => setState(() {
                    _status = v;
                    if (v == 'minor') _color = 'yellow';
                    if (v == 'major') _color = 'red';
                  })),
              const SizedBox(height: 14),
              AnimatedOpacity(
                opacity: _status == 'okay' ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusChoiceRow('Color', const ['green', 'yellow', 'red'],
                        _color, (v) => setState(() => _color = v)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remarkCtrl,
                      enabled: _status != 'okay',
                      decoration: const InputDecoration(
                        labelText: 'Remarks (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
          _status,
          _status == 'okay' ? null : _color,
          _remarkCtrl.text.trim(),
          )),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Leakage detail dialog. Pops (status, remarks) or null on cancel.
class LeakageDetailDialog extends StatefulWidget {
  final String status;
  final String remarks;

  const LeakageDetailDialog({super.key, required this.status, required this.remarks});

  @override
  State<LeakageDetailDialog> createState() => _LeakageDetailDialogState();
}

class _LeakageDetailDialogState extends State<LeakageDetailDialog> {
  late String _status = widget.status;
  late final TextEditingController _remarkCtrl =
  TextEditingController(text: widget.remarks);

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leakage Details'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusChoiceRow('Status', const ['green', 'minor', 'major'],
                  _status, (v) => setState(() => _status = v)),
              const SizedBox(height: 14),
              AnimatedOpacity(
                opacity: _status == 'green' ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: TextField(
                  controller: _remarkCtrl,
                  enabled: _status != 'green',
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_status, _remarkCtrl.text.trim())),
          child: const Text('OK'),
        ),
      ],
    );
  }
}