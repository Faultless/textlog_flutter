import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A whole colour scheme. `light` and `dark` are textlog's own `:root` custom
/// properties, verbatim and under their original names, so a change on the site is a
/// one-line diff here. `sepia` and `dracula` are ours.
///
/// This is a [ThemeExtension] rather than a pair of constants because there are now
/// four of them plus a user-chosen accent — the active palette has to travel with the
/// theme so every `context.palette` keeps working without threading it through.
@immutable
final class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.name,
    required this.brightness,
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
    required this.buttonBg,
    required this.buttonInk,
    required this.unfollowBg,
    required this.disabledBg,
    required this.disabledInk,
    required this.selfInk,
  });

  final String name;
  final Brightness brightness;
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

  final Color buttonBg;
  final Color buttonInk;
  final Color unfollowBg;
  final Color disabledBg;
  final Color disabledInk;

  /// Your own handle, so you can tell at a glance which posts in a thread are yours.
  final Color selfInk;

  /// Links are accent-coloured but underlined in a *quieter* colour — the detail
  /// that keeps a dense monospace feed from looking like a wall of one hue.
  final Color linkBorder;

  static const light = Palette(
    name: 'light',
    brightness: Brightness.light,
    bg: Color(0xfff4f3ee),
    ink: Color(0xff20231f),
    muted: Color(0xff8a9085),
    soft: Color(0xffd9dbd4),
    accent: Color(0xff749668),
    accentDark: Color(0xff55734a),
    panel: Color(0xffffffff),
    tagBg: Color(0xffe6e9df),
    quoteInk: Color(0xff6f766c),
    quoteBg: Color(0x0f749668),
    errorInk: Color(0xff7a3f39),
    linkBorder: Color(0xffafb4a9),
    buttonBg: Color(0xff273126),
    buttonInk: Color(0xffffffff),
    unfollowBg: Color(0xff65775e),
    disabledBg: Color(0xffd9dbd4),
    disabledInk: Color(0xff777d73),
    selfInk: Color(0xff2f6f5f),
  );

  static const dark = Palette(
    name: 'dark',
    brightness: Brightness.dark,
    bg: Color(0xff171a17),
    ink: Color(0xffe5e8e1),
    muted: Color(0xff969d92),
    soft: Color(0xff343a33),
    accent: Color(0xff9abd8e),
    accentDark: Color(0xffb2d1a8),
    panel: Color(0xff20241f),
    tagBg: Color(0xff292f28),
    quoteInk: Color(0xffa8afa4),
    quoteBg: Color(0x149abd8e),
    errorInk: Color(0xffefb3aa),
    linkBorder: Color(0xff50594d),
    buttonBg: Color(0xff3b503d),
    buttonInk: Color(0xffe5e8e1),
    unfollowBg: Color(0xff58705a),
    disabledBg: Color(0xff292f29),
    disabledInk: Color(0xff747c72),
    selfInk: Color(0xff7fd1bd),
  );

  /// Warm paper. Same bones as `light`, aged.
  static const sepia = Palette(
    name: 'sepia',
    brightness: Brightness.light,
    bg: Color(0xfff4ecd8),
    ink: Color(0xff433422),
    muted: Color(0xff8c7a5e),
    soft: Color(0xffe0d4b8),
    accent: Color(0xff8a6d3b),
    accentDark: Color(0xff6b5228),
    panel: Color(0xfffbf6e9),
    tagBg: Color(0xffeae0c6),
    quoteInk: Color(0xff6b5a42),
    quoteBg: Color(0x128a6d3b),
    errorInk: Color(0xff8a3f39),
    linkBorder: Color(0xffc4b593),
    buttonBg: Color(0xff4a3a24),
    buttonInk: Color(0xfffbf6e9),
    unfollowBg: Color(0xff8a7550),
    disabledBg: Color(0xffe0d4b8),
    disabledInk: Color(0xff8c7a5e),
    selfInk: Color(0xff2f6f5f),
  );

  /// The canonical Dracula values, mapped onto textlog's roles.
  static const dracula = Palette(
    name: 'dracula',
    brightness: Brightness.dark,
    bg: Color(0xff282a36),
    ink: Color(0xfff8f8f2),
    muted: Color(0xff6272a4),
    soft: Color(0xff44475a),
    accent: Color(0xffbd93f9),
    accentDark: Color(0xffd6b3ff),
    panel: Color(0xff21222c),
    tagBg: Color(0xff343746),
    quoteInk: Color(0xffb9bcd0),
    quoteBg: Color(0x1abd93f9),
    errorInk: Color(0xffff5555),
    linkBorder: Color(0xff4b4f6b),
    buttonBg: Color(0xff44475a),
    buttonInk: Color(0xfff8f8f2),
    unfollowBg: Color(0xff6272a4),
    disabledBg: Color(0xff343746),
    disabledInk: Color(0xff6272a4),
    selfInk: Color(0xff50fa7b),
  );

  static const all = [light, dark, sepia, dracula];

  /// Swap in a chosen accent. `accentDark` is the hover/active shade — darker on a
  /// light background, lighter on a dark one, which is what the site does too.
  Palette withAccent(Color? colour) {
    if (colour == null) return this;
    final hsl = HSLColor.fromColor(colour);
    final shifted = hsl
        .withLightness(
          (brightness == Brightness.dark ? hsl.lightness + 0.12 : hsl.lightness - 0.12)
              .clamp(0.0, 1.0),
        )
        .toColor();
    return copyWith(
      accent: colour,
      accentDark: shifted,
      quoteBg: colour.withValues(alpha: brightness == Brightness.dark ? 0.10 : 0.06),
    );
  }

  @override
  Palette copyWith({Color? accent, Color? accentDark, Color? quoteBg}) => Palette(
    name: name,
    brightness: brightness,
    bg: bg,
    ink: ink,
    muted: muted,
    soft: soft,
    accent: accent ?? this.accent,
    accentDark: accentDark ?? this.accentDark,
    panel: panel,
    tagBg: tagBg,
    quoteInk: quoteInk,
    quoteBg: quoteBg ?? this.quoteBg,
    errorInk: errorInk,
    linkBorder: linkBorder,
    buttonBg: buttonBg,
    buttonInk: buttonInk,
    unfollowBg: unfollowBg,
    disabledBg: disabledBg,
    disabledInk: disabledInk,
    selfInk: selfInk,
  );

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      name: t < 0.5 ? name : other.name,
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: mix(bg, other.bg),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      soft: mix(soft, other.soft),
      accent: mix(accent, other.accent),
      accentDark: mix(accentDark, other.accentDark),
      panel: mix(panel, other.panel),
      tagBg: mix(tagBg, other.tagBg),
      quoteInk: mix(quoteInk, other.quoteInk),
      quoteBg: mix(quoteBg, other.quoteBg),
      errorInk: mix(errorInk, other.errorInk),
      linkBorder: mix(linkBorder, other.linkBorder),
      buttonBg: mix(buttonBg, other.buttonBg),
      buttonInk: mix(buttonInk, other.buttonInk),
      unfollowBg: mix(unfollowBg, other.unfollowBg),
      disabledBg: mix(disabledBg, other.disabledBg),
      disabledInk: mix(disabledInk, other.disabledInk),
      selfInk: mix(selfInk, other.selfInk),
    );
  }
}

/// How much Material to draw.
///
/// This rides in the theme rather than being read from settings at every call site,
/// so a plain `StatelessWidget` deep in the tree can ask without being handed a ref.
@immutable
final class Chrome extends ThemeExtension<Chrome> {
  const Chrome({this.plain = false, this.scale = 1.0});

  /// Barebones mode. Icons become characters, filled buttons become `[ label ]`,
  /// switches become `[x]`, spinners become words, and nothing ripples or slides.
  ///
  /// Deliberately *not* included: pull to refresh. It is a gesture rather than
  /// chrome, and taking a standard mobile affordance away would make the app worse
  /// rather than more spartan.
  final bool plain;

  /// Text size multiplier, from the reading setting.
  final double scale;

  @override
  Chrome copyWith({bool? plain, double? scale}) =>
      Chrome(plain: plain ?? this.plain, scale: scale ?? this.scale);

  /// A boolean has no midpoint, so it flips at the animation's halfway mark.
  ///
  /// This cannot be made instant from here — `Tween.transform` short-circuits at
  /// `t == 0` and hands back the old theme without consulting `lerp` at all. Turning
  /// barebones *on* skips the crossfade a different way: the app drops the theme
  /// animation to zero while it is on, which is the behaviour that mode wants anyway.
  @override
  Chrome lerp(ThemeExtension<Chrome>? other, double t) =>
      other is Chrome && t >= 0.5 ? other : this;
}

extension ChromeOf on BuildContext {
  Chrome get chrome => Theme.of(this).extension<Chrome>() ?? const Chrome();
}

/// How big the body text runs. The site offers the same four.
enum TextSize {
  small('small', 0.9),
  regular('regular', 1.0),
  large('large', 1.15),
  larger('larger', 1.3);

  const TextSize(this.id, this.scale);

  final String id;
  final double scale;

  static TextSize fromId(String? id) =>
      values.firstWhere((choice) => choice.id == id, orElse: () => TextSize.regular);
}

/// Which palette to use. `system` follows the device between [Palette.light] and
/// [Palette.dark]; the rest are fixed.
enum ThemeChoice {
  system('system'),
  light('light'),
  dark('dark'),
  sepia('sepia'),
  dracula('dracula');

  const ThemeChoice(this.id);
  final String id;

  static ThemeChoice fromId(String? id) =>
      values.firstWhere((choice) => choice.id == id, orElse: () => ThemeChoice.system);

  Palette resolve(Brightness system) => switch (this) {
    ThemeChoice.system => system == Brightness.dark ? Palette.dark : Palette.light,
    ThemeChoice.light => Palette.light,
    ThemeChoice.dark => Palette.dark,
    ThemeChoice.sepia => Palette.sepia,
    ThemeChoice.dracula => Palette.dracula,
  };
}

/// Curated rather than a free colour picker: each one is tuned for both a light and
/// a dark background, so no choice can land you with unreadable links.
enum AccentChoice {
  theme('theme', null, null),
  sage('sage', Color(0xff749668), Color(0xff9abd8e)),
  purple('purple', Color(0xff7c5cbf), Color(0xffbd93f9)),
  cyan('cyan', Color(0xff2f7f8f), Color(0xff8be9fd)),
  pink('pink', Color(0xffb5487f), Color(0xffff79c6)),
  amber('amber', Color(0xff9a6614), Color(0xffffb86c)),
  blue('blue', Color(0xff3a6ea5), Color(0xff7aa2f7)),
  rust('rust', Color(0xffa33b32), Color(0xffff7b72));

  const AccentChoice(this.id, this.onLight, this.onDark);

  final String id;
  final Color? onLight;
  final Color? onDark;

  static AccentChoice fromId(String? id) =>
      values.firstWhere((choice) => choice.id == id, orElse: () => AccentChoice.theme);

  /// Null means "leave the palette's own accent alone".
  Color? forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? onDark : onLight;
}

/// Which monospace face to read in.
///
/// Both bundled fonts cover box drawing and block elements in full, which the
/// previous default (Roboto Mono) did not — it has none of them, so every `┌─┐` in
/// an ASCII-art post fell back to another face mid-line and the drawing came apart.
enum FontChoice {
  jetbrains('jetbrains', 'JetBrains Mono', 'JetBrainsMono', ligatures: false),
  fira('fira', 'Fira Code', 'FiraCode', ligatures: true),

  /// Whatever the platform calls monospace. Costs nothing to ship and is the face
  /// the website itself gets on the same device.
  system('system', 'System', null, ligatures: false);

  const FontChoice(this.id, this.label, this.family, {required this.ligatures});

  final String id;
  final String label;
  final String? family;
  final bool ligatures;

  static FontChoice fromId(String? id) =>
      values.firstWhere((choice) => choice.id == id, orElse: () => FontChoice.jetbrains);

  String get fontFamily => family ?? 'monospace';

  /// Only meaningful for `system`; a bundled family resolves on its own.
  List<String>? get fallback =>
      family == null ? const ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Consolas'] : null;

  /// Fira Code is the option you pick *for* ligatures. JetBrains Mono has them too,
  /// but it is offered as the sober one, so they are turned off there.
  List<FontFeature>? get features => ligatures
      ? null
      : const [FontFeature.disable('liga'), FontFeature.disable('calt')];
}

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

/// What one level of reply nesting costs.
///
/// The site indents by a gutter per level, which is fine at desktop width. On a
/// 390px phone five levels of that is a quarter of the screen gone before a word is
/// drawn, and the deepest replies read as a column two words wide. So the indent
/// scales with the room available: tight on a phone, the site's own gutter once
/// there is space for it.
double replyIndentOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 420) return 11;
  if (width < 700) return 16;
  return gutterOf(context);
}

extension PaletteOf on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.light;
}

/// `a { color: var(--accent); border-bottom: 1px solid var(--link-border) }`
extension LinkStyle on TextStyle {
  TextStyle asLink(Palette palette) => copyWith(
    color: palette.accent,
    decoration: TextDecoration.underline,
    decorationColor: palette.linkBorder,
    decorationThickness: 1,
  );
}

ThemeData textlogTheme(
  Palette palette, [
  FontChoice font = FontChoice.jetbrains,
  Chrome chrome = const Chrome(),
]) {
  // These ship as variable fonts, so weight has to be set as an axis as well —
  // fontWeight alone leaves them at 400.
  TextStyle mono(double size, {FontWeight? weight, double? height, Color? color}) => TextStyle(
    fontFamily: font.fontFamily,
    fontFamilyFallback: font.fallback,
    fontFeatures: font.features,
    fontSize: size * chrome.scale,
    fontWeight: weight,
    fontVariations: weight == null
        ? null
        : [FontVariation.weight(weight.value.toDouble())],
    height: height,
    color: color ?? palette.ink,
  );

  return ThemeData(
    brightness: palette.brightness,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: palette.brightness,
      surface: palette.bg,
    ),
    dividerColor: palette.soft,
    extensions: [palette, chrome],
    textSelectionTheme: TextSelectionThemeData(selectionColor: palette.accent),
    // Barebones: no ripple, no highlight wash, and no page slide. What is left is
    // the press feedback the app draws itself, which is a colour change on the text.
    splashFactory: chrome.plain ? NoSplash.splashFactory : null,
    highlightColor: chrome.plain ? Colors.transparent : null,
    pageTransitionsTheme: chrome.plain
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoTransition(),
              TargetPlatform.iOS: _NoTransition(),
              TargetPlatform.macOS: _NoTransition(),
              TargetPlatform.linux: _NoTransition(),
              TargetPlatform.windows: _NoTransition(),
              TargetPlatform.fuchsia: _NoTransition(),
            },
          )
        : null,
    // `.post p` is 13px/1.65; `.posttop` and nav are 12px; `.feedhead` is 11px.
    textTheme: TextTheme(
      titleLarge: mono(20, weight: FontWeight.w800, height: 1),
      bodyMedium: mono(13, height: 1.65),
      bodySmall: mono(12),
      labelSmall: mono(11, color: palette.muted),
    ),
  );
}

/// A route change with no animation at all.
final class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget? child,
  ) => child!;
}
