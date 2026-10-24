import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_formatters.dart';
import '../../widgets/pouch_widgets.dart';
import 'dashboard_models.dart';

class DashboardProgress extends StatelessWidget {
  const DashboardProgress({
    required this.values,
    required this.strings,
    required this.currency,
    super.key,
  });

  final List<DashboardProgressValue> values;
  final AppStrings strings;
  final String currency;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final value in values)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PouchSummaryRow(
                label: value.name.isEmpty
                    ? strings.text(value.key)
                    : value.name,
                value: formatMoney(value.amount, currency, strings),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: value.basisPoints / 10000,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
                semanticsLabel: value.name.isEmpty
                    ? strings.text(value.key)
                    : value.name,
              ),
              const SizedBox(height: 6),
              Text(
                value.target > 0
                    ? strings.text('dashboardTarget', {
                        'amount': formatMoney(value.target, currency, strings),
                      })
                    : strings.text('dashboardNoTarget'),
              ),
            ],
          ),
        ),
    ],
  );
}
