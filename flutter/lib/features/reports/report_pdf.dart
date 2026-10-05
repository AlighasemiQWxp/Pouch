import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/app_strings.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_models.dart';

Future<Uint8List> buildPouchReportPdf({
  required PouchReport report,
  required AppStrings strings,
  required String currency,
  required Future<String> Function(String) formatDate,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Amiri-Bold.ttf'),
  );
  final daily = <List<String>>[];
  for (final day in report.daily) {
    daily.add([
      await formatDate(day.date),
      formatMoney(day.amount, currency, strings),
    ]);
  }
  final entries = <List<String>>[];
  for (final entry in report.entries) {
    entries.add([
      await formatDate(entry.date),
      entry.description,
      strings.text(entry.category),
      formatMoney(entry.amount, currency, strings),
    ]);
  }
  final planned = <List<String>>[];
  for (final entry in report.planned) {
    planned.add([
      await formatDate(entry.date),
      entry.description,
      strings.text(entry.category),
      formatMoney(entry.amount, currency, strings),
    ]);
  }
  final direction = strings.isPersian
      ? pw.TextDirection.rtl
      : pw.TextDirection.ltr;
  final headings = [
    'date',
    'description',
    'category',
    'amount',
  ].map(strings.text).toList();
  pw.Widget table(List<List<String>> rows, List<String> headers) {
    final orderedHeaders = headers;
    final orderedRows = rows;
    if (strings.isPersian) {
      return pw.TableHelper.fromTextArray(
        headerDirection: direction,
        tableDirection: direction,
        headers: orderedHeaders.reversed.toList(),
        data: orderedRows.map((row) => row.reversed.toList()).toList(),
        cellAlignment: pw.Alignment.centerRight,
        headerStyle: pw.TextStyle(font: bold),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xfff7edd9),
        ),
        cellPadding: const pw.EdgeInsets.all(7),
      );
    }
    return pw.TableHelper.fromTextArray(
      headerDirection: direction,
      tableDirection: direction,
      headers: orderedHeaders,
      data: orderedRows,
      cellAlignment: pw.Alignment.centerLeft,
      headerStyle: pw.TextStyle(font: bold),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xfff7edd9),
      ),
      cellPadding: const pw.EdgeInsets.all(7),
    );
  }

  final document = pw.Document(
    title: strings.text('reportTitle'),
    author: 'Pouch',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 10000,
      textDirection: direction,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (_) => [
        pw.Text(
          strings.text('reportTitle'),
          style: pw.TextStyle(font: bold, fontSize: 22),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          '${strings.text('totalSpent')}: ${formatMoney(report.total, currency, strings)}',
        ),
        pw.Text(
          '${strings.text('totalPlanned')}: ${formatMoney(report.reserved, currency, strings)}',
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          strings.text('dailyTotals'),
          style: pw.TextStyle(font: bold, fontSize: 16),
        ),
        table(daily, [strings.text('date'), strings.text('amount')]),
        pw.SizedBox(height: 16),
        pw.Text(
          strings.text('details'),
          style: pw.TextStyle(font: bold, fontSize: 16),
        ),
        table(entries, headings),
        pw.SizedBox(height: 16),
        pw.Text(
          strings.text('plannedReport'),
          style: pw.TextStyle(font: bold, fontSize: 16),
        ),
        table(planned, headings),
        pw.SizedBox(height: 16),
        pw.Text(strings.text('reportFootnote')),
      ],
    ),
  );
  return document.save();
}
