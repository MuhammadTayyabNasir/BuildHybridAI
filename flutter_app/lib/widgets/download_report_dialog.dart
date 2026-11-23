import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/report_service.dart';
import '../services/share_service.dart';

class DownloadReportDialog extends StatefulWidget {
  const DownloadReportDialog({super.key});

  @override
  State<DownloadReportDialog> createState() => _DownloadReportDialogState();
}

class _DownloadReportDialogState extends State<DownloadReportDialog> {
  // type: 'entries' | 'analysis'
  String _type = 'entries';

  // Date period: 'today' | 'yesterday' | 'custom' (used by all report types)
  String _entriesPeriod = 'yesterday';
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 1));
  DateTime _customTo = DateTime.now().subtract(const Duration(days: 1));

  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.file_download_outlined, size: 22),
          const SizedBox(width: 10),
          const Expanded(child: Text('Download Report')),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Report type selector ────────────────────────────────────
              Text(
                'Report Type',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final opt in const [
                    ('entries', 'Entries'),
                    ('analysis', 'Analysis'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: _type == opt.$1,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _type = opt.$1),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              Text(
                _type == 'entries'
                    ? 'Raw packing log — one row per entry, color-coded by QC status.'
                    : 'QC summary with native charts — quality by section, issue '
                    'types, by supervisor (QC), and a daily pass-rate trend.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Both report types use the same date-period selector.
              ..._entriesOptions(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: _generating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.download, size: 18),
          label: const Text('Generate & Download'),
          onPressed: _generating ? null : _generate,
        ),
      ],
    );
  }

  List<Widget> _entriesOptions(ThemeData theme) {
    return [
      Text(
        'Date / Period',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Today'),
            selected: _entriesPeriod == 'today',
            onSelected: (_) => setState(() => _entriesPeriod = 'today'),
          ),
          ChoiceChip(
            label: const Text('Yesterday'),
            selected: _entriesPeriod == 'yesterday',
            onSelected: (_) => setState(() => _entriesPeriod = 'yesterday'),
          ),
          ChoiceChip(
            label: const Text('Custom range'),
            selected: _entriesPeriod == 'custom',
            onSelected: (_) => setState(() => _entriesPeriod = 'custom'),
          ),
        ],
      ),
      if (_entriesPeriod == 'custom') ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateTile(
                'From',
                _customFrom,
                    (d) => setState(() {
                  _customFrom = d;
                  if (_customTo.isBefore(d)) _customTo = d;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateTile(
                'To',
                _customTo,
                    (d) => setState(() {
                  _customTo = d;
                  if (_customFrom.isAfter(d)) _customFrom = d;
                }),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _dateTile(String label, DateTime date, void Function(DateTime) onPicked) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2024),
          lastDate: DateTime.now(),
        );
        if (d != null) onPicked(d);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              DateFormat('dd MMM yyyy').format(date),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() => _generating = true);

    try {
      final svc = context.read<ReportService>();
      String path;
      final today = DateTime.now();

      final (from, to) = switch (_entriesPeriod) {
        'today' => (today, today),
        'yesterday' => (
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
        ),
        _ => (_customFrom, _customTo),
      };

      path = _type == 'analysis'
          ? await svc.generateAnalysisReport(from: from, to: to)
          : await svc.generateEntriesReport(from: from, to: to);

      if (mounted) {
        Navigator.pop(context);

        final prefs = await SharedPreferences.getInstance();
        final shareEnabled = prefs.getBool(kWhatsappShare) ?? false;
        final recipient = prefs.getString(kWhatsappRecipient);

        if (!mounted) return;

        final messenger = ScaffoldMessenger.of(context);

        if (shareEnabled) {
          ShareService.shareReport(path, recipient: recipient);
        }

        const btnStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.w700);

        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 10),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Report saved')),
                TextButton(
                  onPressed: () => ShareService.shareReport(path, recipient: recipient),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('SHARE', style: btnStyle),
                ),
                TextButton(
                  onPressed: messenger.hideCurrentSnackBar,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('OK', style: btnStyle),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (context.mounted) setState(() => _generating = false);
    }
  }
}