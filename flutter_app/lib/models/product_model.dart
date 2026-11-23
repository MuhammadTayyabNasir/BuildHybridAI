class ProductModel {
  final String id;
  final String name;
  final String section;
  final double price;
  final double weightGrams;
  final double weightToleranceGreen; // ±g for green (default 2)
  final double weightToleranceYellow; // ±g for yellow (default 4)
  final double moistureMax; // green threshold (0 = N/A)
  final double moistureYellowMax; // yellow upper bound (0 = N/A)
  final int expiryDays;
  final String? imagePath;
  final bool isActive;

  const ProductModel({
    required this.id,
    required this.name,
    required this.section,
    required this.price,
    required this.weightGrams,
    this.weightToleranceGreen = 2.0,
    this.weightToleranceYellow = 4.0,
    required this.moistureMax,
    double? moistureYellowMax,
    required this.expiryDays,
    this.imagePath,
    this.isActive = true,
  }) : moistureYellowMax = moistureYellowMax ?? (moistureMax > 0 ? moistureMax + 0.2 : 0);

  String get displayName => '$name (Rs.${price.toStringAsFixed(0)})';

  factory ProductModel.fromMap(Map<String, dynamic> map, String id) {
    final moistureMax = (map['moistureMax'] as num?)?.toDouble() ?? 1.8;
    return ProductModel(
      id: id,
      name: map['name'] as String? ?? '',
      section: map['section'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      weightGrams: (map['weightGrams'] as num?)?.toDouble() ?? 0,
      weightToleranceGreen: (map['weightToleranceGreen'] as num?)?.toDouble() ?? 2.0,
      weightToleranceYellow: (map['weightToleranceYellow'] as num?)?.toDouble() ?? 4.0,
      moistureMax: moistureMax,
      moistureYellowMax: (map['moistureYellowMax'] as num?)?.toDouble() ??
          (moistureMax > 0 ? moistureMax + 0.2 : 0),
      expiryDays: map['expiryDays'] as int? ?? 30,
      imagePath: map['imagePath'] as String?,
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'section': section,
        'price': price,
        'weightGrams': weightGrams,
        'weightToleranceGreen': weightToleranceGreen,
        'weightToleranceYellow': weightToleranceYellow,
        'moistureMax': moistureMax,
        'moistureYellowMax': moistureYellowMax,
        'expiryDays': expiryDays,
        'imagePath': imagePath,
        'isActive': isActive,
      };

  ProductModel copyWith({
    String? name,
    String? section,
    double? price,
    double? weightGrams,
    double? weightToleranceGreen,
    double? weightToleranceYellow,
    double? moistureMax,
    double? moistureYellowMax,
    int? expiryDays,
    String? imagePath,
    bool? isActive,
  }) {
    return ProductModel(
      id: id,
      name: name ?? this.name,
      section: section ?? this.section,
      price: price ?? this.price,
      weightGrams: weightGrams ?? this.weightGrams,
      weightToleranceGreen: weightToleranceGreen ?? this.weightToleranceGreen,
      weightToleranceYellow: weightToleranceYellow ?? this.weightToleranceYellow,
      moistureMax: moistureMax ?? this.moistureMax,
      moistureYellowMax: moistureYellowMax ?? this.moistureYellowMax,
      expiryDays: expiryDays ?? this.expiryDays,
      imagePath: imagePath ?? this.imagePath,
      isActive: isActive ?? this.isActive,
    );
  }
}
