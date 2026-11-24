import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../core/utils/date_utils.dart';
import '../../models/packing_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/status_chip.dart';
import 'entry_form_screen.dart';

class EntryDetailScreen extends StatelessWidget {
  final PackingEntryModel entry;
  final SectionInfo section;

  const EntryDetailScreen({
    super.key,
    required this.entry,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.sectionColor(section.id);
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(foregroundColor: Colors.white, 
        backgroundColor: color,
        title: Text('Entry Detail — ${section.name}'),
        actions: [
          if (auth.user?.isViewer != true)
              TextButton.icon(
                icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                label: const Text(
                  'Edit',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EntryFormScreen(section: section, existing: entry),
                  ),
                ),
              ),

        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(context, color),
            const SizedBox(height: 14),
            _tableCard(context, 'Identification', [
              ['Machine', 'Machine ${entry.machineNumber}'],
              ['Product', entry.productName],
              [
                'Shift',
                entry.shift == 'morning'
                    ? '☀️ Morning Shift'
                    : '🌙 Night Shift',
              ],
              ['QC', entry.operatorName],
              ['Date Added', AppDateUtils.full(entry.createdAt)],
              if (entry.updatedAt != entry.createdAt)
                ['Last Updated', AppDateUtils.full(entry.updatedAt)],
            ]),
            const SizedBox(height: 14),
            _tableCard(context, 'Date Coding', [
              ['Manufacture', AppDateUtils.short(entry.dateCodingManufacture)],
              ['Expiry', AppDateUtils.short(entry.dateCodingExpiry)],
              [
                'Duration',
                '${entry.dateCodingExpiry.difference(entry.dateCodingManufacture).inDays} days',
              ],
            ]),
            const SizedBox(height: 14),
            _tableCard(
              context,
              'Weight Check',
              [
                ['Gross Weight (Target)', '${entry.grossWeight}g'],
                if (entry.pouch1Weight != null)
                  ['Pouch 1', '${entry.pouch1Weight}g'],
                if (entry.pouch2Weight != null)
                  ['Pouch 2', '${entry.pouch2Weight}g'],
                if (entry.pouch3Weight != null)
                  ['Pouch 3', '${entry.pouch3Weight}g'],
                if (entry.pouch4Weight != null)
                  ['Pouch 4', '${entry.pouch4Weight}g'],
                if (entry.avgPouchWeight > 0) ...[
                  [
                    'Average Weight',
                    '${entry.avgPouchWeight.toStringAsFixed(2)}g',
                  ],
                  [
                    'Deviation',
                    '${(entry.avgPouchWeight - entry.grossWeight).toStringAsFixed(2)}g',
                  ],
                ],
              ],
              statusKey: 'Weight',
              statusValue: entry.weightStatus,
            ),
            const SizedBox(height: 14),
            if (section.id != 'wafer' && section.id != 'chocolate')
              _tableCard(
                context,
                'Moisture',
                [
                  if (entry.moistureIdeal != null)
                    ['Ideal Moisture', '${entry.moistureIdeal}'],
                  if (entry.moistureActual != null)
                    ['Actual Moisture', '${entry.moistureActual}'],
                ],
                statusKey: 'Moisture',
                statusValue: entry.moistureStatus,
              ),
            if (section.id != 'wafer' && section.id != 'chocolate')
              const SizedBox(height: 14),
            _tableCard(
              context,
              'Printing',
              [
                [
                  'Status',
                  entry.printingStatus == 'okay' ? 'Okay' : 'Not Okay',
                ],
                if (entry.printingColor != null)
                  ['Level', entry.printingColor!.toUpperCase()],
                if (entry.printingRemarks != null &&
                    entry.printingRemarks!.isNotEmpty)
                  ['Remarks', entry.printingRemarks!],
              ],
              statusKey: 'Print',
              statusValue: entry.printingStatus == 'okay'
                  ? 'green'
                  : (entry.printingColor ?? 'red'),
            ),
            const SizedBox(height: 14),
            _tableCard(
              context,
              'Leakage',
              [
                ['Status', _leakageLabel(entry.leakageStatus)],
              ],
              statusKey: 'Leakage',
              statusValue: entry.leakageStatus,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context, Color color) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.name,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              entry.productName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _whiteChip('Machine ${entry.machineNumber}'),
                _whiteChip(
                  entry.shift == 'morning' ? '☀️ Morning' : '🌙 Night',
                ),
                _whiteChip(AppDateUtils.display(entry.createdAt)),
                if (!entry.isSynced) _whiteChip('⚠️ Not Synced'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableCard(
    BuildContext context,
    String title,
    List<List<String>> rows, {
    String? statusKey,
    String? statusValue,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (statusKey != null && statusValue != null) ...[
                  const Spacer(),
                  StatusChip(status: statusValue, label: statusKey),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ...rows.map((row) => _tableRow(context, row[0], row[1])),
          ],
        ),
      ),
    );
  }

  Widget _tableRow(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              key,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whiteChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  String _leakageLabel(String status) {
    switch (status) {
      case 'green':
        return 'No Leakage';
      case 'yellow':
        return 'Minor Leakage';
      case 'red':
        return 'Major Leakage';
      default:
        return status;
    }
  }
}
