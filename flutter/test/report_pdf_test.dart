import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/core/app_strings.dart';
import 'package:pouch/core/pouch_models.dart';
import 'package:pouch/features/reports/report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['en', 'fa']) {
    test('Long $language reports produce a multi-page offline PDF', () async {
      final strings = await AppStrings.load(language);
      final report = PouchReport(
        dates: const ['2026-10-01'],
        entries: List.generate(
          200,
          (index) => PouchReportEntry(
            date: '2026-10-01',
            id: '$index',
            description: 'Groceries / خرید مواد غذایی $index',
            amount: 123456,
            category: 'food',
            fundedByGoal: false,
          ),
        ),
        daily: const [PouchDailyTotal('2026-10-01', 24691200)],
        categories: const [],
        planned: const [],
        total: 24691200,
        reserved: 0,
      );
      final bytes = await buildPouchReportPdf(
        report: report,
        strings: strings,
        currency: 'USD',
        formatDate: (date) async => date,
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      final source = latin1.decode(bytes);
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(source).length,
        greaterThan(1),
      );
    });
  }
}
