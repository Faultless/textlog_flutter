import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/ui/theme.dart';

void main() {
  test('every choice resolves to a palette, and ids round-trip', () {
    for (final choice in ThemeChoice.values) {
      expect(ThemeChoice.fromId(choice.id), choice);
      expect(choice.resolve(Brightness.light), isA<Palette>());
    }
    expect(ThemeChoice.fromId('nonsense'), ThemeChoice.system);
    expect(ThemeChoice.fromId(null), ThemeChoice.system);
  });

  test('system follows the device, fixed choices do not', () {
    expect(ThemeChoice.system.resolve(Brightness.dark), Palette.dark);
    expect(ThemeChoice.system.resolve(Brightness.light), Palette.light);
    expect(ThemeChoice.dracula.resolve(Brightness.light), Palette.dracula);
    expect(ThemeChoice.sepia.resolve(Brightness.dark), Palette.sepia);
  });

  test('accent ids round-trip and theme means no override', () {
    for (final choice in AccentChoice.values) {
      expect(AccentChoice.fromId(choice.id), choice);
    }
    expect(AccentChoice.theme.forBrightness(Brightness.light), isNull);
    expect(AccentChoice.fromId('nope'), AccentChoice.theme);
  });

  test('withAccent replaces the accent and leaves the rest of the palette alone', () {
    final purple = AccentChoice.purple.forBrightness(Brightness.dark);
    final themed = Palette.dark.withAccent(purple);

    expect(themed.accent, purple);
    expect(themed.bg, Palette.dark.bg, reason: 'background must not shift');
    expect(themed.ink, Palette.dark.ink);
    expect(themed.accentDark, isNot(themed.accent), reason: 'hover shade must differ');
  });

  test('a null accent leaves the palette untouched', () {
    expect(Palette.light.withAccent(null).accent, Palette.light.accent);
  });

  test('the hover shade brightens on dark and darkens on light', () {
    double lightnessOf(Color c) => HSLColor.fromColor(c).lightness;
    final blue = AccentChoice.blue;

    final onDark = Palette.dark.withAccent(blue.forBrightness(Brightness.dark));
    expect(lightnessOf(onDark.accentDark), greaterThan(lightnessOf(onDark.accent)));

    final onLight = Palette.light.withAccent(blue.forBrightness(Brightness.light));
    expect(lightnessOf(onLight.accentDark), lessThan(lightnessOf(onLight.accent)));
  });

  test('the palette travels with the theme so context.palette works', () {
    final theme = textlogTheme(Palette.dracula);
    expect(theme.extension<Palette>(), Palette.dracula);
    expect(theme.brightness, Brightness.dark);
  });

  group('fonts', () {
    test('ids round-trip and an unknown one falls back to the default', () {
      for (final choice in FontChoice.values) {
        expect(FontChoice.fromId(choice.id), choice);
      }
      expect(FontChoice.fromId('comic-sans'), FontChoice.jetbrains);
      expect(FontChoice.fromId(null), FontChoice.jetbrains);
    });

    test('the chosen face reaches the text theme', () {
      final theme = textlogTheme(Palette.dark, FontChoice.fira);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'FiraCode');
    });

    test('only Fira Code keeps ligatures on', () {
      expect(FontChoice.fira.features, isNull);
      expect(FontChoice.jetbrains.features, isNotNull);
      expect(FontChoice.system.features, isNotNull);
    });

    test('system falls back to platform monospace, bundled faces do not', () {
      expect(FontChoice.system.fallback, isNotNull);
      expect(FontChoice.jetbrains.fallback, isNull);
    });
  });
}
