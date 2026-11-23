class MachineModel {
  final String id;
  final int number;
  final String section;
  final bool isActive;

  const MachineModel({
    required this.id,
    required this.number,
    required this.section,
    this.isActive = true,
  });

  String get label => 'Machine $number';
  String get sectionLabel => section.replaceAll('_', ' ').toUpperCase();

  factory MachineModel.fromMap(Map<String, dynamic> map, String id) {
    return MachineModel(
      id: id,
      number: map['number'] as int? ?? 0,
      section: map['section'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'number': number,
        'section': section,
        'isActive': isActive,
      };

  MachineModel copyWith({int? number, String? section, bool? isActive}) {
    return MachineModel(
      id: id,
      number: number ?? this.number,
      section: section ?? this.section,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MachineModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
