import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/unread.dart';
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
  int unread = 2,
  int read = 1,
}) {
  final auth = <String>[];
  final writes = <String>[];
  final page = [
    for (var id = 1; id <= unread; id++) post(id, unread: true),
    for (var id = unread + 1; id <= unread + read; id++) post(id, unread: false),
  ];
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
              'data': page,
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
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, writes: writes);
}

/// Longer than the queue holds ids for. Reads are batched so that scrolling through
/// a feed is one request rather than one a post, so a test has to let it fire.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 500));

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

  test('marking some read tells the screen at once and the server after', () async {
    final t = harness(unread: 4);
    await t.container.read(feedProvider(const LatestFeed()).future);

    await t.container.read(feedProvider(const LatestFeed()).notifier).markRead([1, 2]);

    // On screen immediately — the rail goes as the post scrolls by, not when the
    // request lands.
    final after = t.container.read(feedProvider(const LatestFeed())).valueOrNull!;
    expect(after.posts.where((p) => p.unread == true).map((p) => p.id), [3, 4]);
    expect(after.unreadCount, 2);
    expect(t.writes, isEmpty, reason: 'the ids are batched, not sent per post');

    await settle();
    expect(t.writes.single, contains('feeds/latest/read'));
    expect(t.writes.single, contains('"post_ids":[1,2]'));
  });

  test('a fling is one request, not one a post', () async {
    final t = harness(unread: 6);
    await t.container.read(feedProvider(const LatestFeed()).future);
    final notifier = t.container.read(feedProvider(const LatestFeed()).notifier);

    // What scrolling looks like: a post at a time, several frames apart.
    for (final id in [1, 2, 3, 4]) {
      await notifier.markRead([id]);
    }
    await settle();

    expect(t.writes.single, contains('"post_ids":[1,2,3,4]'));
  });

  test('reading the last of the catch-up set marks the whole feed read', () async {
    // The pages behind these were never loaded and the reader is not going to
    // scroll to them. Having caught up on what they were offered, they are done —
    // and pressing "mark all as read" afterwards was the chore this removes.
    final t = harness(unread: 3);
    await t.container.read(feedProvider(const LatestFeed()).future);
    final notifier = t.container.read(feedProvider(const LatestFeed()).notifier);

    await notifier.markRead([1, 2]);
    expect(t.container.read(latestUnreadProvider), isTrue);

    await notifier.markRead([3]);

    expect(t.writes.last, contains('feeds/latest/read-all'));
    final after = t.container.read(feedProvider(const LatestFeed())).valueOrNull!;
    expect(after.hasUnread, isFalse);
    expect(after.unreadCount, 0);
    expect(t.container.read(latestUnreadProvider), isFalse);
  });

  test('a fresh start offers a dozen posts to catch up on, not four hundred', () async {
    // Scrolling is what marks a post read, so an unread count in the hundreds means
    // a reader who has been away can never clear it by reading.
    final t = harness(unread: 400, read: 0);
    final feed = await t.container.read(feedProvider(const LatestFeed()).future);

    expect(feed.unreadCount, unreadCatchUp);
    expect(feed.posts.where((p) => p.unread == true).length, unreadCatchUp);
    // The newest ones, which are the ones a reader coming back wants.
    expect(feed.posts.take(unreadCatchUp).every((p) => p.unread == true), isTrue);
    expect(feed.hasUnread, isTrue, reason: 'the server still has more than these');
  });

  test('a post that was already read is not sent again', () async {
    final t = harness();
    await t.container.read(feedProvider(const LatestFeed()).future);
    await t.container.read(feedProvider(const LatestFeed()).notifier).markRead([3]);
    await settle();
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
