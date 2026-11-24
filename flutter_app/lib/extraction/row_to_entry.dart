import '../core/utils/status_utils.dart';
import '../models/machine_model.dart';
import '../models/packing_entry_model.dart';
import '../models/product_model.dart';
import 'extracted_form.dart';

/// Turns reviewed rows into normal packing entries. Statuses are computed
/// with the same [StatusUtils] rules as the manual form, never by the model.
class RowToEntry {
  RowToEntry({
    required this.sectionId,
    required this.shift,
    required this.products,
    required this.machines,
    required this.operatorId,
    required this.operatorName,
    required this.sourceLabel,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String sectionId;

  /// 'morning' | 'night'
  final String shift;
  final List<ProductModel> products;
  final List<MachineModel> machines;
  final String operatorId;
  final String operatorName;

  /// e.g. 'pdf:cloud' or 'photo:on-device'
  final String sourceLabel;
  final DateTime Function() _clock;

  static String normShift(String raw) {
    final l = raw.trim().toLowerCase();
    if (l == 'b' || l.contains('night') || l.contains('raat') || l.contains('even')) return 'night';
    return 'morning';
  }

  /// Dates as written on the sheet: 30-5-26, 30.05.2026, 30/5/26.
  static List<DateTime> parseDates(String raw) {
    final out = <DateTime>[];
    for (final m in RegExp(r'(\d{1,2})\s*[-./]\s*(\d{1,2})\s*[-./]\s*(\d{2,4})').allMatches(raw)) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (d < 1 || d > 31 || mo < 1 || mo > 12) continue;
      out.add(DateTime(y, mo, d));
    }
    return out;
  }

  ProductModel? matchProduct(String name, double? price) {
    final inSection = products.where((p) => p.section == sectionId && p.isActive).toList();
    String key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final k = key(name);
    if (k.length >= 3) {
      for (final p in inSection) {
        final pk = key(p.name);
        if (pk.contains(k) || k.contains(pk)) return p;
      }
    }
    if (price != null) {
      final byPrice = inSection.where((p) => p.price == price).toList();
      if (byPrice.length == 1) return byPrice.single;
    }
    return null;
  }

  PackingEntryModel convert(ExtractedPage header, ExtractedRow row) {
    final now = _clock();
    final price = double.tryParse(row[FormColumn.price]);
    final productName = row[FormColumn.product].isNotEmpty ? row[FormColumn.product] : header.product;
    final product = matchProduct(productName, price);
    final machineNo = int.tryParse(row[FormColumn.machine].replaceAll(RegExp(r'^0+(?=\d)'), '')) ?? 0;
    final machine = machines
        .where((m) => m.section == sectionId && m.number == machineNo)
        .firstOrNull;

    final sheetDay = parseDates(header.date).firstOrNull;
    final coding = parseDates(row[FormColumn.dateCoding]);
    final mfg = coding.isNotEmpty ? coding.first : (sheetDay ?? now);
    final exp = coding.length > 1
        ? coding[1]
        : mfg.add(Duration(days: product?.expiryDays ?? 120));

    final w = row.weights;
    double? pw(int i) => i < w.length ? w[i] : null;
    final moisture = double.tryParse(row[FormColumn.moisture]);
    final printing = row[FormColumn.printing].toLowerCase();
    final printingOk = printing.isEmpty ||
        RegExp(r'^(ok|okay|o\.?k\.?|✓|√|good|theek)$').hasMatch(printing.trim());

    final created = sheetDay == null
        ? now
        : DateTime(sheetDay.year, sheetDay.month, sheetDay.day, now.hour, now.minute);
    return PackingEntryModel(
      id: '',
      machineId: machine?.id ?? '',
      machineNumber: machineNo,
      section: sectionId,
      productId: product?.id ?? '',
      productName: product?.name ?? productName,
      price: price ?? product?.price ?? 0,
      shift: shift,
      operatorId: operatorId,
      operatorName: operatorName,
      dateCodingManufacture: mfg,
      dateCodingExpiry: exp,
      grossWeight: product?.weightGrams ?? (w.isEmpty ? 0 : w.reduce((a, b) => a + b) / w.length),
      pouch1Weight: pw(0),
      pouch2Weight: pw(1),
      pouch3Weight: pw(2),
      pouch4Weight: pw(3),
      moistureIdeal: product?.moistureMax,
      moistureActual: moisture,
      weightStatus: product == null
          ? 'na'
          : StatusUtils.weightStatusOfPouches(
              [pw(0), pw(1), pw(2), pw(3)],
              product.weightGrams,
              toleranceGreen: product.weightToleranceGreen,
              toleranceYellow: product.weightToleranceYellow,
            ),
      printingStatus: printingOk ? 'okay' : 'not_okay',
      printingRemarks: printingOk ? null : row[FormColumn.printing],
      leakageStatus: 'green',
      moistureStatus: moisture != null && product != null
          ? StatusUtils.moistureStatus(moisture, product.moistureMax, product.moistureYellowMax)
          : 'na',
      createdAt: created,
      updatedAt: now,
      customFields: {
        'source': sourceLabel,
        if (row[FormColumn.time].isNotEmpty) 'time': row[FormColumn.time],
        if (row[FormColumn.qcSign].isNotEmpty) 'qcSign': row[FormColumn.qcSign],
        if (row[FormColumn.recheck].isNotEmpty) 'recheck': row[FormColumn.recheck],
        if (row[FormColumn.remarks].isNotEmpty) 'remarks': row[FormColumn.remarks],
      },
    );
  }
}
