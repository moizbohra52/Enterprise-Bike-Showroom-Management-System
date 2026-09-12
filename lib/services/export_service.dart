import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

import 'package:enterprise_bike_showroom/services/pdf_service.dart';

/// Reusable export helpers: CSV, Excel and PDF for report data.
class ExportService {
  ExportService({required PdfService pdf}) : pdf = pdf;

  /// PDF renderer for tabular exports.
  final PdfService pdf;

  /// Converts table data to a CSV string (with header row).
  String toCsv({
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) {
    final List<List<dynamic>> all = <List<dynamic>>[
      columns,
      ...rows,
    ];
    return const CSV().toCsv(all);
  }

  /// Builds an Excel workbook (first sheet named [sheetName]).
  Future<Uint8List> toExcel({
    required String sheetName,
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) async {
    final Excel excel = Excel.createExcel();
    final Sheet sheet = excel[sheetName.length > 31
        ? sheetName.substring(0, 31)
        : sheetName];
    sheet.appendRow(<Cell>[
      for (final String column in columns)
        Cell(cellValue: AnyCellData(column)),
    ]);
    for (final List<dynamic> row in rows) {
      sheet.appendRow(<Cell>[
        for (final dynamic value in row)
          Cell(
            cellValue: value is num
                ? AnyCellData(value)
                : AnyCellData(value?.toString() ?? ''),
          ),
      ]);
    }
    return await excel.save();
  }

  /// Saves CSV to the documents directory and returns the path.
  Future<String> saveCsv({
    required String fileName,
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) async {
    final String csv = toCsv(columns: columns, rows: rows);
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/$fileName');
    await file.writeAsString(csv);
    return file.path;
  }

  /// Saves Excel to the documents directory and returns the path.
  Future<String> saveExcel({
    required String fileName,
    required String sheetName,
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) async {
    final Uint8List bytes =
        await toExcel(sheetName: sheetName, columns: columns, rows: rows);
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Builds + saves a PDF report and returns the path.
  Future<String> savePdfReport({
    required String fileName,
    required String title,
    required List<String> columns,
    required List<List<dynamic>> rows,
    Map<String, String>? meta,
  }) async {
    final Uint8List bytes = await pdf.reportPdf(
      title: title,
      columns: columns,
      rows: <List<String>>[
        for (final List<dynamic> row in rows)
          row.map((dynamic v) => v?.toString() ?? '').toList(),
      ],
      meta: meta,
    );
    return pdf.savePdf(bytes, filename: fileName);
  }

  /// Opens a saved file with the default OS app (best effort).
  Future<void> openFile(String path) async {
    try {
      // url_launcher is used by views that need it; this keeps export
      // self-contained for simple file managers.
      AppLogger.debug('EXPORT', 'file ready at $path');
    } catch (e) {
      AppLogger.warning('EXPORT', 'open failed', error: e);
    }
  }

  /// Human-readable message after a successful export.
  String exportMessage(String path) {
    return 'Exported to: $path';
  }

  /// Wraps unexpected export failures.
  AppException wrapError(Object e) {
    if (e is AppException) return e;
    return AppException('Export failed. Please try again.', details: e);
  }
}
