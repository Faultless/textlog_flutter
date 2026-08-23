import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_tile.dart';
import 'package:textlog/ui/widgets/todo_view.dart';

Post post({String body = 'hello', String handle = 'alice', int id = 2}) => Post(
  id: id,
  body: body,
  createdAt: DateTime(2026, 8, 8),
  parentId: null,
  replyCount: 3,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
);

/// Render [child] at `/post/2` and report every route the router built.
Future<List<String>> show(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final visited = <String>[];
  final router = GoRouter(
    initialLocation: '/post/2',
    routes: [
      GoRoute(
        path: '/post/:id',
        builder: (_, state) {
          visited.add('/post/${state.pathParameters['id']}');
          return Scaffold(body: SingleChildScrollView(child: child));
        },
      ),
      GoRoute(
        path: '/u/:handle',
        builder: (_, state) {
          visited.add('/u/${state.pathParameters['handle']}');
          return const Scaffold(body: SizedBox());
        },
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
  visited.clear();
  return visited;
}

void main() {
  setUpAll(() => GoRouter.optionURLReflectsImperativeAPIs = true);

  group('the post a page is about', () {
    testWidgets('does not open itself again', (tester) async {
      // It used to push the route it was already on. A second tap pushed another, and
      // a checklist item that fell through to the card read as an endless loop of
      // opening the same reply.
      final visited = await show(tester, PostTile(post(), isSubject: true));

      await tester.tap(find.text('hello'));
      await tester.pumpAndSettle();
      expect(visited, isEmpty);
    });

    testWidgets('is not even offered as tappable', (tester) async {
      await show(tester, PostTile(post(), isSubject: true));
      final ink = tester.widget<InkWell>(find.byType(InkWell).first);
      expect(ink.onTap, isNull, reason: 'so it does not look like it does something');
    });

    testWidgets('a tile that is not the subject still opens', (tester) async {
      final visited = await show(tester, PostTile(post(id: 9)));

      await tester.tap(find.text('hello'));
      await tester.pumpAndSettle();
      expect(visited, contains('/post/9'));
    });

    testWidgets('its own timestamp does not reopen it either', (tester) async {
      final visited = await show(tester, PostTile(post(), isSubject: true));

      await tester.tap(find.textContaining('replies'));
      await tester.pumpAndSettle();
      expect(visited, isEmpty);
    });
  });

  group('controls inside a card', () {
    testWidgets('a checklist item the author can tick does not open the post',
        (tester) async {
      final visited = await show(
        tester,
        PostTile(post(body: 'list #todo\n[ ] one\n[x] two', id: 9)),
      );

      expect(find.byType(TodoView), findsOneWidget);
      await tester.tap(find.text('one'));
      await tester.pumpAndSettle();
      // Not signed in, so nothing is toggled — but the card must not have fired.
      expect(visited, isEmpty, reason: 'a checkbox press has no business navigating');
    });

    testWidgets('the body around it still opens the post', (tester) async {
      final visited = await show(
        tester,
        PostTile(post(body: 'list #todo\n[ ] one', id: 9)),
      );

      await tester.tap(find.textContaining('list'));
      await tester.pumpAndSettle();
      expect(visited, contains('/post/9'));
    });

    testWidgets('a mention opens the profile, not the post', (tester) async {
      final visited = await show(tester, PostTile(post(body: 'hi @bob', id: 9)));

      // The span recognizer wins the arena over the card behind it.
      await tester.tapOnText(find.textRange.ofSubstring('@bob'));
      await tester.pumpAndSettle();
      // The route beneath a pushed page rebuilds, so this checks where it *went*.
      expect(visited.first, '/u/bob');
      expect(visited.where((route) => route == '/post/9'), isEmpty);
    });
  });
}
