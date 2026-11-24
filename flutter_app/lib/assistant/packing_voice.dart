import '../core/utils/status_utils.dart';
import '../models/machine_model.dart';
import '../models/product_model.dart';
import 'rules_parser.dart';

/// A packing check spoken by an operator, e.g.
/// "chips machine 3 masala, weight 52 53 51 52, leakage theek, printing theek".
///
/// Only the slots the operator actually said are filled. [PackingVoice.missing]
/// lists what still has to be asked before the entry can be read back.
class PackingDraft {
  const PackingDraft({
    this.sectionId,
    this.machineNumber,
    this.productQuery,
    this.product,
    this.weights = const [],
    this.moisture,
    this.leakageOk,
    this.printingOk,
  });

  final String? sectionId;
  final int? machineNumber;

  /// What the operator called the product, before it is matched.
  final String? productQuery;
  final ProductModel? product;
  final List<double> weights;
  final double? moisture;

  /// Null when not said; the read-back states the default ("OK") so the
  /// operator can correct it before saving.
  final bool? leakageOk;
  final bool? printingOk;

  PackingDraft merge(PackingDraft o) => PackingDraft(
        sectionId: o.sectionId ?? sectionId,
        machineNumber: o.machineNumber ?? machineNumber,
        productQuery: o.productQuery ?? productQuery,
        product: o.product ?? product,
        weights: o.weights.isNotEmpty ? o.weights : weights,
        moisture: o.moisture ?? moisture,
        leakageOk: o.leakageOk ?? leakageOk,
        printingOk: o.printingOk ?? printingOk,
      );

  PackingDraft withProduct(ProductModel? p) => PackingDraft(
        sectionId: sectionId ?? p?.section,
        machineNumber: machineNumber,
        productQuery: productQuery,
        product: p,
        weights: weights,
        moisture: moisture,
        leakageOk: leakageOk,
        printingOk: printingOk,
      );

  String weightStatus() => product == null
      ? 'green'
      : StatusUtils.weightStatusOfPouches(
          weights,
          product!.weightGrams,
          toleranceGreen: product!.weightToleranceGreen,
          toleranceYellow: product!.weightToleranceYellow,
        );

  String moistureStatus() => product == null || moisture == null
      ? 'na'
      : StatusUtils.moistureStatus(
          moisture!, product!.moistureMax, product!.moistureYellowMax);
}

class PackingVoice {
  const PackingVoice();

  static const _packingWords = [
    'machine', 'mashin', 'masheen', 'مشین', 'pouch', 'pouches', 'wazan',
    'weight', 'وزن', 'leakage', 'leak', 'printing', 'print', 'packing',
    'پیکنگ', 'لیکج', 'پرنٹنگ',
  ];

  /// True when the sentence is about a packing check rather than a
  /// temperature / humidity reading.
  bool looksLikePacking(String input) {
    final t = RulesParser.normalize(input);
    return _packingWords.any(t.contains) &&
        !RegExp(r'(temp\w*|humid\w*|ہیومیڈیٹی|ٹمپریچر)').hasMatch(t);
  }

  /// Fills the slots that were said. Product names are matched against the
  /// products of the section (or all products when no section was said).
  PackingDraft parse(
    String input, {
    required List<ProductModel> products,
    String? sectionId,
  }) {
    final t = RulesParser.normalize(input);
    const num = r'(\d+(?:\.\d+)?)';

    final machine = RegExp('(machine|mashin|masheen|مشین)\\s*(no|number|#)?\\s*(\\d{1,3})')
        .firstMatch(t);

    // Weights: every number after the weight keyword, up to four pouches,
    // stopping at the next keyword ("moisture 1.6" is not a pouch).
    final weights = <double>[];
    final w = RegExp(r'(weight|wazan|وزن|pouch\w*)').firstMatch(t);
    if (w != null) {
      var rest = t.substring(w.end);
      final stop = RegExp(r'(moisture|nami|نمی|leak|print|machine|mashin)').firstMatch(rest);
      if (stop != null) rest = rest.substring(0, stop.start);
      for (final m in RegExp(num).allMatches(rest)) {
        final v = double.parse(m[1]!);
        if (v > 0 && v < 5000) weights.add(v);
        if (weights.length == 4) break;
      }
    }

    final moist = RegExp('(moisture|nami|نمی)\\D{0,12}?$num').firstMatch(t);

    final section = sectionId;
    final pool = products
        .where((p) => p.isActive && (section == null || p.section == section))
        .toList();
    final product = matchProduct(t, pool);

    return PackingDraft(
      sectionId: section ?? product?.section,
      machineNumber: machine == null ? null : int.tryParse(machine[3]!),
      productQuery: product?.name,
      product: product,
      weights: weights,
      moisture: moist == null ? null : double.parse(moist[2]!),
      leakageOk: _leakage(t),
      printingOk: _printing(t),
    );
  }

  /// "leakage hai" means a leak was found; "leakage nahi" / "leakage theek"
  /// means none.
  static bool? _leakage(String t) {
    final m = RegExp(r'(leak\w*|لیکج)\s+(\w+)(\s+\w+)?').firstMatch(t);
    if (m == null) return null;
    final words = '${m[2]} ${m[3] ?? ''}';
    if (RegExp(r'\b(nahi|nahin|no|none|theek|thik|ok|okay|green|clear)\b').hasMatch(words)) {
      return true;
    }
    if (RegExp(r'\b(hai|ha|yes|found|red|issue)\b').hasMatch(words)) return false;
    return null;
  }

  /// "printing theek" = okay; "printing kharab" / "printing theek nahi" = not.
  static bool? _printing(String t) {
    final m = RegExp(r'(print\w*|پرنٹنگ)\s+(\w+)(\s+\w+)?').firstMatch(t);
    if (m == null) return null;
    final words = '${m[2]} ${m[3] ?? ''}';
    if (RegExp(r'(nahi|nahin|not|kharab|kharaab|kam|faded|issue|red)').hasMatch(words)) {
      return false;
    }
    if (RegExp(r'(theek|thik|ok|okay|sahi|green|clear|fine|good)').hasMatch(words)) {
      return true;
    }
    return null;
  }

  static const _generic = {
    'the', 'and', 'pack', 'chips', 'chip', 'peri', 'nimko', 'wafer',
    'wafers', 'chocolate', 'choco', 'bar',
  };

  /// Best product whose name shares the most words with the sentence.
  static ProductModel? matchProduct(String normalized, List<ProductModel> pool) {
    ProductModel? best;
    var bestScore = 0;
    final said = normalized.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    for (final p in pool) {
      final words = p.name
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          // Section words ("chips" in "Masala Chips") say nothing about
          // which product of that section was meant.
          .where((w) => w.length > 2 && !_generic.contains(w));
      final score = words.where(said.contains).length;
      if (score > bestScore) {
        best = p;
        bestScore = score;
      }
    }
    return best;
  }

  /// What still has to be said before reading the entry back.
  List<String> missing(PackingDraft d) => [
        if (d.sectionId == null) 'section',
        if (d.product == null) 'product',
        if (d.machineNumber == null) 'machine',
        if (d.weights.isEmpty) 'weight',
      ];

  MachineModel? machineFor(PackingDraft d, List<MachineModel> machines) {
    for (final m in machines) {
      if (m.number == d.machineNumber && (d.sectionId == null || m.section == d.sectionId)) {
        return m;
      }
    }
    return null;
  }
}
