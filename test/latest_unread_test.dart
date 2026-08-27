import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
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

class NoSession extends SessionNotifier {
  @override
  Future<Session?> build() async => null;
}

Map<String, dynamic> post(int id, {bool? unread}) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-26T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
  'unread': ?unread,
};

({ProviderContainer container, List<String> auth, List<String> writes}) harness({
  bool signedIn = true,
}) {
  final auth = <String>[];
  final writes = <String>[];
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(signedIn ? FakeSession.new : NoSession.new),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          if (request.method == 'POST') {
            writes.add('${request.url.path} ${request.body}');
            return http.Response('{"data":{"read":2}}', 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          auth.add(request.headers['authorization'] ?? '-');
          return http.Response(
            jsonEncode({
              'data': [post(1, unread: true), post(2, unread: true), post(3, unread: false)],
              'pagination': {'next_cursor': null},
              'has_unread': true,
              'unread_count': 2,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, writes: writes);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeedNotifier.forgetColdStarts();
  });

  test('a feed is read as you, so it carries your unread state', () async {
    // It used to be read anonymously, which meant no unread state — and, worse, a
    // feed that ignored the accounts and hashtags you had blocked.
    final t = harness();
    final feed = await t.container.read(feedProvider(const LatestFeed()).future);

    // A session that resolves after the first build legitimately refetches, so what
    // matters is that no read went out anonymously.
    expect(t.auth, isNotEmpty);
    expect(t.auth.every((header) => header == 'Bearer tok'), isTrue);
    expect(feed.hasUnread, isTrue);
    expect(feed.unreadCount, 2);
    expect(feed.posts.first.unread, isTrue);
    expect(t.container.read(latestUnreadProvider), isTrue);
  });

  test('and anonymously when nobody is signed in', () async {
    final t = harness(signedIn: false);
    await t.container.read(feedProvider(const LatestFeed()).future);
    expect(t.auth.every((header) => header == '-'), isTrue);
  });

  test('marking some read tells the server and the screen', () async {
    final t = harness();
    await t.container.read(feedProvider(const LatestFeed()).future);

    await t.container.read(feedProvider(const LatestFeed()).notifier).markRead([1, 2]);

    expect(t.writes.single, contains('feeds/latest/read'));
    expect(t.writes.single, contains('"post_ids":[1,2]'));
    final after = t.container.read(feedProvider(const LatestFeed())).valueOrNull!;
    expect(after.posts.where((p) => p.unread == true), isEmpty);
    expect(after.unreadCount, 0);
  });

  test('a post that was already read is not sent again', () async {
    final t = harness();
    await t.container.read(feedProvider(const LatestFeed()).future);
    await t.container.read(feedProvider(const LatestFeed()).notifier).markRead([3]);
    expect(t.writes, isEmpty, reason: 'post 3 came back read');
  });

  test('mark all uses the server’s read-all, not a walk over the page', () async {
    // The pages you have not loaded are unread too, and the app cannot name them.
    final t = harness();
    await t.container.read(feedProvider(const LatestFeed()).future);

    await t.container.read(feedProvider(const LatestFeed()).notifier).markAllRead();

    expect(t.writes.single, contains('feeds/latest/read-all'));
    final after = t.container.read(feedProvider(const LatestFeed())).valueOrNull!;
    expect(after.hasUnread, isFalse);
    expect(after.unreadCount, 0);
    expect(t.container.read(latestUnreadProvider), isFalse);
  });

  test('signed out, marking read asks the server nothing', () async {
    final t = harness(signedIn: false);
    await t.container.read(feedProvider(const LatestFeed()).future);
    await t.container.read(feedProvider(const LatestFeed()).notifier).markAllRead();
    expect(t.writes, isEmpty);
  });

  test('a stored feed belongs to the account that read it', () {
    // Sharing one key would show a signed-in reader's timeline to whoever opened
    // the app next.
    expect(coldStorageKeyOf(const LatestFeed()), 'feed:latest');
    expect(coldStorageKeyOf(const LatestFeed(), viewer: 'me'), 'feed:latest:@me');
    expect(
      coldStorageKeyOf(const LatestFeed(), viewer: 'me'),
      isNot(coldStorageKeyOf(const LatestFeed(), viewer: 'you')),
    );
  });
}
