import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/bookmarks.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';

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
  'bookmarked_at': '2026-08-26T09:00:00.000Z',
};

({ProviderContainer container, List<String> calls, List<String> auth}) harness({
  bool failWrites = false,
}) {
  final calls = <String>[];
  final auth = <String>[];
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(FakeSession.new),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          auth.add(request.headers['authorization'] ?? '-');
          if (request.method != 'GET') {
            return http.Response(
              failWrites ? '{"error":{"code":"nope","message":"no"}}' : '{"data":{}}',
              failWrites ? 500 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'data': [post(1), post(2)],
              'pagination': {'next_cursor': null},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, calls: calls, auth: auth);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeedNotifier.forgetColdStarts();
  });

  test('the collection is a feed like any other', () async {
    expect(pathOf(const BookmarksFeed()), 'bookmarks');

    final t = harness();
    final feed = await t.container.read(feedProvider(const BookmarksFeed()).future);

    expect(feed.posts.map((post) => post.id), [1, 2]);
    // It is nobody else's list, so it is read as you or not at all.
    expect(t.auth, everyElement('Bearer tok'));
  });

  test('and is not kept on disk for a cold start', () {
    // It is not a tab the app can open on, and a stale copy of what you kept is of
    // no use to anyone.
    expect(coldStorageKeyOf(const BookmarksFeed(), viewer: 'me'), isNull);
  });

  test('keeping a post says so, and remembers it', () async {
    final t = harness();
    await t.container.read(sessionProvider.future);
    await t.container.read(bookmarksProvider.notifier).toggle(7, bookmarked: true);

    expect(t.calls.single, 'POST /api/v1/posts/7/bookmark');
    expect(t.container.read(bookmarksProvider)[7], isTrue);
  });

  test('and letting it go uses the same route the other way', () async {
    final t = harness();
    await t.container.read(sessionProvider.future);
    await t.container.read(bookmarksProvider.notifier).toggle(7, bookmarked: false);

    expect(t.calls.single, 'DELETE /api/v1/posts/7/bookmark');
    expect(t.container.read(bookmarksProvider)[7], isFalse);
  });

  test('a post nobody has said anything about is simply unknown', () {
    // Which is not "not bookmarked": a feed carries no such field, so the menu
    // offers to keep it and the server sorts out a repeat.
    final t = harness();
    expect(t.container.read(bookmarksProvider)[99], isNull);
  });

  test('a failure puts the label back and says why', () async {
    final t = harness(failWrites: true);
    await t.container.read(sessionProvider.future);
    await expectLater(
      t.container.read(bookmarksProvider.notifier).toggle(7, bookmarked: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(t.container.read(bookmarksProvider)[7], isNull);
  });

  test('what the bookmarks page loaded is known to be kept', () async {
    final t = harness();
    t.container.read(bookmarksProvider.notifier).notice([1, 2]);
    expect(t.container.read(bookmarksProvider), {1: true, 2: true});
  });
}
