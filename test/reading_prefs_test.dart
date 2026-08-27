import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_tile.dart';
import 'package:textlog/ui/widgets/swipe_to_reply.dart';

Post post({String body = 'hello', String? translation, int replies = 3}) => Post(
  id: 7,
  body: body,
  createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  parentId: null,
  replyCount: replies,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/7'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
  translation: translation,
);

Future<void> show(
  WidgetTester tester,
  Post subject, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(child: PostTile(subject)),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('timestamps and reply counts', () {
    testWidgets('both show by default', (tester) async {
      await show(tester, post());
      expect(find.textContaining('3h'), findsWidgets);
      expect(find.textContaining('3 replies'), findsOneWidget);
    });

    testWidgets('the timestamp can be turned off, leaving the count', (tester) async {
      await show(tester, post(), prefs: {'timestamps': false});
      expect(find.textContaining('3 replies'), findsOneWidget);
      expect(find.textContaining('3h'), findsNothing);
    });

    testWidgets('and the count off, leaving the timestamp', (tester) async {
      await show(tester, post(), prefs: {'reply_counts': false});
      expect(find.textContaining('replies'), findsNothing);
      expect(find.textContaining('3h'), findsWidgets);
    });

    testWidgets('both off draws no empty tap target', (tester) async {
      await show(
        tester,
        post(),
        prefs: {'timestamps': false, 'reply_counts': false},
      );
      expect(find.textContaining('3h'), findsNothing);
      expect(find.textContaining('replies'), findsNothing);
      // The post is still there, and the card still opens it.
      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('translation', () {
    testWidgets('is offered when the server found the post was not English',
        (tester) async {
      await show(tester, post(body: 'Супер!', translation: 'Great!'));

      expect(find.text('translate'), findsOneWidget);
      expect(find.text('Супер!'), findsOneWidget);

      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(find.text('Great!'), findsOneWidget);
      expect(find.text('show original'), findsOneWidget);
    });

    testWidgets('and not on an English post', (tester) async {
      await show(tester, post());
      expect(find.text('translate'), findsNothing);
    });

    testWidgets('nor when the translation says the same thing', (tester) async {
      // The translator sometimes hands back its input, and a button that swaps a
      // body for itself is worse than no button.
      await show(tester, post(body: 'same', translation: 'same'));
      expect(find.text('translate'), findsNothing);
    });

    testWidgets('nor when the reader turned it off', (tester) async {
      await show(
        tester,
        post(body: 'Супер!', translation: 'Great!'),
        prefs: {'translate': false},
      );
      expect(find.text('translate'), findsNothing);
      expect(find.text('Супер!'), findsOneWidget);
    });
  });

  group('swipe to reply', () {
    testWidgets('a drag to the left reveals the hint', (tester) async {
      await show(tester, post());

      final gesture = await tester.startGesture(tester.getCenter(find.text('hello')));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();

      expect(find.text('reply'), findsWidgets, reason: 'the hint is uncovered');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('is absent when the reader turned it off', (tester) async {
      await show(tester, post(), prefs: {'swipe_to_reply': false});
      expect(find.byType(SwipeToReply), findsOneWidget);
      // Present in the tree but transparent: it hands back its child untouched.
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('a wide code block still scrolls sideways inside the post',
        (tester) async {
      // Both this and the swipe want horizontal drags. The code block is deeper in
      // the hit test, so it wins its own gesture — otherwise a post containing a
      // long line would become unreadable in exchange for a shortcut.
      final long = 'x' * 400;
      await show(tester, post(body: 'look:\n\n```\n$long\n```'));

      final scroller = find.ancestor(
        of: find.text(long),
        matching: find.byType(Scrollable),
      );
      expect(scroller, findsWidgets);
      // No controller on that view, so ask the state for its position. And drag from
      // a point that is actually on screen: the text is 5000px wide, so its centre —
      // which `tester.drag` would use — is nowhere near the viewport.
      double offset() => tester.state<ScrollableState>(scroller.first).position.pixels;
      final box = tester.getRect(scroller.first);
      final before = offset();

      await tester.dragFrom(Offset(box.left + 40, box.center.dy), const Offset(-120, 0));
      await tester.pumpAndSettle();

      final after = offset();
      expect(after, greaterThan(before), reason: 'the code scrolled, not the card');
      expect(find.textContaining('Reply to'), findsNothing);
    });

    testWidgets('a vertical drag still scrolls rather than replying', (tester) async {
      await show(tester, post());
      final gesture = await tester.startGesture(tester.getCenter(find.text('hello')));
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // No compose sheet: the vertical drag belongs to the list.
      expect(find.textContaining('Reply to'), findsNothing);
    });
  });
}
