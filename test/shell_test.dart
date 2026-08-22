import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/shell.dart';

class FakeSession extends SessionNotifier {
  FakeSession(this.session);

  final Session? session;

  @override
  Future<Session?> build() async => session;
}

Session sessionFor(String handle) => Session(
  token: 'tok',
  expiresAt: DateTime(2027),
  account: Account(handle: handle, bio: '', canPost: true),
);

/// The plain text of the wordmark as rendered.
String brandText(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.descendant(of: find.byType(Brand), matching: find.byType(RichText)),
  );
  return rich.text.toPlainText();
}

Future<void> showBrand(WidgetTester tester, double room) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      theme: textlogTheme(Palette.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: room, child: const Brand()),
        ),
      ),
    ),
  ),
);

void main() {
  group('the wordmark', () {
    testWidgets('shows in full when there is room for it', (tester) async {
      await showBrand(tester, 4000);
      expect(brandText(tester), '>_ textlog');
    });

    testWidgets('drops to the caret when there is not', (tester) async {
      // Measured, not a width breakpoint: what fits depends on the font, the text
      // size and how much the controls beside it have taken.
      await showBrand(tester, 40);
      expect(brandText(tester), '>_');
    });

    testWidgets('never renders clipped', (tester) async {
      // The old version let Flexible cut the word in half — `>_ te`.
      for (final room in [40.0, 80.0, 120.0, 200.0, 400.0]) {
        await showBrand(tester, room);
        expect(brandText(tester), anyOf('>_', '>_ textlog'), reason: 'at $room');

        final rendered = tester.getSize(
          find.descendant(of: find.byType(Brand), matching: find.byType(RichText)),
        );
        expect(rendered.width, lessThanOrEqualTo(room), reason: 'at $room');
      }
    });

    testWidgets('a bigger text size makes it yield sooner', (tester) async {
      Future<String> at(TextSize size, double room) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: textlogTheme(Palette.dark, FontChoice.jetbrains, Chrome(scale: size.scale)),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: room, child: const Brand()),
                ),
              ),
            ),
          ),
        );
        // MaterialApp crossfades a theme change, so the new text size only lands
        // after the animation — a bare pump measures the previous one.
        await tester.pump(kThemeAnimationDuration + const Duration(milliseconds: 50));
        return brandText(tester);
      }

      // A room that fits the small wordmark but not the largest one. A breakpoint
      // on screen width could not tell these apart.
      const room = 215.0;
      expect(await at(TextSize.small, room), '>_ textlog');
      expect(await at(TextSize.larger, room), '>_');
    });
  });

  group('the header keeps every control reachable', () {
    Future<void> showBar(WidgetTester tester, double width, String handle) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(
        width * tester.view.devicePixelRatio,
        844 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sessionProvider.overrideWith(() => FakeSession(sessionFor(handle)))],
          child: MaterialApp(
            theme: textlogTheme(Palette.dark),
            home: Builder(
              builder: (context) => Scaffold(appBar: textlogAppBar(context, path: '/hot')),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // A 320px phone and a handle at the server's 24-character limit is the worst
    // case, and it used to push the appearance control off the right edge.
    for (final (width, handle) in <(double, String)>[
      (320, 'me'),
      (320, 'averylonghandle_24chars'),
      (390, 'averylonghandle_24chars'),
      (768, 'averylonghandle_24chars'),
    ]) {
      testWidgets('at ${width.toInt()}px as @$handle', (tester) async {
        await showBar(tester, width, handle);

        for (final tooltip in ['search', 'appearance']) {
          final rect = tester.getRect(find.byTooltip(tooltip));
          expect(rect.right, lessThanOrEqualTo(width), reason: '$tooltip runs off the edge');
          expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$tooltip starts off the edge');
        }
        // The handle truncates rather than shoving the controls aside.
        expect(tester.getRect(find.textContaining('@')).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the tab row', () {
    Future<double> tabsWidth(WidgetTester tester, double room, {required bool wordy}) async {
      late bool sawCompact;
      await tester.pumpWidget(
        MaterialApp(
          theme: textlogTheme(Palette.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: room,
                child: FeedTabs(
                  tabs: const [
                    TabSpec('for you', '/for-you'),
                    TabSpec('to me', '/to-me'),
                    TabSpec('hot', '/hot'),
                    TabSpec('latest', '/latest'),
                    TabSpec('live', '/live'),
                  ],
                  active: 0,
                  onSelect: (_) {},
                  trailing: (compact) {
                    sawCompact = compact;
                    return Text(
                      compact ? 'mark read' : (wordy ? "you've seen it all" : 'mark all as read'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(sawCompact, room < 520);
      return tester.getSize(find.byType(SingleChildScrollView)).width;
    }

    testWidgets('leaves the tabs most of a phone-width row', (tester) async {
      // `you've seen it all` used to take 207px of a 390px row, leaving the tabs
      // 153px — four of the five tabs off screen before you scrolled.
      final width = await tabsWidth(tester, 390, wordy: true);
      expect(width, greaterThan(390 * 0.6));
    });

    testWidgets('the action never takes more than its share of the row', (tester) async {
      // Even at a text scale that would make the label enormous.
      await tester.pumpWidget(
        MaterialApp(
          theme: textlogTheme(Palette.dark),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: FeedTabs(
                    tabs: const [TabSpec('for you', '/for-you'), TabSpec('hot', '/hot')],
                    active: 0,
                    onSelect: (_) {},
                    trailing: (_) => const Text(
                      'mark all as read',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'a Row overflow is an exception');
      expect(tester.getRect(find.text('mark all as read')).right, lessThanOrEqualTo(320.0));
      expect(tester.getSize(find.byType(SingleChildScrollView)).width, greaterThan(320 * 0.55));
    });

    testWidgets('spells it out when the row is wide', (tester) async {
      await tabsWidth(tester, 760, wordy: true);
      expect(find.text("you've seen it all"), findsOneWidget);
      expect(find.text('mark read'), findsNothing);
    });

    testWidgets('shortens the action when the row is narrow', (tester) async {
      await tabsWidth(tester, 390, wordy: false);
      expect(find.text('mark read'), findsOneWidget);
      expect(find.text('mark all as read'), findsNothing);
    });
  });
}
