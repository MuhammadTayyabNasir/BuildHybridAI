import 'package:flutter/material.dart';

import '../../../../core/previews/theme_preview.dart';

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Option Picker Dialog')
Widget previewOptionPickerDialog() => const OptionPickerDialog(
  heading: 'QC Check',
  options: ['Pass', 'Fail', 'Recheck'],
  selected: 'Pass',
);

class OptionPickerDialog extends StatelessWidget {
  final String heading;
  final List<String> options;
  final String selected;

  const OptionPickerDialog({
    super.key,
    required this.heading,
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(heading),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: options
              .map((o) => ListTile(
            dense: true,
            title: Text(o, style: const TextStyle(fontSize: 14)),
            trailing: selected == o
                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(context, o),
          ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}