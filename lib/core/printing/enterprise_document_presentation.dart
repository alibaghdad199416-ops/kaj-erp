import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Structural contract shared by customer-facing order documents.
abstract final class EnterpriseDocumentPresentation {
  static final landscapePageFormat = PdfPageFormat.a4.landscape;
  static const pageMargin = pw.EdgeInsets.fromLTRB(24, 20, 24, 22);

  static const double titleSize = 18;
  static const double sectionHeadingSize = 11;
  static const double bodySize = 8;
  static const double tableHeaderSize = 6.9;
  static const double tableBodySize = 7;
  static const double footerSize = 7;

  static const fieldPadding = pw.EdgeInsets.symmetric(
    horizontal: 7,
    vertical: 5,
  );
  static const tableHeaderPadding = pw.EdgeInsets.symmetric(
    horizontal: 5,
    vertical: 6,
  );
  static const tableCellPadding = pw.EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 4,
  );
}
