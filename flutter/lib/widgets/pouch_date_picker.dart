import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_strings.dart';
import '../core/pouch_bridge.dart';
import '../core/pouch_formatters.dart';
import '../core/pouch_models.dart';
import '../core/pouch_theme.dart';

// Keep both calendars and the preceding budget cycle within the core's 1900 limit.
const firstPouchRecordDate = '1900-03-01';

Future<String?> showPouchDatePicker({
  required BuildContext context,
  required PouchBridge bridge,
  required AppStrings strings,
  required String initialDate,
  required String calendar,
  required int weekStart,
  required String firstDate,
  required String lastDate,
  Set<String> highlightedDates = const {},
  Set<String>? selectedDates,
}) => showDialog<String>(
  context: context,
  builder: (context) => _PouchDateDialog(
    bridge: bridge,
    strings: strings,
    initialDate: initialDate,
    calendar: calendar,
    weekStart: weekStart,
    firstDate: firstDate,
    lastDate: lastDate,
    highlightedDates: highlightedDates,
    selectedDates: selectedDates,
  ),
);

class PouchDateLabel extends StatelessWidget {
  const PouchDateLabel({
    required this.bridge,
    required this.strings,
    required this.date,
    required this.calendar,
    super.key,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final String date;
  final String calendar;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _formatDate(bridge, date, calendar, strings),
    builder: (context, snapshot) => Text(
      snapshot.data ?? localizeDigits(date, strings.language),
      textAlign: TextAlign.start,
    ),
  );
}

Future<String> formatPouchDate(
  PouchBridge bridge,
  String date,
  String calendar,
  AppStrings strings,
) => _formatDate(bridge, date, calendar, strings);

Future<String> _formatDate(
  PouchBridge bridge,
  String date,
  String calendar,
  AppStrings strings,
) async {
  if (calendar == 'gregory') return formatGregorianDate(date, strings.language);
  final parts = await bridge.dateParts(date, calendar);
  return formatJalaliDate(parts.$1, parts.$2, parts.$3, strings.language);
}

class _PouchDateDialog extends StatefulWidget {
  const _PouchDateDialog({
    required this.bridge,
    required this.strings,
    required this.initialDate,
    required this.calendar,
    required this.weekStart,
    required this.firstDate,
    required this.lastDate,
    required this.highlightedDates,
    required this.selectedDates,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final String initialDate;
  final String calendar;
  final int weekStart;
  final String firstDate;
  final String lastDate;
  final Set<String> highlightedDates;
  final Set<String>? selectedDates;

  @override
  State<_PouchDateDialog> createState() => _PouchDateDialogState();
}

class _PouchDateDialogState extends State<_PouchDateDialog> {
  late Future<PouchCalendarMonth> _month = widget.bridge.calendarMonth(
    widget.initialDate,
    widget.calendar,
    0,
  );
  late final Future<List<PouchCalendarMonth>> _bounds = Future.wait([
    widget.bridge.calendarMonth(widget.firstDate, widget.calendar, 0),
    widget.bridge.calendarMonth(_lastDate, widget.calendar, 0),
  ]);

  String get _lastDate {
    const jalaliConversionLimit = '3797-12-31';
    if (widget.calendar == 'persian' &&
        widget.lastDate.compareTo(jalaliConversionLimit) > 0) {
      return jalaliConversionLimit;
    }
    return widget.lastDate;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
    contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    title: FutureBuilder<List<PouchCalendarMonth>>(
      future: _bounds,
      builder: (context, bounds) => FutureBuilder<PouchCalendarMonth>(
        future: _month,
        builder: (context, month) {
          if (!bounds.hasData || !month.hasData) {
            return const LinearProgressIndicator();
          }
          final range = bounds.data!;
          final currentIndex = _monthIndex(month.data!);
          final minIndex = _monthIndex(range[0]);
          final maxIndex = _monthIndex(range[1]);
          return Row(
            children: [
              IconButton(
                tooltip: widget.strings.text('previousMonth'),
                onPressed: currentIndex <= minIndex ? null : () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  _monthTitle(month.data!),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: widget.strings.text('nextMonth'),
                onPressed: currentIndex >= maxIndex ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          );
        },
      ),
    ),
    content: FutureBuilder<PouchCalendarMonth>(
      future: _month,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            height: 280,
            child: Center(child: Text(widget.strings.text('invalidDate'))),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final month = snapshot.data!;
        final firstOffset = (month.firstWeekday - widget.weekStart + 7) % 7;
        final count = firstOffset + month.dayCount;
        final weekdayLabels = List.generate(7, (index) {
          final weekday = (widget.weekStart + index) % 7;
          return DateFormat.E(widget.strings.language)
              .format(DateTime.utc(2023, 1, weekday + 1));
        });
        return SizedBox(
          width: 330,
          height: 306,
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in weekdayLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: context.pouchPalette.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: count,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemBuilder: (context, index) {
                    final day = index - firstOffset + 1;
                    if (day < 1) return const SizedBox.shrink();
                    final iso = _dayIso(month, day);
                    final isSelected =
                        widget.selectedDates?.contains(iso) ??
                        _sameDate(widget.initialDate, month, day);
                    final isHighlighted = widget.highlightedDates.contains(iso);
                    final enabled =
                        iso.compareTo(widget.firstDate) >= 0 &&
                        iso.compareTo(_lastDate) <= 0;
                    return TextButton(
                      onPressed: enabled ? () => _select(month, day) : null,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        foregroundColor: isSelected
                            ? Colors.white
                            : context.pouchPalette.ink,
                        backgroundColor: isSelected
                            ? context.pouchPalette.goldDeep
                            : Colors.transparent,
                        shape: const CircleBorder(),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(localizeDigits('$day', widget.strings.language)),
                          if (isHighlighted)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : context.pouchPalette.goldBright,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.text('cancel')),
      ),
    ],
  );

  void _shift(int count) {
    final month = _month;
    setState(() {
      _month = month.then(
        (value) => widget.bridge.calendarMonth(
          value.startDate,
          widget.calendar,
          count,
        ),
      );
    });
  }

  Future<void> _select(PouchCalendarMonth month, int day) async {
    final date = await widget.bridge.calendarDate(
      year: month.year,
      month: month.month,
      day: day,
      calendar: widget.calendar,
    );
    if (mounted) Navigator.pop(context, date);
  }

  String _monthTitle(PouchCalendarMonth month) {
    if (widget.calendar == 'gregory') {
      return DateFormat.MMMM(widget.strings.language)
          .format(DateTime.utc(month.year, month.month));
    }
    const english = [
      'Farvardin',
      'Ordibehesht',
      'Khordad',
      'Tir',
      'Mordad',
      'Shahrivar',
      'Mehr',
      'Aban',
      'Azar',
      'Dey',
      'Bahman',
      'Esfand',
    ];
    const persian = [
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    final names = widget.strings.isPersian ? persian : english;
    return '${names[month.month - 1]} ${localizeDigits('${month.year}', widget.strings.language)}';
  }

  bool _sameDate(String value, PouchCalendarMonth month, int day) =>
      value == _dayIso(month, day);

  String _dayIso(PouchCalendarMonth month, int day) {
    final offset = month.startDate;
    return DateTime.parse('${offset}T00:00:00Z')
        .add(Duration(days: day - 1))
        .toIso8601String()
        .substring(0, 10);
  }

  int _monthIndex(PouchCalendarMonth month) => month.year * 12 + month.month;
}
