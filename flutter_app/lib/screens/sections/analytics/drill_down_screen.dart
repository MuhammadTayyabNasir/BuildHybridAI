import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/sections.dart';
import '../../../../models/packing_entry_model.dart';
import '../entry_detail_screen.dart';
import '../../../ui/pma_ui.dart';

class DrillDownScreen extends StatelessWidget {
  final String title;
  final SectionInfo section;
  final List<PackingEntryModel> entries;

  const DrillDownScreen({
    super.key,
    required this.title,
    required this.section,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PmaAppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                '${entries.length} entr${entries.length == 1 ? 'y' : 'ies'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No entries'))
          : ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = entries[i];
          final issues = <String>[
            if (e.weightStatus == 'red') 'Weight',
            if (e.moistureStatus == 'red') 'Moisture',
            if (e.printingStatus == 'not_okay') 'Printing',
            if (e.leakageStatus == 'red') 'Leakage',
          ];
          return ListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EntryDetailScreen(entry: e, section: section),
              ),
            ),
            title: Text(
              '${DateFormat('dd MMM · HH:mm').format(e.createdAt)}   ·   M${e.machineNumber}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.productName}${e.operatorName.trim().isEmpty ? '' : ' · ${e.operatorName.trim()}'}',
                  style: const TextStyle(fontSize: 11),
                ),
                if (issues.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: issues
                        .map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.red, fontWeight: FontWeight.w600)),
                    ))
                        .toList(),
                  ),
                ],
              ],
            ),
            trailing: issues.isEmpty
                ? const Icon(Icons.check_circle, color: AppColors.green, size: 18)
                : const Icon(Icons.chevron_right, size: 18),
            isThreeLine: issues.isNotEmpty,
          );
        },
      ),
    );
  }
}