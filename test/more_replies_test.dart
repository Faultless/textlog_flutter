import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/reply_tree.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/reply_tree.dart';

Post post(int id, {int replyCount = 0}) => Post(
  id: id,
  body: 'post $id',
  createdAt: DateTime(2026, 8, 8),
  parentId: 1,
  replyCount: replyCount,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
);

/// Renders [nodes] as a thread branch and reports where taps navigate to.
Future<({GoRouter router, List<String> calls, List<String> visited})> show(
  WidgetTester tester,
  List<ReplyNode> nodes, {
  int? rootId = 1,
}) async {
  final calls = <String>[];
  final visited = <String>[];
  final router = GoRouter(
    initialLocation: '/post/1',
    routes: [
      GoRoute(
        path: '/post/:id',
        builder: (_, state) {
          visited.add(state.pathParameters['id']!);
          return Scaffold(
            body: SingleChildScrollView(child: ReplyBranch(nodes, rootId: rootId)),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            calls.add(request.url.path);
            return http.Response('{"data":[],"pagination":{"next_cursor":null}}', 200);
          }),
        ),
      ],
      child: MaterialApp.router(
        theme: textlogTheme(Palette.dark),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, calls: calls, visited: visited);
}

void main() {
  setUpAll(() {
    // What the app sets in main.dart: without it `push` keeps the back stack but
    // leaves the reported location behind, so a test cannot see where it went.
    GoRouter.optionURLReflectsImperativeAPIs = true;
  });

  testWidgets('a node that cannot be expanded here opens the post instead', (tester) async {
    // This is the case that used to fire a request and change nothing at all: the
    // replies exist, but below the nesting cap, so there is nowhere to draw them.
    final tree = [
      ReplyNode(post: post(2, replyCount: 4), children: const [], unloaded: 4),
    ];
    final harness = await show(tester, tree);

    expect(find.text('+ 4 more replies'), findsOneWidget);
    await tester.tap(find.text('+ 4 more replies'));
    await tester.pumpAndSettle();

    // The route beneath rebuilds under the pushed page, so this is a containment
    // check rather than a check of what is last.
    expect(harness.visited, contains('2'), reason: 'the tap goes somewhere');
    expect(harness.calls, isEmpty, reason: 'and costs nothing');
  });

  testWidgets('one reply reads in the singular', (tester) async {
    final tree = [
      ReplyNode(post: post(2, replyCount: 1), children: const [], unloaded: 1),
    ];
    await show(tester, tree);
    expect(find.text('+ 1 more reply'), findsOneWidget);
  });

  testWidgets('a node with nothing missing offers nothing', (tester) async {
    final tree = [ReplyNode(post: post(2), children: const [], unloaded: 0)];
    await show(tester, tree);
    expect(find.textContaining('more repl'), findsNothing);
  });

  testWidgets('inside a feed it reads as read more and opens the thread', (tester) async {
    // A feed tree is only what that page returned; there is no thread notifier to
    // ask, so a count of what is missing would be noise.
    final tree = [
      ReplyNode(post: post(2, replyCount: 9), children: const [], unloaded: 9),
    ];
    final harness = await show(tester, tree, rootId: null);

    expect(find.text('read more'), findsOneWidget);
    await tester.tap(find.text('read more'));
    await tester.pumpAndSettle();

    expect(harness.visited, contains('2'));
    expect(harness.calls, isEmpty);
  });

  testWidgets('a node whose replies were never fetched loads them in place', (tester) async {
    final tree = [
      ReplyNode(
        post: post(2, replyCount: 3),
        children: const [],
        unloaded: 3,
        expandable: true,
      ),
    ];
    final harness = await show(tester, tree);

    await tester.tap(find.text('+ 3 more replies'));
    await tester.pumpAndSettle();

    expect(harness.visited, isNot(contains('2')), reason: 'it stays put');
    expect(
      harness.calls,
      contains('/api/v1/posts/2/replies'),
      reason: 'and asks for what it is missing',
    );
  });
}
