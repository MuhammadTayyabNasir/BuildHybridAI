import 'package:flutter/material.dart';
import '../../../../core/previews/theme_preview.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Settings Header')
Widget previewSettingsSectionHeader() => const Scaffold(
  body: Padding(
    padding: EdgeInsets.all(16.0),
    child: SettingsSectionHeader(title: 'Example Settings Category'),
  ),
);