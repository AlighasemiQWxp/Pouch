import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/app_strings.dart';
import '../../core/pouch_formatters.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import 'dashboard_models.dart';

class DashboardSeries {
  const DashboardSeries(this.label, this.values);
  final String label;
  final List<int> values;
}

List<Color> _colors(BuildContext context) => [
  context.pouchPalette.goldDeep,
  const Color(0xFF397E83),
  const Color(0xFF9B6A91),
  const Color(0xFFB27E35),
  const Color(0xFF587DA9),
  const Color(0xFF937C61),
  const Color(0xFF6E8656),
];

class DashboardChart extends StatefulWidget {
  const DashboardChart({
    required this.title,
    required this.hint,
    required this.labels,
    required this.series,
    required this.strings,
    required this.currency,
    this.line = false,
    this.switchable = false,
    this.interactiveLegend = false,
    this.steps = false,
    super.key,
  });

  final String title, hint, currency;
  final List<String> labels;
  final List<DashboardSeries> series;
  final AppStrings strings;
  final bool line, switchable, steps, interactiveLegend;

  @override
  State<DashboardChart> createState() => _DashboardChartState();
}

class _DashboardChartState extends State<DashboardChart> {
  final Set<int> _hidden = {};
  late bool _line = widget.line;
  bool _table = false;

  String _money(int amount) =>
      formatMoney(amount, widget.currency, widget.strings);
  String _label(int index) =>
      localizeDigits(widget.labels[index], widget.strings.language);

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final active = [
      for (var i = 0; i < widget.series.length; i++)
        if (!_hidden.contains(i)) i,
    ];
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: widget.title),
          const SizedBox(height: 8),
          Text(widget.hint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.series.length; i++)
                if (widget.interactiveLegend)
                  FilterChip(
                    avatar: Icon(
                      Icons.circle,
                      size: 12,
                      color: colors[i % colors.length],
                    ),
                    label: Text(widget.series[i].label),
                    selected: !_hidden.contains(i),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _hidden.remove(i);
                      } else {
                        _hidden.add(i);
                      }
                    }),
                  )
                else
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: colors[i % colors.length],
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: Text(widget.series[i].label)),
                      ],
                    ),
                  ),
              if (widget.switchable)
                ActionChip(
                  avatar: Icon(_line ? Icons.bar_chart : Icons.show_chart),
                  label: Text(
                    widget.strings.text(
                      _line ? 'dashboardBars' : 'dashboardLines',
                    ),
                  ),
                  onPressed: () => setState(() => _line = !_line),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.labels.isEmpty || active.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(widget.strings.text('dashboardNoSeries')),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = _line
                    ? constraints.maxWidth
                    : math.max(
                        constraints.maxWidth,
                        widget.labels.length * 42.0,
                      );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: 260,
                    child: ExcludeSemantics(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12, right: 12),
                          child: _line
                              ? LineChart(
                                  _lineData(active, colors),
                                  duration: duration,
                                )
                              : BarChart(
                                  _barData(active, colors),
                                  duration: duration,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Text(
            widget.strings.text('dashboardChartHint', {
              'currency': widget.currency,
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(widget.strings.text('dashboardViewData')),
            onExpansionChanged: (value) => setState(() => _table = value),
            children: [
              if (_table)
                for (var i = 0; i < widget.labels.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _label(i),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        for (final series in widget.series)
                          PouchSummaryRow(
                            label: series.label,
                            value: _money(series.values[i]),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  FlTitlesData _titles() => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        getTitlesWidget: (value, meta) => Text(
          NumberFormat.compact(locale: widget.strings.language)
              .format(value / 100),
          style: const TextStyle(fontSize: 10),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 40,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 ||
              index >= widget.labels.length ||
              value != index.toDouble()) {
            return const SizedBox.shrink();
          }
          final every = math.max(1, (widget.labels.length / 3).ceil());
          if (index % every != 0 && index != widget.labels.length - 1) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              localizeDigits(
                widget.labels[index].split('\n').first.split(' – ').first,
                widget.strings.language,
              ),
              style: const TextStyle(fontSize: 10),
            ),
          );
        },
      ),
    ),
  );

  (double, double) _bounds(List<int> active) {
    var low = 0.0;
    var high = 0.0;
    for (final index in active) {
      for (final value in widget.series[index].values) {
        low = math.min(low, value.toDouble());
        high = math.max(high, value.toDouble());
      }
    }
    if (low == high) return (0, 1);
    final padding = (high - low) * 0.12;
    if (low < 0) low -= padding;
    return (low, high + padding);
  }

  LineChartData _lineData(
    List<int> active,
    List<Color> colors,
  ) => LineChartData(
    minY: _bounds(active).$1,
    maxY: _bounds(active).$2,
    minX: 0,
    maxX: math.max(1, widget.labels.length - 1).toDouble(),
    titlesData: _titles(),
    gridData: const FlGridData(drawVerticalLine: false),
    borderData: FlBorderData(show: false),
    lineBarsData: [
      for (final i in active)
        LineChartBarData(
          color: colors[i % colors.length],
          barWidth: 2.5,
          isCurved: false,
          isStepLineChart: widget.steps,
          dotData: FlDotData(show: widget.labels.length == 1),
          spots: [
            for (var j = 0; j < widget.labels.length; j++)
              FlSpot(j.toDouble(), widget.series[i].values[j].toDouble()),
          ],
        ),
    ],
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: (spots) => [
          for (final spot in spots)
            LineTooltipItem(
              '${_label(spot.spotIndex)}\n${widget.series[active[spot.barIndex]].label}\n'
              '${_money(widget.series[active[spot.barIndex]].values[spot.spotIndex])}',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    ),
  );

  BarChartData _barData(List<int> active, List<Color> colors) => BarChartData(
    minY: _bounds(active).$1,
    maxY: _bounds(active).$2,
    titlesData: _titles(),
    gridData: const FlGridData(drawVerticalLine: false),
    borderData: FlBorderData(show: false),
    barGroups: [
      for (var j = 0; j < widget.labels.length; j++)
        BarChartGroupData(
          x: j,
          barRods: [
            for (final i in active)
              BarChartRodData(
                toY: widget.series[i].values[j].toDouble(),
                width: 10,
                color: colors[i % colors.length],
                borderRadius: BorderRadius.circular(3),
              ),
          ],
        ),
    ],
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
          '${_label(group.x)}\n${widget.series[active[rodIndex]].label}\n'
          '${_money(widget.series[active[rodIndex]].values[group.x])}',
          const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ),
  );
}

class DashboardDonut extends StatefulWidget {
  const DashboardDonut({
    required this.title,
    required this.hint,
    required this.values,
    required this.currency,
    required this.strings,
    super.key,
  });
  final String title, hint, currency;
  final List<DashboardSlice> values;
  final AppStrings strings;

  @override
  State<DashboardDonut> createState() => _DashboardDonutState();
}

class _DashboardDonutState extends State<DashboardDonut> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final values = widget.values.where((value) => value.amount > 0).toList();
    String text(int index) =>
        '${widget.strings.text(values[index].key)}: '
        '${formatMoney(values[index].amount, widget.currency, widget.strings)}';
    return PouchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PouchSectionHeading(title: widget.title),
          const SizedBox(height: 8),
          Text(widget.hint),
          const SizedBox(height: 16),
          if (values.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(widget.strings.text('dashboardNoSeries')),
            )
          else ...[
            SizedBox(
              height: 200,
              child: ExcludeSemantics(
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 48,
                    sectionsSpace: 3,
                    sections: [
                      for (var i = 0; i < values.length; i++)
                        PieChartSectionData(
                          value: values[i].amount.toDouble(),
                          color: colors[i % colors.length],
                          radius: _selected == i ? 45 : 37,
                          showTitle: false,
                        ),
                    ],
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final index =
                            response?.touchedSection?.touchedSectionIndex;
                        setState(() {
                          _selected = null;
                          if (event.isInterestedForInteractions &&
                              index != null &&
                              index >= 0 &&
                              index < values.length) {
                            _selected = index;
                          }
                        });
                      },
                    ),
                  ),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                ),
              ),
            ),
            if (_selected != null && _selected! < values.length)
              Semantics(
                liveRegion: true,
                child: Text(text(_selected!), textAlign: TextAlign.center),
              ),
            const SizedBox(height: 12),
            for (var i = 0; i < values.length; i++)
              Tooltip(
                message: text(i),
                child: TextButton(
                  onPressed: () => setState(() => _selected = i),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: colors[i % colors.length],
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(text(i))),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
