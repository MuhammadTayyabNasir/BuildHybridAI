import '../../models/packing_entry_model.dart';

class ExcelHelpers {
  /// Excel sheet names cannot contain certain characters and must be <= 31 chars.
  static String safeSheetName(String name) {
    var s = name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (s.isEmpty) s = 'Section';
    if (s.length > 31) s = s.substring(0, 31);
    return s;
  }

  /// Converts a 1-based column index to an Excel column letter (e.g., 1 -> A, 27 -> AA)
  static String colLetter(int index) {
    var i = index;
    var s = '';
    while (i > 0) {
      final rem = (i - 1) % 26;
      s = String.fromCharCode(65 + rem) + s;
      i = (i - 1) ~/ 26;
    }
    return s;
  }

  static String overallStatus(PackingEntryModel e) {
    final ss = [
      e.weightStatus,
      if (e.moistureStatus != 'na') e.moistureStatus,
      e.printingStatus == 'okay' ? 'green' : (e.printingColor ?? 'red'),
      e.leakageStatus,
    ];
    if (ss.any((s) => s == 'red')) return 'red';
    if (ss.any((s) => s == 'yellow')) return 'yellow';
    return 'green';
  }

  static String rowBgHex(PackingEntryModel e) {
    final s = overallStatus(e);
    return s == 'red'
        ? '#FFCDD2'
        : s == 'yellow'
        ? '#FFF9C4'
        : '#C8E6C9';
  }

  static String statusLabel(String s) => s == 'green'
      ? 'PASS'
      : s == 'yellow'
      ? 'WARN'
      : 'FAIL';

  static String statusHex(String s) => s == 'green'
      ? '#C8E6C9'
      : s == 'yellow'
      ? '#FFF9C4'
      : '#FFCDD2';

  static String printLabel(PackingEntryModel e) {
    if (e.printingStatus == 'okay') return 'OK';
    final p = [e.printingStatus.toUpperCase()];
    if (e.printingRemarks?.isNotEmpty == true) p.add(e.printingRemarks!);
    return p.join(' — ');
  }

  static String leakLabel(PackingEntryModel e) {
    if (e.leakageStatus == 'green') return 'OK';
    final base = e.leakageStatus == 'minor' ? 'Minor' : 'Major';
    if (e.leakageRemarks?.isNotEmpty == true) {
      return '$base — ${e.leakageRemarks}';
    }
    return base;
  }
}
