import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-section QC color bands for Temp & Humidity.
/// value <= greenMax                 → green
/// greenMax < value <= yellowMax     → yellow
/// value > yellowMax                 → red   (no upper bound — a reading can
///                                             spike arbitrarily high; it's
///                                             still saved, just flagged)
///
/// greenMax and yellowMax are both independently admin-set — there's no fixed
/// formula between them (e.g. green=35, yellow=40 is fine; so is green=35,
/// yellow=55).
class ThThreshold {
  static const double defaultTempGreenMax = 35;
  static const double defaultTempYellowMax = 40;
  static const double defaultHumGreenMax = 50;
  static const double defaultHumYellowMax = 55;

  final String sectionId;
  final double tempGreenMax;
  final double tempYellowMax;
  final double humGreenMax;
  final double humYellowMax;
  final DateTime? updatedAt;
  final String? updatedBy;

  const ThThreshold({
    required this.sectionId,
    this.tempGreenMax = defaultTempGreenMax,
    this.tempYellowMax = defaultTempYellowMax,
    this.humGreenMax = defaultHumGreenMax,
    this.humYellowMax = defaultHumYellowMax,
    this.updatedAt,
    this.updatedBy,
  });

  factory ThThreshold.defaults(String sectionId) => ThThreshold(sectionId: sectionId);

  factory ThThreshold.fromMap(String sectionId, Map<String, dynamic> map) => ThThreshold(
    sectionId: sectionId,
    tempGreenMax: (map['tempGreenMax'] as num?)?.toDouble() ?? defaultTempGreenMax,
    tempYellowMax: (map['tempYellowMax'] as num?)?.toDouble() ?? defaultTempYellowMax,
    humGreenMax: (map['humGreenMax'] as num?)?.toDouble() ?? defaultHumGreenMax,
    humYellowMax: (map['humYellowMax'] as num?)?.toDouble() ?? defaultHumYellowMax,
    updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    updatedBy: map['updatedBy'] as String?,
  );

  Map<String, dynamic> toMap({String? by}) => {
    'tempGreenMax': tempGreenMax,
    'tempYellowMax': tempYellowMax,
    'humGreenMax': humGreenMax,
    'humYellowMax': humYellowMax,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': ?by,
  };

  /// 'green' | 'yellow' | 'red'. Red is unbounded above — never rejects a value.
  String classifyTemp(double v) {
    if (v <= tempGreenMax) return 'green';
    if (v <= tempYellowMax) return 'yellow';
    return 'red';
  }

  /// 'green' | 'yellow' | 'red'. Negative humidity is physically invalid → red.
  String classifyHumidity(double v) {
    if (v < 0) return 'red';
    if (v <= humGreenMax) return 'green';
    if (v <= humYellowMax) return 'yellow';
    return 'red';
  }

  ThThreshold copyWith({
    double? tempGreenMax,
    double? tempYellowMax,
    double? humGreenMax,
    double? humYellowMax,
  }) =>
      ThThreshold(
        sectionId: sectionId,
        tempGreenMax: tempGreenMax ?? this.tempGreenMax,
        tempYellowMax: tempYellowMax ?? this.tempYellowMax,
        humGreenMax: humGreenMax ?? this.humGreenMax,
        humYellowMax: humYellowMax ?? this.humYellowMax,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
}