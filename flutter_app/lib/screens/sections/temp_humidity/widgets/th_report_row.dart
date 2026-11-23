import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../models/temp_humidity_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../core/previews/theme_preview.dart';

class THReportRow extends StatelessWidget {
  final TempHumidityReport report;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const THReportRow({
    super.key,
    required this.report,
    required this.color,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final date = DateFormat('dd MMM').format(report.date);
    final isNight = report.shift == 'night';
    final temps = report.rows
        .where((r) => r.temperature != null)
        .map((r) => r.temperature!)
        .toList();
    final hums = report.rows
        .where((r) => r.humidity != null)
        .map((r) => r.humidity!)
        .toList();
    final avgTemp = temps.isEmpty
        ? null
        : temps.fold(0.0, (s, v) => s + v) / temps.length;
    final avgHum = hums.isEmpty
        ? null
        : hums.fold(0.0, (s, v) => s + v) / hums.length;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!report.isSynced)
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 10,
                      color: AppColors.yellow,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 34,
              child: Icon(
                isNight ? Icons.nightlight_round : Icons.wb_sunny,
                size: 14,
                color: isNight ? Colors.indigo : Colors.amber,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${report.rows.length}',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Text(
                avgTemp != null ? '${avgTemp.toStringAsFixed(1)}°C' : '—',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Text(
                avgHum != null ? '${avgHum.toStringAsFixed(1)}%' : '—',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 16,
              child: Icon(
                report.isSynced ? Icons.cloud_done : Icons.cloud_off,
                size: 13,
                color: report.isSynced ? AppColors.green : Colors.orange,
              ),
            ),
            if (auth.user?.isViewer != true)
              GestureDetector(
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.teal,
                  ),
                ),
              ),
            if (auth.user?.isViewer != true)
              GestureDetector(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'TH Report Row')
Widget previewTHReportRow() => Scaffold(
  body: THReportRow(
    report: TempHumidityReport(
      id: 'test',
      sectionId: 'chips',
      date: DateTime.now(),
      shift: 'morning',
      rows: [
        TempHumidityRow(time: '08:00', temperature: 24.5, humidity: 45.0, section: 'chips', verifiedByQc: 'Admin', remarks: ''),
      ],
      preparedBy: 'Admin',
      isSynced: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    color: AppColors.primary,
    onTap: () {},
    onEdit: () {},
    onDelete: () {},
  ),
);