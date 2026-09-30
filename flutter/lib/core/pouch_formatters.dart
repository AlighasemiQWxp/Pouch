import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app_strings.dart';

String formatMoney(int hundredths, String currency, AppStrings strings) {
  final value = hundredths / 100;
  if (currency == 'TOMAN') {
    return '${NumberFormat.decimalPattern(strings.language).format(value)} ${strings.text('toman')}';
  }
  return NumberFormat.currency(
    locale: strings.language,
    name: currency,
    symbol: currency,
    decimalDigits: 2,
  ).format(value);
}

String amountInput(int hundredths, {String language = 'en'}) {
  final whole = hundredths ~/ 100;
  final fraction = hundredths % 100;
  var value = '$whole';
  if (fraction != 0) {
    if (fraction % 10 == 0) {
      value = '$value.${fraction ~/ 10}';
    } else {
      value = '$value.${fraction.toString().padLeft(2, '0')}';
    }
  }
  return formatMoneyEntry(value, language);
}

String formatMoneyEntry(String value, String language) {
  var normalized = _normalizeMoneyEntry(value);
  if (normalized.startsWith('.')) normalized = '0$normalized';
  final decimalIndex = normalized.indexOf('.');
  final whole = decimalIndex < 0
      ? normalized
      : normalized.substring(0, decimalIndex);
  final fraction = decimalIndex < 0
      ? ''
      : normalized.substring(decimalIndex + 1);
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => language == 'fa' ? '٬' : ',',
  );
  final decimal = language == 'fa' ? '٫' : '.';
  final result = decimalIndex < 0 ? grouped : '$grouped$decimal$fraction';
  return localizeDigits(result, language);
}

String _normalizeMoneyEntry(String value) {
  final output = StringBuffer();
  var hasDecimal = false;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final digit = _asciiDigit(character);
    if (digit != null) {
      output.write(digit);
      continue;
    }
    if ((character == '.' || character == '٫') && !hasDecimal) {
      output.write('.');
      hasDecimal = true;
    }
  }
  return output.toString();
}

String? _asciiDigit(String character) {
  final code = character.runes.first;
  if (code >= 48 && code <= 57) return character;
  if (code >= 0x06F0 && code <= 0x06F9) {
    return String.fromCharCode(code - 0x06F0 + 48);
  }
  if (code >= 0x0660 && code <= 0x0669) {
    return String.fromCharCode(code - 0x0660 + 48);
  }
  return null;
}

class PouchMoneyInputFormatter extends TextInputFormatter {
  PouchMoneyInputFormatter(this.language);

  final String language;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final cursor = newValue.selection.baseOffset
        .clamp(0, newValue.text.length)
        .toInt();
    final beforeCursor = newValue.text.substring(0, cursor);
    final digitsBeforeCursor = _normalizeMoneyEntry(beforeCursor)
        .replaceAll('.', '')
        .length;
    final decimalBeforeCursor =
        beforeCursor.contains('.') || beforeCursor.contains('٫');
    final atEnd = cursor == newValue.text.length;
    final formatted = formatMoneyEntry(newValue.text, language);
    var offset = 0;
    var digitsSeen = 0;
    while (offset < formatted.length && digitsSeen < digitsBeforeCursor) {
      final char = formatted.substring(offset, offset + 1);
      if (_asciiDigit(char) != null || _isLocalizedDigit(char)) digitsSeen++;
      offset++;
    }
    if (decimalBeforeCursor &&
        !formatted.substring(0, offset).contains('.') &&
        !formatted.substring(0, offset).contains('٫')) {
      final dot = formatted.indexOf(language == 'fa' ? '٫' : '.');
      if (dot >= 0) offset = dot + 1;
    }
    if (atEnd) offset = formatted.length;
    if (offset < 0) offset = 0;
    if (offset > formatted.length) offset = formatted.length;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  bool _isLocalizedDigit(String character) {
    final code = character.runes.first;
    return (code >= 0x06F0 && code <= 0x06F9) ||
        (code >= 0x0660 && code <= 0x0669);
  }
}

String localizeDigits(String value, String language) {
  if (language != 'fa') return value;
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  return value.replaceAllMapped(RegExp(r'\d'), (match) {
    return persianDigits[int.parse(match.group(0)!)];
  });
}

String formatGregorianDate(String value, String language) {
  final date = DateTime.parse(value);
  return DateFormat.yMMMd(language).format(date);
}

String formatJalaliDate(int year, int month, int day, String language) {
  final separator = language == 'fa' ? ' / ' : '/';
  final yearText = localizeDigits(year.toString(), language);
  final monthText = localizeDigits(month.toString().padLeft(2, '0'), language);
  final dayText = localizeDigits(day.toString().padLeft(2, '0'), language);
  return '$yearText$separator$monthText$separator$dayText';
}
