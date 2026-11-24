import 'package:flutter_test/flutter_test.dart';
import 'package:pma/extraction/extracted_form.dart';
import 'package:pma/extraction/pdf_extraction_job.dart';
import 'package:pma/extraction/pdf_pages.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:typed_data';
import 'package:pma/extraction/row_to_entry.dart';
import 'package:pma/models/machine_model.dart';
import 'package:pma/models/product_model.dart';

// Synthetic sheet text, shaped like the model's JSON reply.
const page1 = '''```json
{"date":"30-05-26","product":"Peri Peri","shift":"A","rows":[
 {"sr":"1","machine":"20","price":"20","time":"9:10","dateCoding":"30-5-26 / 29-9-26","w1":"18","w2":"18","w3":"19","w4":"18","product":"Masala","printing":"ok"},
 {"sr":"2","machine":"20","price":"\\"","time":"","dateCoding":"11","w1":"18","w2":"17","w3":"18","product":"\\"","printing":"〃"},
 {"sr":"3","machine":"50","price":"\\"","dateCoding":"\\"","w1":"40","w2":"38","w3":"40","product":"11","printing":"smudged"},
 {}
]}
```''';

void main() {
  group('DittoFill', () {
    test('fills ditto marks from the nearest real value above', () {
      final p = ExtractedPage.parseModel(page1, 1)!;
      expect(p.rows, hasLength(3)); // blank row dropped
      final filled = DittoFill.apply(p.rows);
      expect(filled, greaterThanOrEqualTo(6));
      expect(p.rows[1][FormColumn.price], '20');
      expect(p.rows[1][FormColumn.dateCoding], '30-5-26 / 29-9-26');
      expect(p.rows[1][FormColumn.product], 'Masala');
      expect(p.rows[1][FormColumn.printing], 'ok');
      expect(p.rows[2][FormColumn.product], 'Masala'); // "11" read as ditto in a text column
      expect(p.rows[2][FormColumn.price], '20'); // ditto under ditto
      expect(p.rows[1].origin[FormColumn.product], CellOrigin.ditto);
    });

    test('"11" in a numeric column is a number, not a ditto', () {
      final rows = [
        ExtractedRow({FormColumn.machine: '20'}),
        ExtractedRow({FormColumn.machine: '11'}),
      ];
      DittoFill.apply(rows);
      expect(rows[1][FormColumn.machine], '11');
    });

    test('non-table replies are rejected', () {
      expect(ExtractedPage.parseModel('Sorry, I cannot read this.', 1), isNull);
    });
  });

  group('PdfExtractionJob', () {
    test('retries a page, records a hard failure and resumes without re-reading', () async {
      final kv = <String, String>{};
      final calls = <int>[];
      var flaky = 0;
      Future<String> reader(int page) async {
        calls.add(page);
        if (page == 2 && flaky++ == 0) throw StateError('network');
        if (page == 3) return 'not json';
        return page1;
      }

      PdfExtractionJob job() => PdfExtractionJob(
            fileHash: 'abc',
            fileName: 'sheets.pdf',
            pageCount: 3,
            readPage: reader,
            readMeta: (k) => kv[k],
            writeMeta: (k, v) async => kv[k] = v,
            maxAttempts: 2,
            backoff: Duration.zero,
          );

      final first = job();
      await first.run();
      expect(first.pages.keys, unorderedEquals([1, 2]));
      expect(first.failures.keys, [3]);
      expect(calls, [1, 2, 2, 3, 3]);

      // A new job for the same file resumes from saved progress.
      calls.clear();
      final resumed = job();
      expect(resumed.pages.keys, unorderedEquals([1, 2]));
      await resumed.run();
      expect(calls, isEmpty); // failed page is skipped unless asked
      await resumed.run(retryFailed: true);
      expect(calls, [3, 3]);
      expect(resumed.allRows(), hasLength(6));
    });
  });

  group('RowToEntry', () {
    test('maps a reviewed row with app status rules', () {
      final p = ExtractedPage.parseModel(page1, 1)!;
      DittoFill.apply(p.rows);
      final conv = RowToEntry(
        sectionId: 'peri_peri',
        shift: RowToEntry.normShift(p.shift),
        products: const [
          ProductModel(
            id: 'p1',
            name: 'Masala Peri',
            section: 'peri_peri',
            price: 20,
            weightGrams: 18,
            moistureMax: 0,
            moistureYellowMax: 0,
            expiryDays: 120,
          ),
        ],
        machines: const [MachineModel(id: 'm20', number: 20, section: 'peri_peri')],
        operatorId: 'u1',
        operatorName: 'qc',
        sourceLabel: 'pdf:cloud',
        clock: () => DateTime(2026, 11, 24, 10),
      );
      final e = conv.convert(p, p.rows[0]);
      expect(e.shift, 'morning');
      expect(e.productId, 'p1');
      expect(e.machineId, 'm20');
      expect(e.dateCodingManufacture, DateTime(2026, 5, 30));
      expect(e.dateCodingExpiry, DateTime(2026, 9, 29));
      expect(e.pouch3Weight, 19);
      expect(e.weightStatus, isNotEmpty);
      expect(e.printingStatus, 'okay');
      expect(e.createdAt.day, 30);
      final bad = conv.convert(p, p.rows[2]);
      expect(bad.printingStatus, 'not_okay');
      expect(bad.machineId, ''); // machine 50 not registered
    });
  });

  test('PdfPages splits a document into single-page PDFs', () async {
    final doc = PdfDocument();
    doc.pages.add();
    doc.pages.add();
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    final pages = PdfPages(bytes);
    expect(pages.count, 2);
    final second = PdfDocument(inputBytes: await pages.page(2));
    expect(second.pages.count, 1);
    second.dispose();
    pages.dispose();
  });
}
