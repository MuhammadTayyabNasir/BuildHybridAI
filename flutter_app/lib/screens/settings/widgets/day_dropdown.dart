import 'package:flutter/material.dart';
import '../../../../core/previews/theme_preview.dart';

class DayDropdown extends StatelessWidget {
  final int value;
  final bool includeEveryDay;
  final ValueChanged<int> onChanged;

  const DayDropdown({
    super.key,
    required this.value,
    required this.includeEveryDay,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<int>>[
      if (includeEveryDay)
        const DropdownMenuItem(value: 0, child: Text('Every day')),
      const DropdownMenuItem(value: DateTime.monday, child: Text('Monday')),
      const DropdownMenuItem(value: DateTime.tuesday, child: Text('Tuesday')),
      const DropdownMenuItem(value: DateTime.wednesday, child: Text('Wednesday')),
      const DropdownMenuItem(value: DateTime.thursday, child: Text('Thursday')),
      const DropdownMenuItem(value: DateTime.friday, child: Text('Friday')),
      const DropdownMenuItem(value: DateTime.saturday, child: Text('Saturday')),
      const DropdownMenuItem(value: DateTime.sunday, child: Text('Sunday')),
    ];

    final safeValue = (!includeEveryDay && value == 0) ? DateTime.monday : value;

    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          items: items,
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Day Dropdown')
Widget previewDayDropdown() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16.0),
    child: DayDropdown(
      value: DateTime.wednesday,
      includeEveryDay: true,
      onChanged: (v) {},
    ),
  ),
);