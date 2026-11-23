import 'package:uuid/uuid.dart';

class TempHumidityRow {
  final String time;
  final double? temperature;
  final double? humidity;
  final String section;
  final String verifiedByQc;
  final String remarks;

  // Audit trail for readings made through the PMA assistant.
  /// Who said / typed the reading.
  final String enteredBy;
  /// 'manual' | 'voice:on-device' | 'voice:cloud' | 'voice:rules' | 'text:…'
  final String source;
  /// Who confirmed the read-back ('' when saved without confirmation).
  final String confirmedBy;
  final DateTime? enteredAt;

  const TempHumidityRow({
    required this.time,
    this.temperature,
    this.humidity,
    required this.section,
    this.verifiedByQc = '',
    this.remarks = '',
    this.enteredBy = '',
    this.source = '',
    this.confirmedBy = '',
    this.enteredAt,
  });

  Map<String, dynamic> toMap() => {
        'time': time,
        if (temperature != null) 'temperature': temperature,
        if (humidity != null) 'humidity': humidity,
        'section': section,
        'verifiedByQc': verifiedByQc,
        'remarks': remarks,
        if (enteredBy.isNotEmpty) 'enteredBy': enteredBy,
        if (source.isNotEmpty) 'source': source,
        if (confirmedBy.isNotEmpty) 'confirmedBy': confirmedBy,
        if (enteredAt != null) 'enteredAt': enteredAt!.millisecondsSinceEpoch,
      };

  factory TempHumidityRow.fromMap(Map<String, dynamic> m) => TempHumidityRow(
        time: m['time'] as String? ?? '',
        temperature: (m['temperature'] as num?)?.toDouble(),
        humidity: (m['humidity'] as num?)?.toDouble(),
        section: m['section'] as String? ?? '',
        verifiedByQc: m['verifiedByQc'] as String? ?? '',
        remarks: m['remarks'] as String? ?? '',
        enteredBy: m['enteredBy'] as String? ?? '',
        source: m['source'] as String? ?? '',
        confirmedBy: m['confirmedBy'] as String? ?? '',
        enteredAt: m['enteredAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['enteredAt'] as int)
            : null,
      );

  TempHumidityRow copyWith({
    String? time,
    double? temperature,
    double? humidity,
    String? section,
    String? verifiedByQc,
    String? remarks,
    String? confirmedBy,
  }) =>
      TempHumidityRow(
        time: time ?? this.time,
        temperature: temperature ?? this.temperature,
        humidity: humidity ?? this.humidity,
        section: section ?? this.section,
        verifiedByQc: verifiedByQc ?? this.verifiedByQc,
        remarks: remarks ?? this.remarks,
        enteredBy: enteredBy,
        source: source,
        confirmedBy: confirmedBy ?? this.confirmedBy,
        enteredAt: enteredAt,
      );
}

class TempHumidityReport {
  final String id;
  final String sectionId;
  final DateTime date;
  final String shift;
  final List<TempHumidityRow> rows;
  final String preparedBy;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TempHumidityReport({
    required this.id,
    required this.sectionId,
    required this.date,
    required this.shift,
    required this.rows,
    this.preparedBy = '',
    this.isSynced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sectionId': sectionId,
        'date': date.millisecondsSinceEpoch,
        'shift': shift,
        'rows': rows.map((r) => r.toMap()).toList(),
        'preparedBy': preparedBy,
        'isSynced': isSynced,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory TempHumidityReport.fromMap(Map<String, dynamic> m, String id) {
    final rawRows = m['rows'];
    final rows = <TempHumidityRow>[];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is Map<String, dynamic>) rows.add(TempHumidityRow.fromMap(r));
      }
    }
    return TempHumidityReport(
      id: id,
      sectionId: m['sectionId'] as String? ?? '',
      date: m['date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['date'] as int)
          : DateTime.now(),
      shift: m['shift'] as String? ?? 'morning',
      rows: rows,
      preparedBy: m['preparedBy'] as String? ?? '',
      isSynced: m['isSynced'] as bool? ?? false,
      createdAt: m['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int)
          : DateTime.now(),
      updatedAt: m['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int)
          : DateTime.now(),
    );
  }

  TempHumidityReport copyWith({
    String? sectionId,
    DateTime? date,
    String? shift,
    List<TempHumidityRow>? rows,
    String? preparedBy,
    bool? isSynced,
    DateTime? updatedAt,
  }) =>
      TempHumidityReport(
        id: id,
        sectionId: sectionId ?? this.sectionId,
        date: date ?? this.date,
        shift: shift ?? this.shift,
        rows: rows ?? this.rows,
        preparedBy: preparedBy ?? this.preparedBy,
        isSynced: isSynced ?? this.isSynced,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static String generateId() => const Uuid().v4();

  /// True midnight of the given date (for storage key)
  static DateTime dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
