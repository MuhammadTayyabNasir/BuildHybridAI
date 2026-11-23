import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/sections.dart';
import '../../core/utils/status_utils.dart';
import '../../models/packing_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entries_provider.dart';
import '../../services/local_storage_service.dart';

class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  bool _downloading = false;
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import Entries')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Step 1: Download Template',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text(
                      'Download the Excel template, fill in the packing data, then upload it.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: _downloading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download),
                      label: const Text('Download Template'),
                      onPressed: _downloading ? null : _downloadTemplate,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Step 2: Upload Filled Template',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text(
                      'Pick your filled Excel file to preview and import entries.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: _picking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.upload_file),
                      label: const Text('Pick Excel File & Import'),
                      onPressed: _picking ? null : _pickAndImport,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.nimko),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Template Columns:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ColChip('Section'), _ColChip('Machine#'), _ColChip('Product Name'),
                _ColChip('Price'), _ColChip('Shift (morning/night)'),
                _ColChip('Manufacture Date'), _ColChip('Expiry Date'),
                _ColChip('Gross Weight'), _ColChip('Pouch1'), _ColChip('Pouch2'),
                _ColChip('Pouch3'), _ColChip('Pouch4'), _ColChip('Moisture'),
                _ColChip('Printing (okay/not_okay)'), _ColChip('Printing Color'),
                _ColChip('Leakage (green/yellow/red)'), _ColChip('Remarks'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['Template'];

      final headers = [
        'Section', 'Machine#', 'Product Name', 'Price', 'Shift (morning/night)',
        'Manufacture Date (DD/MM/YYYY)', 'Expiry Date (DD/MM/YYYY)',
        'Gross Weight', 'Pouch1', 'Pouch2', 'Pouch3', 'Pouch4',
        'Moisture', 'Printing Status (okay/not_okay)',
        'Printing Color (yellow/red)', 'Leakage (green/yellow/red)', 'Remarks',
      ];

      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );

      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = headerStyle;
      }

      // Sample rows
      final sampleData = [
        ['chips', '1', 'Chips Masala', '20', 'morning', '01/06/2025', '01/07/2025', '12', '11.5', '12.1', '11.8', '12.3', '1.5', 'okay', '', 'green', ''],
        ['peri_peri', '2', 'Peri Peri Cheese', '50', 'night', '01/06/2025', '01/07/2025', '45', '44', '45.5', '44.8', '45.2', '1.7', 'not_okay', 'yellow', 'green', 'Minor color issue'],
        ['nimko', '3', 'Nimko Mix', '100', 'morning', '01/06/2025', '29/08/2025', '113', '112', '113.5', '114', '112.8', '1.6', 'okay', '', 'green', ''],
      ];

      for (int r = 0; r < sampleData.length; r++) {
        for (int c = 0; c < sampleData[r].length; c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
          cell.value = TextCellValue(sampleData[r][c]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to encode template');

      String downloadsDir;
      if (Platform.isWindows) {
        final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public';
        downloadsDir = '$home\\Downloads';
      } else {
        final dir = await getDownloadsDirectory();
        downloadsDir = dir?.path ?? (await getApplicationDocumentsDirectory()).path;
      }

      final path = '$downloadsDir\\PMA_Import_Template.xlsx';
      await File(path).writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Template saved to: $path'), backgroundColor: Colors.green, duration: const Duration(seconds: 6)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickAndImport() async {
    setState(() => _picking = true);
    // Capture context-dependent references before any async gap
    final auth = context.read<AuthProvider>();
    final local = context.read<LocalStorageService>();
    final ep = context.read<EntriesProvider>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes ?? await File(result.files.first.path!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final sheet = excel.sheets.values.first;
      final rows = sheet.rows;
      if (rows.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data rows found'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final parsed = <_ParsedRow>[];
      final errors = <String>[];

      // Map section+number to machineId — read from the local DB (kept fresh by
      // the gRPC listener on mobile / REST sync on Windows), never a REST query.
      final machines = local.getMachines();

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty || row.every((c) => c?.value == null)) continue;

        String cell(int c) => row.length > c ? (row[c]?.value?.toString().trim() ?? '') : '';

        final section = cell(0).toLowerCase().replaceAll(' ', '_');
        final machineNumStr = cell(1);
        final productName = cell(2);
        final priceStr = cell(3);
        final shift = cell(4).toLowerCase();
        final mfgDateStr = cell(5);
        final expDateStr = cell(6);
        final grossWeightStr = cell(7);
        final p1Str = cell(8);
        final p2Str = cell(9);
        final p3Str = cell(10);
        final p4Str = cell(11);
        final moistureStr = cell(12);
        final printingStatus = cell(13).isEmpty ? 'okay' : cell(13);
        final printingColor = cell(14).isEmpty ? null : cell(14);
        final leakageStatus = cell(15).isEmpty ? 'green' : cell(15);
        final remarks = cell(16);

        // Validate
        if (!Sections.ids.contains(section)) {
          errors.add('Row ${r + 1}: Invalid section "$section"');
          continue;
        }

        final machineNum = int.tryParse(machineNumStr);
        if (machineNum == null) {
          errors.add('Row ${r + 1}: Invalid machine number "$machineNumStr"');
          continue;
        }

        final machine = machines.where((m) => m.section == section && m.number == machineNum).firstOrNull;
        if (machine == null) {
          errors.add('Row ${r + 1}: Machine $machineNum not found in section $section');
          continue;
        }

        DateTime? mfgDate, expDate;
        try {
          mfgDate = DateFormat('dd/MM/yyyy').parse(mfgDateStr);
          expDate = DateFormat('dd/MM/yyyy').parse(expDateStr);
        } catch (_) {
          errors.add('Row ${r + 1}: Invalid date format (use DD/MM/YYYY)');
          continue;
        }

        final price = double.tryParse(priceStr) ?? 0;
        final grossWeight = double.tryParse(grossWeightStr) ?? 0;
        final p1 = double.tryParse(p1Str);
        final p2 = double.tryParse(p2Str);
        final p3 = double.tryParse(p3Str);
        final p4 = double.tryParse(p4Str);
        final moisture = double.tryParse(moistureStr);

        final now = DateTime.now();
        final entry = PackingEntryModel(
          id: '',
          machineId: machine.id,
          machineNumber: machineNum,
          section: section,
          productId: '',
          productName: productName,
          price: price,
          shift: shift.isEmpty ? 'morning' : shift,
          operatorId: auth.user?.id ?? '',
          operatorName: auth.user?.username ?? 'import',
          dateCodingManufacture: mfgDate,
          dateCodingExpiry: expDate,
          grossWeight: grossWeight,
          pouch1Weight: p1,
          pouch2Weight: p2,
          pouch3Weight: p3,
          pouch4Weight: p4,
          moistureActual: moisture,
          moistureIdeal: 0,
          weightStatus: StatusUtils.weightStatusOfPouches(
              [p1, p2, p3, p4], grossWeight),
          printingStatus: printingStatus,
          printingColor: printingColor,
          printingRemarks: remarks.isEmpty ? null : remarks,
          leakageStatus: leakageStatus,
          moistureStatus: moisture != null ? 'green' : 'na',
          isSynced: false,
          createdAt: now,
          updatedAt: now,
        );
        parsed.add(_ParsedRow(rowNum: r + 1, entry: entry));
      }

      if (!mounted) return;

      // Show preview
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _PreviewDialog(parsed: parsed, errors: errors),
      );

      if (confirmed == true && mounted) {
        int imported = 0;
        for (final row in parsed) {
          final err = await ep.addEntry(row.entry);
          if (err == null) imported++;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported $imported / ${parsed.length} entries'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}

class _ParsedRow {
  final int rowNum;
  final PackingEntryModel entry;
  _ParsedRow({required this.rowNum, required this.entry});
}

class _PreviewDialog extends StatelessWidget {
  final List<_ParsedRow> parsed;
  final List<String> errors;

  const _PreviewDialog({required this.parsed, required this.errors});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Preview: ${parsed.length} entries to import'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errors.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${errors.length} rows skipped:', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ...errors.take(5).map((e) => Text(e, style: const TextStyle(fontSize: 12, color: Colors.red))),
                    if (errors.length > 5) Text('... and ${errors.length - 5} more', style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (parsed.isEmpty)
              const Expanded(child: Center(child: Text('No valid rows to import')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: parsed.length,
                  itemBuilder: (ctx, i) {
                    final r = parsed[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 12, child: Text('${r.rowNum}', style: const TextStyle(fontSize: 10))),
                      title: Text('${r.entry.productName} — Machine ${r.entry.machineNumber}'),
                      subtitle: Text('${r.entry.section} · ${r.entry.shift} · Rs.${r.entry.price.toStringAsFixed(0)}'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        if (parsed.isNotEmpty)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Import ${parsed.length} Entries'),
          ),
      ],
    );
  }
}

class _ColChip extends StatelessWidget {
  final String label;
  const _ColChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
