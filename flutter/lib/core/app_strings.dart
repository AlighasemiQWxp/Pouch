import 'dart:convert';

import 'package:flutter/services.dart';

class AppStrings {
  AppStrings(this.language, this._messages);

  final String language;
  final Map<String, String> _messages;

  bool get isPersian => language == 'fa';

  static Future<AppStrings> load(String language) async {
    final locale = language == 'fa' ? 'fa' : 'en';
    final source = await rootBundle.loadString(
      'assets/l10n/strings_$locale.json',
    );
    final messages = (jsonDecode(source) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return AppStrings(locale, messages);
  }

  String text(String key, [Map<String, Object> values = const {}]) {
    var result = _messages[key] ?? key;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return result;
  }
}
