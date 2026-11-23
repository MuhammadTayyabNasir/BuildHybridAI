import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum CustomColumnType { text, number, options }

class CustomColumn {
  final String id;
  final String heading;
  final CustomColumnType type;
  final List<String> options;
  final bool isRequired;

  const CustomColumn({
    required this.id,
    required this.heading,
    this.type = CustomColumnType.text,
    this.options = const [],
    this.isRequired = false,
  });

  double get width {
    switch (type) {
      case CustomColumnType.number:
        return 88.0;
      case CustomColumnType.options:
        return 110.0;
      case CustomColumnType.text:
        return 120.0;
    }
  }

  String get typeLabel {
    switch (type) {
      case CustomColumnType.text:
        return 'Text';
      case CustomColumnType.number:
        return 'Number';
      case CustomColumnType.options:
        return 'Options';
    }
  }

  // FIX: Added isRequired to toJson so it saves to SharedPreferences
  Map<String, dynamic> toJson() => {
    'id': id,
    'heading': heading,
    'type': type.name,
    'options': options,
    'isRequired': isRequired,
  };

  // FIX: Added isRequired to fromJson so it loads correctly on app restart
  factory CustomColumn.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? 'text';
    final type = CustomColumnType.values.firstWhere(
          (t) => t.name == typeStr,
      orElse: () => CustomColumnType.text,
    );
    return CustomColumn(
      id: j['id'] as String? ?? '',
      heading: j['heading'] as String? ?? '',
      type: type,
      options: List<String>.from(j['options'] as List? ?? []),
      isRequired: j['isRequired'] as bool? ?? false,
    );
  }

  factory CustomColumn.fromMap(Map<String, dynamic> map) {
    return CustomColumn(
      id: map['id'] ?? '',
      heading: map['heading'] ?? '',
      type: CustomColumnType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => CustomColumnType.text,
      ),
      options: List<String>.from(map['options'] ?? []),
      isRequired: map['isRequired'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'heading': heading,
      'type': type.name,
      'options': options,
      'isRequired': isRequired,
    };
  }

  // FIX: Added isRequired to copyWith
  CustomColumn copyWith({
    String? heading,
    CustomColumnType? type,
    List<String>? options,
    bool? isRequired,
  }) =>
      CustomColumn(
        id: id,
        heading: heading ?? this.heading,
        type: type ?? this.type,
        options: options ?? this.options,
        isRequired: isRequired ?? this.isRequired,
      );
}

class CustomColumnsService {
  static const _kKey = 'custom_columns_v1';
  static const _uuid = Uuid();

  static Future<List<CustomColumn>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? [];
    return raw
        .map((s) {
      try {
        return CustomColumn.fromJson(
            jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    })
        .whereType<CustomColumn>()
        .toList();
  }

  static Future<void> save(List<CustomColumn> cols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kKey,
      cols.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  static String generateId() => _uuid.v4();
}