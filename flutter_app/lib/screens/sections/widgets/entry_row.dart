import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/packing_entry_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../core/previews/theme_preview.dart';

class EntryRow extends StatelessWidget {
  final PackingEntryModel entry;
  final Color sectionColor;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const EntryRow({
    super.key,
    required this.entry,
    required this.sectionColor,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  Widget _dot(String status) {
    final color = status == 'green'
        ? AppColors.green
        : status == 'yellow'
        ? AppColors.yellow
        : AppColors.red;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _leakColor(String status) {
    if (status == 'minor') return 'yellow';
    if (status == 'major') return 'red';
    return 'green';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isViewer = auth.user?.isViewer == true;
    final date = DateFormat('dd MMM').format(entry.createdAt);
    final isNight = entry.shift == 'night';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
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
                  if (!entry.isSynced)
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 11,
                      color: AppColors.yellow,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 38,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'M${entry.machineNumber}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: sectionColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.productName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Rs.${entry.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 26,
              child: Icon(
                isNight ? Icons.nightlight_round : Icons.wb_sunny,
                size: 14,
                color: isNight ? Colors.indigo : Colors.amber,
              ),
            ),
            SizedBox(
              width: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dot(entry.weightStatus),
                  const SizedBox(width: 2),
                  _dot(
                    entry.moistureStatus == 'na'
                        ? 'green'
                        : entry.moistureStatus,
                  ),
                  const SizedBox(width: 2),
                  _dot(
                    entry.printingStatus == 'okay'
                        ? 'green'
                        : (entry.printingColor ?? 'red'),
                  ),
                  const SizedBox(width: 2),
                  _dot(_leakColor(entry.leakageStatus)),
                ],
              ),
            ),
            SizedBox(
              width: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isViewer)
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
                  if (!isViewer)
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
          ],
        ),
      ),
    );
  }
}

// ── Preview ─────────────────────────────────────────────────────────────
@ThemePreview(name: 'Entry Row')
Widget previewEntryRow() => Scaffold(
  body: EntryRow(
    entry: PackingEntryModel(
      id: '1',
      machineId: 'm1',
      machineNumber: 1,
      section: 'chips',
      productId: 'p1',
      productName: 'Sample Chips',
      price: 50.0,
      shift: 'morning',
      operatorId: 'o1',
      operatorName: 'John Doe',
      dateCodingManufacture: DateTime.now(),
      dateCodingExpiry: DateTime.now(),
      grossWeight: 50.0,
      weightStatus: 'green',
      printingStatus: 'okay',
      leakageStatus: 'green',
      moistureStatus: 'green',
      isSynced: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    sectionColor: AppColors.primary,
    onTap: () {},
    onEdit: () {},
    onDelete: () {},
  ),
);