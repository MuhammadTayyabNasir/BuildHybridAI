import 'package:flutter/material.dart';
import '../../../../core/previews/theme_preview.dart';

class ReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget? child;

  const ReportCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onToggle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: enabled ? color : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: enabled ? null : Colors.grey,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: onToggle),
              ],
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}

// ── Previews ────────────────────────────────────────────────────────────
@ThemePreview(name: 'Report Card - Enabled')
Widget previewReportCardEnabled() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16.0),
    child: ReportCard(
      icon: Icons.analytics_outlined,
      title: 'QC Analysis',
      subtitle: 'Pass rates per machine & metric. Weekly trends.',
      enabled: true,
      onToggle: (v) {},
    ),
  ),
);

@ThemePreview(name: 'Report Card - Disabled')
Widget previewReportCardDisabled() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16.0),
    child: ReportCard(
      icon: Icons.table_rows_outlined,
      title: 'Entries Log',
      subtitle: 'One row per packing entry. Color-coded by QC status.',
      enabled: false,
      onToggle: (v) {},
    ),
  ),
);