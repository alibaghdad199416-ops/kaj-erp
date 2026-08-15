import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/app/brand_identity.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/unified_pdf_document.dart';

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
    pw.MemoryImage? logo;
    try {
      final logoBytes = (await rootBundle.load(
        'assets/images/logo.png',
      )).buffer.asUint8List();
      logo = pw.MemoryImage(logoBytes);
    } catch (_) {
      logo = null;
    }
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
    String clean(Object? value) => PdfTextSupport.sanitize(value);

    final document = pw.Document(
      title: clean(transaction.voucherNumber),
      author: 'Quality Line ERP',
      creator: 'Quality Line ERP',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    document.addPage(
      pw.MultiPage(
        pageTheme: UnifiedPdfDocument.pageTheme(
          fonts,
          textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        ),
        header: (_) => UnifiedPdfDocument.documentHeader(
          bold: bold,
          documentType: title,
          documentNumber: transaction.voucherNumber,
          logo: logo,
          companyName: arabic
              ? BrandIdentity.companyNameAr
              : BrandIdentity.companyNameEn,
        ),
        footer: (context) => UnifiedPdfDocument.footer(
          regular: regular,
          pageNumber: context.pageNumber,
          pageCount: context.pagesCount,
          arabic: arabic,
        ),
        build: (_) => <pw.Widget>[
          UnifiedPdfDocument.titleBlock(
            bold: bold,
            title: title,
            subtitle:
                '${t('رقم السند', 'Voucher number')}: ${transaction.voucherNumber}',
            status: t('معتمد', 'Approved'),
          ),
          pw.Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: t('المبلغ', 'Amount'),
                value: MoneyFormatter.withCurrency(
                  transaction.amount,
                  transaction.currency,
                ),
              ),
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: t('التاريخ', 'Date'),
                value: date(transaction.transactionDate),
              ),
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: t('التصنيف', 'Category'),
                value: transaction.category,
              ),
            ],
          ),
          UnifiedPdfDocument.sectionHeader(
            bold: bold,
            title: t('تفاصيل السند', 'Voucher details'),
          ),
          UnifiedPdfDocument.table(
            regular: regular,
            bold: bold,
            arabic: arabic,
            headers: [t('الحقل', 'Field'), t('القيمة', 'Value')],
            rows: <List<String>>[
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
            ].map((row) => row.map(clean).toList()).toList(growable: false),
          ),
          UnifiedPdfDocument.sectionHeader(
            bold: bold,
            title: t('الاعتماد المحاسبي', 'Accounting approval'),
          ),
          pw.Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: t('حالة المستند', 'Document status'),
                value: t('معتمد', 'Approved'),
                width: 180,
              ),
              UnifiedPdfDocument.summaryTile(
                bold: bold,
                label: t('مرجع الإدخال المحاسبي', 'Accounting posting reference'),
                value: journalEntryNumber ??
                    _compactReference(transaction.journalEntryId),
                width: 260,
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            children: [
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: t('توقيع المستلم', 'Recipient signature'),
              ),
              pw.SizedBox(width: 12),
              UnifiedPdfDocument.signatureBox(
                bold: bold,
                title: t('توقيع المسؤول', 'Authorized signature'),
              ),
            ],
          ),
        ],
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
