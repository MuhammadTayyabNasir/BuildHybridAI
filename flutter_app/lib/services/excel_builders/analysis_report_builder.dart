import 'dart:io';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:syncfusion_officechart/officechart.dart' as officechart;

import '../../core/constants/sections.dart';
import '../../models/packing_entry_model.dart';
import '../../models/custom_column_model.dart';
import 'excel_helpers.dart';

class AnalysisReportBuilder {
  static Future<String> build({
    required DateTime from,
    required DateTime to,
    required List<PackingEntryModel> entries,
    required List<CustomColumn> customCols,
    required String downloadDir,
  }) async {
    final isSinglePeriod = from.year == to.year && from.month == to.month && from.day == to.day;
    final periodLabel = isSinglePeriod
        ? DateFormat('dd MMM yyyy').format(from)
        : '${DateFormat('dd MMM').format(from)} – ${DateFormat('dd MMM yyyy').format(to)}';

    final wb = xlsio.Workbook();
    try {
      _xOverviewSheet(wb.worksheets[0], entries, periodLabel);
      _xBySectionSheet(wb.worksheets.addWithName('BySection'), entries, periodLabel);
      _xWeeklyBySectionSheet(wb.worksheets.addWithName('WeeklyBySection'), entries, periodLabel);
      _xIssueTypeSheet(wb.worksheets.addWithName('IssueTypes'), entries, periodLabel);
      _xSupervisorSheet(wb.worksheets.addWithName('BySupervisor'), entries, periodLabel);
      _xFailureLogSheet(wb.worksheets.addWithName('FailureLog'), entries, periodLabel, customCols);
      _xTrendSheet(wb.worksheets.addWithName('DailyTrend'), entries, periodLabel);

      final bytes = wb.saveAsStream();
      final sep = Platform.pathSeparator;
      final stamp = isSinglePeriod
          ? DateFormat('yyyy-MM-dd').format(from)
          : '${DateFormat('yyyy-MM-dd').format(from)}_to_${DateFormat('yyyy-MM-dd').format(to)}';

      final path = '$downloadDir${sep}4U_Analysis_$stamp.xlsx';
      await File(path).writeAsBytes(bytes);
      return path;
    } finally {
      wb.dispose();
    }
  }

  static void _addColumnChart(
      officechart.ChartCollection charts,
      xlsio.Worksheet sheet, {
        required String title,
        required String categoryRef,
        required List<(String, String)> series,
        required int topRow,
        required int leftCol,
        required int bottomRow,
        required int rightCol,
      }) {
    final chart = charts.add();
    chart.chartType = officechart.ExcelChartType.column;
    chart.chartTitle = title;
    final cat = sheet.getRangeByName(categoryRef);
    var idx = 0;
    for (final (headerRef, valuesRef) in series) {
      final s = chart.series.add();
      s.index = idx++;
      s.isDefaultName = true;
      s.nameOrFormula = sheet.getRangeByName(headerRef).addressGlobal;
      s.categoryLabels = cat;
      s.values = sheet.getRangeByName(valuesRef);
    }
    chart.topRow = topRow;
    chart.leftColumn = leftCol;
    chart.bottomRow = bottomRow;
    chart.rightColumn = rightCol;
  }

  static void _linkCell(xlsio.Worksheet sheet, int row, int col, String text) {
    sheet.hyperlinks.add(
      sheet.getRangeByIndex(row, col),
      xlsio.HyperlinkType.workbook,
      'FailureLog!A1',
      'Open the traceable Failure Log (filter to this row)',
      text,
    );
  }

  static void _xOverviewSheet(xlsio.Worksheet sheet, List<PackingEntryModel> entries, String periodLabel) {
    sheet.name = 'Overview';
    _xSheetHeader(sheet, 'QC Overview', periodLabel, 12);
    sheet.getRangeByIndex(3, 1).setText('Section');
    sheet.getRangeByIndex(3, 2).setText('Pass');
    sheet.getRangeByIndex(3, 3).setText('Warning');
    sheet.getRangeByIndex(3, 4).setText('Fail');
    sheet.getRangeByName('A3:D3').cellStyle.bold = true;

    var row = 4;
    var totG = 0, totY = 0, totR = 0;
    for (final sec in Sections.all) {
      final se = entries.where((e) => e.section == sec.id).toList();
      if (se.isEmpty) continue;
      final g = se.where((e) => ExcelHelpers.overallStatus(e) == 'green').length;
      final y = se.where((e) => ExcelHelpers.overallStatus(e) == 'yellow').length;
      final r = se.where((e) => ExcelHelpers.overallStatus(e) == 'red').length;

      sheet.getRangeByIndex(row, 1).setText(sec.name);
      _linkCell(sheet, row, 1, sec.name);
      sheet.getRangeByIndex(row, 2).setNumber(g.toDouble());
      sheet.getRangeByIndex(row, 3).setNumber(y.toDouble());
      sheet.getRangeByIndex(row, 4).setNumber(r.toDouble());
      totG += g;
      totY += y;
      totR += r;
      row++;
    }
    final lastRow = row - 1;
    if (lastRow < 4) {
      sheet.getRangeByIndex(4, 1).setText('No entries for the selected period.');
      return;
    }
    final charts = officechart.ChartCollection(sheet);
    _addColumnChart(charts, sheet, title: 'Quality by Section', categoryRef: 'A4:A$lastRow', series: [('B3', 'B4:B$lastRow'), ('C3', 'C4:C$lastRow'), ('D3', 'D4:D$lastRow')], topRow: row + 1, leftCol: 1, bottomRow: row + 16, rightCol: 6);

    sheet.getRangeByIndex(3, 6).setText('Result');
    sheet.getRangeByIndex(3, 7).setText('Count');
    sheet.getRangeByIndex(4, 6).setText('Pass');
    sheet.getRangeByIndex(4, 7).setNumber(totG.toDouble());
    sheet.getRangeByIndex(5, 6).setText('Warning');
    sheet.getRangeByIndex(5, 7).setNumber(totY.toDouble());
    sheet.getRangeByIndex(6, 6).setText('Fail');
    sheet.getRangeByIndex(6, 7).setNumber(totR.toDouble());

    final pie = charts.add();
    pie.chartType = officechart.ExcelChartType.pie;
    pie.chartTitle = 'Overall Result';
    final pieSeries = pie.series.add();
    pieSeries.index = 0;
    pieSeries.isDefaultName = true;
    pieSeries.nameOrFormula = sheet.getRangeByName('F3').addressGlobal;
    pieSeries.categoryLabels = sheet.getRangeByName('F4:F6');
    pieSeries.values = sheet.getRangeByName('G4:G6');
    pie.topRow = row + 1;
    pie.leftColumn = 7;
    pie.bottomRow = row + 16;
    pie.rightColumn = 12;
    sheet.charts = charts;
  }

  static void _xIssueTypeSheet(xlsio.Worksheet sheet, List<PackingEntryModel> entries, String periodLabel) {
    _xSheetHeader(sheet, 'Failures by Issue Type', periodLabel, 9);
    sheet.getRangeByIndex(3, 1).setText('Section');
    sheet.getRangeByIndex(3, 2).setText('Weight');
    sheet.getRangeByIndex(3, 3).setText('Moisture');
    sheet.getRangeByIndex(3, 4).setText('Printing');
    sheet.getRangeByIndex(3, 5).setText('Leakage');
    sheet.getRangeByName('A3:E3').cellStyle.bold = true;

    var row = 4;
    for (final sec in Sections.all) {
      final se = entries.where((e) => e.section == sec.id).toList();
      if (se.isEmpty) continue;
      sheet.getRangeByIndex(row, 1).setText(sec.name);
      _linkCell(sheet, row, 1, sec.name);
      sheet.getRangeByIndex(row, 2).setNumber(se.where((e) => e.weightStatus == 'red').length.toDouble());
      sheet.getRangeByIndex(row, 3).setNumber(se.where((e) => e.moistureStatus == 'red').length.toDouble());
      sheet.getRangeByIndex(row, 4).setNumber(se.where((e) => e.printingStatus == 'not_okay').length.toDouble());
      sheet.getRangeByIndex(row, 5).setNumber(se.where((e) => e.leakageStatus == 'red').length.toDouble());
      row++;
    }
    final lastRow = row - 1;
    if (lastRow < 4) {
      sheet.getRangeByIndex(4, 1).setText('No entries for the selected period.');
      return;
    }
    final charts = officechart.ChartCollection(sheet);
    _addColumnChart(charts, sheet, title: 'Failures by Issue Type & Section', categoryRef: 'A4:A$lastRow', series: [('B3', 'B4:B$lastRow'), ('C3', 'C4:C$lastRow'), ('D3', 'D4:D$lastRow'), ('E3', 'E4:E$lastRow')], topRow: row + 1, leftCol: 1, bottomRow: row + 18, rightCol: 9);
    sheet.charts = charts;
  }

  static void _xSupervisorSheet(xlsio.Worksheet sheet, List<PackingEntryModel> entries, String periodLabel) {
    _xSheetHeader(sheet, 'Quality by Supervisor (QC)', periodLabel, 11);
    final byQc = <String, List<PackingEntryModel>>{};
    for (final e in entries) {
      final qc = e.operatorName.trim().isEmpty ? 'Unknown' : e.operatorName.trim();
      byQc.putIfAbsent(qc, () => []).add(e);
    }
    final qcs = byQc.keys.toList()..sort();

    sheet.getRangeByIndex(3, 1).setText('QC / Supervisor');
    sheet.getRangeByIndex(3, 2).setText('Entries');
    sheet.getRangeByIndex(3, 3).setText('Pass');
    sheet.getRangeByIndex(3, 4).setText('Fail');
    sheet.getRangeByIndex(3, 5).setText('Pass %');
    sheet.getRangeByName('A3:E3').cellStyle.bold = true;

    sheet.getRangeByIndex(3, 7).setText('QC');
    sheet.getRangeByIndex(3, 8).setText('Weight');
    sheet.getRangeByIndex(3, 9).setText('Moisture');
    sheet.getRangeByIndex(3, 10).setText('Printing');
    sheet.getRangeByIndex(3, 11).setText('Leakage');
    sheet.getRangeByName('G3:K3').cellStyle.bold = true;

    var row = 4;
    for (final qc in qcs) {
      final list = byQc[qc]!;
      final n = list.length;
      final pass = list.where((e) => ExcelHelpers.overallStatus(e) == 'green').length;
      final fail = list.where((e) => ExcelHelpers.overallStatus(e) == 'red').length;
      sheet.getRangeByIndex(row, 1).setText(qc);
      _linkCell(sheet, row, 1, qc);
      sheet.getRangeByIndex(row, 2).setNumber(n.toDouble());
      sheet.getRangeByIndex(row, 3).setNumber(pass.toDouble());
      sheet.getRangeByIndex(row, 4).setNumber(fail.toDouble());
      sheet.getRangeByIndex(row, 5).setNumber(n == 0 ? 0 : double.parse((pass / n * 100).toStringAsFixed(1)));

      sheet.getRangeByIndex(row, 7).setText(qc);
      sheet.getRangeByIndex(row, 8).setNumber(list.where((e) => e.weightStatus == 'red').length.toDouble());
      sheet.getRangeByIndex(row, 9).setNumber(list.where((e) => e.moistureStatus == 'red').length.toDouble());
      sheet.getRangeByIndex(row, 10).setNumber(list.where((e) => e.printingStatus == 'not_okay').length.toDouble());
      sheet.getRangeByIndex(row, 11).setNumber(list.where((e) => e.leakageStatus == 'red').length.toDouble());
      row++;
    }
    final lastRow = row - 1;
    if (lastRow < 4) {
      sheet.getRangeByIndex(4, 1).setText('No entries for the selected period.');
      return;
    }
    final charts = officechart.ChartCollection(sheet);
    _addColumnChart(charts, sheet, title: 'Issue Types by Supervisor (QC)', categoryRef: 'G4:G$lastRow', series: [('H3', 'H4:H$lastRow'), ('I3', 'I4:I$lastRow'), ('J3', 'J4:J$lastRow'), ('K3', 'K4:K$lastRow')], topRow: row + 1, leftCol: 1, bottomRow: row + 18, rightCol: 9);
    sheet.charts = charts;
  }

  static void _xFailureLogSheet(
      xlsio.Worksheet sheet,
      List<PackingEntryModel> entries,
      String periodLabel,
      List<CustomColumn> customCols,
      ) {
    final totalCols = 9 + customCols.length;
    _xSheetHeader(
      sheet,
      'Failure Log (traceable)',
      periodLabel,
      totalCols,
      note: 'One row per failure. Use the filter arrows to slice by section / QC / issue / date.',
    );

    final cols = [
      'Date', 'Time', 'Section', 'Machine', 'Product', 'Shift', 'QC / Supervisor', 'Issues', 'Remarks',
      ...customCols.map((c) => c.heading)
    ];

    for (var i = 0; i < cols.length; i++) {
      sheet.getRangeByIndex(3, i + 1).setText(cols[i]);
    }
    sheet.getRangeByName('A3:${ExcelHelpers.colLetter(totalCols)}3').cellStyle.bold = true;

    final fails = entries.where((e) => e.weightStatus == 'red' || e.moistureStatus == 'red' || e.printingStatus == 'not_okay' || e.leakageStatus == 'red').toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (fails.isEmpty) {
      sheet.getRangeByIndex(4, 1).setText('No failures in the selected period.');
      return;
    }

    final dmf = DateFormat('dd/MM/yyyy');
    final tmf = DateFormat('HH:mm');
    var r = 4;
    for (final e in fails) {
      final issues = <String>[
        if (e.weightStatus == 'red') 'Weight',
        if (e.moistureStatus == 'red') 'Moisture',
        if (e.printingStatus == 'not_okay') 'Printing',
        if (e.leakageStatus == 'red') 'Leakage',
      ];
      final remarks = [
        if (e.printingRemarks?.isNotEmpty == true) 'Print: ${e.printingRemarks}',
        if (e.leakageRemarks?.isNotEmpty == true) 'Leak: ${e.leakageRemarks}',
      ].join(' · ');
      sheet.getRangeByIndex(r, 1).setText(dmf.format(e.createdAt));
      sheet.getRangeByIndex(r, 2).setText(tmf.format(e.createdAt));
      sheet.getRangeByIndex(r, 3).setText(Sections.byId(e.section).name);
      sheet.getRangeByIndex(r, 4).setNumber(e.machineNumber.toDouble());
      sheet.getRangeByIndex(r, 5).setText(e.price > 0 ? '${e.productName} (Rs ${e.price.toStringAsFixed(0)})' : e.productName);
      sheet.getRangeByIndex(r, 6).setText(e.shift == 'morning' ? 'Morning' : 'Night');
      sheet.getRangeByIndex(r, 7).setText(e.operatorName.trim().isEmpty ? 'Unknown' : e.operatorName.trim());
      sheet.getRangeByIndex(r, 8).setText(issues.join(', '));
      sheet.getRangeByIndex(r, 9).setText(remarks);

      for (var cIdx = 0; cIdx < customCols.length; cIdx++) {
        final col = customCols[cIdx];
        final val = e.customFields?[col.id] ?? '';
        final targetCol = 10 + cIdx;
        if (col.type == CustomColumnType.number) {
          final numVal = double.tryParse(val);
          if (numVal != null) {
            sheet.getRangeByIndex(r, targetCol).setNumber(numVal);
          } else {
            sheet.getRangeByIndex(r, targetCol).setText(val);
          }
        } else {
          sheet.getRangeByIndex(r, targetCol).setText(val);
        }
      }
      r++;
    }

    sheet.autoFilters.filterRange = sheet.getRangeByName('A3:${ExcelHelpers.colLetter(totalCols)}${r - 1}');

    for (var c = 1; c <= totalCols; c++) {
      sheet.autoFitColumn(c);
    }
  }

  static void _xTrendSheet(xlsio.Worksheet sheet, List<PackingEntryModel> entries, String periodLabel) {
    _xSheetHeader(sheet, 'Daily Pass-Rate Trend', periodLabel, 8);
    sheet.getRangeByIndex(3, 1).setText('Date');
    sheet.getRangeByIndex(3, 2).setText('Pass Rate %');
    sheet.getRangeByName('A3:B3').cellStyle.bold = true;

    final byDate = <String, List<PackingEntryModel>>{};
    for (final e in entries) {
      byDate.putIfAbsent(DateFormat('yyyy-MM-dd').format(e.createdAt), () => []).add(e);
    }
    final dates = byDate.keys.toList()..sort();
    var tr = 4;
    for (final d in dates) {
      final list = byDate[d]!;
      final pass = list.where((e) => ExcelHelpers.overallStatus(e) == 'green').length;
      final rate = list.isEmpty ? 0.0 : pass / list.length * 100;
      sheet.getRangeByIndex(tr, 1).setText(DateFormat('dd/MM').format(DateTime.parse(d)));
      sheet.getRangeByIndex(tr, 2).setNumber(double.parse(rate.toStringAsFixed(1)));
      tr++;
    }
    final tLast = tr - 1;
    if (tLast < 4) return;
    final charts = officechart.ChartCollection(sheet);
    _addColumnChart(charts, sheet, title: 'Daily Pass Rate %', categoryRef: 'A4:A$tLast', series: [('B3', 'B4:B$tLast')], topRow: tr + 1, leftCol: 1, bottomRow: tr + 16, rightCol: 8);
    sheet.autoFilters.filterRange = sheet.getRangeByName('A3:K3');
    sheet.charts = charts;
    for (var c = 1; c <= 2; c++) {
      sheet.autoFitColumn(c);
    }
  }

  static void _xWeeklyBySectionSheet(xlsio.Worksheet sheet, List<PackingEntryModel> allEntries, String periodLabel) {
    _xSheetHeader(sheet, 'WEEKLY BY SECTION — Weak Link', periodLabel, 14, note: 'Scroll down for each section. Every metric compared week-over-week. Yellow = warning, Red = fail. Lower bars = better.');

    if (allEntries.isEmpty) {
      sheet.getRangeByIndex(4, 1).setText('No entries for the selected period.');
      return;
    }

    final charts = officechart.ChartCollection(sheet);
    final metrics = <(String, String Function(PackingEntryModel))>[
      ('Weight Variation', (e) => e.weightStatus),
      ('Leakage', (e) => e.leakageStatus),
      ('Printing', (e) => e.printingStatus == 'okay' ? 'green' : (e.printingColor == 'yellow' ? 'yellow' : 'red')),
      ('Moisture', (e) => e.moistureStatus),
    ];

    var row = 4;
    for (final sec in Sections.all) {
      final entries = allEntries.where((e) => e.section == sec.id).toList();
      final weeks = _byWeek(entries);

      sheet.getRangeByIndex(row, 1).setText('◆  ${sec.name.toUpperCase()}');
      final banner = sheet.getRangeByName('A$row:N$row');
      banner.merge();
      banner.cellStyle.bold = true;
      banner.cellStyle.fontSize = 12;
      banner.cellStyle.backColor = '#37474F';
      banner.cellStyle.fontColor = '#FFFFFF';
      row += 1;

      if (weeks.isEmpty) {
        sheet.getRangeByIndex(row, 1).setText('No entries for ${sec.name} in the selected period.');
        row += 2;
        continue;
      }
      for (final (name, cls) in metrics) {
        row = _xWeeklyMetricBlock(sheet, charts, row, name, weeks, cls);
      }
      row += 1;
    }
    sheet.charts = charts;

    for (var c = 1; c <= 5; c++) {
      sheet.autoFitColumn(c);
    }
  }

  static int _xWeeklyMetricBlock(xlsio.Worksheet sheet, officechart.ChartCollection charts, int startRow, String metricName, List<({DateTime start, int week, List<PackingEntryModel> entries})> weeks, String Function(PackingEntryModel) cls) {
    sheet.getRangeByIndex(startRow, 1).setText('$metricName — weekly defect %');
    final titleRange = sheet.getRangeByName('A$startRow:E$startRow');
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.backColor = '#0D47A1';
    titleRange.cellStyle.fontColor = '#FFFFFF';

    final hdr = startRow + 1;
    const heads = ['Week', 'Green %', 'Yellow %', 'Red %', 'Entries'];
    for (var c = 0; c < heads.length; c++) {
      sheet.getRangeByIndex(hdr, c + 1).setText(heads[c]);
    }
    sheet.getRangeByName('A$hdr:E$hdr').cellStyle.bold = true;
    sheet.getRangeByName('B$hdr').cellStyle.backColor = '#C8E6C9';
    sheet.getRangeByName('C$hdr').cellStyle.backColor = '#FFF59D';
    sheet.getRangeByName('D$hdr').cellStyle.backColor = '#EF9A9A';

    final dmf = DateFormat('dd MMM');
    var r = hdr + 1;
    final firstData = r;
    for (final w in weeks) {
      final list = w.entries.where((e) => cls(e) != 'na').toList();
      final tot = list.length;
      final g = list.where((e) => cls(e) == 'green').length;
      final y = list.where((e) => cls(e) == 'yellow').length;
      final rd = list.where((e) => cls(e) == 'red').length;
      final end = w.start.add(const Duration(days: 6));
      sheet.getRangeByIndex(r, 1).setText('Wk ${w.week} (${dmf.format(w.start)}–${dmf.format(end)})');
      double pct(int n) => tot == 0 ? 0 : double.parse((n / tot * 100).toStringAsFixed(2));
      sheet.getRangeByIndex(r, 2).setNumber(pct(g));
      sheet.getRangeByIndex(r, 3).setNumber(pct(y));
      sheet.getRangeByIndex(r, 4).setNumber(pct(rd));
      sheet.getRangeByIndex(r, 5).setNumber(tot.toDouble());
      sheet.getRangeByName('B$r:D$r').numberFormat = '0.00';
      r++;
    }
    final lastData = r - 1;

    _addColumnChart(charts, sheet, title: '$metricName (Yellow=warning, Red=fail)', categoryRef: 'A$firstData:A$lastData', series: [('C$hdr', 'C$firstData:C$lastData'), ('D$hdr', 'D$firstData:D$lastData')], topRow: startRow, leftCol: 7, bottomRow: startRow + 15, rightCol: 14);

    return (lastData > startRow + 15 ? lastData : startRow + 15) + 2;
  }

  static void _xBySectionSheet(xlsio.Worksheet sheet, List<PackingEntryModel> entries, String periodLabel) {
    _xSheetHeader(sheet, 'BY SECTION — Weak Link', periodLabel, 15, note: 'Each metric across all sections. Yellow = warning, Red = fail. Weak Link = machine with the most defects for that metric.');

    if (entries.isEmpty) {
      sheet.getRangeByIndex(4, 1).setText('No entries for the selected period.');
      return;
    }

    final charts = officechart.ChartCollection(sheet);
    var row = 4;
    final metrics = <(String, String Function(PackingEntryModel))>[
      ('Weight Variation', (e) => e.weightStatus),
      ('Leakage', (e) => e.leakageStatus),
      ('Printing', (e) => e.printingStatus == 'okay' ? 'green' : (e.printingColor == 'yellow' ? 'yellow' : 'red')),
      ('Moisture', (e) => e.moistureStatus),
    ];
    for (final (name, cls) in metrics) {
      row = _xBySectionMetricBlock(sheet, charts, row, name, entries, cls);
    }
    sheet.charts = charts;

    for (var c = 1; c <= 6; c++) {
      sheet.autoFitColumn(c);
    }
  }

  static int _xBySectionMetricBlock(xlsio.Worksheet sheet, officechart.ChartCollection charts, int startRow, String metricName, List<PackingEntryModel> entries, String Function(PackingEntryModel) cls) {
    sheet.getRangeByIndex(startRow, 1).setText('$metricName — by section');
    final titleRange = sheet.getRangeByName('A$startRow:F$startRow');
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.backColor = '#0D47A1';
    titleRange.cellStyle.fontColor = '#FFFFFF';

    final hdr = startRow + 1;
    const heads = ['Section', 'Green %', 'Yellow %', 'Red %', 'Entries', 'Weak Link (machine)'];
    for (var c = 0; c < heads.length; c++) {
      sheet.getRangeByIndex(hdr, c + 1).setText(heads[c]);
    }
    sheet.getRangeByName('A$hdr:F$hdr').cellStyle.bold = true;
    sheet.getRangeByName('B$hdr').cellStyle.backColor = '#C8E6C9';
    sheet.getRangeByName('C$hdr').cellStyle.backColor = '#FFF59D';
    sheet.getRangeByName('D$hdr').cellStyle.backColor = '#EF9A9A';

    var r = hdr + 1;
    final firstData = r;
    for (final sec in Sections.all) {
      final list = entries.where((e) => e.section == sec.id && cls(e) != 'na').toList();
      final tot = list.length;
      final g = list.where((e) => cls(e) == 'green').length;
      final y = list.where((e) => cls(e) == 'yellow').length;
      final rd = list.where((e) => cls(e) == 'red').length;
      double pct(int n) => tot == 0 ? 0 : double.parse((n / tot * 100).toStringAsFixed(2));

      sheet.getRangeByIndex(r, 1).setText(sec.name);
      sheet.getRangeByIndex(r, 2).setNumber(pct(g));
      sheet.getRangeByIndex(r, 3).setNumber(pct(y));
      sheet.getRangeByIndex(r, 4).setNumber(pct(rd));
      sheet.getRangeByIndex(r, 5).setNumber(tot.toDouble());
      sheet.getRangeByIndex(r, 6).setText(_weakLinkMachine(list, cls));
      sheet.getRangeByName('B$r:D$r').numberFormat = '0.00';
      r++;
    }
    final lastData = r - 1;

    _addColumnChart(charts, sheet, title: '$metricName by section (Yellow=warning, Red=fail)', categoryRef: 'A$firstData:A$lastData', series: [('C$hdr', 'C$firstData:C$lastData'), ('D$hdr', 'D$firstData:D$lastData')], topRow: startRow, leftCol: 8, bottomRow: startRow + 12, rightCol: 15);

    return (lastData > startRow + 12 ? lastData : startRow + 12) + 2;
  }

  static String _weakLinkMachine(List<PackingEntryModel> list, String Function(PackingEntryModel) cls) {
    final defects = <int, int>{};
    for (final e in list) {
      final s = cls(e);
      if (s == 'yellow' || s == 'red') {
        defects[e.machineNumber] = (defects[e.machineNumber] ?? 0) + 1;
      }
    }
    if (defects.isEmpty) return '—';
    final worst = defects.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return 'M-${worst.key} (${worst.value} def)';
  }

  static List<({DateTime start, int week, List<PackingEntryModel> entries})> _byWeek(List<PackingEntryModel> entries) {
    final map = <DateTime, List<PackingEntryModel>>{};
    for (final e in entries) {
      final d = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      map.putIfAbsent(monday, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) (start: k, week: _isoWeek(k), entries: map[k]!)];
  }

  static int _isoWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final dayOfYear = int.parse(DateFormat('D').format(d));
    final woy = (dayOfYear - d.weekday + 10) ~/ 7;
    if (woy < 1) return _isoWeek(DateTime(date.year - 1, 12, 31));
    if (woy > 52) {
      final dec31 = DateTime(date.year, 12, 31);
      final last = (int.parse(DateFormat('D').format(dec31)) - dec31.weekday + 10) ~/ 7;
      if (woy > last) return 1;
    }
    return woy;
  }

  static void _xSheetHeader(xlsio.Worksheet sheet, String title, String periodLabel, int lastColIndex, {String? note}) {
    final lastCol = ExcelHelpers.colLetter(lastColIndex);
    sheet.getRangeByIndex(1, 1).setText('REMOXIN ENTERPRISES — $title');
    final tr = sheet.getRangeByName('A1:${lastCol}1');
    tr.merge();
    tr.cellStyle.bold = true;
    tr.cellStyle.fontSize = 13;
    tr.cellStyle.backColor = '#0D47A1';
    tr.cellStyle.fontColor = '#FFFFFF';
    tr.cellStyle.hAlign = xlsio.HAlignType.center;

    sheet.getRangeByIndex(2, 1).setText('Period: $periodLabel${note == null ? '' : '   ·   $note'}');
    final pr = sheet.getRangeByName('A2:${lastCol}2');
    pr.merge();
    pr.cellStyle.bold = true;
    pr.cellStyle.backColor = '#E3F2FD';
  }
}