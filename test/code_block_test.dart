import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_body.dart';

/// Render [body] the way a tile does: inside a scrolling page of bounded width.
Future<void> show(
  WidgetTester tester,
  String body, {
  double width = 390,
  bool markdown = false,
}) async {
  SharedPreferences.setMockInitialValues({'markdown': markdown});
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: textlogTheme(Palette.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ListView(children: [PostBody(body)]),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a fenced code block', () {
    testWidgets('does not take the page down with it', (tester) async {
      // It used to ask for `width: double.infinity` inside its own sideways
      // viewport, where the width is unbounded. That threw during layout, and the
      // whole thread — post, replies and all — painted as an empty page.
      await show(tester, 'look:\n\n```\nplain(text)\n```\n');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('plain(text)'), findsOneWidget);
      expect(find.textContaining('look'), findsOneWidget);
    });

    testWidgets('still fills the column when the code is narrow', (tester) async {
      await show(tester, '```\nok\n```');

      final tint = tester.widget<Container>(
        find.ancestor(of: find.text('ok'), matching: find.byType(Container)).first,
      );
      expect(tester.getSize(find.byWidget(tint)).width, 390);
    });

    testWidgets('is free to be wider than the column, and scrolls', (tester) async {
      final long = 'x' * 400;
      await show(tester, '```\n$long\n```');

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(long)).width, greaterThan(390));
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('a table is not stretched to the column', (tester) async {
      // Only code carries a background worth filling; a table drawn to full width
      // would put its border out where its last column is not.
      await show(tester, '| a | b |\n| - | - |\n| 1 | 2 |', markdown: true);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Table)).width, lessThan(390));
    });
  });
}
