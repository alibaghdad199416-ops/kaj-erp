import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/exporting/xlsx_integrity.dart';

void main() {
  test('normalizes worksheet order and used range without changing cells', () {
    const sheetData =
        '<sheetData><row r="5"><c r="C5" t="n"><v>42</v></c></row></sheetData>';
    const worksheet =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetFormatPr defaultColWidth="18" defaultRowHeight="21"/>'
        '<dimension ref="A1"/>'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        '<cols><col min="1" max="3" width="18" customWidth="1"/></cols>'
        '$sheetData'
        '<mergeCells count="1"><mergeCell ref="A1:D1"/></mergeCells>'
        '</worksheet>';

    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'xl/worksheets/sheet1.xml',
          utf8.encode(worksheet).length,
          utf8.encode(worksheet),
        ),
      );
    final encoded = ZipEncoder().encode(archive)!;

    final finalized = XlsxIntegrity.finalize(encoded);
    final decoded = ZipDecoder().decodeBytes(finalized, verify: true);
    final xml = utf8.decode(
      decoded.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );

    expect(xml, contains('<dimension ref="A1:D5"/>'));
    expect(xml, contains(sheetData));
    expect(xml.indexOf('<dimension '), lessThan(xml.indexOf('<sheetViews')));
    expect(
      xml.indexOf('</sheetViews>'),
      lessThan(xml.indexOf('<sheetFormatPr ')),
    );
    expect(xml.indexOf('<sheetFormatPr '), lessThan(xml.indexOf('<cols>')));
    expect(xml.indexOf('<cols>'), lessThan(xml.indexOf('<sheetData>')));
  });
}
