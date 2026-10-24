import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../widgets/pouch_app_shell.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({
    required this.section,
    required this.strings,
    required this.onSelect,
    required this.child,
    super.key,
  });
  final AppPage section;
  final AppStrings strings;
  final ValueChanged<AppPage> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in [
              (AppPage.dashboard, 'insightsSpending'),
              (AppPage.reports, 'navReports'),
              (AppPage.forecast, 'insightsForecast'),
            ])
              ChoiceChip(
                key: ValueKey('insights-${entry.$1.name}'),
                label: Text(strings.text(entry.$2)),
                selected: section == entry.$1,
                onSelected: (_) => onSelect(entry.$1),
              ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}
