import 'dart:io';
import 'dart:typed_data';

import 'package:enterprise_bike_showroom/core/helpers/formatters.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:enterprise_bike_showroom/core/utils/date_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Flat data structures consumed by the PDF layouts. Feature controllers map
/// their domain models into these before rendering.
class InvoicePdfData {
  InvoicePdfData({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.invoiceType,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.outstandingAmount,
    this.status = 'FINALIZED',
    this.items = const <InvoicePdfItem>[],
    this.showroomName = '',
    this.showroomAddress = '',
    this.showroomPhone = '',
    this.showroomGst = '',
    this.customerName = '',
    this.customerAddress = '',
    this.customerPhone = '',
    this.customerGst = '',
    this.notes,
  });

  final String invoiceNumber;
  final DateTime invoiceDate;
  final String invoiceType;
  final num subtotal;
  final num discount;
  final num taxAmount;
  final num totalAmount;
  final num paidAmount;
  final num outstandingAmount;
  final String status;
  final List<InvoicePdfItem> items;
  final String showroomName;
  final String showroomAddress;
  final String showroomPhone;
  final String showroomGst;
  final String customerName;
  final String customerAddress;
  final String customerPhone;
  final String customerGst;
  final String? notes;
}

class InvoicePdfItem {
  InvoicePdfItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.totalAmount,
  });

  final String description;
  final num quantity;
  final num unitPrice;
  final num discount;
  final num taxRate;
  final num totalAmount;
}

class PaymentReceiptData {
  PaymentReceiptData({
    required this.paymentNumber,
    required this.paymentDate,
    required this.amount,
    required this.method,
    required this.referenceNumber,
    required this.customerName,
    this.invoiceNumber,
    this.showroomName = '',
    this.showroomAddress = '',
    this.receivedBy,
    this.status = 'COMPLETED',
  });

  final String paymentNumber;
  final DateTime paymentDate;
  final num amount;
  final String method;
  final String referenceNumber;
  final String customerName;
  final String? invoiceNumber;
  final String showroomName;
  final String showroomAddress;
  final String? receivedBy;
  final String status;
}

class EmiReceiptData {
  EmiReceiptData({
    required this.loanNumber,
    required this.emiNumber,
    required this.paymentDate,
    required this.emiAmount,
    required this.principalAmount,
    required this.interestAmount,
    required this.customerName,
    required this.loanBalance,
    this.showroomName = '',
    this.showroomAddress = '',
  });

  final String loanNumber;
  final int emiNumber;
  final DateTime paymentDate;
  final num emiAmount;
  final num principalAmount;
  final num interestAmount;
  final String customerName;
  final num loanBalance;
  final String showroomName;
  final String showroomAddress;
}

/// Reusable PDF generation (invoices, receipts, generic report tables).
///
/// Note: PDF uses built-in Helvetica fonts, so the rupee glyph is not
/// available - amounts are rendered with the `INR` prefix.
class PdfService {
  PdfService();

  static const String _moneyPrefix = 'INR';

  /// Builds an invoice PDF (A4, printable).
  Future<Uint8List> invoicePdf(InvoicePdfData data) async {
    final pw.Document doc = pw.Document();
    final PdfColor primary = const PdfColor.fromInt(0xFF14532D);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            children: <pw.Widget>[
              _header(data.showroomName, data.showroomAddress,
                  data.showroomPhone, data.showroomGst),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      _label('BILL TO'),
                      pw.Text(data.customerName,
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      if (data.customerAddress.isNotEmpty)
                        pw.Text(data.customerAddress,
                            style: const pw.TextStyle(fontSize: 9)),
                      if (data.customerPhone.isNotEmpty)
                        pw.Text(data.customerPhone,
                            style: const pw.TextStyle(fontSize: 9)),
                      if (data.customerGst.isNotEmpty)
                        pw.Text('GSTIN: ${data.customerGst.toUpperCase()}',
                            style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: <pw.Widget>[
                      pw.Text('INVOICE',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: primary)),
                      pw.SizedBox(height: 4),
                      pw.Text('No: ${data.invoiceNumber}',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Date: ${DateUtils.format(data.invoiceDate)}',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Type: ${AppFormatters.humanize(data.invoiceType)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Table(
                border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCBD5E1)),
                columnWidths: <int, pw.TableColumnWidth>{
                  0: const pw.FlexColumnWidth(3.2),
                  1: const pw.FixedColumnWidth(60),
                  2: const pw.FixedColumnWidth(80),
                  3: const pw.FixedColumnWidth(70),
                  4: const pw.FixedColumnWidth(50),
                  5: const pw.FixedColumnWidth(80),
                },
                children: <pw.TableRow>[
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
                    children: <pw.Widget>[
                      _head('DESCRIPTION'),
                      _head('QTY'),
                      _head('RATE'),
                      _head('DISC.'),
                      _head('TAX%'),
                      _head('AMOUNT'),
                    ],
                  ),
                  for (final InvoicePdfItem item in data.items)
                    pw.TableRow(
                      children: <pw.Widget>[
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                          child: pw.Text(item.description,
                              style: const pw.TextStyle(fontSize: 9)),
                        ),
                        _cell(item.quantity.toString()),
                        _cell(AppFormatters.amount(item.unitPrice)),
                        _cell(AppFormatters.amount(item.discount)),
                        _cell('${item.taxRate.toStringAsFixed(1)}'),
                        _cell(AppFormatters.amount(item.totalAmount),
                            alignment: pw.Alignment.centerRight),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: <pw.Widget>[
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: <pw.Widget>[
                      _totalRow('Subtotal', data.subtotal),
                      _totalRow('Discount', data.discount),
                      _totalRow('Tax', data.taxAmount),
                      pw.Container(
                        margin: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text(
                          'TOTAL  ${_moneyPrefix} ${AppFormatters.amount(data.totalAmount)}',
                          style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: primary),
                        ),
                      ),
                      _totalRow('Paid', data.paidAmount),
                      _totalRow('Outstanding', data.outstandingAmount),
                    ],
                  ),
                ],
              ),
              if (data.notes != null && data.notes!.isNotEmpty) ...<pw.Widget>[
                pw.SizedBox(height: 10),
                pw.Text('Notes: ${data.notes}', style: const pw.TextStyle(fontSize: 9)),
              ],
              pw.SizedBox(height: 24),
              pw.Divider(color: const PdfColor.fromInt(0xFFCBD5E1)),
              pw.Text(
                'This is a computer generated invoice. Status: ${data.status}.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B)),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Builds a payment receipt PDF.
  Future<Uint8List> paymentReceiptPdf(PaymentReceiptData data) async {
    final pw.Document doc = pw.Document();
    final PdfColor primary = const PdfColor.fromInt(0xFF14532D);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            children: <pw.Widget>[
              _header(data.showroomName, data.showroomAddress),
              pw.SizedBox(height: 16),
              pw.Center(
                child: pw.Text('PAYMENT RECEIPT',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                width: 400,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFCBD5E1))),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    _kv('Receipt No', data.paymentNumber),
                    _kv('Date', DateUtils.format(data.paymentDate)),
                    _kv('Received From', data.customerName),
                    if (data.invoiceNumber != null) _kv('Against Invoice', data.invoiceNumber!),
                    _kv('Amount', '$_moneyPrefix ${AppFormatters.amount(data.amount)}'),
                    _kv('Method', AppFormatters.humanize(data.method)),
                    if (data.referenceNumber.isNotEmpty) _kv('Reference', data.referenceNumber),
                    if (data.receivedBy != null) _kv('Received By', data.receivedBy!),
                    _kv('Status', AppFormatters.humanize(data.status)),
                  ],
                ),
              ),
              pw.SizedBox(height: 60),
              pw.Divider(color: const PdfColor.fromInt(0xFFCBD5E1)),
              pw.Text('Thank you for your payment.',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Builds an EMI receipt PDF.
  Future<Uint8List> emiReceiptPdf(EmiReceiptData data) async {
    final pw.Document doc = pw.Document();
    final PdfColor primary = const PdfColor.fromInt(0xFF14532D);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            children: <pw.Widget>[
              _header(data.showroomName, data.showroomAddress),
              pw.SizedBox(height: 16),
              pw.Center(
                child: pw.Text('EMI PAYMENT RECEIPT',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                width: 400,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFCBD5E1))),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    _kv('Loan No', data.loanNumber),
                    _kv('Paid Installment', 'EMI #${data.emiNumber}'),
                    _kv('Date', DateUtils.format(data.paymentDate)),
                    _kv('Customer', data.customerName),
                    _kv('EMI Amount', '$_moneyPrefix ${AppFormatters.amount(data.emiAmount)}'),
                    _kv('Principal', '$_moneyPrefix ${AppFormatters.amount(data.principalAmount)}'),
                    _kv('Interest', '$_moneyPrefix ${AppFormatters.amount(data.interestAmount)}'),
                    _kv('Loan Balance', '$_moneyPrefix ${AppFormatters.amount(data.loanBalance)}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 60),
              pw.Divider(color: const PdfColor.fromInt(0xFFCBD5E1)),
              pw.Text('This receipt confirms the EMI payment described above.',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Generic tabular report (P&L, sales, stock, ...). Long reports are split
  /// across pages with a repeated header.
  Future<Uint8List> reportPdf({
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
    Map<String, String>? meta,
  }) async {
    final pw.Document doc = pw.Document();
    final PdfColor primary = const PdfColor.fromInt(0xFF14532D);
    const int rowsPerPage = 28;
    final List<List<List<String>>> pages = rows.chunked(rowsPerPage);
    for (int i = 0; i < pages.length; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: <pw.Widget>[
                    pw.Text(title,
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: primary)),
                    pw.Text('Page ${i + 1} / ${pages.length}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                if (meta != null) ...<pw.Widget>[
                  pw.SizedBox(height: 6),
                  pw.Text(meta.values.join('   |   '),
                      style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
                ],
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCBD5E1)),
                  children: <pw.TableRow>[
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFF1F5F9)),
                      children: <pw.Widget>[
                        for (final String column in columns) _head(column),
                      ],
                    ),
                    for (final List<String> row in pages[i])
                      pw.TableRow(
                        children: <pw.Widget>[
                          for (final String cell in row)
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                              child: pw.Text(cell, style: const pw.TextStyle(fontSize: 8)),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }
    return doc.save();
  }

  /// Prints the PDF using the platform print dialog.
  Future<void> printPdf(Uint8List bytes, {required String filename}) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: filename,
      );
    } catch (e) {
      AppLogger.error('PDF', 'print failed', error: e);
    }
  }

  /// Saves the PDF to the documents directory; returns the file path.
  Future<String> savePdf(Uint8List bytes, {required String filename}) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ---------------------------------------------------------------- private

  pw.Widget _header(String name, String address, [String? phone, String? gst]) {
    final PdfColor primary = const PdfColor.fromInt(0xFF14532D);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          width: 42,
          height: 42,
          color: primary,
          alignment: pw.Alignment.center,
          child: pw.Text('EB',
              style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFFFFFFFF))),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(name,
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: primary)),
              if (address.isNotEmpty)
                pw.Text(address, style: const pw.TextStyle(fontSize: 8)),
              if (phone != null && phone.isNotEmpty)
                pw.Text('Ph: $phone', style: const pw.TextStyle(fontSize: 8)),
              if (gst != null && gst.isNotEmpty)
                pw.Text('GSTIN: $gst', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _head(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _cell(String text, {pw.Alignment alignment = pw.Alignment.center}) {
    pw.TextAlign textAlign = pw.TextAlign.center;
    if (alignment == pw.Alignment.centerRight) {
      textAlign = pw.TextAlign.right;
    } else if (alignment == pw.Alignment.centerLeft) {
      textAlign = pw.TextAlign.left;
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9), textAlign: textAlign),
    );
  }

  pw.Widget _totalRow(String label, num value) {
    return pw.Row(
      children: <pw.Widget>[
        pw.Text('$label:  ', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('$_moneyPrefix ${AppFormatters.amount(value)}',
            style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  pw.Widget _kv(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Container(
            width: 130,
            child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF64748B))),
          ),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _label(String text) {
    return pw.Text(text,
        style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B)));
  }
}

/// Chunk helper for report pagination.
extension _ListChunkX<T> on List<T> {
  List<List<T>> chunked(int size) {
    final List<List<T>> chunks = <List<T>>[];
    for (int i = 0; i < length; i += size) {
      chunks.add(sublist(i, i + size > length ? length : i + size));
    }
    return chunks;
  }
}
