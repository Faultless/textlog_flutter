import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/feed_view.dart';
import 'package:textlog/ui/widgets/parent_quote.dart';
import 'package:textlog/ui/widgets/post_tile.dart';
import 'package:textlog/ui/widgets/reply_tree.dart';

Map<String, dynamic> post(
  int id, {
  int? parentId,
  Map<String, dynamic>? parent,
  int replyCount = 0,
  String handle = 'a',
  String? body,
}) => {
  'id': id,
  'top_id': null,
  'body': body ?? 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': parentId,
  'reply_count': replyCount,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': handle,
    'url': 'https://textlog.cc/u/$handle',
    'api_url': 'https://textlog.cc/api/v1/users/$handle',
  },
  'parent': parent,
};

Future<void> showFeed(WidgetTester tester, List<Map<String, dynamic>> page) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'data': page, 'pagination': {'next_cursor': null}}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: textlogTheme(Palette.dark),
        home: const Scaffold(body: FeedView(LatestFeed())),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('a reply to a post on the same page is nested, not duplicated', (tester) async {
    // Flat, this rendered two posts and quoted the parent again under the reply.
    await showFeed(tester, [
      post(2, parentId: 1, body: 'the reply', handle: 'b'),
      post(1, replyCount: 1, body: 'the parent'),
    ]);

    expect(find.text('the parent'), findsOneWidget, reason: 'said once, not twice');
    expect(find.text('the reply'), findsOneWidget);
    // One tile for the root; the reply is drawn by the branch, not as a second tile.
    expect(find.byType(PostTile), findsOneWidget);
    expect(find.byType(ReplyBranch), findsWidgets);
    expect(find.byType(ParentQuote), findsNothing);
  });

  testWidgets('a reply whose parent is elsewhere keeps its quote', (tester) async {
    await showFeed(tester, [
      post(2, parentId: 99, parent: post(99, body: 'the absent parent'), handle: 'b'),
    ]);

    expect(find.byType(PostTile), findsOneWidget);
    expect(find.byType(ParentQuote), findsOneWidget);
    expect(find.text('the absent parent'), findsOneWidget);
  });

  testWidgets('a feed of top-level notes is one tile each', (tester) async {
    await showFeed(tester, [post(3), post(2), post(1)]);
    expect(find.byType(PostTile), findsNWidgets(3));
    expect(find.byType(ReplyBranch), findsNothing);
  });

  testWidgets('a node with replies the page lacks offers to read more', (tester) async {
    await showFeed(tester, [
      post(2, parentId: 1, replyCount: 4, handle: 'b'),
      post(1, replyCount: 5),
    ]);

    // In a feed there is no thread to expand into, so it navigates instead of
    // advertising a count the page cannot satisfy.
    expect(find.text('read more'), findsOneWidget);
    expect(find.textContaining('more replies'), findsNothing);
  });

  testWidgets('a whole conversation on one page is one block', (tester) async {
    await showFeed(tester, [
      post(3, parentId: 2, body: 'third'),
      post(2, parentId: 1, body: 'second', replyCount: 1),
      post(1, body: 'first', replyCount: 2),
    ]);

    expect(find.byType(PostTile), findsOneWidget);
    for (final body in ['first', 'second', 'third']) {
      expect(find.text(body), findsOneWidget, reason: body);
    }
    expect(tester.takeException(), isNull);
  });
}
