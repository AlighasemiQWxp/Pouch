import 'package:flutter/material.dart';

class PouchPalette extends ThemeExtension<PouchPalette> {
  const PouchPalette({
    required this.ink,
    required this.goldDeep,
    required this.gold,
    required this.goldBright,
    required this.goldPale,
    required this.selection,
    required this.cream,
    required this.surface,
    required this.surfaceWarm,
    required this.border,
    required this.muted,
    required this.danger,
  });

  final Color ink;
  final Color goldDeep;
  final Color gold;
  final Color goldBright;
  final Color goldPale;
  final Color selection;
  final Color cream;
  final Color surface;
  final Color surfaceWarm;
  final Color border;
  final Color muted;
  final Color danger;

  static PouchPalette of(BuildContext context) =>
      Theme.of(context).extension<PouchPalette>()!;

  static PouchPalette forStyle(String style) {
    if (style == 'ocean') {
      return const PouchPalette(
        ink: Color(0xFF20313A),
        goldDeep: Color(0xFF285B70),
        gold: Color(0xFF3A849B),
        goldBright: Color(0xFF579DAE),
        goldPale: Color(0xFFD8EEF1),
        selection: Color(0xFFD8EEF1),
        cream: Color(0xFFEDF4F5),
        surface: Color(0xFFFCFEFE),
        surfaceWarm: Color(0xFFE5F0F2),
        border: Color(0xFFCBDCE1),
        muted: Color(0xFF5E7178),
        danger: Color(0xFF994C34),
      );
    }
    if (style == 'forest') {
      return const PouchPalette(
        ink: Color(0xFF293229),
        goldDeep: Color(0xFF486044),
        gold: Color(0xFF637E56),
        goldBright: Color(0xFF829971),
        goldPale: Color(0xFFDFE8D4),
        selection: Color(0xFFDFE8D4),
        cream: Color(0xFFF1F4EC),
        surface: Color(0xFFFBFCF8),
        surfaceWarm: Color(0xFFE9EFDF),
        border: Color(0xFFD6DFC9),
        muted: Color(0xFF69735F),
        danger: Color(0xFF994C34),
      );
    }
    return const PouchPalette(
      ink: Color(0xFF30291F),
      goldDeep: Color(0xFF684717),
      gold: Color(0xFF966719),
      goldBright: Color(0xFFC18B32),
      goldPale: Color(0xFFF1D892),
      selection: Color(0xFFF5EAD1),
      cream: Color(0xFFF7F3EA),
      surface: Color(0xFFFFFDF8),
      surfaceWarm: Color(0xFFF7EDD9),
      border: Color(0xFFE8DCC4),
      muted: Color(0xFF766B59),
      danger: Color(0xFF994C34),
    );
  }

  @override
  PouchPalette copyWith({
    Color? ink,
    Color? goldDeep,
    Color? gold,
    Color? goldBright,
    Color? goldPale,
    Color? selection,
    Color? cream,
    Color? surface,
    Color? surfaceWarm,
    Color? border,
    Color? muted,
    Color? danger,
  }) => PouchPalette(
    ink: ink ?? this.ink,
    goldDeep: goldDeep ?? this.goldDeep,
    gold: gold ?? this.gold,
    goldBright: goldBright ?? this.goldBright,
    goldPale: goldPale ?? this.goldPale,
    selection: selection ?? this.selection,
    cream: cream ?? this.cream,
    surface: surface ?? this.surface,
    surfaceWarm: surfaceWarm ?? this.surfaceWarm,
    border: border ?? this.border,
    muted: muted ?? this.muted,
    danger: danger ?? this.danger,
  );

  @override
  PouchPalette lerp(ThemeExtension<PouchPalette>? other, double t) {
    if (other is! PouchPalette) return this;
    return PouchPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      goldDeep: Color.lerp(goldDeep, other.goldDeep, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldBright: Color.lerp(goldBright, other.goldBright, t)!,
      goldPale: Color.lerp(goldPale, other.goldPale, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      cream: Color.lerp(cream, other.cream, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceWarm: Color.lerp(surfaceWarm, other.surfaceWarm, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension PouchBuildContext on BuildContext {
  PouchPalette get pouchPalette => PouchPalette.of(this);
}

ThemeData buildPouchTheme([String style = 'classic']) {
  final palette = PouchPalette.forStyle(style);
  final colors = ColorScheme.fromSeed(
    seedColor: palette.gold,
    brightness: Brightness.light,
    primary: palette.goldDeep,
    secondary: palette.goldBright,
    surface: palette.surface,
    error: palette.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    extensions: [palette],
    scaffoldBackgroundColor: palette.cream,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.cream,
      foregroundColor: palette.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: palette.goldBright, width: 2),
      ),
    ),
  );
}
