class StatusUtils {
  StatusUtils._();

  static String weightStatus(
    double avgWeight,
    double targetWeight, {
    double toleranceGreen = 2.0,
    double toleranceYellow = 4.0,
  }) {
    final diff = (avgWeight - targetWeight).abs();
    if (diff <= toleranceGreen) return 'green';
    if (diff <= toleranceYellow) return 'yellow';
    return 'red';
  }

  // moistureMax == 0 means N/A (wafer / chocolate)
  static String moistureStatus(
    double moisture,
    double moistureMax,
    double moistureYellowMax,
  ) {
    if (moistureMax == 0) return 'na';
    if (moisture <= moistureMax) return 'green';
    if (moisture <= moistureYellowMax) return 'yellow';
    return 'red';
  }

  static String printingStatus(String status, String? color) {
    if (status == 'okay') return 'green';
    return color?.toLowerCase() ?? 'red';
  }

  /// Weight status from INDIVIDUAL pouches (not the average): each valid pouch
  /// is classified on its own and the WORST result wins. One pouch red → red;
  /// a yellow plus a red → red. If no valid pouch weights, returns 'green'.
  static String weightStatusOfPouches(
    List<double?> weights,
    double targetWeight, {
    double toleranceGreen = 2.0,
    double toleranceYellow = 4.0,
  }) {
    var worst = 'green';
    var any = false;
    for (final w in weights) {
      if (w == null || w <= 0) continue;
      any = true;
      final s = weightStatus(w, targetWeight,
          toleranceGreen: toleranceGreen, toleranceYellow: toleranceYellow);
      worst = worseStatus(worst, s);
      if (worst == 'red') break;
    }
    return any ? worst : 'green';
  }

  /// Returns the more severe of two statuses (red > yellow > green; na lowest).
  static String worseStatus(String a, String b) {
    const rank = {'green': 0, 'yellow': 1, 'red': 2};
    return (rank[a] ?? -1) >= (rank[b] ?? -1) ? a : b;
  }

  static double avgWeight(List<double?> weights) {
    final valid = weights.where((w) => w != null && w > 0).map((w) => w!).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'green':
        return 'OK';
      case 'yellow':
        return 'Warning';
      case 'red':
        return 'Alert';
      case 'na':
        return 'N/A';
      default:
        return status;
    }
  }

  static bool isDefect(String status) => status == 'yellow' || status == 'red';
}
