import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Splits a scanned PDF into single-page PDFs so each page can be sent,
/// retried and resumed on its own.
class PdfPages {
  PdfPages(Uint8List bytes) : _doc = PdfDocument(inputBytes: bytes);

  final PdfDocument _doc;

  int get count => _doc.pages.count;

  /// Page [n] (1-based) as its own PDF.
  Future<Uint8List> page(int n) async {
    final src = _doc.pages[n - 1];
    final template = src.createTemplate();
    final out = PdfDocument();
    try {
      out.pageSettings.margins.all = 0;
      out.pageSettings.size = src.size;
      out.pages.add().graphics.drawPdfTemplate(template, Offset.zero, src.size);
      return Uint8List.fromList(await out.save());
    } finally {
      out.dispose();
    }
  }

  void dispose() => _doc.dispose();
}
