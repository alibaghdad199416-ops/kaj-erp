import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/app/brand_identity.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/premium_document_theme.dart';

import '../models/cash_transaction_model.dart';

class CashVoucherPdfService {
  const CashVoucherPdfService();

  Future<Uint8List> build(
    CashTransactionModel transaction, {
    required bool arabic,
    String? cashAccountName,
    String? counterAccountName,
    String? journalEntryNumber,
  }) async {
    arabic = PdfTextSupport.canonicalPdfArabic(arabic);
    final fonts = await PdfTextSupport.loadFonts();
    final regular = fonts.regular;
    final bold = fonts.bold;
    String clean(Object? value) => PdfTextSupport.sanitize(value);
    pw.MemoryImage? logo;
    try {
      final logoBytes = (await rootBundle.load(
        'assets/images/logo.png',
      )).buffer.asUint8List();
      logo = pw.MemoryImage(logoBytes);
    } catch (_) {
      logo = null;
    }
    final document = pw.Document(
      title: clean(transaction.voucherNumber),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final isTransfer = (transaction.referenceType ?? '').toLowerCase().contains(
      'transfer',
    );
    final title = isTransfer
        ? (arabic ? 'سند تحويل' : 'Transfer voucher')
        : transaction.isReceipt
        ? (arabic ? 'سند قبض' : 'Receipt voucher')
        : (arabic ? 'سند صرف' : 'Payment voucher');
    String t(String ar, String en) => arabic ? ar : en;
    String date(DateTime value) =>
        '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PremiumDocumentTheme.ink,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 54,
                        height: 54,
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(7),
                        ),
                        child: logo == null
                            ? pw.SizedBox()
                            : pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            arabic
                                ? BrandIdentity.companyNameAr
                                : BrandIdentity.companyNameEn,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 18,
                              color: PdfColors.white,
                            ),
                          ),
                          pw.Text(
                            t(
                              'نظام إدارة الموارد المؤسسية',
                              'Enterprise Resource Planning',
                            ),
                            style: const pw.TextStyle(color: PdfColors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 16,
                      color: PremiumDocumentTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              '${t('رقم السند', 'Voucher number')}: ${transaction.voucherNumber}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 18),
            ),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
              headers: [
                t('الحقل', 'Field'),
                t('القيمة', 'Value'),
              ].map(clean).toList(),
              data: <List<Object?>>[
                [t('رقم السند', 'Voucher number'), transaction.voucherNumber],
                [t('التاريخ', 'Date'), date(transaction.transactionDate)],
                [t('التصنيف', 'Category'), transaction.category],
                [
                  t('المبلغ', 'Amount'),
                  MoneyFormatter.withCurrency(
                    transaction.amount,
                    transaction.currency,
                  ),
                ],
                [t('الطرف', 'Party'), transaction.partyName ?? '-'],
                [t('طريقة الدفع', 'Payment method'), transaction.paymentMethod],
                [
                  t('نوع المرجع', 'Reference type'),
                  transaction.referenceType ?? '-',
                ],
                [
                  t('رقم المرجع', 'Reference ID'),
                  _compactReference(transaction.referenceId),
                ],
                [
                  t('حساب الصندوق', 'Cash account'),
                  cashAccountName ?? transaction.cashAccountId ?? '-',
                ],
                [
                  t('الحساب المقابل', 'Counter account'),
                  counterAccountName ?? transaction.counterAccountId ?? '-',
                ],
                [
                  t('رقم القيد المحاسبي', 'Journal entry reference'),
                  journalEntryNumber ??
                      _compactReference(transaction.journalEntryId),
                ],
                [t('الملاحظات', 'Notes'), transaction.notes ?? '-'],
              ].map((row) => row.map(clean).toList()).toList(),
              headerStyle: pw.TextStyle(font: bold),
              cellStyle: pw.TextStyle(font: regular),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PremiumDocumentTheme.accentSoft,
                border: pw.Border.all(color: PremiumDocumentTheme.accent),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    t('حالة المستند: معتمد', 'Document status: Approved'),
                    style: pw.TextStyle(font: bold),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    '${t('مرجع الإدخال المحاسبي', 'Accounting posting reference')}: ${journalEntryNumber ?? _compactReference(transaction.journalEntryId)}',
                    softWrap: true,
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(t('توقيع المستلم', 'Recipient signature')),
                pw.Text(t('توقيع المسؤول', 'Authorized signature')),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Divider(color: PremiumDocumentTheme.accent),
            pw.Text(
              t(
                'تم إنشاء التقرير إلكترونيًا بواسطة نظام خط الجودة',
                'Generated electronically by Quality Line ERP',
              ),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  String _compactReference(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.isEmpty) return '-';
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuid.hasMatch(reference)) return reference;
    return '${reference.substring(0, 8)}…${reference.substring(reference.length - 4)}';
  }

  Future<void> printVoucher(
    CashTransactionModel transaction, {
    required bool arabic,
    String? cashAccountName,
    String? counterAccountName,
    String? journalEntryNumber,
  }) async {
    final bytes = await build(
      transaction,
      arabic: arabic,
      cashAccountName: cashAccountName,
      counterAccountName: counterAccountName,
      journalEntryNumber: journalEntryNumber,
    );
    await PdfPrintService.print(
      fileName: '${transaction.voucherNumber}.pdf',
      bytes: bytes,
    );
  }
}
