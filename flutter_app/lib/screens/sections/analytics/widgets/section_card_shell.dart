import 'package:flutter/material.dart';
import '../../../../../core/previews/theme_preview.dart';

class SectionCardShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const SectionCardShell({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing case final trailing!) trailing,
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Section Card Shell')
Widget previewSectionCardShell() => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16.0),
    child: SectionCardShell(
      icon: Icons.analytics_outlined,
      title: 'Example Analytics Card',
      trailing: const Text('100 entries'),
      child: const Text('This is the inner content of the card.'),
    ),
  ),
);