import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/features/forecast/forecast_metric.dart';

void main() {
  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    for (final width in [280.0, 1000.0]) {
      testWidgets('Forecast metrics fit $width pixels in $direction', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: ForecastMetricGrid(
                    children: const [
                      ForecastMetric(
                        label: 'Fixed and essential expenses',
                        value: '30,000,000 Toman',
                      ),
                      ForecastMetric(
                        label: 'پس‌انداز موردنیاز برای رسیدن به هدف',
                        value: '۸٬۵۰۰٬۰۰۰ تومان',
                      ),
                      ForecastMetric(
                        label: 'Estimated completion',
                        value: '962 days · 04/03/1408',
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('30,000,000 Toman'), findsOneWidget);
        expect(find.text('۸٬۵۰۰٬۰۰۰ تومان'), findsOneWidget);
        expect(find.text('962 days · 04/03/1408'), findsOneWidget);
      });
    }
  }
}
