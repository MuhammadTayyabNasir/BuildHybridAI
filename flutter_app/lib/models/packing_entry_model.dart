class PackingEntryModel {
  final String id;
  final String machineId;
  final int machineNumber;
  final String section;
  final String productId;
  final String productName;
  final double price;
  final String shift;
  final String operatorId;
  final String operatorName;
  final DateTime dateCodingManufacture;
  final DateTime dateCodingExpiry;
  final double grossWeight;
  final double? pouch1Weight;
  final double? pouch2Weight;
  final double? pouch3Weight;
  final double? pouch4Weight;
  final double? moistureIdeal;
  final double? moistureActual;
  final String weightStatus;
  final String printingStatus;
  final String? printingColor;
  final String? printingRemarks;
  final String leakageStatus;
  final String? leakageRemarks;
  final String moistureStatus;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, String>? customFields;

  const PackingEntryModel({
    required this.id,
    required this.machineId,
    required this.machineNumber,
    required this.section,
    required this.productId,
    required this.productName,
    required this.price,
    required this.shift,
    required this.operatorId,
    required this.operatorName,
    required this.dateCodingManufacture,
    required this.dateCodingExpiry,
    required this.grossWeight,
    this.pouch1Weight,
    this.pouch2Weight,
    this.pouch3Weight,
    this.pouch4Weight,
    this.moistureIdeal,
    this.moistureActual,
    required this.weightStatus,
    required this.printingStatus,
    this.printingColor,
    this.printingRemarks,
    required this.leakageStatus,
    this.leakageRemarks,
    required this.moistureStatus,
    this.isSynced = false,
    required this.createdAt,
    required this.updatedAt,
    this.customFields,
  });

  double get avgPouchWeight {
    final weights = [pouch1Weight, pouch2Weight, pouch3Weight, pouch4Weight]
        .where((w) => w != null && w > 0)
        .map((w) => w!)
        .toList();
    if (weights.isEmpty) return 0;
    return weights.reduce((a, b) => a + b) / weights.length;
  }

  factory PackingEntryModel.fromMap(Map<String, dynamic> map, String id) {
    return PackingEntryModel(
      id: id,
      machineId: map['machineId'] as String? ?? '',
      machineNumber: map['machineNumber'] as int? ?? 0,
      section: map['section'] as String? ?? '',
      productId: map['productId'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      shift: map['shift'] as String? ?? 'morning',
      operatorId: map['operatorId'] as String? ?? '',
      operatorName: map['operatorName'] as String? ?? '',
      dateCodingManufacture: map['dateCodingManufacture'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['dateCodingManufacture'] as int)
          : DateTime.now(),
      dateCodingExpiry: map['dateCodingExpiry'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['dateCodingExpiry'] as int)
          : DateTime.now(),
      grossWeight: (map['grossWeight'] as num?)?.toDouble() ?? 0,
      pouch1Weight: (map['pouch1Weight'] as num?)?.toDouble(),
      pouch2Weight: (map['pouch2Weight'] as num?)?.toDouble(),
      pouch3Weight: (map['pouch3Weight'] as num?)?.toDouble(),
      pouch4Weight: (map['pouch4Weight'] as num?)?.toDouble(),
      moistureIdeal: (map['moistureIdeal'] as num?)?.toDouble(),
      moistureActual: (map['moistureActual'] as num?)?.toDouble(),
      weightStatus: map['weightStatus'] as String? ?? 'green',
      printingStatus: map['printingStatus'] as String? ?? 'okay',
      printingColor: map['printingColor'] as String?,
      printingRemarks: map['printingRemarks'] as String?,
      leakageStatus: map['leakageStatus'] as String? ?? 'green',
      leakageRemarks: map['leakageRemarks'] as String?,
      moistureStatus: map['moistureStatus'] as String? ?? 'green',
      isSynced: map['isSynced'] as bool? ?? true,
      customFields: (map['customFields'] as Map?)
          ?.map((k, v) => MapEntry(k.toString(), v.toString())),
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'machineId': machineId,
        'machineNumber': machineNumber,
        'section': section,
        'productId': productId,
        'productName': productName,
        'price': price,
        'shift': shift,
        'operatorId': operatorId,
        'operatorName': operatorName,
        'dateCodingManufacture': dateCodingManufacture.millisecondsSinceEpoch,
        'dateCodingExpiry': dateCodingExpiry.millisecondsSinceEpoch,
        'grossWeight': grossWeight,
        'pouch1Weight': pouch1Weight,
        'pouch2Weight': pouch2Weight,
        'pouch3Weight': pouch3Weight,
        'pouch4Weight': pouch4Weight,
        'moistureIdeal': moistureIdeal,
        'moistureActual': moistureActual,
        'weightStatus': weightStatus,
        'printingStatus': printingStatus,
        'printingColor': printingColor,
        'printingRemarks': printingRemarks,
        'leakageStatus': leakageStatus,
        'leakageRemarks': leakageRemarks,
        'moistureStatus': moistureStatus,
        'isSynced': isSynced,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        if (customFields != null && customFields!.isNotEmpty)
          'customFields': customFields,
      };

  PackingEntryModel copyWith({
    String? id,
    String? machineId,
    int? machineNumber,
    String? section,
    String? productId,
    String? productName,
    double? price,
    String? shift,
    String? operatorId,
    String? operatorName,
    DateTime? dateCodingManufacture,
    DateTime? dateCodingExpiry,
    double? grossWeight,
    double? pouch1Weight,
    double? pouch2Weight,
    double? pouch3Weight,
    double? pouch4Weight,
    double? moistureIdeal,
    double? moistureActual,
    String? weightStatus,
    String? printingStatus,
    String? printingColor,
    String? printingRemarks,
    String? leakageStatus,
    String? leakageRemarks,
    String? moistureStatus,
    bool? isSynced,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, String>? customFields,
  }) {
    return PackingEntryModel(
      id: id ?? this.id,
      machineId: machineId ?? this.machineId,
      machineNumber: machineNumber ?? this.machineNumber,
      section: section ?? this.section,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      price: price ?? this.price,
      shift: shift ?? this.shift,
      operatorId: operatorId ?? this.operatorId,
      operatorName: operatorName ?? this.operatorName,
      dateCodingManufacture: dateCodingManufacture ?? this.dateCodingManufacture,
      dateCodingExpiry: dateCodingExpiry ?? this.dateCodingExpiry,
      grossWeight: grossWeight ?? this.grossWeight,
      pouch1Weight: pouch1Weight ?? this.pouch1Weight,
      pouch2Weight: pouch2Weight ?? this.pouch2Weight,
      pouch3Weight: pouch3Weight ?? this.pouch3Weight,
      pouch4Weight: pouch4Weight ?? this.pouch4Weight,
      moistureIdeal: moistureIdeal ?? this.moistureIdeal,
      moistureActual: moistureActual ?? this.moistureActual,
      weightStatus: weightStatus ?? this.weightStatus,
      printingStatus: printingStatus ?? this.printingStatus,
      printingColor: printingColor ?? this.printingColor,
      printingRemarks: printingRemarks ?? this.printingRemarks,
      leakageStatus: leakageStatus ?? this.leakageStatus,
      leakageRemarks: leakageRemarks ?? this.leakageRemarks,
      moistureStatus: moistureStatus ?? this.moistureStatus,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customFields: customFields ?? this.customFields,
    );
  }
}
