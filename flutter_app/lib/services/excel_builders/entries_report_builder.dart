import 'dart:io';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../core/constants/sections.dart';
import '../../models/packing_entry_model.dart';
import '../../models/temp_humidity_model.dart';
import '../../models/custom_column_model.dart';
import '../th_threshold_service.dart';
import 'excel_helpers.dart';

class EntriesReportBuilder {
  static Future<String> build({
    required DateTime from,
    required DateTime to,
    required List<PackingEntryModel> entries,
    required List<TempHumidityReport> thReports,
    required List<CustomColumn> customCols,
    required ThThresholdService thresholds,
    required String downloadDir,
  }) async {
    final isSingle = from.year == to.year && from.month == to.month && from.day == to.day;
    final periodLabel = isSingle
        ? DateFormat('dd MMM yyyy').format(from)
        : '${DateFormat('dd MMM').format(from)} – ${DateFormat('dd MMM yyyy').format(to)}';

    final wb = xlsio.Workbook();
    try {
      _buildTempHumiditySheet(wb.worksheets[0], thReports, periodLabel, thresholds);

      var anySection = false;
      for (final sec in Sections.all) {
        final se = entries.where((e) => e.section == sec.id).toList();
        if (se.isEmpty) continue;
        anySection = true;
        final sheet = wb.worksheets.addWithName(ExcelHelpers.safeSheetName(sec.name));

        _buildEntriesSheet(sheet, se, sec.name, periodLabel, customCols);
      }

      if (!anySection) {
        final s = wb.worksheets.addWithName('NoData');
        final msg = s.getRangeByIndex(1, 1);
        msg.setText('No entries found for $periodLabel.');
        msg.cellStyle..bold = true..fontColor = '#616161';
        final tip = s.getRangeByIndex(2, 1);
        tip.setText('Tip: pull-to-refresh on a section screen to load entries from the server.');
        tip.cellStyle.fontColor = '#9E9E9E';
      }

      final sep = Platform.pathSeparator;
      final stamp = isSingle
          ? DateFormat('yyyy-MM-dd').format(from)
          : '${DateFormat('yyyy-MM-dd').format(from)}_to_${DateFormat('yyyy-MM-dd').format(to)}';

      final path = '$downloadDir${sep}PMA_Entries_$stamp.xlsx';
      final bytes = wb.saveAsStream();
      await File(path).writeAsBytes(bytes);
      return path;
    } finally {
      wb.dispose();
    }
  }

  static void _buildEntriesSheet(
      xlsio.Worksheet sheet,
      List<PackingEntryModel> entries,
      String sectionName,
      String periodLabel,
      List<CustomColumn> customCols,
      ) {
    final totalCols = 20 + customCols.length;
    final lastCol = ExcelHelpers.colLetter(totalCols);

    // ── Header (rows 1–2) ─────────────────────────────────────────────────
    final title = sheet.getRangeByIndex(1, 1);
    title.setText('PMA — Packing Entries Log');
    final titleRange = sheet.getRangeByName('A1:${lastCol}1');
    titleRange.merge();
    titleRange.cellStyle
      ..bold = true
      ..fontSize = 14
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center
      ..backColor = '#0D47A1'
      ..fontColor = '#FFFFFF';

    sheet.getRangeByIndex(2, 1).setText('Section: $sectionName');
    final sub1 = sheet.getRangeByName('A2:J2');
    sub1.merge();
    sub1.cellStyle
      ..bold = true
      ..fontSize = 10
      ..backColor = '#1565C0'
      ..fontColor = '#FFFFFF';

    sheet.getRangeByIndex(2, 11).setText('Period: $periodLabel');
    final sub2 = sheet.getRangeByName('K2:${lastCol}2');
    sub2.merge();
    sub2.cellStyle
      ..bold = true
      ..fontSize = 10
      ..backColor = '#1565C0'
      ..fontColor = '#FFFFFF';

    // ── Column headers (row 3) ──────────────────────────────────────────────
    final cols = [
      'Sr#', 'Machine', 'Product', 'Price (Rs.)', 'Shift', 'Date', 'Time',
      'Mfg Date', 'Exp Date', 'Gross Wt (g)', 'P1 (g)', 'P2 (g)', 'P3 (g)',
      'P4 (g)', 'Avg Wt (g)', 'Moisture (%)', 'Wt Status', 'Print', 'Leakage', 'QC',
      ...customCols.map((c) => c.heading)
    ];

    for (var c = 0; c < cols.length; c++) {
      final cell = sheet.getRangeByIndex(3, c + 1);
      cell.setText(cols[c]);
      cell.cellStyle
        ..bold = true
        ..fontSize = 9
        ..hAlign = xlsio.HAlignType.center
        ..backColor = '#1E88E5'
        ..fontColor = '#FFFFFF';
    }

    // ── Data rows (row 4+) ───────────────────────────────────────────────────
    final dmf = DateFormat('dd/MM/yy');
    final tmf = DateFormat('HH:mm');

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final r = 4 + i;
      final bgHex = ExcelHelpers.rowBgHex(e);

      void bg(int col, {bool center = false}) {
        final style = sheet.getRangeByIndex(r, col).cellStyle;
        style.backColor = bgHex;
        if (center) style.hAlign = xlsio.HAlignType.center;
      }

      sheet.getRangeByIndex(r, 1).setNumber((i + 1).toDouble()); bg(1, center: true);
      sheet.getRangeByIndex(r, 2).setNumber(e.machineNumber.toDouble()); bg(2, center: true);
      sheet.getRangeByIndex(r, 3).setText(e.productName); bg(3);
      sheet.getRangeByIndex(r, 4).setNumber(e.price); bg(4, center: true);
      sheet.getRangeByIndex(r, 5).setText(e.shift == 'morning' ? 'Morning' : 'Night'); bg(5, center: true);
      sheet.getRangeByIndex(r, 6).setText(dmf.format(e.createdAt)); bg(6, center: true);
      sheet.getRangeByIndex(r, 7).setText(tmf.format(e.createdAt)); bg(7, center: true);
      sheet.getRangeByIndex(r, 8).setText(dmf.format(e.dateCodingManufacture)); bg(8, center: true);
      sheet.getRangeByIndex(r, 9).setText(dmf.format(e.dateCodingExpiry)); bg(9, center: true);
      sheet.getRangeByIndex(r, 10).setNumber(e.grossWeight); bg(10, center: true);
      if (e.pouch1Weight != null) sheet.getRangeByIndex(r, 11).setNumber(e.pouch1Weight!); bg(11, center: true);
      if (e.pouch2Weight != null) sheet.getRangeByIndex(r, 12).setNumber(e.pouch2Weight!); bg(12, center: true);
      if (e.pouch3Weight != null) sheet.getRangeByIndex(r, 13).setNumber(e.pouch3Weight!); bg(13, center: true);
      if (e.pouch4Weight != null) sheet.getRangeByIndex(r, 14).setNumber(e.pouch4Weight!); bg(14, center: true);

      final avg = e.avgPouchWeight;
      if (avg > 0) sheet.getRangeByIndex(r, 15).setNumber(avg); bg(15, center: true);

      if (e.moistureActual != null) sheet.getRangeByIndex(r, 16).setNumber(e.moistureActual!); bg(16, center: true);

      final wtCell = sheet.getRangeByIndex(r, 17);
      wtCell.setText(ExcelHelpers.statusLabel(e.weightStatus));
      wtCell.cellStyle..bold = true..hAlign = xlsio.HAlignType.center..backColor = ExcelHelpers.statusHex(e.weightStatus);

      final printCell = sheet.getRangeByIndex(r, 18);
      printCell.setText(ExcelHelpers.printLabel(e));
      printCell.cellStyle..bold = true..hAlign = xlsio.HAlignType.center..backColor = ExcelHelpers.statusHex(e.printingStatus == 'okay' ? 'green' : (e.printingColor ?? 'red'));

      final leakCell = sheet.getRangeByIndex(r, 19);
      leakCell.setText(ExcelHelpers.leakLabel(e));
      leakCell.cellStyle..bold = true..hAlign = xlsio.HAlignType.center..backColor = ExcelHelpers.statusHex(e.leakageStatus);

      sheet.getRangeByIndex(r, 20).setText(e.operatorName); bg(20);

      // Custom fields
      for (var cIdx = 0; cIdx < customCols.length; cIdx++) {
        final col = customCols[cIdx];
        final val = e.customFields?[col.id] ?? '';
        final cellCol = 21 + cIdx;

        if (col.type == CustomColumnType.number) {
          final numVal = double.tryParse(val);
          if (numVal != null) {
            sheet.getRangeByIndex(r, cellCol).setNumber(numVal);
          } else {
            sheet.getRangeByIndex(r, cellCol).setText(val);
          }
        } else {
          sheet.getRangeByIndex(r, cellCol).setText(val);
        }
        bg(cellCol, center: col.type == CustomColumnType.number);
      }
    }

    if (entries.isNotEmpty) {
      final lastDataRow = 4 + entries.length - 1;
      sheet.autoFilters.filterRange = sheet.getRangeByName('A3:$lastCol$lastDataRow');
    }

    if (entries.isEmpty) {
      sheet.autoFitColumn(3);
      return;
    }

    // ── Summary row ──────────────────────────────────────────────────────────
    final sr = 4 + entries.length + 1;
    final total = entries.length;
    final green = entries.where((e) => ExcelHelpers.overallStatus(e) == 'green').length;
    final yellow = entries.where((e) => ExcelHelpers.overallStatus(e) == 'yellow').length;
    final red = entries.where((e) => ExcelHelpers.overallStatus(e) == 'red').length;

    void summaryCell(int c1, int c2, String text, String backHex) {
      sheet.getRangeByIndex(sr, c1).setText(text);
      final range = sheet.getRangeByName('${ExcelHelpers.colLetter(c1)}$sr:${ExcelHelpers.colLetter(c2)}$sr');
      range.merge();
      range.cellStyle
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..backColor = backHex;
    }

    summaryCell(1, 5, 'Total: $total entries', '#E3F2FD');
    summaryCell(6, 10, 'Pass: $green (${green * 100 ~/ total}%)', '#C8E6C9');
    summaryCell(11, 15, 'Caution: $yellow (${yellow * 100 ~/ total}%)', '#FFF9C4');
    summaryCell(16, totalCols < 16 ? 20 : totalCols, 'Fail: $red (${red * 100 ~/ total}%)', '#FFCDD2');

    sheet.autoFitColumn(3);
    sheet.autoFitColumn(20);
  }

  static void _buildTempHumiditySheet(
      xlsio.Worksheet sheet,
      List<TempHumidityReport> reports,
      String periodLabel,
      ThThresholdService thresholds,
      ) {
    sheet.name = 'TempHumidity';

    sheet.getRangeByIndex(1, 1).setText('PMA — Temp & Humidity Log');
    final title = sheet.getRangeByName('A1:G1');
    title.merge();
    title.cellStyle
      ..bold = true
      ..fontSize = 14
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center
      ..backColor = '#00695C'
      ..fontColor = '#FFFFFF';

    sheet.getRangeByIndex(2, 1).setText('Period: $periodLabel');
    final sub = sheet.getRangeByName('A2:G2');
    sub.merge();
    sub.cellStyle
      ..bold = true
      ..fontSize = 10
      ..backColor = '#00897B'
      ..fontColor = '#FFFFFF';

    if (reports.isEmpty) {
      final cell = sheet.getRangeByIndex(4, 1);
      cell.setText('No Temp & Humidity readings recorded for this period.');
      cell.cellStyle..bold = true..fontColor = '#616161';
      return;
    }

    final dmf = DateFormat('dd MMM yyyy');
    var r = 4;
    for (final rep in reports) {
      final secName = Sections.byId(rep.sectionId).name;
      final shift = rep.shift == 'morning' ? 'Morning' : 'Night';
      final threshold = thresholds.forSection(rep.sectionId);

      sheet.getRangeByIndex(r, 1).setText('$secName  ·  ${dmf.format(rep.date)}  ·  $shift');
      final banner = sheet.getRangeByName('A$r:G$r');
      banner.merge();
      banner.cellStyle..bold = true..fontSize = 10..backColor = '#00897B'..fontColor = '#FFFFFF';
      r++;

      const cols = ['Time', 'Temp (°C)', 'Humidity (%)', 'Verified by QC', 'Remarks'];
      for (var c = 0; c < cols.length; c++) {
        final cell = sheet.getRangeByIndex(r, c + 1);
        cell.setText(cols[c]);
        cell.cellStyle..bold = true..fontSize = 9..hAlign = xlsio.HAlignType.center..backColor = '#26A69A'..fontColor = '#FFFFFF';
      }
      r++;

      final temps = <double>[];
      final hums = <double>[];

      for (final row in rep.rows) {
        if (row.time.trim().isEmpty && row.temperature == null && row.humidity == null) {
          continue;
        }
        sheet.getRangeByIndex(r, 1).setText(row.time);

        if (row.temperature != null) {
          final cell = sheet.getRangeByIndex(r, 2);
          cell.setNumber(row.temperature!);
          cell.cellStyle.backColor = ExcelHelpers.statusHex(threshold.classifyTemp(row.temperature!));
          temps.add(row.temperature!);
        }
        if (row.humidity != null) {
          final cell = sheet.getRangeByIndex(r, 3);
          cell.setNumber(row.humidity!);
          cell.cellStyle.backColor = ExcelHelpers.statusHex(threshold.classifyHumidity(row.humidity!));
          hums.add(row.humidity!);
        }
        sheet.getRangeByIndex(r, 4).setText(row.verifiedByQc);
        sheet.getRangeByIndex(r, 5).setText(row.remarks);
        r++;
      }

      double avg(List<double> v) => v.isEmpty ? 0 : double.parse((v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1));
      double mx(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);

      void sumCell(int c, String text, [String? backHex]) {
        final cell = sheet.getRangeByIndex(r, c);
        cell.setText(text);
        cell.cellStyle..bold = true..backColor = backHex ?? '#E0F2F1';
      }

      final dayAvgT = avg(temps), dayMaxT = mx(temps);
      final dayAvgH = avg(hums), dayMaxH = mx(hums);

      sumCell(1, 'Avg / Max');
      sumCell(2, temps.isEmpty ? '—' : '$dayAvgT / $dayMaxT', temps.isEmpty ? null : ExcelHelpers.statusHex(threshold.classifyTemp(dayMaxT)));
      sumCell(3, hums.isEmpty ? '—' : '$dayAvgH / $dayMaxH', hums.isEmpty ? null : ExcelHelpers.statusHex(threshold.classifyHumidity(dayMaxH)));
      sumCell(4, '');
      sumCell(5, rep.preparedBy.isEmpty ? '' : 'Prepared by: ${rep.preparedBy}');
      r += 2;
    }
    for (var c = 1; c <= 5; c++) {
      sheet.autoFitColumn(c);
    }
  }
}