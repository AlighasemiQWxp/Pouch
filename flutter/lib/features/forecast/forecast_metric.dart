import 'package:flutter/material.dart';

class ForecastMetric extends StatelessWidget {
  const ForecastMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final caption = Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        );
        var amountStyle = Theme.of(context).textTheme.titleMedium;
        if (emphasized) amountStyle = Theme.of(context).textTheme.headlineSmall;
        final amount = Text(value, style: amountStyle);
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, const SizedBox(height: 6), amount],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: caption),
            const SizedBox(width: 16),
            Expanded(child: amount),
          ],
        );
      },
    ),
  );
}

class ForecastMetricGrid extends StatelessWidget {
  const ForecastMetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var columns = 1;
      if (constraints.maxWidth >= 540) columns = 2;
      if (constraints.maxWidth >= 900) columns = 3;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
