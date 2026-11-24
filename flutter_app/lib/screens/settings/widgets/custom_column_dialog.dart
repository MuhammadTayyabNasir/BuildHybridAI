import 'package:flutter/material.dart';
// Adjust this import path if your CustomColumn is located elsewhere
import '../../../../models/custom_column_model.dart';

class CustomColumnDialog extends StatefulWidget {
  final CustomColumn? existing;
  const CustomColumnDialog({super.key, this.existing});

  @override
  State<CustomColumnDialog> createState() => _CustomColumnDialogState();
}

class _CustomColumnDialogState extends State<CustomColumnDialog> {
  late TextEditingController _headingCtrl;
  late TextEditingController _optionsCtrl;
  CustomColumnType _type = CustomColumnType.text;

  // 1. We track if the admin wants this to be compulsory
  bool _isRequired = false;

  @override
  void initState() {
    super.initState();
    _headingCtrl = TextEditingController(text: widget.existing?.heading ?? '');
    _type = widget.existing?.type ?? CustomColumnType.text;
    _optionsCtrl = TextEditingController(text: widget.existing?.options.join(', ') ?? '');

    // Load existing required state if editing an older column
    _isRequired = widget.existing?.isRequired ?? false;
  }

  @override
  void dispose() {
    _headingCtrl.dispose();
    _optionsCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_headingCtrl.text.trim().isEmpty) return;

    final opts = _type == CustomColumnType.options
        ? _optionsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final col = CustomColumn(
      id: widget.existing?.id ?? CustomColumnsService.generateId(),
      heading: _headingCtrl.text.trim(),
      type: _type,
      options: opts,
      // 2. Pass the setting back to the model so it saves to SharedPreferences
      isRequired: _isRequired,
    );
    Navigator.pop(context, col);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Column' : 'Edit Column'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _headingCtrl,
              decoration: const InputDecoration(labelText: 'Column Heading (e.g. Batch No)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CustomColumnType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Data Type'),
              items: CustomColumnType.values.map((t) {
                final label = t.name[0].toUpperCase() + t.name.substring(1);
                return DropdownMenuItem(value: t, child: Text(label));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            if (_type == CustomColumnType.options) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _optionsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Options (comma separated)',
                  hintText: 'e.g. Yes, No, N/A',
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 3. THIS is the option inside the Settings Add/Edit popup!
            SwitchListTile(
              title: const Text('Make this field compulsory', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Operators cannot save without filling this out.'),
              value: _isRequired,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Theme.of(context).colorScheme.primary,
              onChanged: (val) => setState(() => _isRequired = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}