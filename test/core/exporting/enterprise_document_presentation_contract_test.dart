import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/printing/enterprise_document_presentation.dart';

void main() {
  test(
    'sales purchase and maintenance share the order presentation contract',
    () {
      final commercial = File(
        'lib/core/printing/enterprise_document_pdf_service.dart',
      ).readAsStringSync();
      final maintenance = File(
        'lib/core/printing/maintenance_document_pdf_service.dart',
      ).readAsStringSync();

      for (final source in <String>[commercial, maintenance]) {
        expect(source, contains('EnterpriseDocumentPresentation.pageMargin'));
        expect(
          source,
          contains('EnterpriseDocumentPresentation.landscapePageFormat'),
        );
        expect(source, contains('PremiumDocumentTheme.accent'));
        expect(source, contains('PdfTextSupport.canonicalPdf'));
      }

      expect(EnterpriseDocumentPresentation.pageMargin.left, 24);
      expect(EnterpriseDocumentPresentation.pageMargin.top, 20);
      expect(EnterpriseDocumentPresentation.titleSize, 18);
      expect(EnterpriseDocumentPresentation.sectionHeadingSize, 11);
      expect(EnterpriseDocumentPresentation.bodySize, 8);
      expect(EnterpriseDocumentPresentation.tableHeaderSize, 6.9);
      expect(EnterpriseDocumentPresentation.tableBodySize, 7);
      expect(EnterpriseDocumentPresentation.footerSize, 7);
    },
  );
}
