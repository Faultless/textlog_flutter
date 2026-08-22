import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/form_parts.dart';
import 'package:textlog/ui/widgets/glyph.dart';
import 'package:textlog/ui/widgets/status.dart';

/// Pump [child] under a theme with barebones on or off, and let the theme land.
Future<void> show(WidgetTester tester, Widget child, {required bool plain}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: textlogTheme(Palette.dark, FontChoice.jetbrains, Chrome(plain: plain)),
      home: Scaffold(body: child),
    ),
  );
  // MaterialApp crossfades a theme change. Not pumpAndSettle: a spinner never
  // settles, and one of these tests is about a spinner.
  await tester.pump(kThemeAnimationDuration + const Duration(milliseconds: 50));
}

void main() {
  group('barebones swaps Material for characters', () {
    testWidgets('an icon becomes its glyph', (tester) async {
      await show(tester, const Glyph(Icons.search, '/'), plain: false);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('/'), findsNothing);

      await show(tester, const Glyph(Icons.search, '/'), plain: true);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.text('/'), findsOneWidget);
    });

    testWidgets('a filled button becomes [ label ]', (tester) async {
      await show(tester, TextlogButton('post →', onPressed: () {}), plain: false);
      expect(find.text('post →'), findsOneWidget);

      await show(tester, TextlogButton('post →', onPressed: () {}), plain: true);
      expect(find.text('[ post → ]'), findsOneWidget);
    });

    testWidgets('a switch becomes [x]', (tester) async {
      await show(tester, PlainCheck(value: true, onChanged: (_) {}), plain: false);
      expect(find.byType(Switch), findsOneWidget);

      await show(tester, PlainCheck(value: true, onChanged: (_) {}), plain: true);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('[x]'), findsOneWidget);

      await show(tester, PlainCheck(value: false, onChanged: (_) {}), plain: true);
      expect(find.text('[ ]'), findsOneWidget);
    });

    testWidgets('a checkbox still toggles', (tester) async {
      var value = false;
      await show(
        tester,
        PlainCheck(value: value, onChanged: (next) => value = next),
        plain: true,
      );
      await tester.tap(find.text('[ ]'));
      expect(value, isTrue);
    });

    testWidgets('a spinner becomes a word', (tester) async {
      await show(tester, const Spinner(), plain: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await show(tester, const Spinner(), plain: true);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('loading…'), findsOneWidget);
    });

    testWidgets('nothing ripples and nothing slides', (tester) async {
      await show(tester, const SizedBox(), plain: true);
      final theme = Theme.of(tester.element(find.byType(SizedBox).first));
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.highlightColor, Colors.transparent);
      expect(theme.extension<Chrome>()!.plain, isTrue);
    });

    testWidgets('the default keeps every bit of it', (tester) async {
      await show(tester, const SizedBox(), plain: false);
      final theme = Theme.of(tester.element(find.byType(SizedBox).first));
      expect(theme.extension<Chrome>()!.plain, isFalse);
      expect(theme.splashFactory, isNot(NoSplash.splashFactory));
    });
  });

  group('text size', () {
    double bodySize(TextSize size) => textlogTheme(
      Palette.dark,
      FontChoice.jetbrains,
      Chrome(scale: size.scale),
    ).textTheme.bodyMedium!.fontSize!;

    test('scales the body text', () {
      expect(bodySize(TextSize.small), lessThan(bodySize(TextSize.regular)));
      expect(bodySize(TextSize.large), greaterThan(bodySize(TextSize.regular)));
      expect(bodySize(TextSize.larger), greaterThan(bodySize(TextSize.large)));
    });

    test('an unknown id falls back to regular', () {
      expect(TextSize.fromId('enormous'), TextSize.regular);
      expect(TextSize.fromId(null), TextSize.regular);
      expect(TextSize.fromId('large'), TextSize.large);
    });
  });

  group('reply nesting', () {
    Future<double> indentAt(WidgetTester tester, double width) async {
      late double indent;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            theme: textlogTheme(Palette.dark),
            home: Builder(
              builder: (context) {
                indent = replyIndentOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return indent;
    }

    testWidgets('five levels stay inside a fifth of a phone screen', (tester) async {
      // A full gutter per level put a quarter of a 390px screen behind the rail
      // before a word was drawn.
      expect(await indentAt(tester, 390) * 5, lessThan(390 * 0.2));
    });

    testWidgets("a wide window gets the site's own gutter back", (tester) async {
      expect(await indentAt(tester, 1200), greaterThan(await indentAt(tester, 390)));
    });
  });
}
