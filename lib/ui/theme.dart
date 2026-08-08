import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours are the `:root` custom properties from textlog's styles.css, verbatim.
/// Keep them named as they are there — when the site changes, the diff is obvious.
final class Palette {
  const Palette({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.soft,
    required this.accent,
    required this.accentDark,
    required this.panel,
    required this.tagBg,
    required this.quoteInk,
    required this.quoteBg,
    required this.errorInk,
    required this.linkBorder,
  });

  final Color bg;
  final Color ink;
  final Color muted;
  final Color soft;
  final Color accent;
  final Color accentDark;
  final Color panel;
  final Color tagBg;
  final Color quoteInk;
  final Color quoteBg;
  final Color errorInk;

  /// Links are accent-coloured but underlined in a *quieter* colour — the detail
  /// that keeps a dense monospace feed from looking like a wall of green.
  final Color linkBorder;

  static const light = Palette(
    bg: Color(0xfff4f3ee),
    ink: Color(0xff20231f),
    muted: Color(0xff8a9085),
    soft: Color(0xffd9dbd4),
    accent: Color(0xff749668),
    accentDark: Color(0xff55734a),
    panel: Color(0xffffffff),
    tagBg: Color(0xffe6e9df),
    quoteInk: Color(0xff6f766c),
    quoteBg: Color(0x0f749668), // rgb(116 150 104 / 6%)
    errorInk: Color(0xff7a3f39),
    linkBorder: Color(0xffafb4a9),
  );

  static const dark = Palette(
    bg: Color(0xff171a17),
    ink: Color(0xffe5e8e1),
    muted: Color(0xff969d92),
    soft: Color(0xff343a33),
    accent: Color(0xff9abd8e),
    accentDark: Color(0xffb2d1a8),
    panel: Color(0xff20241f),
    tagBg: Color(0xff292f28),
    quoteInk: Color(0xffa8afa4),
    quoteBg: Color(0x149abd8e), // rgb(154 189 142 / 8%)
    errorInk: Color(0xffefb3aa),
    linkBorder: Color(0xff50594d),
  );
}

/// The site's `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` stack,
/// pinned to one bundled face so Android, iOS and web render identically.
const monoFamily = 'RobotoMono';

/// The site's `--space-*` scale.
const space1 = 4.0;
const space2 = 8.0;
const space3 = 12.0;
const space4 = 16.0;
const space5 = 24.0;
const space6 = 32.0;

/// `.parent-quote` indent: `clamp(16px, 3vw, 24px)`
double quoteIndentOf(BuildContext context) =>
    math.min(24.0, math.max(16.0, MediaQuery.sizeOf(context).width * 0.03));

/// `--gutter: clamp(18px, 3vw, 28px)`
double gutterOf(BuildContext context) =>
    math.min(28.0, math.max(18.0, MediaQuery.sizeOf(context).width * 0.03));

extension PaletteOf on BuildContext {
  Palette get palette =>
      Theme.of(this).brightness == Brightness.dark ? Palette.dark : Palette.light;
}

/// `a { color: var(--accent); border-bottom: 1px solid var(--link-border) }`
extension LinkStyle on TextStyle {
  TextStyle asLink(Palette palette) => copyWith(
    color: palette.accent,
    decoration: TextDecoration.underline,
    decorationColor: palette.linkBorder,
  );
}

ThemeData textlogTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? Palette.dark : Palette.light;

  // RobotoMono ships as a variable font, so weight has to be set as an axis as
  // well — fontWeight alone leaves it at 400.
  TextStyle mono(double size, {FontWeight? weight, double? height, Color? color}) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    fontVariations: weight == null
        ? null
        : [FontVariation.weight(weight.value.toDouble())],
    height: height,
    color: color ?? palette.ink,
  );

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      surface: palette.bg,
    ),
    dividerColor: palette.soft,
    textSelectionTheme: TextSelectionThemeData(selectionColor: palette.accent),
    // `.post p` is 13px/1.65; `.posttop` and nav are 12px; `.feedhead` is 11px.
    textTheme: TextTheme(
      titleLarge: mono(20, weight: FontWeight.w800, height: 1),
      bodyMedium: mono(13, height: 1.65),
      bodySmall: mono(12),
      labelSmall: mono(11, color: palette.muted),
    ),
  );
}
