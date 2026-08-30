import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/unread.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/feed_view.dart';

final _session = Session(
  token: 'tok',
  expiresAt: DateTime(2027),
  account: const Account(handle: 'me', bio: '', canPost: true),
);

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => _session;
}

Map<String, dynamic> post(int id) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-26T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
  'unread': true,
};

/// The paths written to, in order — `feeds/latest/read` for a batch of ids,
/// `feeds/latest/read-all` for the lot.
Future<List<String>> show(WidgetTester tester, {required int unread}) async {
  SharedPreferences.setMockInitialValues({});
  FeedNotifier.forgetColdStarts();
  final writes = <String>[];

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: FeedView(LatestFeed())),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(FakeSession.new),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') {
              writes.add(request.url.path);
              return http.Response('{"data":{}}', 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }
            return http.Response(
              jsonEncode({
                'data': [for (var id = unread; id >= 1; id--) post(id)],
                'pagination': {'next_cursor': null},
                'has_unread': true,
                'unread_count': unread,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ],
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await flushReads(tester);
  return writes;
}

/// Let the batched ids go out. See ReadQueue: marking is instant on screen and the
/// request waits for the reader to pause.
Future<void> flushReads(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

FeedState state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FeedView)))
        .read(feedProvider(const LatestFeed()))
        .value!;

void main() {
  testWidgets('a fresh start offers a dozen posts, not the whole backlog',
      (tester) async {
    await show(tester, unread: 200);
    expect(state(tester).unreadCount, lessThanOrEqualTo(unreadCatchUp));
  });

  testWidgets('the first screenful is read without touching anything',
      (tester) async {
    final writes = await show(tester, unread: 200);
    expect(writes, isNotEmpty, reason: 'what is on screen has been seen');
    expect(writes.first, contains('feeds/latest/read'));
  });

  testWidgets('and scrolling through the rest marks the whole feed read',
      (tester) async {
    // The point of capping the catch-up set: reading it is finishing, so the
    // hundreds behind it — pages this app never even loaded — go with it instead of
    // waiting on a button.
    final writes = await show(tester, unread: 200);

    for (var i = 0; i < 12 && !writes.any((path) => path.endsWith('read-all')); i++) {
      await tester.fling(find.byType(CustomScrollView), const Offset(0, -600), 1000);
      await tester.pumpAndSettle();
      await flushReads(tester);
    }

    expect(writes.last, endsWith('feeds/latest/read-all'));
    expect(state(tester).hasUnread, isFalse);
  });
}
