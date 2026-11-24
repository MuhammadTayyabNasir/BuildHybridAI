import 'dart:convert';

/// Columns of the paper "Daily process monitoring — packing report".
/// Order matches the printed sheet so the review grid reads like the paper.
enum FormColumn {
  sr('sr', 'Sr#', numeric: true),
  machine('machine', 'Mach#', numeric: true),
  price('price', 'Rs', numeric: true),
  time('time', 'Time'),
  dateCoding('dateCoding', 'Date coding'),
  w1('w1', 'Wt 1', numeric: true),
  w2('w2', 'Wt 2', numeric: true),
  w3('w3', 'Wt 3', numeric: true),
  w4('w4', 'Wt 4', numeric: true),
  recheck('recheck', 'Recheck'),
  product('product', 'Product'),
  qcSign('qcSign', 'QC sig'),
  moisture('moisture', 'Moisture'),
  printing('printing', 'Printing'),
  remarks('remarks', 'Remarks');

  const FormColumn(this.key, this.label, {this.numeric = false});
  final String key;
  final String label;
  final bool numeric;

  /// Columns where a handwritten ditto (") is common and OCR often reads it
  /// as "11". Numbers are never forward-filled from "11".
  bool get textDitto => !numeric && this != FormColumn.time && this != FormColumn.remarks;
}

/// Where a cell value came from, for review highlighting.
enum CellOrigin { read, ditto, edited }

class ExtractedRow {
  ExtractedRow(Map<FormColumn, String> cells, {Map<FormColumn, CellOrigin>? origin})
      : cells = {for (final c in FormColumn.values) c: (cells[c] ?? '').trim()},
        origin = origin ?? {};

  final Map<FormColumn, String> cells;
  final Map<FormColumn, CellOrigin> origin;

  String operator [](FormColumn c) => cells[c] ?? '';

  void set(FormColumn c, String v) {
    cells[c] = v.trim();
    origin[c] = CellOrigin.edited;
  }

  bool get isBlank => cells.values.every((v) => v.isEmpty);

  /// Numeric pouch weights read on this row.
  List<double> get weights => [
        for (final c in const [FormColumn.w1, FormColumn.w2, FormColumn.w3, FormColumn.w4])
          ?double.tryParse(cells[c] ?? ''),
      ];

  /// Problems the reviewer must look at before saving.
  List<String> issues() {
    final out = <String>[];
    for (final c in FormColumn.values) {
      final v = cells[c] ?? '';
      if (v.isEmpty || !c.numeric) continue;
      if (double.tryParse(v) == null) out.add('${c.label} "$v" is not a number');
    }
    if ((cells[FormColumn.machine] ?? '').isEmpty) out.add('Machine number missing');
    if (weights.isEmpty) out.add('No pouch weight');
    return out;
  }

  Map<String, String> toJson() => {
        for (final c in FormColumn.values)
          if ((cells[c] ?? '').isNotEmpty) c.key: cells[c]!,
        for (final c in FormColumn.values)
          if (origin[c] != null && origin[c] != CellOrigin.read) '_${c.key}': origin[c]!.name,
      };

  static ExtractedRow fromJson(Map<String, Object?> m) {
    final cells = <FormColumn, String>{};
    final origin = <FormColumn, CellOrigin>{};
    for (final c in FormColumn.values) {
      final v = m[c.key];
      if (v != null) cells[c] = v is num ? _num(v) : '$v';
      final o = m['_${c.key}'];
      if (o is String) {
        origin[c] = CellOrigin.values.firstWhere((x) => x.name == o, orElse: () => CellOrigin.read);
      }
    }
    return ExtractedRow(cells, origin: origin);
  }

  static String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// One scanned page: header fields plus table rows.
class ExtractedPage {
  ExtractedPage({
    required this.page,
    this.date = '',
    this.product = '',
    this.shift = '',
    List<ExtractedRow>? rows,
  }) : rows = rows ?? [];

  final int page;
  String date;
  String product;
  String shift;
  final List<ExtractedRow> rows;

  Map<String, Object?> toJson() => {
        'page': page,
        'date': date,
        'product': product,
        'shift': shift,
        'rows': [for (final r in rows) r.toJson()],
      };

  static ExtractedPage fromJson(Map<String, Object?> m) => ExtractedPage(
        page: (m['page'] as num?)?.toInt() ?? 0,
        date: '${m['date'] ?? ''}',
        product: '${m['product'] ?? ''}',
        shift: '${m['shift'] ?? ''}',
        rows: [
          for (final r in (m['rows'] as List? ?? const []))
            if (r is Map) ExtractedRow.fromJson(Map<String, Object?>.from(r)),
        ],
      );

  /// Reads the model's JSON for one page. Tolerates code fences and prose
  /// around the object; returns null when there is no usable table.
  static ExtractedPage? parseModel(String raw, int page) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final m = jsonDecode(raw.substring(start, end + 1));
      if (m is! Map) return null;
      final p = ExtractedPage.fromJson({...Map<String, Object?>.from(m), 'page': page});
      p.rows.removeWhere((r) => r.isBlank);
      return p;
    } catch (_) {
      return null;
    }
  }
}

/// Forward-fills handwritten ditto marks (" 〃 ” ,, do -do-, and "11" in text
/// columns where OCR reads a ditto as eleven) from the row above, and marks
/// those cells so the review grid can show them.
class DittoFill {
  const DittoFill._();

  static final _ditto = RegExp(r'''^\s*(["“”″〃'`]{1,2}|,,|-?\s*do\s*-?|same|ditto)\s*$''',
      caseSensitive: false);

  static bool isDitto(String v, FormColumn c) {
    if (_ditto.hasMatch(v)) return true;
    return c.textDitto && RegExp(r'^\s*(11|ll|\|\|)\s*$').hasMatch(v);
  }

  /// Returns how many cells were filled.
  static int apply(List<ExtractedRow> rows) {
    var filled = 0;
    for (var i = 0; i < rows.length; i++) {
      for (final c in FormColumn.values) {
        final v = rows[i][c];
        if (v.isEmpty || !isDitto(v, c)) continue;
        // Walk up to the nearest real value (a ditto under a ditto is common).
        String? above;
        for (var j = i - 1; j >= 0; j--) {
          final a = rows[j][c];
          if (a.isNotEmpty && !isDitto(a, c)) {
            above = a;
            break;
          }
        }
        if (above == null) continue;
        rows[i].cells[c] = above;
        rows[i].origin[c] = CellOrigin.ditto;
        filled++;
      }
    }
    return filled;
  }
}

/// Prompt shared by the PDF (cloud, page image) and photo (on-device OCR
/// text) extractors.
const formExtractionInstructions =
    'You read a scanned handwritten "Daily process monitoring packing report" from a snack '
    'factory. Return JSON only: {"date":"as written","product":"section/product in the header",'
    '"shift":"A/B/morning/night as written","rows":[{"sr":"","machine":"","price":"","time":"",'
    '"dateCoding":"","w1":"","w2":"","w3":"","w4":"","recheck":"","product":"","qcSign":"",'
    '"moisture":"","printing":"","remarks":""}]}. One object per filled table row, top to bottom. '
    'Copy what is written; never invent values. If a cell holds a ditto mark (" or 〃 or a mark '
    'meaning "same as above"), output exactly " (a double quote) — do not resolve it. '
    'Leave unreadable or empty cells as "". Weights are the "Wt of pouches" columns, left to right.';
